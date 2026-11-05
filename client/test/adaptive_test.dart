import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_client/app/adaptive.dart';
import 'package:openhuman_client/app/theme.dart';
import 'package:openhuman_client/core/sdk_provider.dart';
import 'package:openhuman_client/features/chat/chat_screen.dart';
import 'package:openhuman_client/features/chat/conversation_sidebar.dart';
import 'package:openhuman_client/features/chat/room_composer.dart';
import 'package:openhuman_client/widgets/brand.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

import 'visual/harness.dart';

Future<void> _boot(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      openHumanClientProvider.overrideWithValue(FakeClient()),
      currentHumanProvider.overrideWith(
        (ref) => const oh.HumanSession(id: 'hum_me', displayName: '我'),
      ),
      connectionStateProvider.overrideWith(
        (ref) => Stream.value(oh.ConnectionState.connected),
      ),
    ],
    child: MaterialApp(theme: darkTheme, home: const ChatScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('window classes follow the Material breakpoints', () {
    expect(Fit.forWidth(390), Fit.compact);
    expect(Fit.forWidth(639), Fit.compact);
    expect(Fit.forWidth(640), Fit.medium);
    expect(Fit.forWidth(1099), Fit.medium);
    expect(Fit.forWidth(1100), Fit.expanded);
  });

  test('a narrow stream tightens its lanes', () {
    expect(StreamMetrics.forWidth(360).phone, isTrue);
    expect(StreamMetrics.forWidth(360).side, lessThan(16));
    expect(StreamMetrics.forWidth(700).phone, isFalse);
    expect(
      StreamMetrics.forWidth(1000).side,
      greaterThan(StreamMetrics.forWidth(700).side),
    );
  });

  testWidgets('phone: list first, a tap opens the stream, back returns',
      (tester) async {
    await _boot(tester, const Size(390, 844));
    expect(find.byType(ConversationSidebar), findsOneWidget);
    expect(find.byType(Composer), findsNothing);
    // The list is the phone's home screen and wears the brand.
    expect(find.byType(BrandLockup), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('conv-cnv_lin')));
    await tester.pumpAndSettle();
    expect(find.byType(Composer), findsOneWidget);
    expect(find.byType(ConversationSidebar), findsNothing);

    await tester.tap(find.byTooltip('会话列表'));
    await tester.pumpAndSettle();
    expect(find.byType(ConversationSidebar), findsOneWidget);
  });

  testWidgets('tablet: list and stream side by side, runtime overlays',
      (tester) async {
    await _boot(tester, const Size(1024, 768));
    expect(find.byType(ConversationSidebar), findsOneWidget);
    expect(find.byType(Composer), findsOneWidget);
  });

  testWidgets('the mark paints at small and large sizes', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Row(children: [
        BrandMark(size: 16),
        BrandMark(size: 96, tile: true),
      ]),
    ));
    expect(find.byType(BrandMark), findsNWidgets(2));
  });
}
