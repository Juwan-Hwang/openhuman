// Verifies renaming and the trash over the real API.
//
// Run:  dart run tool/verify_manage.dart <ws-url> <api-key> <agent-id>
import 'package:openhuman_sdk_dart/openhuman.dart';

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    print('usage: dart run tool/verify_manage.dart <ws-url> <api-key> <agent-id>');
    return;
  }
  final client = OpenHumanClient();
  await client.connect(args[0], args[1]);

  for (var i = 0;
      i < 120 && client.currentState != ConnectionState.connected;
      i++) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  print('state: ${client.currentState.name}');

  final agentId = args[2];

  // Rename, then put it back.
  final ok = await client.renameAgent(agentId, '临时改名验证');
  print('rename -> $ok');
  final live = await client.fetchConversations(limit: 3);
  print('name now: ${live.first.agentName}');
  await client.renameAgent(agentId, 'Codex Workspace');
  final after = await client.fetchConversations(limit: 3);
  print('restored: ${after.first.agentName}');

  // Trash a conversation and bring it back.
  final target = live.first.id;
  print('trashing $target');
  print('delete   -> ${await client.deleteConversation(target)}');
  final trash = await client.fetchTrash();
  print('in trash -> ${trash.any((c) => c.id == target)}');
  print('restore  -> ${await client.restoreConversation(target)}');
  final trash2 = await client.fetchTrash();
  print('still in trash -> ${trash2.any((c) => c.id == target)}');

  await client.disconnect();
  client.dispose();
}
