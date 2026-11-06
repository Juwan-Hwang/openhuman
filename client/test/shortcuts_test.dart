import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_client/app/theme.dart';
import 'package:openhuman_client/core/sdk_provider.dart';
import 'package:openhuman_client/features/chat/chat_screen.dart';
import 'package:openhuman_client/features/chat/shortcuts_sheet.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

import 'visual/harness.dart';

void main() {
  testWidgets('keyboard walks the list, jumps to waiting, shows the card',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      openHumanClientProvider.overrideWithValue(FakeClient()),
      currentHumanProvider.overrideWith(
        (ref) => const oh.HumanSession(id: 'hum_me', displayName: '我'),
      ),
      connectionStateProvider.overrideWith(
        (ref) => Stream.value(oh.ConnectionState.connected),
      ),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: darkTheme, home: const ChatScreen()),
    ));
    await tester.pumpAndSettle();

    final entries = container.read(conversationListProvider).entries;
    final ordered = [
      ...entries.where((c) => !c.isGroup),
      ...entries.where((c) => c.isGroup),
    ];
    String? active() => container.read(activeConversationIdProvider);

    container
        .read(conversationListProvider.notifier)
        .selectConversation(ordered.first.id);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(active(), ordered[1].id);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final now = entries.firstWhere((c) => c.id == active());
    expect(now.id, isNot(ordered[1].id));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(ShortcutsSheet), findsOneWidget);
  });
}
