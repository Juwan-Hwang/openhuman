// ═════════════════════════════════════════════════════════════════
// OpenHuman Dart SDK — Protocol Tests: connection.dart
//
// Since OpenHumanConnection wraps a real WebSocketChannel, we cannot
// test the actual network I/O without a live server. Instead, we
// verify the connection-layer logic that is deterministic and does
// not require a network connection:
//
//   - Initial state (idle)
//   - Stream setup (broadcast streams)
//   - Send when disconnected → StateError
//   - disconnect from idle → disconnected state
//   - dispose closes streams
//
// We explicitly do NOT test connect() with a real WebSocket, because
// that requires a live server and would be flaky in CI. The actual
// WS integration is covered by the Rust server's ws_chain.rs tests.
// ═════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:test/test.dart';
import 'package:openhuman_sdk_dart/openhuman.dart';

void main() {
  late OpenHumanConnection conn;

  setUp(() {
    conn = OpenHumanConnection();
  });

  tearDown(() async {
    try {
      await conn.dispose();
    } catch (_) {}
  });

  // ── Initial state ──────────────────────────────────────────────────

  group('OpenHumanConnection initial state', () {
    test('currentState is idle on creation', () {
      expect(conn.currentState, ConnectionState.idle);
    });

    test('events stream is a broadcast stream (multi-listener)', () {
      // A broadcast stream allows multiple listeners without error.
      final sub1 = conn.events.listen((_) {});
      final sub2 = conn.events.listen((_) {});
      expect(sub1, isNotNull);
      expect(sub2, isNotNull);
      sub1.cancel();
      sub2.cancel();
    });

    test('connectionState stream is a broadcast stream (multi-listener)', () {
      final sub1 = conn.connectionState.listen((_) {});
      final sub2 = conn.connectionState.listen((_) {});
      expect(sub1, isNotNull);
      expect(sub2, isNotNull);
      sub1.cancel();
      sub2.cancel();
    });
  });

  // ── Sending when disconnected ──────────────────────────────────────

  group('Send when disconnected throws StateError', () {
    test('sendReply throws when not connected', () {
      expect(
        () => conn.sendReply('cnv_test', 'hello'),
        throwsStateError,
      );
    });

    test('updatePresence throws when not connected', () {
      expect(
        () => conn.updatePresence(HumanStatus.online),
        throwsStateError,
      );
    });

    test('invokeTool throws when not connected', () {
      expect(
        () => conn.invokeTool(
          conversationId: 'cnv_test',
          invocationId: 'inv_test',
          toolId: 'terminal',
          input: {},
        ),
        throwsStateError,
      );
    });

    test('publishCapabilityManifest throws when not connected', () {
      expect(
        () => conn.publishCapabilityManifest(
          agentId: 'agt_test',
          capabilities: const [],
        ),
        throwsStateError,
      );
    });
  });

  // ── disconnect from idle ──────────────────────────────────────────

  group('disconnect from idle', () {
    test('disconnect transitions to disconnected state', () async {
      // Listen to state changes BEFORE disconnecting.
      final states = <ConnectionState>[];
      final completer = Completer<ConnectionState>();
      final sub = conn.connectionState.listen((state) {
        states.add(state);
        if (state == ConnectionState.disconnected && !completer.isCompleted) {
          completer.complete(state);
        }
      });

      await conn.disconnect();

      // Wait for the state to propagate.
      await completer.future.timeout(const Duration(seconds: 1));

      expect(conn.currentState, ConnectionState.disconnected);
      expect(states, contains(ConnectionState.disconnected));

      await sub.cancel();
    });

    test('disconnect is idempotent — safe to call twice', () async {
      await conn.disconnect();
      // Second call should not throw.
      await conn.disconnect();
      expect(conn.currentState, ConnectionState.disconnected);
    });
  });

  // ── Dispose cleanup ────────────────────────────────────────────────

  group('dispose', () {
    test('dispose closes the events stream', () async {
      final sub = conn.events.listen((_) {});
      await conn.dispose();
      await sub.cancel();
      // After dispose, the stream is closed — listening again
      // should either throw or immediately get a done event.
      // We verify the stream is closed by checking that a new
      // listener receives done immediately.
      final doneCompleter = Completer<bool>();
      try {
        conn.events.listen(
          (_) {},
          onDone: () => doneCompleter.complete(true),
        );
        // If we got here without throwing, the stream is closed
        // and should call onDone immediately.
        final result = await doneCompleter.future
            .timeout(const Duration(seconds: 1));
        expect(result, isTrue);
      } catch (e) {
        // Some implementations throw StateError on closed controllers,
        // which is also acceptable.
        expect(e, isA<StateError>());
      }
    });

    test('dispose closes the connectionState stream', () async {
      final sub = conn.connectionState.listen((_) {});
      await conn.dispose();
      await sub.cancel();

      final doneCompleter = Completer<bool>();
      try {
        conn.connectionState.listen(
          (_) {},
          onDone: () => doneCompleter.complete(true),
        );
        final result = await doneCompleter.future
            .timeout(const Duration(seconds: 1));
        expect(result, isTrue);
      } catch (e) {
        expect(e, isA<StateError>());
      }
    });
  });
}
