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

        def create_timer(self, *_args, **_kwargs):
            return types.SimpleNamespace(cancel=lambda: None)

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
    assert node.detect_command("Stop now").name == "stop"
    assert node.detect_command("RIGHT") is None
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


def make_logger():
    records = {"info": [], "warning": [], "error": []}

    logger = types.SimpleNamespace(
        info=lambda *args, **_kwargs: records["info"].append(args[0] if args else ""),
        warning=lambda *args, **_kwargs: records["warning"].append(args[0] if args else ""),
        error=lambda *args, **_kwargs: records["error"].append(args[0] if args else ""),
    )
    return logger, records


def make_fake_node(node_module):
    logger, records = make_logger()
    published = []

    fake_node = types.SimpleNamespace(
        get_logger=lambda: logger,
        publish_twist=lambda linear_x, angular_z: published.append((linear_x, angular_z)),
        _motion_lock=threading.Lock(),
        _motion_linear_x=0.0,
        _motion_angular_z=0.0,
        _motion_deadline=0.0,
        _stop_publish_remaining=0,
    )
    fake_node._start_stop_burst = lambda immediate: node_module.VoiceTeleopNode._start_stop_burst(
        fake_node, immediate
    )
    fake_node._on_motion_tick = lambda: node_module.VoiceTeleopNode._on_motion_tick(fake_node)
    fake_node.stop_robot = lambda: node_module.VoiceTeleopNode.stop_robot(fake_node)
    fake_node.step_forward = lambda: node_module.VoiceTeleopNode.step_forward(fake_node)
    return fake_node, published, records


def make_session(node_module):
    fake_node, published, records = make_fake_node(node_module)
    session = node_module.AzureRealtimeSession.__new__(node_module.AzureRealtimeSession)
    session._node = fake_node
    session._endpoint = "https://example.openai.azure.com"
    session._api_key = "secret"
    session._deployment_name = "go2-voice"
    session._transcription_model = "whisper-1"
    session._voice = "alloy"
    session._errors = queue.Queue()
    session._thread = None
    session._action_thread = None
    session._loop = None
    session._send_queue = None
    session._ws = None
    session._transport_ready = threading.Event()
    session._session_ready = threading.Event()
    session._closed = threading.Event()
    session._action_queue = queue.Queue()
    session._speech_started_at = None
    session._pending_turns = deque()
    session._pending_calls = {}
    session._response_transcripts = {}
    session._response_audio_transcripts = {}
    session._latest_input_transcript = ""
    session._audio_player = types.SimpleNamespace(write=lambda _audio: None, close=lambda: None)
    session._playback_failed = False
    session._queue_client_event = lambda payload: queued.append(payload)
    queued = []
    return session, fake_node, published, records, queued


def test_azure_realtime_session_payload_enables_tools_and_audio_reply():
    node = load_node_module()
    session, _fake_node, _published, _records, _queued = make_session(node)

    payload = session._session_update_payload()
    session_cfg = payload["session"]
    instructions = session_cfg["instructions"]

    assert session_cfg["type"] == "realtime"
    assert session_cfg["output_modalities"] == ["audio"]
    assert "step_forward" not in instructions
    assert "stop_robot" not in instructions
    assert "tool's description clearly matches the requested action" in instructions
    assert "Whether you call a tool or not, always reply to the user in short Japanese." in instructions
    assert session_cfg["audio"]["input"]["transcription"]["model"] == "whisper-1"
    assert session_cfg["audio"]["input"]["format"] == {"type": "audio/pcm", "rate": 24000}
    assert session_cfg["audio"]["input"]["turn_detection"]["create_response"] is True
    assert session_cfg["audio"]["output"]["voice"] == "alloy"
    assert session_cfg["audio"]["output"]["format"] == {"type": "audio/pcm", "rate": 24000}
    assert [tool["name"] for tool in session_cfg["tools"]] == [
        "step_forward",
        "stop_robot",
    ]


def test_azure_transcript_completion_logs_but_does_not_publish_motion():
    node = load_node_module()
    session, _fake_node, published, records, _queued = make_session(node)
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

    assert published == []
    assert any("azure_input_transcript" in message for message in records["info"])


def test_azure_tool_call_dispatches_step_forward_and_returns_output():
    node = load_node_module()
    session, _fake_node, published, records, queued = make_session(node)
    session._latest_input_transcript = "前進して"

    original_monotonic = node.time.monotonic
    values = iter([10.0, 10.1, 10.2, 10.31, 10.41, 10.51])
    node.time.monotonic = lambda: next(values)
    try:
        session._handle_server_event(
            {
                "type": "response.output_item.done",
                "item": {
                    "id": "item-1",
                    "type": "function_call",
                    "call_id": "call-1",
                    "name": "step_forward",
                    "arguments": "{}",
                    "status": "completed",
                },
            }
        )
        pending = session._action_queue.get_nowait()
        output = session._execute_tool_call(pending)
        for _ in range(4):
            session._node._on_motion_tick()
        session._queue_client_event(
            {
                "type": "conversation.item.create",
                "item": {
                    "type": "function_call_output",
                    "call_id": pending.call_id,
                    "output": node.json.dumps(output, ensure_ascii=True),
                },
            }
        )
        session._queue_followup_response()
    finally:
        node.time.monotonic = original_monotonic

    assert published == [
        (node.LINEAR_SPEED, 0.0),
        (node.LINEAR_SPEED, 0.0),
        (node.LINEAR_SPEED, 0.0),
        (0.0, 0.0),
        (0.0, 0.0),
    ]
    assert any("azure_tool_call_completed name=step_forward" in message for message in records["info"])
    assert queued[0]["item"]["call_id"] == "call-1"
    assert queued[1] == {
        "type": "response.create",
        "response": {"output_modalities": ["audio"]},
    }


def test_azure_function_call_argument_deltas_are_accumulated_before_dispatch():
    node = load_node_module()
    session, _fake_node, _published, _records, _queued = make_session(node)

    session._handle_server_event(
        {
            "type": "response.output_item.added",
            "item": {"id": "item-1", "type": "function_call", "call_id": "call-1", "name": "stop_robot"},
        }
    )
    session._handle_server_event(
        {
            "type": "response.function_call_arguments.delta",
            "item_id": "item-1",
            "delta": "{",
        }
    )
    session._handle_server_event(
        {
            "type": "response.function_call_arguments.done",
            "item_id": "item-1",
            "arguments": "{}",
        }
    )

    assert session._action_queue.empty()
    pending = session._pending_calls["item-1"]
    assert pending.name == "stop_robot"
    assert pending.arguments_json == "{}"


def test_stop_robot_tool_publishes_zero_twist():
    node = load_node_module()
    session, _fake_node, published, records, _queued = make_session(node)

    output = session._execute_tool_call(
        node.PendingToolCall(call_id="call-2", name="stop_robot", arguments_json="{}")
    )
    session._node._on_motion_tick()
    session._node._on_motion_tick()

    assert published == [(0.0, 0.0), (0.0, 0.0), (0.0, 0.0)]
    assert output["executed"] == "stop_robot"
    assert any("azure_tool_call_completed name=stop_robot" in message for message in records["info"])


def test_step_forward_tool_runs_even_for_non_movement_transcript():
    node = load_node_module()
    session, _fake_node, published, records, _queued = make_session(node)
    session._latest_input_transcript = "こんにちは"

    original_monotonic = node.time.monotonic
    values = iter([20.0, 20.1, 20.2, 20.31, 20.41, 20.51])
    node.time.monotonic = lambda: next(values)
    try:
        output = session._execute_tool_call(
            node.PendingToolCall(call_id="call-3", name="step_forward", arguments_json="{}")
        )
        for _ in range(4):
            session._node._on_motion_tick()
    finally:
        node.time.monotonic = original_monotonic

    assert published == [
        (node.LINEAR_SPEED, 0.0),
        (node.LINEAR_SPEED, 0.0),
        (node.LINEAR_SPEED, 0.0),
        (0.0, 0.0),
        (0.0, 0.0),
    ]
    assert output["ok"] is True
    assert output["executed"] == "step_forward"
    assert any("azure_tool_call_completed name=step_forward" in message for message in records["info"])


def test_step_forward_can_be_interrupted_by_stop_robot():
    node = load_node_module()
    fake_node, published, _records = make_fake_node(node)

    original_monotonic = node.time.monotonic
    values = iter([30.0, 30.1, 30.2])
    node.time.monotonic = lambda: next(values)
    try:
        fake_node.step_forward()
        fake_node._on_motion_tick()
        fake_node.stop_robot()
        fake_node._on_motion_tick()
    finally:
        node.time.monotonic = original_monotonic

    assert published == [
        (node.LINEAR_SPEED, 0.0),
        (node.LINEAR_SPEED, 0.0),
        (0.0, 0.0),
        (0.0, 0.0),
    ]


def test_handle_asr_result_uses_shared_actions_for_parakeet():
    node = load_node_module()
    fake_node, published, records = make_fake_node(node)

    last_action_ts = node.handle_asr_result(
        fake_node,
        "parakeet",
        node.AsrResult("前進してください", latency_ms=12.0, utterance_ms=400.0, utterance_end_ts=1.0),
        last_action_ts=0.0,
    )

    assert last_action_ts > 0.0
    assert published == [(node.LINEAR_SPEED, 0.0)]
    assert any("action=step_forward" in message for message in records["info"])


def test_handle_asr_result_ignores_removed_parakeet_commands():
    node = load_node_module()
    fake_node, published, records = make_fake_node(node)

    last_action_ts = node.handle_asr_result(
        fake_node,
        "parakeet",
        node.AsrResult("右へ", latency_ms=12.0, utterance_ms=400.0, utterance_end_ts=1.0),
        last_action_ts=0.0,
    )

    assert last_action_ts == 0.0
    assert published == []
    assert any("command=-" in message and "action=-" in message for message in records["info"])


def test_azure_tool_call_is_dispatched_only_after_output_item_done():
    node = load_node_module()
    session, _fake_node, _published, _records, _queued = make_session(node)

    session._handle_server_event(
        {
            "type": "response.function_call_arguments.done",
            "item_id": "item-1",
            "call_id": "call-1",
            "name": "step_forward",
            "arguments": "{}",
        }
    )
    assert session._action_queue.empty()
    session._handle_server_event(
        {
            "type": "response.output_item.done",
            "item": {
                "id": "item-1",
                "type": "function_call",
                "call_id": "call-1",
                "name": "step_forward",
                "arguments": "{}",
                "status": "completed",
            },
        }
    )

    pending = session._action_queue.get_nowait()
    assert pending.call_id == "call-1"
    assert pending.name == "step_forward"
    assert pending.arguments_json == "{}"
    assert "item-1" not in session._pending_calls


def test_response_audio_delta_is_forwarded_to_player():
    node = load_node_module()
    session, _fake_node, _published, _records, _queued = make_session(node)
    captured = []
    session._audio_player = types.SimpleNamespace(
        write=lambda audio: captured.append(audio), close=lambda: None
    )

    session._handle_server_event(
        {
            "type": "response.output_audio.delta",
            "delta": "AQI=",
        }
    )

    assert captured == [b"\x01\x02"]
