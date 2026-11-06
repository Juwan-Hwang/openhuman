// Bulk actions: many conversations to the trash at once, undo, restore
// everything, empty the trash; and the swipe row that drives them on a
// phone.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

import 'package:openhuman_client/core/sdk_provider.dart';
import 'package:openhuman_client/features/chat/conversation_sidebar.dart';
import 'package:openhuman_client/widgets/swipe_actions.dart';

class _Server extends oh.OpenHumanClient {
  final trashed = <String>{};
  final destroyed = <String>{};

  /// Ids the server refuses to touch.
  final refuse = <String>{};

  @override
  Future<bool> deleteConversation(String conversationId) async {
    if (refuse.contains(conversationId)) return false;
    trashed.add(conversationId);
    return true;
  }

  @override
  Future<bool> restoreConversation(String conversationId) async {
    if (refuse.contains(conversationId)) return false;
    return trashed.remove(conversationId);
  }

  @override
  Future<bool> deleteConversationPermanently(String conversationId) async {
    if (refuse.contains(conversationId)) return false;
    trashed.remove(conversationId);
    destroyed.add(conversationId);
    return true;
  }

  @override
  Future<List<oh.HistoryConversation>> fetchTrash({int limit = 50}) async => [
        for (final id in trashed)
          oh.HistoryConversation(id: id, agentId: 'agt_$id', agentName: id),
      ];

  @override
  Future<List<oh.HistoryConversation>> fetchConversations({
    int limit = 50,
  }) async =>
      const [];
}

ConversationInfo _c(String id) =>
    ConversationInfo(id: id, agentId: 'agt_$id', agentName: id);

void main() {
  test('several rows go to the trash at once; refused ones stay', () async {
    final server = _Server()..refuse.add('c');
    final box = ProviderContainer(
      overrides: [openHumanClientProvider.overrideWithValue(server)],
    );
    addTearDown(box.dispose);
    final list = box.read(conversationListProvider.notifier);
    for (final id in ['c', 'b', 'a']) {
      list.add(_c(id));
    }

    final n = await list.trashMany(['a', 'b', 'c']);

    expect(n, 2);
    expect(server.trashed, {'a', 'b'});
    expect(box.read(conversationListProvider).entries.map((c) => c.id), ['c']);
  });

  test('undo puts the row back where it was', () async {
    final server = _Server();
    final box = ProviderContainer(
      overrides: [openHumanClientProvider.overrideWithValue(server)],
    );
    addTearDown(box.dispose);
    final list = box.read(conversationListProvider.notifier);
    for (final id in ['c', 'b', 'a']) {
      list.add(_c(id));
    }
    final b = box.read(conversationListProvider).entries[1];

    await list.trash('b');
    expect(box.read(conversationListProvider).entries.map((c) => c.id),
        ['a', 'c']);
    await list.untrash(b, at: 1);

    expect(box.read(conversationListProvider).entries.map((c) => c.id),
        ['a', 'b', 'c']);
    expect(server.trashed, isEmpty);
  });

  test('restore all and empty the trash', () async {
    final server = _Server()..trashed.addAll(['x', 'y', 'z']);
    final box = ProviderContainer(
      overrides: [openHumanClientProvider.overrideWithValue(server)],
    );
    addTearDown(box.dispose);
    final trash = box.read(trashListProvider.notifier);
    await trash.refresh();
    expect(box.read(trashListProvider).entries, hasLength(3));

    server.refuse.add('z');
    expect(await trash.restoreAll(), 2);
    expect(box.read(conversationListProvider).entries.map((c) => c.id).toSet(),
        {'x', 'y'});
    expect(box.read(trashListProvider).entries.map((c) => c.id), ['z']);

    server.refuse.clear();
    expect(await trash.destroyAll(), 1);
    expect(box.read(trashListProvider).entries, isEmpty);
    expect(server.destroyed, {'z'});
  });

  testWidgets('the trash empties in one go, after a confirm', (tester) async {
    final server = _Server()..trashed.addAll(['x', 'y']);
    await tester.pumpWidget(ProviderScope(
      overrides: [openHumanClientProvider.overrideWithValue(server)],
      child: const MaterialApp(home: Scaffold(body: ConversationSidebar())),
    ));
    await tester.tap(find.byKey(const ValueKey('open-trash')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('trash-restore-all')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trash-empty')));
    await tester.pumpAndSettle();
    expect(find.textContaining('将永久删除 2 个对话'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trash-empty-confirm')));
    await tester.pumpAndSettle();

    expect(server.destroyed, {'x', 'y'});
    expect(find.text('废纸篓为空'), findsOneWidget);
    expect(find.byKey(const ValueKey('trash-empty')), findsNothing);
  });

  testWidgets('a long swipe runs the last action; a short one opens the row',
      (tester) async {
    final group = SwipeGroup();
    var deleted = 0;
    var more = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: SwipeRow(
            id: 'r',
            group: group,
            actions: [
              SwipeAction(
                label: '更多',
                icon: Icons.more_horiz,
                color: Colors.grey,
                onTap: () => more++,
              ),
              SwipeAction(
                label: '删除',
                icon: Icons.delete,
                color: Colors.red,
                onTap: () => deleted++,
              ),
            ],
            child: const SizedBox(height: 60, child: Text('row')),
          ),
        ),
      ),
    ));

    // Short drag past half the buttons: stays open, nothing runs.
    await tester.drag(find.text('row'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(deleted, 0);
    expect(find.text('删除'), findsOneWidget);
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    expect(more, 1);

    // Long drag: deletes on release.
    await tester.drag(find.text('row'), const Offset(-330, 0));
    await tester.pumpAndSettle();
    expect(deleted, 1);
  });
}
