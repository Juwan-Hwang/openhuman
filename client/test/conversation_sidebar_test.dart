// ═════════════════════════════════════════════════════════════════
// Flutter Widget Test: ConversationSidebar load states
//
// The reported bug: the sidebar spun on "正在加载会话…" forever.
// A failed history fetch cleared an internal flag but never touched
// anything the widget watched, so the spinner outlived the request.
//
// These tests pin the four states apart. The important one is that a
// failure becomes visible and can be retried, rather than looking
// identical to a fetch still in flight.
// ═════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

import 'package:openhuman_client/core/sdk_provider.dart';
import 'package:openhuman_client/features/chat/conversation_sidebar.dart';

/// Stands in for a server that answers slowly, not at all, or normally.
class _FakeClient extends oh.OpenHumanClient {
  _FakeClient({this.result, this.error, this.gate});

  /// Returned when [error] is null. Mutable so a test can turn the link
  /// back on mid-run.
  List<oh.HistoryConversation>? result;

  /// Thrown when set, standing in for a timeout or a dead socket.
  /// Mutable so a test can turn the link back on mid-run.
  Object? error;

  /// Held open so a test can watch the spinner mid-request.
  Completer<List<oh.HistoryConversation>>? gate;

  /// Returned by fetchTrash. Assigned after construction so a test can
  /// turn the link back on mid-run.
  List<oh.HistoryConversation>? trashed;

  @override
  Future<List<oh.HistoryConversation>> fetchTrash({int limit = 50}) async {
    fetchCount++;
    if (error != null) throw error!;
    return trashed ?? const [];
  }

  int fetchCount = 0;

  @override
  Future<List<oh.HistoryConversation>> fetchConversations({
    int limit = 50,
  }) async {
    fetchCount++;
    final held = gate;
    if (held != null) return held.future;
    if (error != null) throw error!;
    return result ?? const [];
  }
}

/// The sidebar, wired to [client] instead of the live singleton.
Widget _host(_FakeClient client) {
  return ProviderScope(
    overrides: [openHumanClientProvider.overrideWithValue(client)],
    child: const MaterialApp(home: Scaffold(body: ConversationSidebar())),
  );
}

/// The status the sidebar would be rendering right now.
ConversationListStatus _statusOf(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ConversationSidebar)),
  );
  return container.read(conversationListProvider).status;
}

/// Opens the trash sheet over the console.
///
/// Returns a finder scoped to the sheet: the sidebar underneath has its
/// own retry button, so an unscoped `find.text('重试')` is ambiguous.
Future<Finder> _openTrash(WidgetTester tester) async {
  await tester.tap(find.text('回收站'));
  await tester.pumpAndSettle();
  final sheet = find.byType(BottomSheet);
  expect(sheet, findsOneWidget);
  return sheet;
}

void main() {
  testWidgets('idle before the first fetch — not a spinner', (tester) async {
    // History is fetched only once the socket connects. Until then the
    // request has not started, and a spinner would promise otherwise.
    await tester.pumpWidget(_host(_FakeClient()));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('等待连接'), findsOneWidget);
    expect(find.text('正在加载会话…'), findsNothing);
  });

  testWidgets('spinner while the fetch is genuinely in flight', (tester) async {
    final gate = Completer<List<oh.HistoryConversation>>();
    await tester.pumpWidget(_host(_FakeClient(gate: gate)));

    // Drive the fetch the way an incoming connection would.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationSidebar)),
    );
    unawaited(container.read(conversationListProvider.notifier).retry());
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('正在加载会话…'), findsOneWidget);

    gate.complete([]);
    await tester.pumpAndSettle();
  });

  testWidgets('a failed fetch stops spinning and offers a retry', (
    tester,
  ) async {
    // The regression: this used to keep showing the spinner forever.
    await tester.pumpWidget(_host(_FakeClient(error: TimeoutException('30s'))));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationSidebar)),
    );
    await container.read(conversationListProvider.notifier).retry();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('加载超时'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(_statusOf(tester), ConversationListStatus.error);
  });

  testWidgets('retry re-asks instead of staying on the failure', (
    tester,
  ) async {
    final client = _FakeClient(error: TimeoutException('30s'));
    await tester.pumpWidget(_host(client));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationSidebar)),
    );
    await container.read(conversationListProvider.notifier).retry();
    await tester.pump();
    expect(client.fetchCount, 1);

    // The link comes back.
    client.error = null;
    client.result = [
      const oh.HistoryConversation(id: 'conv_1', agentId: 'agent_trae'),
    ];

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(client.fetchCount, 2);
    expect(_statusOf(tester), ConversationListStatus.ready);
    // And the recovered row replaces the error message.
    expect(find.text('加载超时'), findsNothing);
    expect(find.byType(CircleAvatar), findsOneWidget);
  });

  testWidgets('an empty account reads as empty, not as loading', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_FakeClient(result: const [])));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationSidebar)),
    );
    await container.read(conversationListProvider.notifier).retry();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('还没有会话'), findsOneWidget);
  });

  testWidgets('retry works with no socket at all', (tester) async {
    // The SDK stores the API key before the handshake, so history can be
    // pulled over HTTP even while the WebSocket is still struggling.
    // On a flaky link this is the difference between recovering from the
    // sidebar and having to restart the app.
    final client = _FakeClient(
      result: [
        const oh.HistoryConversation(id: 'conv_9', agentId: 'agent_trae'),
      ],
    );
    await tester.pumpWidget(_host(client));
    expect(find.text('等待连接'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(client.fetchCount, 1);
    expect(find.text('等待连接'), findsNothing);
    expect(find.byType(CircleAvatar), findsOneWidget);
  });

  test('a failed trash load does not read as an empty trash', () async {
    // The regression: a failed fetch was swallowed by a bare
    // debugPrint, so the sheet said the trash was empty — which invites
    // the reader to conclude their conversations were deleted for good.
    final client = _FakeClient(error: TimeoutException('30s'));
    final container = ProviderContainer(
      overrides: [openHumanClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    await container.read(trashListProvider.notifier).loadIfNeeded();

    final state = container.read(trashListProvider);
    expect(state.status, ConversationListStatus.error);
    expect(state.entries, isEmpty);
  });

  testWidgets('a failed trash load offers a retry, not a lie', (tester) async {
    final client = _FakeClient(error: TimeoutException('30s'));
    await tester.pumpWidget(_host(client));
    final sheet = await _openTrash(tester);

    expect(
      find.descendant(of: sheet, matching: find.text('回收站是空的')),
      findsNothing,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('加载失败')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('重试')),
      findsOneWidget,
    );
  });

  testWidgets('an empty trash really does say so', (tester) async {
    await tester.pumpWidget(_host(_FakeClient()));
    final sheet = await _openTrash(tester);

    expect(
      find.descendant(of: sheet, matching: find.text('回收站是空的')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('重试')),
      findsNothing,
    );
  });

  testWidgets('retrying a failed trash load recovers it', (tester) async {
    final client = _FakeClient(error: TimeoutException('30s'));
    await tester.pumpWidget(_host(client));
    final sheet = await _openTrash(tester);
    expect(
      find.descendant(of: sheet, matching: find.text('加载失败')),
      findsOneWidget,
    );

    client.error = null;
    client.trashed = [
      const oh.HistoryConversation(id: 'conv_gone', agentId: 'agent_trae'),
    ];

    await tester.tap(
      find.descendant(of: sheet, matching: find.text('重试')),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: sheet, matching: find.text('加载失败')),
      findsNothing,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('回收站是空的')),
      findsNothing,
    );
    expect(find.text('agent_trae'), findsOneWidget);
  });

  test('a failure lands in error state, not in a silent reset', () async {
    // The provider-level half of the regression: the old code cleared
    // `_loading` and left `status` on loading, so nothing rebuilt.
    final client = _FakeClient(error: TimeoutException('30s'));
    final container = ProviderContainer(
      overrides: [openHumanClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(conversationListProvider.notifier);
    await notifier.retry();

    final state = container.read(conversationListProvider);
    expect(state.status, ConversationListStatus.error);
    expect(state.error, '加载超时');
  });

  test('a fetch before connect says so instead of "加载失败"', () async {
    // The SDK throws this when the socket never registered.
    final client = _FakeClient(
      error: StateError('fetch called before connect()'),
    );
    final container = ProviderContainer(
      overrides: [openHumanClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    await container.read(conversationListProvider.notifier).retry();

    expect(container.read(conversationListProvider).error, '还没连接上');
  });

  test('a dead socket is told apart from a slow one', () async {
    final client = _FakeClient(
      error: const SocketException('Connection failed'),
    );
    final container = ProviderContainer(
      overrides: [openHumanClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    await container.read(conversationListProvider.notifier).retry();

    expect(container.read(conversationListProvider).error, '网络连不上');
  });
}