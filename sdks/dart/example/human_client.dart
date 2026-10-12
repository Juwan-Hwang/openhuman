// ═════════════════════════════════════════════════════════════════
// OpenHuman Dart SDK — Example: Human Client
//
// Demonstrates:
//   - Connecting to an OpenHuman server via WebSocket
//   - Receiving agent messages
//   - Sending human replies
//   - Listening to connection state changes
//   - Clean disconnect
//
// Usage:
//   dart run example/human_client.dart
//
// Prerequisites:
//   - OpenHuman server running on ws://localhost:8080
//   - API key: ohk_demo_alice_codex (seeded in MemoryStore)
// ═════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';
import 'package:openhuman_sdk_dart/openhuman.dart';

void main() async {
  final client = OpenHumanClient();

  // ── Listen to connection state ────────────────────────────────────
  client.connectionState.listen((state) {
    print('[connection] $state');
  });

  // ── Listen for incoming agent messages ───────────────────────────
  client.messages.listen((msg) {
    print('[message] from ${msg.senderId} (${msg.senderType}):');
    print('  ${msg.text}');
    print('  conversation: (tracked by client)');
    print('');
  });

  // ── Listen for reply delivery acks ────────────────────────────────
  client.replyAcks.listen((ack) {
    print('[reply.delivered] delivered=${ack.delivered}');
  });

  // ── Listen for errors ─────────────────────────────────────────────
  client.errors.listen((err) {
    print('[error] ${err.code}: ${err.message}');
  });

  // ── Connect ───────────────────────────────────────────────────────
  const url = 'ws://localhost:8080/ws';
  const apiKey = 'ohk_demo_alice_codex';

  print('Connecting to $url ...');
  await client.connect(url, apiKey);

  // Wait for session.connected to arrive.
  // The connection state transitions to `connected` when the server
  // sends the first frame.
  await client.connectionState
      .firstWhere((s) => s == ConnectionState.connected)
      .timeout(const Duration(seconds: 10));

  print('');
  print('Connected as ${client.currentHuman?.displayName} '
      '(${client.currentHuman?.id})');
  print('Active conversations: ${client.activeConversations}');
  print('');
  print('Waiting for messages... Press Ctrl+C to disconnect.');
  print('');

  // ── Keep the program alive ────────────────────────────────────────
  // In a real app, the Flutter framework keeps the client alive.
  // For this CLI example, we wait until the user presses Ctrl+C.
  final stopCompleter = Completer<void>();

  // Handle Ctrl+C.
  final sigSub = ProcessSignal.sigint.watch().listen((_) {
    if (!stopCompleter.isCompleted) {
      stopCompleter.complete();
    }
  });

  await stopCompleter.future;

  await sigSub.cancel();

  // ── Disconnect cleanly ────────────────────────────────────────────
  print('');
  print('Disconnecting...');
  await client.disconnect();
  client.dispose();

  print('Goodbye.');
}
