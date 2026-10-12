// ═════════════════════════════════════════════════════════════════
// Flutter Widget Test: AuthScreen
//
// Tests:
//   - Renders URL and API key text fields
//   - Renders Connect button
//   - Shows error when fields are empty
//   - Tapping Connect with input triggers client.connect()
// ═════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

import 'package:openhuman_client/features/auth/auth_screen.dart';
import 'package:openhuman_client/core/sdk_provider.dart';

/// A fake OpenHumanClient that records connect calls and reports
/// itself connected right after (so the screen's poll loop exits).
class _FakeClient extends oh.OpenHumanClient {
  String? connectedUrl;
  String? connectedApiKey;
  bool _connected = false;

  @override
  Future<void> connect(String url, String apiKey, {String? deviceToken}) async {
    connectedUrl = url;
    connectedApiKey = apiKey;
    _connected = true;
  }

  @override
  oh.ConnectionState get currentState =>
      _connected ? oh.ConnectionState.connected : oh.ConnectionState.idle;

  @override
  void dispose() {}
}

void main() {
  late _FakeClient fakeClient;
  late ProviderContainer container;

  setUp(() {
    fakeClient = _FakeClient();
    container = ProviderContainer(
      overrides: [
        openHumanClientProvider.overrideWithValue(fakeClient),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  Future<void> pumpAuthScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: AuthScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  // ── UI rendering ──────────────────────────────────────────────────

  group('AuthScreen UI', () {
    testWidgets('renders OpenHuman title', (tester) async {
      await pumpAuthScreen(tester);
      expect(find.text('OpenHuman'), findsOneWidget);
    });

    testWidgets('renders Server URL text field', (tester) async {
      await pumpAuthScreen(tester);
      expect(find.text('Server URL'), findsOneWidget);
    });

    testWidgets('renders API Key text field', (tester) async {
      await pumpAuthScreen(tester);
      expect(find.text('API Key'), findsOneWidget);
    });

    testWidgets('renders Connect button', (tester) async {
      await pumpAuthScreen(tester);
      expect(find.text('Connect'), findsOneWidget);
    });
  });

  // ── Validation ────────────────────────────────────────────────────

  group('AuthScreen validation', () {
    testWidgets('shows error when URL is empty', (tester) async {
      await pumpAuthScreen(tester);

      // Only enter API key, leave URL empty.
      await tester.enterText(
        find.byType(TextField).at(1),
        'ohk_demo_alice_codex',
      );

      await tester.tap(find.text('Connect'));
      await tester.pump();

      expect(find.textContaining('Please enter both'), findsOneWidget);
    });

    testWidgets('shows error when API key is empty', (tester) async {
      await pumpAuthScreen(tester);

      // Only enter URL, leave API key empty.
      await tester.enterText(
        find.byType(TextField).at(0),
        'ws://localhost:8080/ws',
      );

      await tester.tap(find.text('Connect'));
      await tester.pump();

      expect(find.textContaining('Please enter both'), findsOneWidget);
    });
  });

  // ── Connect interaction ───────────────────────────────────────────

  group('AuthScreen connect', () {
    testWidgets('calls client.connect with entered URL and API key',
        (tester) async {
      await pumpAuthScreen(tester);

      // Enter URL and API key.
      await tester.enterText(
        find.byType(TextField).at(0),
        'ws://localhost:8080/ws',
      );
      await tester.enterText(
        find.byType(TextField).at(1),
        'ohk_demo_alice_codex',
      );

      // Tap Connect — use runAsync to allow the real async timeout
      // timer to run. We then pump to flush, and immediately check.
      await tester.tap(find.text('Connect'));

      // Pump a few frames to let the connect() call execute.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Verify the client was called with the right values.
      expect(fakeClient.connectedUrl, 'ws://localhost:8080/ws');
      expect(fakeClient.connectedApiKey, 'ohk_demo_alice_codex');

      // The fake never connects, so the screen sits in its 40s poll loop.
      // That loop is driven by wall-clock DateTime (not the fake async
      // clock), so no amount of pumping advances it — and this test only
      // cares that connect() was invoked with the right values, which is
      // already verified above. Do NOT pumpAndSettle here: the pending
      // poll timers would time it out.
    });
  });
}

