import asyncio
import base64
import json
import math
import os
import queue
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import wave
from collections import deque
from dataclasses import dataclass

import numpy as np
import rclpy
from geometry_msgs.msg import Twist
from rclpy.node import Node


SR = 16000
CH_IN = 1
FRAME_MS = 30
FRAME_SAMPLES = SR * FRAME_MS // 1000
FRAME_BYTES = FRAME_SAMPLES * 2

COOLDOWN_SEC = 0.4
LINEAR_SPEED = 0.5
ANGULAR_SPEED = 0.8

VAD_PREFIX_PADDING_MS = 300
VAD_START_SPEECH_MS = 90
VAD_SILENCE_DURATION_MS = 600
VAD_MIN_UTTERANCE_MS = 250
VAD_MAX_UTTERANCE_SEC = 15.0
VAD_MIN_RMS = 550.0
VAD_THRESHOLD_RATIO = 2.3


@dataclass(frozen=True)
class CommandMatch:
    name: str
    linear_x: float
    angular_z: float


@dataclass(frozen=True)
class AsrResult:
    text: str
    latency_ms: float
    utterance_ms: float | None = None
    utterance_end_ts: float | None = None


class VoiceTeleopNode(Node):
    def __init__(self) -> None:
        super().__init__("voice_teleop")
        self.pub = self.create_publisher(Twist, "/cmd_vel", 10)
        self.get_logger().info("voice_teleop node ready; publishing Twist on /cmd_vel")

    def publish_twist(self, linear_x: float, angular_z: float) -> None:
        msg = Twist()
        msg.linear.x = float(linear_x)
        msg.angular.z = float(angular_z)
        self.pub.publish(msg)
        self.get_logger().info(
            f"publish /cmd_vel linear.x={linear_x:.2f} angular.z={angular_z:.2f}"
        )


def detect_command(text: str) -> CommandMatch | None:
    t = (text or "").strip()
    if not t:
        return None
    t_lower = t.lower()
    if any(k in t for k in ["止ま", "停止", "ストップ", "やめ"]) or "stop" in t_lower:
        return CommandMatch("stop", 0.0, 0.0)
    if any(k in t for k in ["左", "ひだり"]) or "left" in t_lower:
        return CommandMatch("left", 0.0, ANGULAR_SPEED)
    if any(k in t for k in ["右", "みぎ"]) or "right" in t_lower:
        return CommandMatch("right", 0.0, -ANGULAR_SPEED)
    if any(k in t for k in ["後退", "下がっ", "バック", "後ろ"]) or "back" in t_lower:
        return CommandMatch("back", -LINEAR_SPEED, 0.0)
    if any(k in t for k in ["前進", "進ん", "進め", "まっすぐ", "前に", "前へ"]) or "forward" in t_lower:
        return CommandMatch("forward", LINEAR_SPEED, 0.0)
    return None


class AsrEngine:
    backend_name = "unknown"

    def transcribe(self, audio_f32: np.ndarray) -> AsrResult:
        raise NotImplementedError


def write_wav_file(audio_f32: np.ndarray) -> str:
    pcm = np.clip(audio_f32, -1.0, 1.0)
    pcm_i16 = (pcm * 32767.0).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wav_path = tmp.name
    with wave.open(wav_path, "wb") as wav_file:
        wav_file.setnchannels(CH_IN)
        wav_file.setsampwidth(2)
        wav_file.setframerate(SR)
        wav_file.writeframes(pcm_i16.tobytes())
    return wav_path


class ParakeetAsrEngine(AsrEngine):
    backend_name = "parakeet"

    def __init__(self, model_name: str, device: str) -> None:
        from nemo.collections.asr.models import EncDecHybridRNNTCTCBPEModel
        import torch

        self._model = EncDecHybridRNNTCTCBPEModel.from_pretrained(model_name=model_name)
        self._model = self._model.to(torch.device(device))
        self._model.eval()
        if hasattr(self._model, "freeze"):
            self._model.freeze()
        self._device = device
        self._model_name = model_name

    def _transcribe_config(self):
        config = self._model.get_transcribe_config()
        config.batch_size = 1
        config.num_workers = 0
        config.use_lhotse = False
        config.verbose = False
        return config

    def transcribe(self, audio_f32: np.ndarray) -> AsrResult:
        wav_path = None
        try:
            wav_path = write_wav_file(audio_f32)
            started_at = time.perf_counter()
            result = self._model.transcribe(
                [wav_path], override_config=self._transcribe_config()
            )
            latency_ms = (time.perf_counter() - started_at) * 1000.0
            if not result:
                return AsrResult("", latency_ms)
            first = result[0]
            return AsrResult(
                (getattr(first, "text", None) or str(first) or "").strip(),
                latency_ms,
            )
        finally:
            if wav_path and os.path.exists(wav_path):
                os.unlink(wav_path)


class AzureRealtimeSession:
    backend_name = "azure"

    def __init__(
        self,
        endpoint: str,
        api_key: str,
        deployment_name: str,
        transcription_model: str,
    ) -> None:
        try:
            import websockets
        except ImportError as exc:
            raise RuntimeError(
                "python3-websockets is not installed in this environment"
            ) from exc

        self._endpoint = endpoint
        self._api_key = api_key
        self._deployment_name = deployment_name
        self._transcription_model = transcription_model
        self._websockets = websockets
        self._results: queue.Queue[AsrResult] = queue.Queue()
        self._errors: queue.Queue[BaseException] = queue.Queue()
        self._thread: threading.Thread | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._send_queue: asyncio.Queue | None = None
        self._ws = None
        self._transport_ready = threading.Event()
        self._session_ready = threading.Event()
        self._closed = threading.Event()
        self._speech_started_at: float | None = None
        self._pending_turns: deque[tuple[float, float | None]] = deque()

    def start(self) -> None:
        if self._thread is not None:
            return
        self._thread = threading.Thread(target=self._run_loop, daemon=True)
        self._thread.start()
        if not self._transport_ready.wait(timeout=10.0):
            raise TimeoutError("timed out initializing Azure Realtime client")
        deadline = time.time() + 10.0
        while not self._session_ready.is_set():
            self.raise_if_error()
            if time.time() >= deadline:
                raise TimeoutError("timed out waiting for Azure Realtime session.update")
            time.sleep(0.05)

    def close(self) -> None:
        if self._loop is not None and self._send_queue is not None:
            self._loop.call_soon_threadsafe(self._send_queue.put_nowait, None)
        if self._loop is not None and self._ws is not None:
            try:
                asyncio.run_coroutine_threadsafe(self._ws.close(), self._loop).result(timeout=5.0)
            except Exception:
                pass
        if self._thread is not None:
            self._thread.join(timeout=5.0)
        self._thread = None

    def send_audio_frame(self, frame_i16: np.ndarray) -> None:
        self.raise_if_error()
        if self._loop is None or self._send_queue is None:
            raise RuntimeError("Azure Realtime client is not started")
        payload = {
            "type": "input_audio_buffer.append",
            "audio": base64.b64encode(frame_i16.tobytes()).decode("ascii"),
        }
        self._loop.call_soon_threadsafe(self._send_queue.put_nowait, payload)

    def poll_result(self) -> AsrResult | None:
        self.raise_if_error()
        try:
            return self._results.get_nowait()
        except queue.Empty:
            return None

    def raise_if_error(self) -> None:
        try:
            err = self._errors.get_nowait()
        except queue.Empty:
            return
        raise RuntimeError(f"azure realtime failed: {err}") from err

    def _run_loop(self) -> None:
        loop = asyncio.new_event_loop()
        self._loop = loop
        asyncio.set_event_loop(loop)
        self._send_queue = asyncio.Queue()
        self._transport_ready.set()
        try:
            loop.run_until_complete(self._run_session())
        except Exception as exc:
            self._errors.put(exc)
        finally:
            self._closed.set()
            self._session_ready.set()
            try:
                loop.run_until_complete(loop.shutdown_asyncgens())
            except Exception:
                pass
            loop.close()

    async def _run_session(self) -> None:
        uri = build_azure_realtime_uri(self._endpoint, self._deployment_name)
        async with self._websockets.connect(
            uri,
            extra_headers={"api-key": self._api_key},
            max_size=None,
            ping_interval=20,
            ping_timeout=20,
        ) as ws:
            self._ws = ws
            await ws.send(json.dumps(self._session_update_payload()))
            sender_task = asyncio.create_task(self._sender_loop(ws))
            receiver_task = asyncio.create_task(self._receiver_loop(ws))
            done, pending = await asyncio.wait(
                [sender_task, receiver_task], return_when=asyncio.FIRST_EXCEPTION
            )
            for task in pending:
                task.cancel()
            for task in done:
                exc = task.exception()
                if exc is not None:
                    raise exc

    async def _sender_loop(self, ws) -> None:
        assert self._send_queue is not None
        while True:
            message = await self._send_queue.get()
            if message is None:
                break
            await ws.send(json.dumps(message))

    async def _receiver_loop(self, ws) -> None:
        async for raw_message in ws:
            self._handle_server_event(json.loads(raw_message))

    def _handle_server_event(self, event: dict) -> None:
        event_type = event.get("type")
        if event_type == "session.updated":
            self._session_ready.set()
            return
        if event_type == "input_audio_buffer.speech_started":
            self._speech_started_at = time.time()
            return
        if event_type == "input_audio_buffer.speech_stopped":
            stopped_at = time.time()
            utterance_ms = None
            if self._speech_started_at is not None:
                utterance_ms = max(0.0, (stopped_at - self._speech_started_at) * 1000.0)
            self._speech_started_at = None
            self._pending_turns.append((stopped_at, utterance_ms))
            return
        if event_type in {
            "conversation.item.input_audio_transcription.completed",
            "conversation.item.audio_transcription.completed",
        }:
            transcript = (event.get("transcript") or "").strip()
            stopped_at = time.time()
            utterance_ms = None
            if self._pending_turns:
                stopped_at, utterance_ms = self._pending_turns.popleft()
            latency_ms = max(0.0, (time.time() - stopped_at) * 1000.0)
            self._results.put(AsrResult(transcript, latency_ms, utterance_ms, stopped_at))
            return
        if event_type in {
            "conversation.item.input_audio_transcription.failed",
            "conversation.item.audio_transcription.failed",
        }:
            error = event.get("error") or {}
            message = error.get("message") or "input transcription failed"
            self._errors.put(RuntimeError(message))
            return
        if event_type == "error":
            error = event.get("error") or {}
            message = error.get("message") or str(event)
            self._errors.put(RuntimeError(message))

    def _session_update_payload(self) -> dict:
        return {
            "type": "session.update",
            "session": {
                "instructions": (
                    "Transcribe the user's speech for robot teleoperation command detection. "
                    "Do not generate assistant responses."
                ),
                "input_audio_format": "pcm16",
                "input_audio_transcription": {"model": self._transcription_model},
                "turn_detection": {
                    "type": "server_vad",
                    "threshold": 0.5,
                    "prefix_padding_ms": VAD_PREFIX_PADDING_MS,
                    "silence_duration_ms": VAD_SILENCE_DURATION_MS,
                    "create_response": False,
                },
                "tools": [],
            },
        }


def parse_asr_backend(value: str | None) -> str:
    backend = (value or "parakeet").strip().lower()
    if backend not in {"parakeet", "azure"}:
        raise ValueError(
            f"unsupported VOICE_ASR_BACKEND={value!r}; expected 'parakeet' or 'azure'"
        )
    return backend


def parse_azure_openai_endpoint(value: str | None) -> str:
    endpoint = (value or "").strip().rstrip("/")
    if not endpoint:
        raise ValueError("AZURE_OPENAI_ENDPOINT is required for VOICE_ASR_BACKEND=azure")
    parsed = urllib.parse.urlparse(endpoint)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ValueError(
            f"AZURE_OPENAI_ENDPOINT must be an absolute http(s) URL, got {value!r}"
        )
    return endpoint


def parse_azure_openai_deployment_name(value: str | None) -> str:
    deployment_name = (value or "").strip()
    if not deployment_name:
        raise ValueError(
            "AZURE_OPENAI_DEPLOYMENT_NAME is required for VOICE_ASR_BACKEND=azure"
        )
    return deployment_name


def parse_azure_openai_api_key(value: str | None) -> str:
    api_key = (value or "").strip()
    if not api_key:
        raise ValueError("AZURE_OPENAI_API_KEY is required for VOICE_ASR_BACKEND=azure")
    return api_key


def build_azure_realtime_uri(endpoint: str, deployment_name: str) -> str:
    parsed = urllib.parse.urlparse(endpoint)
    scheme = "wss" if parsed.scheme == "https" else "ws"
    return urllib.parse.urlunparse(
        (
            scheme,
            parsed.netloc,
            "/openai/v1/realtime",
            "",
            urllib.parse.urlencode({"model": deployment_name}),
            "",
        )
    )


def create_parakeet_asr_engine() -> AsrEngine:
    asr_device = os.environ.get("VOICE_ASR_DEVICE", "cuda")
    asr_model = os.environ.get("VOICE_ASR_MODEL", "nvidia/parakeet-tdt_ctc-0.6b-ja")
    return ParakeetAsrEngine(asr_model, asr_device)


def create_azure_realtime_session() -> AzureRealtimeSession:
    return AzureRealtimeSession(
        endpoint=parse_azure_openai_endpoint(os.environ.get("AZURE_OPENAI_ENDPOINT")),
        api_key=parse_azure_openai_api_key(os.environ.get("AZURE_OPENAI_API_KEY")),
        deployment_name=parse_azure_openai_deployment_name(
            os.environ.get("AZURE_OPENAI_DEPLOYMENT_NAME")
        ),
        transcription_model=(
            os.environ.get("AZURE_OPENAI_TRANSCRIPTION_MODEL", "whisper-1").strip()
            or "whisper-1"
        ),
    )


class VadGate:
    def __init__(self) -> None:
        self._noise_rms = VAD_MIN_RMS
        self._in_speech = False
        self._voiced_run = 0
        self._silence_run = 0
        self._prefix = deque(maxlen=max(1, VAD_PREFIX_PADDING_MS // FRAME_MS))
        self._buffer: list[np.ndarray] = []
        self._start_frames = max(1, math.ceil(VAD_START_SPEECH_MS / FRAME_MS))
        self._end_frames = max(1, math.ceil(VAD_SILENCE_DURATION_MS / FRAME_MS))
        self._min_frames = max(1, math.ceil(VAD_MIN_UTTERANCE_MS / FRAME_MS))
        self._max_frames = max(1, math.ceil(VAD_MAX_UTTERANCE_SEC * 1000 / FRAME_MS))

    def _is_speech(self, frame_i16: np.ndarray) -> bool:
        if frame_i16.size == 0:
            return False
        rms = float(np.sqrt(np.mean(frame_i16.astype(np.float32) ** 2)))
        threshold = max(VAD_MIN_RMS, self._noise_rms * VAD_THRESHOLD_RATIO)
        is_speech = rms >= threshold
        if not is_speech:
            self._noise_rms = 0.92 * self._noise_rms + 0.08 * rms
        return is_speech

    def _flush(self):
        utterance = None
        if len(self._buffer) >= self._min_frames:
            utterance = np.concatenate(self._buffer)
        self._in_speech = False
        self._buffer = []
        self._prefix.clear()
        self._voiced_run = 0
        self._silence_run = 0
        return utterance

    def push(self, frame_i16: np.ndarray):
        """Push one frame. Returns a float32 utterance array when speech ends, else None."""
        frame_f32 = frame_i16.astype(np.float32) / 32768.0
        is_speech = self._is_speech(frame_i16)

        if not self._in_speech:
            self._prefix.append(frame_f32)
            self._voiced_run = self._voiced_run + 1 if is_speech else 0
            if self._voiced_run >= self._start_frames:
                self._in_speech = True
                self._buffer = list(self._prefix)
                self._silence_run = 0
            return None

        self._buffer.append(frame_f32)
        if is_speech:
            self._silence_run = 0
        else:
            self._silence_run += 1

        if len(self._buffer) >= self._max_frames:
            return self._flush()
        if self._silence_run >= self._end_frames:
            return self._flush()
        return None


def capture_frames(capture_dev: str):
    proc = subprocess.Popen(
        [
            "arecord", "-D", capture_dev, "-f", "S16_LE",
            "-c", str(CH_IN), "-r", str(SR), "-t", "raw",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    try:
        while True:
            buf = proc.stdout.read(FRAME_BYTES)
            if not buf or len(buf) < FRAME_BYTES:
                break
            yield np.frombuffer(buf, dtype=np.int16), proc
    finally:
        if proc.poll() is None:
            proc.terminate()
        try:
            proc.wait(timeout=1)
        except Exception:
            pass


def handle_asr_result(
    node: VoiceTeleopNode,
    backend_name: str,
    result: AsrResult,
    last_action_ts: float,
) -> float:
    utterance_end_ts = result.utterance_end_ts or time.time()
    transcript_ready_ts = time.time()
    text = result.text
    cmd = detect_command(text)
    now = time.time()
    published = False
    cmd_latency_ms = (transcript_ready_ts - utterance_end_ts) * 1000.0
    if cmd is not None and now - last_action_ts >= COOLDOWN_SEC:
        node.publish_twist(cmd.linear_x, cmd.angular_z)
        last_action_ts = time.time()
        cmd_latency_ms = (last_action_ts - utterance_end_ts) * 1000.0
        published = True
    node.get_logger().info(
        "asr_result "
        f"backend={backend_name} "
        f"utterance_ms={(result.utterance_ms or 0.0):.1f} "
        f"stt_latency_ms={result.latency_ms:.1f} "
        f"cmd_latency_ms={cmd_latency_ms:.1f} "
        f"published={int(published)} "
        f"command={cmd.name if cmd else '-'} "
        f"transcript={text!r}"
    )
    return last_action_ts


def main_loop_batch(node: VoiceTeleopNode, asr: AsrEngine, vad: VadGate, capture_dev: str) -> None:
    last_action_ts = 0.0
    for frame_i16, _proc in capture_frames(capture_dev):
        utterance = vad.push(frame_i16)
        if utterance is None:
            continue
        utterance_end_ts = time.time()
        try:
            result = asr.transcribe(utterance)
        except Exception as e:
            node.get_logger().warning(f"asr failed: {e}")
            continue
        if result.utterance_ms is None:
            result = AsrResult(
                result.text,
                result.latency_ms,
                len(utterance) * 1000.0 / SR,
                utterance_end_ts,
            )
        last_action_ts = handle_asr_result(node, asr.backend_name, result, last_action_ts)


def main_loop_realtime(
    node: VoiceTeleopNode, azure_session: AzureRealtimeSession, capture_dev: str
) -> None:
    last_action_ts = 0.0
    for frame_i16, _proc in capture_frames(capture_dev):
        azure_session.send_audio_frame(frame_i16)
        while True:
            result = azure_session.poll_result()
            if result is None:
                break
            last_action_ts = handle_asr_result(
                node, azure_session.backend_name, result, last_action_ts
            )
    for _ in range(20):
        drained = False
        while True:
            result = azure_session.poll_result()
            if result is None:
                break
            drained = True
            last_action_ts = handle_asr_result(
                node, azure_session.backend_name, result, last_action_ts
            )
        if not drained:
            azure_session.raise_if_error()
            time.sleep(0.05)


def main() -> None:
    capture_dev = os.environ.get("VOICE_CAPTURE_DEV", "plughw:1,0")
    asr_backend = parse_asr_backend(os.environ.get("VOICE_ASR_BACKEND"))

    rclpy.init()
    node = VoiceTeleopNode()
    spin_thread = threading.Thread(target=rclpy.spin, args=(node,), daemon=True)
    spin_thread.start()

    try:
        node.get_logger().info(f"loading ASR backend={asr_backend}")
        node.get_logger().info(f"capturing from {capture_dev} @ {SR} Hz")
        if asr_backend == "azure":
            azure_session = create_azure_realtime_session()
            node.get_logger().info("connecting Azure OpenAI Realtime session")
            azure_session.start()
            try:
                main_loop_realtime(node, azure_session, capture_dev)
            finally:
                azure_session.close()
        else:
            asr = create_parakeet_asr_engine()
            node.get_logger().info("loading energy VAD")
            vad = VadGate()
            main_loop_batch(node, asr, vad, capture_dev)
    except KeyboardInterrupt:
        node.get_logger().info("stopped by user")
    except Exception as e:
        node.get_logger().error(f"fatal: {e}")
        sys.exit(1)
    finally:
        rclpy.shutdown()


if __name__ == "__main__":
    main()
