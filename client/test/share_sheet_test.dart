import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_client/app/theme.dart';
import 'package:openhuman_client/core/sdk_provider.dart';
import 'package:openhuman_client/features/chat/share_sheet.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

import 'visual/harness.dart';

void main() {
  test('the note for a friend carries all three fields, by name', () {
    final note = friendNote(
      baseUrl: 'https://oh.example.com/v1',
      apiKey: 'ohk_x',
      modelName: 'huang-zhiwen',
      me: '黄治文',
    );
    expect(note, contains('向黄治文发送消息'));
    expect(note, contains('https://oh.example.com/v1'));
    expect(note, contains('ohk_x'));
    expect(note, contains('模型：huang-zhiwen'));
    expect(note, contains('请勿转发'));
  });

  test('a note for one person greets them by name', () {
    final note = friendNote(
      baseUrl: 'https://oh.example.com/v1',
      apiKey: 'ohk_y',
      modelName: 'm',
      me: '黄治文',
      to: '林晓',
    );
    expect(note, startsWith('林晓，你好。'));
  });

  testWidgets('each person gets a key of their own, shown once, revoked alone',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = FakeClient();
    final c = ProviderContainer(overrides: [
      openHumanClientProvider.overrideWithValue(fake),
      currentHumanProvider.overrideWith(
        (ref) => const oh.HumanSession(id: 'hum_me', displayName: '黄治文'),
      ),
      serverConfigProvider.overrideWith((ref) => const ServerConfig(
            serverUrl: 'wss://oh.example.com/ws',
            apiKey: 'ohk_seat_secret',
          )),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: darkTheme,
        home: const Scaffold(body: ShareSheet()),
      ),
    ));
    await tester.pumpAndSettle();

    // The seat's own key is never on offer once people have keys.
    expect(find.textContaining('ohk_seat'), findsNothing);
    expect(find.text('有访问权限的人'), findsOneWidget);
    expect(find.text('林晓'), findsWidgets);
    expect(find.text('已停用'), findsOneWidget); // 王磊

    await tester.enterText(find.byKey(const ValueKey('share-new-name')), '周叙白');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('share-make-key')));
    await tester.pumpAndSettle();
    expect(find.textContaining('密钥仅显示一次'), findsOneWidget);
    expect(find.text('ohk_7f3a9c2e51d84b06a1e9f0c4d2b8e637'), findsOneWidget);
    expect(find.text('复制邀请文字'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('share-revoke-key_lin')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '停用'));
    await tester.pumpAndSettle();
    expect(fake.callers.firstWhere((k) => k.id == 'key_lin').revoked, isTrue);
    expect(find.text('已停用'), findsNWidgets(2));
  });
}
