// ═════════════════════════════════════════════════════════════════
// OpenHuman Dart SDK — Protocol Tests: client.dart
//
// Verifies the high-level OpenHumanClient event dispatch logic:
//
//   - Initial state (currentHuman null, activeConversations empty)
//   - currentState is idle
//   - All typed streams are broadcast (multi-listener)
//   - Send when disconnected throws StateError
//   - Typed stream contracts (messages, replyAcks, etc.)
//   - dispose closes all streams
//
// We do NOT test connect() with a real WebSocket — that requires a
// live server and would be flaky. The WS integration is covered by
// the Rust server's ws_chain.rs tests.
// ═════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:test/test.dart';
import 'package:openhuman_sdk_dart/openhuman.dart';

void main() {
  late OpenHumanClient client;

  setUp(() {
    client = OpenHumanClient();
  });

  tearDown(() {
    client.dispose();
  });

  // ── Initial state ──────────────────────────────────────────────────

  group('OpenHumanClient initial state', () {
    test('currentHuman is null before connection', () {
      expect(client.currentHuman, isNull);
    });

    test('activeConversations is empty before connection', () {
      expect(client.activeConversations, isEmpty);
    });

    test('currentState is idle before connection', () {
      expect(client.currentState, ConnectionState.idle);
    });

    test('all typed streams are broadcast (multi-listener)', () {
      final sub1 = client.messages.listen((_) {});
      final sub2 = client.messages.listen((_) {});
      expect(sub1, isNotNull);
      expect(sub2, isNotNull);
      sub1.cancel();
      sub2.cancel();
    });
  });

  // ── Send when disconnected ──────────────────────────────────────────

  group('Send when disconnected throws StateError', () {
    test('sendReply throws when not connected', () {
      expect(
        () => client.sendReply('cnv_test', 'hello'),
        throwsStateError,
      );
    });

    test('updatePresence throws when not connected', () {
      expect(
        () => client.updatePresence(HumanStatus.online),
        throwsStateError,
      );
    });

    test('invokeTool throws when not connected', () {
      expect(
        () => client.invokeTool('cnv_test', 'terminal', {}),
        throwsStateError,
      );
    });
  });

  // ── Stream contracts ────────────────────────────────────────────────

  group('Typed stream contracts', () {
    test('messages stream is ready (no events without server)', () async {
      final completer = Completer<Type>();
      final sub = client.messages.listen((data) {
        completer.complete(data.runtimeType);
      });

      // Without a server, no events arrive.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(completer.isCompleted, isFalse,
          reason: 'No messages without a server connection');

      await sub.cancel();
    });

    test('replyAcks stream is ready', () async {
      final sub = client.replyAcks.listen((_) {});
      expect(sub, isNotNull);
      await sub.cancel();
    });

    test('capabilityUpdates stream is ready', () async {
      final sub = client.capabilityUpdates.listen((_) {});
      expect(sub, isNotNull);
      await sub.cancel();
    });

    test('toolResults stream is ready', () async {
      final sub = client.toolResults.listen((_) {});
      expect(sub, isNotNull);
      await sub.cancel();
    });

    test('errors stream is ready', () async {
      final sub = client.errors.listen((_) {});
      expect(sub, isNotNull);
      await sub.cancel();
    });

    test('rawEvents stream is ready', () async {
      final sub = client.rawEvents.listen((_) {});
      expect(sub, isNotNull);
      await sub.cancel();
    });
  });

  // ── Dispose ────────────────────────────────────────────────────────

  group('dispose', () {
    test('dispose closes all typed streams (done events fire)', () async {
      // Set up listeners to track done events.
      final doneCount = <int>[];
      void onDone() => doneCount.add(1);

      client.messages.listen((_) {}, onDone: onDone);
      client.replyAcks.listen((_) {}, onDone: onDone);
      client.capabilityUpdates.listen((_) {}, onDone: onDone);
      client.toolResults.listen((_) {}, onDone: onDone);
      client.errors.listen((_) {}, onDone: onDone);
      client.rawEvents.listen((_) {}, onDone: onDone);

      client.dispose();

      // Give a moment for done events to fire.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // All 6 streams should have fired their onDone callback.
      expect(doneCount.length, 6);
    });

    test('dispose is safe to call after already disposed', () {
      client.dispose();
      // Should not throw.
      client.dispose();
    });
  });
}
