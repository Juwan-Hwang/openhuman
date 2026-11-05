import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_client/app/theme.dart';
import 'package:openhuman_client/core/sdk_provider.dart';
import 'package:openhuman_client/features/chat/conversation_sidebar.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

import 'visual/harness.dart';

Future<(FakeClient, ProviderContainer)> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = FakeClient();
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
          alignment: Alignment.centerLeft,
          child: ConversationSidebar(),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return (fake, c);
}

void main() {
  testWidgets('the library lists files with size and origin, and deletes',
      (tester) async {
    final (fake, _) = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('open-files')));
    await tester.pumpAndSettle();
    expect(find.text('文件库'), findsOneWidget);
    expect(find.text('海边日落.png'), findsOneWidget);
    expect(find.textContaining('2.3 MB'), findsOneWidget);
    expect(find.textContaining('你交出去的'), findsWidgets);
    expect(find.text('3 个文件 · 8.7 MB'), findsOneWidget);

    // Row actions show on hover.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(find.byKey(const ValueKey('file-file_review'))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('file-file_review')),
      matching: find.byTooltip('删除'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(fake.deletedFiles, {'file_review'});
    expect(find.text('发布评审纪要.pdf'), findsNothing);
  });

  testWidgets('an invite code opens the room it belongs to', (tester) async {
    final (_, c) = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('join-room')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('join-code')), 'K7Q2-9XMA');
    await tester.tap(find.widgetWithText(FilledButton, '加入'));
    await tester.pumpAndSettle();
    expect(c.read(activeConversationIdProvider), 'room_1');
    expect(find.text('已加入「发布评审」'), findsOneWidget);
  });

  testWidgets('a wrong code says so, plainly', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('join-room')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('join-code')), 'NOPE');
    await tester.tap(find.widgetWithText(FilledButton, '加入'));
    await tester.pumpAndSettle();
    expect(find.text('这个邀请码不对，或者已经作废了'), findsOneWidget);
  });
}
