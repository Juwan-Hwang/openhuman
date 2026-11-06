// The details pane: the person first, technical details folded; in a
// room, members and the owner's invite.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_client/app/theme.dart';
import 'package:openhuman_client/core/sdk_provider.dart';
import 'package:openhuman_client/features/chat/details_panel.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

import 'visual/harness.dart';

class _Invites extends FakeClient {
  int minted = 0;
  @override
  Future<Map<String, dynamic>> mintInvite(String roomId) async {
    minted++;
    return {'code': 'K7Q2-9XMA'};
  }
}

Future<(_Invites, ProviderContainer)> _pump(
  WidgetTester tester,
  String conversation,
) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = _Invites();
  final c = ProviderContainer(overrides: [
    openHumanClientProvider.overrideWithValue(fake),
    currentHumanProvider.overrideWith(
      (ref) => const oh.HumanSession(id: 'hum_me', displayName: '黄治文'),
    ),
    connectionStateProvider
        .overrideWith((ref) => Stream.value(oh.ConnectionState.connected)),
  ]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: darkTheme,
      home: const Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: DetailsPanel(),
        ),
      ),
    ),
  ));
  // Let the list fill from history, then open the conversation.
  await c.read(conversationListProvider.notifier).retry();
  c.read(activeConversationIdProvider.notifier).state = conversation;
  await tester.pumpAndSettle();
  return (fake, c);
}

void main() {
  testWidgets('a person: name and tool first, ids folded away', (tester) async {
    await _pump(tester, 'cnv_lin');
    expect(find.byKey(const ValueKey('details-person')), findsOneWidget);
    expect(find.text('林晓'), findsWidgets);
    expect(find.text('经由 Claude Code'), findsOneWidget);
    expect(find.text('名称'), findsOneWidget);
    // The technical side is there, but closed.
    expect(find.text('高级'), findsOneWidget);
    expect(find.text('agt_lin'), findsNothing);
    await tester.tap(find.text('高级'));
    await tester.pumpAndSettle();
    expect(find.text('agt_lin'), findsOneWidget);
  });

  testWidgets('a room: members with the owner marked, and an invite',
      (tester) async {
    final (fake, _) = await _pump(tester, 'room_1');
    expect(find.byKey(const ValueKey('details-room')), findsOneWidget);
    expect(find.text('成员'), findsOneWidget);
    expect(find.text('群主'), findsOneWidget);
    expect(find.text('Mia Chen'), findsOneWidget);
    await tester.tap(find.text('创建邀请码'));
    await tester.pumpAndSettle();
    expect(fake.minted, 1);
    expect(find.text('K7Q2-9XMA'), findsOneWidget);
  });
}
