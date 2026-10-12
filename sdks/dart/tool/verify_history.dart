// Verifies the history path without a UI: connect, then fetch
// conversations and messages over HTTP.
//
// Run:  dart run tool/verify_history.dart <ws-url> <api-key>
// e.g.  dart run tool/verify_history.dart ws://localhost:8080/ws ohk_demo_alice_codex

import 'package:openhuman_sdk_dart/openhuman.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    print('usage: dart run tool/verify_history.dart <ws-url> <api-key>');
    return;
  }
  final url = args[0];
  final apiKey = args[1];

  final client = OpenHumanClient();

  print('connecting to $url ...');
  await client.connect(url, apiKey);

  // Give the socket a moment to reach "connected".
  for (var i = 0; i < 120 && client.currentState != ConnectionState.connected; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  print('state: ${client.currentState.name}');

  try {
    final conversations = await client.fetchConversations();
    print('conversations: ${conversations.length}');
    for (final c in conversations.take(3)) {
      print('  ${c.id}  last=${c.lastMessageAt}');
    }

    if (conversations.isNotEmpty) {
      final first = conversations.first;
      final messages = await client.fetchMessages(first.id, limit: 5);
      print('messages in ${first.id}: ${messages.length}');
      for (final m in messages.take(5)) {
        print('  [${m.senderType}] ${m.text.replaceAll("\n", " ")}'
            '${m.images.isEmpty ? "" : "  (+${m.images.length} img)"}');
      }
    }
  } catch (e, st) {
    print('FAILED: $e');
    print(st);
  }

  await client.disconnect();
  client.dispose();
}
