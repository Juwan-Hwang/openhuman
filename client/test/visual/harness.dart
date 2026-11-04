// Shared parts of the visual shots: a fake client with sample data and
// the real fonts. Sample content is for the shots only.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

class FakeClient extends oh.OpenHumanClient {
  final msgs = StreamController<oh.MessageReceivedData>.broadcast();
  @override
  oh.HumanSession? get currentHuman =>
      const oh.HumanSession(id: 'hum_me', displayName: '黄治文');
  @override
  Stream<oh.MessageReceivedData> get messages => msgs.stream;
  @override
  Stream<oh.ReplyDeliveredData> get replyAcks => const Stream.empty();
  @override
  Stream<oh.OpenHumanEvent> get rawEvents => const Stream.empty();
  final caps = StreamController<oh.CapabilityUpdatedData>.broadcast();
  @override
  Stream<oh.CapabilityUpdatedData> get capabilityUpdates => caps.stream;
  @override
  oh.ConnectionState get currentState => oh.ConnectionState.connected;
  @override
  Stream<oh.ConnectionState> get connectionState =>
      Stream.value(oh.ConnectionState.connected);
  @override
  List<String> get activeConversations => ['cnv_1'];
  @override
  Future<void> sendReply(String c, String t, {String? invocationId}) async {}
  @override
  Future<List<oh.HistoryConversation>> fetchConversations({
    int limit = 50,
  }) async {
    final now = DateTime.now();
    return [
      oh.HistoryConversation(
        id: 'cnv_1',
        agentId: 'agt_cc',
        agentName: 'Claude Code',
        lastMessageAt: now,
      ),
      oh.HistoryConversation(
        id: 'cnv_2',
        agentId: 'agt_codex',
        agentName: 'Codex',
        lastMessageAt: now.subtract(const Duration(minutes: 40)),
      ),
      oh.HistoryConversation(
        id: 'cnv_3',
        agentId: 'agt_oc',
        agentName: 'OpenCode',
        lastMessageAt: now.subtract(const Duration(days: 1)),
      ),
      oh.HistoryConversation(
        id: 'cnv_4',
        agentId: 'agt_pi',
        agentName: 'pi',
        lastMessageAt: now.subtract(const Duration(days: 3)),
      ),
      oh.HistoryConversation(
        id: 'room_1',
        type: 'group',
        title: '发布评审',
        memberCount: 4,
        lastMessageAt: now.subtract(const Duration(hours: 2)),
      ),
    ];
  }
}

Future<void> loadFont(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(rootBundle.load(f));
  }
  await l.load();
}


Future<void> loadFonts() async {
  await loadFont('Manrope', [
    for (final w in [400, 500, 600, 700]) 'assets/fonts/Manrope-$w.ttf',
  ]);
  await loadFont('GeistMono', [
    'assets/fonts/GeistMono-400.ttf',
    'assets/fonts/GeistMono-500.ttf',
  ]);
  await loadFont('NotoSansSC', [
    'assets/fonts/NotoSansSC-400.ttf',
    'assets/fonts/NotoSansSC-700.ttf',
  ]);
  await loadFont('MaterialIcons', ['fonts/MaterialIcons-Regular.otf']);
}

/// Sample thread used by every shot.
const sampleRequest1 =
    '我在改 `server/src/api/task.rs`，准备把 API 任务的超时从 900 秒改成可配置。'
    '下面是改动，你看行不行：\n\n```diff\n'
    '-const TASK_TIMEOUT: u64 = 900;\n'
    '+fn task_timeout() -> u64 {\n'
    '+    env_u64("OMNI2API_TASK_TIMEOUT").unwrap_or(900)\n'
    '+}\n```\n\n'
    '另外有两个问题：\n1. 环境变量名用这个可以吗？\n'
    '2. 要不要顺便写进 **docs/server-env.md**？';
const sampleReply = '可以。文档要写，默认值也写上。';
const sampleRequest2 = '好。文档已补，`cargo clippy -- -D warnings` 通过。'
    '最后确认一下：超时之后，任务状态返回 `expired` 还是 `failed`？';

const sampleCaps = oh.CapabilityUpdatedData(
  agentId: 'agt_cc',
  capabilities: [
    {
      'id': 'read_file',
      'name': '读取文件',
      'description': '读取工作区里的一个文件',
      'category': 'fs',
      'input_schema': {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'description': '文件路径'},
        },
        'required': ['path'],
      },
    },
    {
      'id': 'run_tests',
      'name': '运行测试',
      'description': '在工作区运行 cargo test',
      'category': 'terminal',
    },
    {
      'id': 'git_diff',
      'name': '查看改动',
      'description': '显示未提交的 diff',
      'category': 'git',
    },
  ],
);

/// Asset images decode off the fake clock; wait for every one on screen.
Future<void> settleImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pump();
}
