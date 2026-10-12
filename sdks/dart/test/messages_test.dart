// ═════════════════════════════════════════════════════════════════
// OpenHuman Dart SDK — Protocol Tests: messages.dart
//
// Verifies:
//   - ContentBlock union decode (text, structured, multipart)
//   - ParticipantRef encode/decode (snake_case fields)
//   - ParticipantType / MessageStatus enum wire values
//   - OpenHumanMessage full round-trip (via JSON string)
//   - Attachment deserialize
//
// All JSON fixtures are taken verbatim from the Rust server's
// `server/src/model/content.rs` and `server/src/model/identity.rs`
// to guarantee wire-format compatibility.
// ═════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:test/test.dart';
import 'package:openhuman_sdk_dart/openhuman.dart';

void main() {
  // ── ParticipantType enum ───────────────────────────────────────────

  group('ParticipantType wire values', () {
    test('human serializes to "human" via ParticipantRef', () {
      final json = ParticipantRef.human('hum_test').toJson();
      expect(json['participant_type'], 'human');
    });

    test('agent serializes to "agent" via ParticipantRef', () {
      final json = ParticipantRef.agent('agt_test').toJson();
      expect(json['participant_type'], 'agent');
    });

    test('deserializes "human" from ParticipantRef', () {
      final ref = ParticipantRef.fromJson({
        'participant_id': 'hum_test',
        'participant_type': 'human',
      });
      expect(ref.participantType, ParticipantType.human);
    });

    test('deserializes "agent" from ParticipantRef', () {
      final ref = ParticipantRef.fromJson({
        'participant_id': 'agt_test',
        'participant_type': 'agent',
      });
      expect(ref.participantType, ParticipantType.agent);
    });
  });

  // ── MessageStatus enum ────────────────────────────────────────────

  group('MessageStatus wire values', () {
    test('all statuses produce correct wire strings', () {
      // We verify via the OpenHumanMessage.toJson() which uses the
      // generated _$MessageStatusEnumMap.
      for (final status in MessageStatus.values) {
        final msg = OpenHumanMessage(
          id: 'msg_${status.name}',
          conversationId: 'cnv_test',
          sender: ParticipantRef.human('hum_test'),
          content: const ContentBlock.text(text: 'test'),
          status: status,
          createdAt: DateTime.parse('2025-01-01T00:00:00Z'),
        );
        final json = msg.toJson();
        expect(json['status'], status.name,
            reason: '${status.name} should serialize to lowercase');
      }
    });
  });

  // ── ParticipantRef ────────────────────────────────────────────────

  group('ParticipantRef', () {
    test('deserializes snake_case fields from server', () {
      final ref = ParticipantRef.fromJson({
        'participant_id': 'hum_0189abc123',
        'participant_type': 'human',
      });

      expect(ref.participantId, 'hum_0189abc123');
      expect(ref.participantType, ParticipantType.human);
    });

    test('serializes to snake_case', () {
      const ref = ParticipantRef(
        participantId: 'agt_0189def456',
        participantType: ParticipantType.agent,
      );

      final json = ref.toJson();
      expect(json['participant_id'], 'agt_0189def456');
      expect(json['participant_type'], 'agent');
    });

    test('human() factory creates correct type', () {
      final ref = ParticipantRef.human('hum_123');
      expect(ref.participantType, ParticipantType.human);
      expect(ref.participantId, 'hum_123');
    });

    test('agent() factory creates correct type', () {
      final ref = ParticipantRef.agent('agt_456');
      expect(ref.participantType, ParticipantType.agent);
      expect(ref.participantId, 'agt_456');
    });
  });

  // ── ContentBlock union ────────────────────────────────────────────

  group('ContentBlock.text', () {
    test('deserializes from server wire format', () {
      // Exact shape from Rust ContentBlock::Text { text: String }
      final block = ContentBlock.fromJson({
        'type': 'text',
        'text': 'Review the auth module.',
      });

      expect(block, isA<TextContent>());
      expect((block as TextContent).text, 'Review the auth module.');
    });

    test('serializes with type discriminator', () {
      const block = ContentBlock.text(text: 'Hello world');
      final json = block.toJson();

      expect(json['type'], 'text');
      expect(json['text'], 'Hello world');
    });
  });

  group('ContentBlock.structured', () {
    test('deserializes from server wire format', () {
      final block = ContentBlock.fromJson({
        'type': 'structured',
        'schema': {'type': 'object', 'properties': {}},
        'data': {'files': []},
      });

      expect(block, isA<StructuredContent>());
      final structured = block as StructuredContent;
      expect(structured.schema['type'], 'object');
      expect((structured.data as Map)['files'], []);
    });

    test('serializes with type discriminator', () {
      const block = ContentBlock.structured(
        schema: {'type': 'object'},
        data: {'key': 'value'},
      );

      final json = block.toJson();
      expect(json['type'], 'structured');
      expect(json['schema']['type'], 'object');
    });
  });

  group('ContentBlock.multipart', () {
    test('deserializes nested parts', () {
      final block = ContentBlock.fromJson({
        'type': 'multipart',
        'parts': [
          {'type': 'text', 'text': 'Here is the diff:'},
          {
            'type': 'structured',
            'schema': {'type': 'object'},
            'data': {'diff': '...'},
          },
        ],
      });

      expect(block, isA<MultipartContent>());
      final multipart = block as MultipartContent;
      expect(multipart.parts, hasLength(2));
      expect(multipart.parts.first, isA<TextContent>());
      expect(multipart.parts.last, isA<StructuredContent>());
    });
  });

  // ── Attachment ─────────────────────────────────────────────────────

  group('Attachment', () {
    test('deserializes snake_case fields', () {
      final att = Attachment.fromJson({
        'id': 'att_0189xyz',
        'filename': 'auth-review.pdf',
        'content_type': 'application/pdf',
        'size_bytes': 245678,
        'url': 'https://cdn.openhuman.dev/attachments/att_0189xyz',
      });

      expect(att.id, 'att_0189xyz');
      expect(att.filename, 'auth-review.pdf');
      expect(att.contentType, 'application/pdf');
      expect(att.sizeBytes, 245678);
      expect(att.url, 'https://cdn.openhuman.dev/attachments/att_0189xyz');
    });

    test('serializes to snake_case', () {
      const att = Attachment(
        id: 'att_test',
        filename: 'test.txt',
        contentType: 'text/plain',
        sizeBytes: 1024,
        url: 'https://example.com/test.txt',
      );

      final json = att.toJson();
      expect(json['content_type'], 'text/plain');
      expect(json['size_bytes'], 1024);
    });
  });

  // ── OpenHumanMessage full round-trip ──────────────────────────────

  group('OpenHumanMessage', () {
    test('deserializes complete message from server wire format', () {
      // This JSON shape comes from Rust server/src/model/message.rs::Message
      final json = jsonDecode(r'''
        {
          "id": "msg_0189abc123def456789",
          "conversation_id": "cnv_0189abc123def456",
          "sender": {
            "participant_id": "agt_0189def456",
            "participant_type": "agent"
          },
          "content": {
            "type": "text",
            "text": "Review the auth middleware."
          },
          "attachments": [],
          "metadata": {},
          "status": "pending",
          "created_at": "2025-01-15T09:28:00Z"
        }
      ''') as Map<String, dynamic>;

      final msg = OpenHumanMessage.fromJson(json);

      expect(msg.id, 'msg_0189abc123def456789');
      expect(msg.conversationId, 'cnv_0189abc123def456');
      expect(msg.sender.participantId, 'agt_0189def456');
      expect(msg.sender.participantType, ParticipantType.agent);
      expect(msg.content, isA<TextContent>());
      expect((msg.content as TextContent).text, 'Review the auth middleware.');
      expect(msg.attachments, isEmpty);
      expect(msg.status, MessageStatus.pending);
    });

    test('round-trip through JSON string preserves all fields', () {
      // Round-trip via JSON string to ensure the generated code
      // correctly serializes/deserializes nested objects.
      final original = OpenHumanMessage(
        id: 'msg_roundtrip',
        conversationId: 'cnv_roundtrip',
        sender: ParticipantRef.human('hum_roundtrip'),
        content: const ContentBlock.text(text: 'Round trip'),
        attachments: const [],
        metadata: const {'trace_id': 'trace_123'},
        status: MessageStatus.delivered,
        createdAt: DateTime.parse('2025-06-15T12:00:00Z'),
      );

      // Serialize to JSON string, then deserialize.
      final jsonStr = jsonEncode(original.toJson());
      final restored = OpenHumanMessage.fromJson(
        jsonDecode(jsonStr) as Map<String, dynamic>,
      );

      expect(restored.id, original.id);
      expect(restored.conversationId, original.conversationId);
      expect(restored.sender.participantId, original.sender.participantId);
      expect(restored.sender.participantType, original.sender.participantType);
      expect((restored.content as TextContent).text,
          (original.content as TextContent).text);
      expect(restored.metadata['trace_id'], 'trace_123');
      expect(restored.status, original.status);
    });
  });
}
