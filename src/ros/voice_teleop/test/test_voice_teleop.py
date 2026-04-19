import importlib
import queue
import sys
import threading
import types
from collections import deque
from pathlib import Path


def load_node_module():
    pkg_root = Path(__file__).resolve().parents[1]
    if str(pkg_root) not in sys.path:
        sys.path.insert(0, str(pkg_root))

    geometry_msgs = types.ModuleType("geometry_msgs")
    geometry_msgs_msg = types.ModuleType("geometry_msgs.msg")
    numpy = types.ModuleType("numpy")
    numpy.ndarray = object

    class Twist:
        def __init__(self):
            self.linear = types.SimpleNamespace(x=0.0)
            self.angular = types.SimpleNamespace(z=0.0)

    geometry_msgs_msg.Twist = Twist
    geometry_msgs.msg = geometry_msgs_msg

    rclpy = types.ModuleType("rclpy")
    rclpy.init = lambda: None
    rclpy.shutdown = lambda: None
    rclpy.spin = lambda _node: None

    rclpy_node = types.ModuleType("rclpy.node")

    class Node:
        def __init__(self, _name):
            pass

        def create_publisher(self, *_args, **_kwargs):
            return types.SimpleNamespace(publish=lambda _msg: None)

        def get_logger(self):
            return types.SimpleNamespace(
                info=lambda *_args, **_kwargs: None,
                warning=lambda *_args, **_kwargs: None,
                error=lambda *_args, **_kwargs: None,
            )

    rclpy_node.Node = Node

    sys.modules["numpy"] = numpy
    sys.modules["geometry_msgs"] = geometry_msgs
    sys.modules["geometry_msgs.msg"] = geometry_msgs_msg
    sys.modules["rclpy"] = rclpy
    sys.modules["rclpy.node"] = rclpy_node

    sys.modules.pop("voice_teleop.node", None)
    return importlib.import_module("voice_teleop.node")


def test_detect_command_handles_japanese_and_case_insensitive_english():
    node = load_node_module()

    assert node.detect_command("前進してください").name == "forward"
    assert node.detect_command("RIGHT").name == "right"
    assert node.detect_command("Stop now").name == "stop"
    assert node.detect_command("雑談です") is None


def test_parse_asr_backend_defaults_and_rejects_unknown_values():
    node = load_node_module()

    assert node.parse_asr_backend(None) == "parakeet"
    assert node.parse_asr_backend("Azure") == "azure"

    try:
        node.parse_asr_backend("whisper")
    except ValueError as exc:
        assert "VOICE_ASR_BACKEND" in str(exc)
    else:
        raise AssertionError("expected ValueError for unsupported backend")


def test_parse_azure_openai_env_helpers_and_realtime_uri():
    node = load_node_module()

    assert node.parse_azure_openai_endpoint("https://example.openai.azure.com/") == (
        "https://example.openai.azure.com"
    )
    assert node.parse_azure_openai_deployment_name(" go2-voice ") == "go2-voice"
    assert node.parse_azure_openai_api_key(" secret ") == "secret"
    assert (
        node.build_azure_realtime_uri(
            "https://example.openai.azure.com", "go2-voice"
        )
        == "wss://example.openai.azure.com/openai/v1/realtime?model=go2-voice"
    )

    try:
        node.parse_azure_openai_endpoint("example.openai.azure.com")
    except ValueError as exc:
        assert "AZURE_OPENAI_ENDPOINT" in str(exc)
    else:
        raise AssertionError("expected ValueError for invalid endpoint")


def test_azure_realtime_session_converts_completed_transcripts_to_asr_results():
    node = load_node_module()

    session = node.AzureRealtimeSession.__new__(node.AzureRealtimeSession)
    session._results = queue.Queue()
    session._errors = queue.Queue()
    session._session_ready = threading.Event()
    session._speech_started_at = 100.0
    session._pending_turns = deque()

    original_time = node.time.time
    values = iter([100.6, 100.9, 100.9])
    node.time.time = lambda: next(values)
    try:
        session._handle_server_event({"type": "input_audio_buffer.speech_stopped"})
        session._handle_server_event(
            {
                "type": "conversation.item.input_audio_transcription.completed",
                "transcript": "前進してください",
            }
        )
    finally:
        node.time.time = original_time

    result = session.poll_result()
    assert result is not None
    assert result.text == "前進してください"
    assert abs(result.utterance_ms - 600.0) < 1e-6
    assert result.utterance_end_ts == 100.6
    assert abs(result.latency_ms - 300.0) < 1e-6
