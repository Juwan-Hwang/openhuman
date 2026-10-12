// Basic smoke test — verifies the app builds without crashing.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:openhuman_client/app/app.dart';

void main() {
  testWidgets('App builds and renders auth screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: OpenHumanApp(),
      ),
    );

    // The auth screen should show the OpenHuman title.
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('OpenHuman'), findsOneWidget);
  });
}
