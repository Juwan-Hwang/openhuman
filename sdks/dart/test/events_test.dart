// ═════════════════════════════════════════════════════════════════
// OpenHuman Dart SDK — Protocol Tests: events.dart
//
// Verifies:
//   - OpenHumanEvent envelope deserialize
//   - EventType enum ↔ wire string mapping (snake_case)
//   - SessionConnectedData / MessageReceivedData / ReplyDeliveredData
//   - CapabilityUpdatedData / ToolResultData / ErrorData
//   - Client → Server message toWireJson (reply.send, presence.update,
//     capability.manifest, tool.invoke)
//
// All JSON fixtures are taken verbatim from the Rust server's
// `server/src/ws/protocol.rs` event builders to guarantee wire-format
// compatibility.
// ═════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:test/test.dart';
import 'package:openhuman_sdk_dart/openhuman.dart';

void main() {
  // ── EventType ↔ wire string ──────────────────────────────────────

  group('EventType wire mapping', () {
    test('sessionConnected ↔ "session.connected"', () {
      expect(EventType.sessionConnected.wireName, 'session.connected');
      expect(
        EventTypeX.fromWireName('session.connected'),
        EventType.sessionConnected,
      );
    });

    test('messageReceived ↔ "message.received"', () {
      expect(EventType.messageReceived.wireName, 'message.received');
      expect(
        EventTypeX.fromWireName('message.received'),
        EventType.messageReceived,
      );
    });

    test('replyDelivered ↔ "reply.delivered"', () {
      expect(EventType.replyDelivered.wireName, 'reply.delivered');
      expect(
        EventTypeX.fromWireName('reply.delivered'),
        EventType.replyDelivered,
      );
    });

    test('capabilityUpdated ↔ "capability.updated"', () {
      expect(EventType.capabilityUpdated.wireName, 'capability.updated');
      expect(
        EventTypeX.fromWireName('capability.updated'),
        EventType.capabilityUpdated,
      );
    });

    test('toolResult ↔ "tool.result"', () {
      expect(EventType.toolResult.wireName, 'tool.result');
      expect(
        EventTypeX.fromWireName('tool.result'),
        EventType.toolResult,
      );
    });

    test('error ↔ "error"', () {
      expect(EventType.error.wireName, 'error');
      expect(
        EventTypeX.fromWireName('error'),
        EventType.error,
      );
    });

    test('unknown wire name returns null (forward-compatible)', () {
      expect(EventTypeX.fromWireName('future.event'), isNull);
      expect(EventTypeX.fromWireName(null), isNull);
    });

    test('all six event types have unique wire names', () {
      final names = EventType.values.map((e) => e.wireName).toSet();
      expect(names.length, EventType.values.length);
    });
  });

  // ── OpenHumanEvent envelope ──────────────────────────────────────

  group('OpenHumanEvent envelope deserialize', () {
    test('deserializes message.received envelope from server wire format', () {
      // This JSON is exactly what server/src/ws/protocol.rs::message_received
      // produces (via serde_json::to_string on the Event struct).
      final json = jsonDecode(r'''
        {
          "event_id": "evt_0189abc123",
          "event_type": "message.received",
          "conversation_id": "cnv_0189abc123def456",
          "timestamp": "2025-01-15T09:28:00.123Z",
          "data": {
            "message_id": "msg_0189def456",
            "sender_id": "agt_demo_codex",
            "sender_type": "agent",
            "text": "Review the auth module."
          }
        }
      ''') as Map<String, dynamic>;

      final event = OpenHumanEvent.fromJson(json);

      expect(event.eventId, 'evt_0189abc123');
      expect(event.eventType, 'message.received');
      expect(event.conversationId, 'cnv_0189abc123def456');
      expect(event.timestamp, DateTime.parse('2025-01-15T09:28:00.123Z'));
      expect(event.data['message_id'], 'msg_0189def456');
    });

    test('deserializes session.connected envelope', () {
      final json = jsonDecode(r'''
        {
          "event_id": "evt_001",
          "event_type": "session.connected",
          "conversation_id": "hum_demo_alice",
          "timestamp": "2025-01-15T09:00:00Z",
          "data": {
            "human_id": "hum_demo_alice",
            "display_name": "Alice Chen"
          }
        }
      ''') as Map<String, dynamic>;

      final event = OpenHumanEvent.fromJson(json);

      expect(event.eventType, 'session.connected');
      expect(event.conversationId, 'hum_demo_alice');
      expect(event.data['human_id'], 'hum_demo_alice');
      expect(event.data['display_name'], 'Alice Chen');
    });

    test('round-trip: fromJson → toJson preserves all fields', () {
      final original = <String, dynamic>{
        'event_id': 'evt_roundtrip',
        'event_type': 'error',
        'conversation_id': 'cnv_test',
        'timestamp': '2025-06-15T12:00:00.000Z',
        'data': {'code': 'tool_not_found', 'message': 'Tool not found'},
      };

      final event = OpenHumanEvent.fromJson(original);
      final roundTripped = event.toJson();

      expect(roundTripped['event_id'], original['event_id']);
      expect(roundTripped['event_type'], original['event_type']);
      expect(roundTripped['conversation_id'], original['conversation_id']);
      expect(roundTripped['data']['code'], 'tool_not_found');
    });
  });

  // ── SessionConnectedData ──────────────────────────────────────────

  group('SessionConnectedData', () {
    test('deserializes snake_case fields from server', () {
      final data = SessionConnectedData.fromJson({
        'human_id': 'hum_demo_alice',
        'display_name': 'Alice Chen',
      });

      expect(data.humanId, 'hum_demo_alice');
      expect(data.displayName, 'Alice Chen');
    });

    test('serializes back to snake_case', () {
      const data = SessionConnectedData(
        humanId: 'hum_123',
        displayName: 'Test Human',
      );

      final json = data.toJson();
      expect(json['human_id'], 'hum_123');
      expect(json['display_name'], 'Test Human');
    });
  });

  // ── MessageReceivedData ────────────────────────────────────────────

  group('MessageReceivedData', () {
    test('deserializes from server wire format', () {
      // Exact payload from protocol.rs::message_received, plus the
      // conversation_id the client injects from the event envelope.
      final data = MessageReceivedData.fromJson({
        'conversation_id': 'cnv_0189abc123',
        'message_id': 'msg_0189def456',
        'sender_id': 'agt_demo_codex',
        'sender_type': 'agent',
        'text': 'Review the auth module.',
      });

      expect(data.messageId, 'msg_0189def456');
      expect(data.senderId, 'agt_demo_codex');
      expect(data.senderType, 'agent');
      expect(data.text, 'Review the auth module.');
    });

    test('serializes to snake_case', () {
      const data = MessageReceivedData(
        conversationId: 'cnv_test',
        messageId: 'msg_test',
        senderId: 'agt_test',
        senderType: 'agent',
        text: 'Hello',
      );

      final json = data.toJson();
      expect(json['message_id'], 'msg_test');
      expect(json['sender_id'], 'agt_test');
      expect(json['sender_type'], 'agent');
      expect(json['text'], 'Hello');
    });
  });

  // ── ReplyDeliveredData ─────────────────────────────────────────────

  group('ReplyDeliveredData', () {
    test('deserializes delivered=true', () {
      final data = ReplyDeliveredData.fromJson({'delivered': true});
      expect(data.delivered, isTrue);
    });

    test('deserializes delivered=false', () {
      final data = ReplyDeliveredData.fromJson({'delivered': false});
      expect(data.delivered, isFalse);
    });
  });

  // ── CapabilityUpdatedData ──────────────────────────────────────────

  group('CapabilityUpdatedData', () {
    test('deserializes with capabilities array and null context', () {
      final data = CapabilityUpdatedData.fromJson({
        'agent_id': 'agt_demo_codex',
        'capabilities': [
          {'id': 'github_create_issue', 'name': 'Create GitHub Issue'},
        ],
        'context': null,
      });

      expect(data.agentId, 'agt_demo_codex');
      expect(data.capabilities, hasLength(1));
      expect(data.capabilities.first['id'], 'github_create_issue');
      expect(data.context, isNull);
    });

    test('deserializes with empty capabilities and context object', () {
      final data = CapabilityUpdatedData.fromJson({
        'agent_id': 'agt_test',
        'capabilities': [],
        'context': {'system_prompt': 'You are a coding assistant.'},
      });

      expect(data.capabilities, isEmpty);
      expect(data.context?['system_prompt'], 'You are a coding assistant.');
    });
  });

  // ── ToolResultData ─────────────────────────────────────────────────

  group('ToolResultData', () {
    test('deserializes success result', () {
      final data = ToolResultData.fromJson({
        'invocation_id': 'inv_0189abc',
        'tool_id': 'github_create_issue',
        'status': 'success',
        'output': {'issue_number': 42},
        'error': null,
      });

      expect(data.invocationId, 'inv_0189abc');
      expect(data.toolId, 'github_create_issue');
      expect(data.status, 'success');
      expect((data.output as Map)['issue_number'], 42);
      expect(data.error, isNull);
    });

    test('deserializes error result', () {
      final data = ToolResultData.fromJson({
        'invocation_id': 'inv_0189err',
        'tool_id': 'terminal',
        'status': 'error',
        'output': null,
        'error': 'Permission denied',
      });

      expect(data.status, 'error');
      expect(data.error, 'Permission denied');
    });
  });

  // ── ErrorData ──────────────────────────────────────────────────────

  group('ErrorData', () {
    test('deserializes error event payload', () {
      final data = ErrorData.fromJson({
        'code': 'tool_not_found',
        'message': 'Tool not found in manifest.',
      });

      expect(data.code, 'tool_not_found');
      expect(data.message, 'Tool not found in manifest.');
    });
  });

  // ── Client → Server: toWireJson ────────────────────────────────────

  group('ReplySend toWireJson', () {
    test('produces exact wire format with event_type tag', () {
      const msg = ReplySend(
        conversationId: 'cnv_0189abc',
        text: 'Looks good, ship it!',
      );

      final wire = msg.toWireJson();

      expect(wire['event_type'], 'reply.send');
      expect(wire['conversation_id'], 'cnv_0189abc');
      expect(wire['text'], 'Looks good, ship it!');
      expect(wire.length, 3);
    });

    test('JSON encoding matches Rust ClientMessage::ReplySend', () {
      const msg = ReplySend(conversationId: 'cnv_test', text: 'Hello');
      final encoded = jsonEncode(msg.toWireJson());

      // This is exactly what the Rust server's serde parses:
      // {"event_type":"reply.send","conversation_id":"cnv_test","text":"Hello"}
      expect(encoded,
          '{"event_type":"reply.send","conversation_id":"cnv_test","text":"Hello"}');
    });
  });

  group('PresenceUpdate toWireJson', () {
    test('produces wire format with event_type tag', () {
      const msg = PresenceUpdate(status: 'online');

      final wire = msg.toWireJson();

      expect(wire['event_type'], 'presence.update');
      expect(wire['status'], 'online');
    });
  });

  group('CapabilityManifest toWireJson', () {
    test('produces wire format with capabilities array', () {
      const msg = CapabilityManifest(
        agentId: 'agt_demo_codex',
        capabilities: [
          {'id': 'terminal', 'name': 'Terminal'},
        ],
      );

      final wire = msg.toWireJson();

      expect(wire['event_type'], 'capability.manifest');
      expect(wire['agent_id'], 'agt_demo_codex');
      expect(wire['capabilities'], hasLength(1));
      // context should be omitted when null
      expect(wire.containsKey('context'), isFalse);
    });

    test('includes context when provided', () {
      const msg = CapabilityManifest(
        agentId: 'agt_demo_codex',
        capabilities: [],
        context: {'system_prompt': 'You are a coding assistant.'},
      );

      final wire = msg.toWireJson();

      expect(wire['context']['system_prompt'], 'You are a coding assistant.');
    });
  });

  group('ToolInvokeMessage toWireJson', () {
    test('produces exact wire format', () {
      const msg = ToolInvokeMessage(
        conversationId: 'cnv_0189abc',
        invocationId: 'inv_0189def',
        toolId: 'github_create_issue',
        input: {'repo': 'openhuman/openhuman', 'title': 'Bug: login fails'},
      );

      final wire = msg.toWireJson();

      expect(wire['event_type'], 'tool.invoke');
      expect(wire['conversation_id'], 'cnv_0189abc');
      expect(wire['invocation_id'], 'inv_0189def');
      expect(wire['tool_id'], 'github_create_issue');
      expect((wire['input'] as Map)['repo'], 'openhuman/openhuman');
    });

    test('carries companion text when provided', () {
      const msg = ToolInvokeMessage(
        conversationId: 'cnv_1',
        invocationId: 'inv_1',
        toolId: 'Bash',
        input: {'command': 'ls'},
        text: 'run this and tell them I am here',
      );

      final wire = msg.toWireJson();
      expect(wire['text'], 'run this and tell them I am here');
    });

    test('omits text when absent', () {
      const msg = ToolInvokeMessage(
        conversationId: 'cnv_1',
        invocationId: 'inv_1',
        toolId: 'Bash',
        input: {},
      );

      expect(msg.toWireJson().containsKey('text'), isFalse);
    });
  });

  group('ReplySend toWireJson', () {
    test('carries invocation_id for async turns', () {
      const msg = ReplySend(
        conversationId: 'cnv_1',
        text: 'done',
        invocationId: 'inv_async_1',
      );

      final wire = msg.toWireJson();
      expect(wire['event_type'], 'reply.send');
      expect(wire['invocation_id'], 'inv_async_1');
    });

    test('omits invocation_id for blocking turns', () {
      const msg = ReplySend(conversationId: 'cnv_1', text: 'done');

      expect(msg.toWireJson().containsKey('invocation_id'), isFalse);
    });
  });

  group('AsyncInvocationCreatedData', () {
    test('deserializes from server wire format', () {
      final data = AsyncInvocationCreatedData.fromJson({
        'conversation_id': 'cnv_1',
        'invocation_id': 'inv_async_1',
      });

      expect(data.conversationId, 'cnv_1');
      expect(data.invocationId, 'inv_async_1');
    });

    test('EventTypeX round-trips the wire name', () {
      expect(
        EventTypeX.fromWireName('async.invocation.created'),
        EventType.asyncInvocationCreated,
      );
      expect(
        EventType.asyncInvocationCreated.wireName,
        'async.invocation.created',
      );
    });
  });
}
