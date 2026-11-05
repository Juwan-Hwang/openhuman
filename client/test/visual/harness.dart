// Shared parts of the visual shots: a fake client with sample data and
// the real fonts. Sample content is for the shots only.
//
// The people:
//   林晓      writes from Claude Code   everyday talk, a long code block,
//                                       a photo, and a reply of mine that
//                                       fails to send
//   周子航    writes from Cursor        an expired task from yesterday,
//                                       then plain talk; waiting on me
//   Mia Chen  writes from WorkBuddy     an open picture task
//   (unnamed) a bare "Claude Code"      speaks in the room
//   发布评审  a room with all of them   @mentions

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

/// Names exactly as the server hands them over.
const linName = '林晓的 Claude Code · a3f9';
const zhouName = '周子航 via Cursor';
const miaName = 'Mia Chen (WorkBuddy)';
const anonName = 'Claude Code · 7c21';

/// A photo, inlined the way the server sends attachments.
final String samplePhoto =
    'data:image/png;base64,${base64Encode(File('test/visual/fixtures/sunset.png').readAsBytesSync())}';

const sampleCode = '''
看了下超时那块，我先这样改，你帮我过一眼：

```rust
/// How long an API task waits for its answer.
fn task_timeout() -> Duration {
    let secs = std::env::var("OPENHUMAN_TASK_TIMEOUT")
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .filter(|s| *s >= 30)
        .unwrap_or(900);
    Duration::from_secs(secs)
}

pub async fn wait_for_answer(
    app: &AppState,
    task: &Task,
) -> Result<Answer, TaskError> {
    let deadline = task.created_at + task_timeout();
    loop {
        if let Some(a) = app.answers.take(&task.id).await {
            return Ok(a);
        }
        if Instant::now() >= deadline {
            app.tasks.mark_expired(&task.id).await;
            return Err(TaskError::Expired);
        }
        tokio::time::sleep(Duration::from_millis(250)).await;
    }
}
```

低于 30 秒的值我直接忽略了，免得有人手滑配成 0。''';

class FakeClient extends oh.OpenHumanClient {
  FakeClient({DateTime? now}) : now = now ?? DateTime.now();

  /// The shots' clock: sample times count back from here.
  final DateTime now;

  final msgs = StreamController<oh.MessageReceivedData>.broadcast();
  final raw = StreamController<oh.OpenHumanEvent>.broadcast();

  /// The next send fails, the way a dropped socket fails it.
  bool failNext = false;

  @override
  oh.HumanSession? get currentHuman =>
      const oh.HumanSession(id: 'hum_me', displayName: '黄治文');
  @override
  Stream<oh.MessageReceivedData> get messages => msgs.stream;
  @override
  Stream<oh.ReplyDeliveredData> get replyAcks => const Stream.empty();
  @override
  Stream<oh.OpenHumanEvent> get rawEvents => raw.stream;
  final caps = StreamController<oh.CapabilityUpdatedData>.broadcast();
  @override
  Stream<oh.CapabilityUpdatedData> get capabilityUpdates => caps.stream;
  @override
  oh.ConnectionState get currentState => oh.ConnectionState.connected;
  @override
  Stream<oh.ConnectionState> get connectionState =>
      Stream.value(oh.ConnectionState.connected);
  @override
  List<String> get activeConversations => ['cnv_lin'];
  @override
  Future<void> sendReply(String c, String t, {String? invocationId}) async {
    if (failNext) {
      failNext = false;
      throw StateError('not connected');
    }
  }

  @override
  Future<void> endTurn(String conversationId) async {}

  DateTime _ago(Duration d) => now.subtract(d);

  @override
  Future<List<oh.HistoryConversation>> fetchConversations({
    int limit = 50,
  }) async {
    return [
      oh.HistoryConversation(
        id: 'cnv_lin',
        agentId: 'agt_lin',
        agentName: linName,
        lastMessageAt: _ago(const Duration(minutes: 1)),
      ),
      oh.HistoryConversation(
        id: 'cnv_mia',
        agentId: 'agt_mia',
        agentName: miaName,
        lastMessageAt: _ago(const Duration(minutes: 2)),
      ),
      oh.HistoryConversation(
        id: 'cnv_zhou',
        agentId: 'agt_zhou',
        agentName: zhouName,
        lastMessageAt: _ago(const Duration(minutes: 6)),
      ),
      oh.HistoryConversation(
        id: 'room_1',
        type: 'group',
        title: '发布评审',
        memberCount: 4,
        lastMessageAt: _ago(const Duration(hours: 2)),
      ),
      oh.HistoryConversation(
        id: 'cnv_anon',
        agentId: 'agt_anon',
        agentName: 'Claude Code',
        lastMessageAt: _ago(const Duration(days: 3)),
      ),
    ];
  }

  @override
  Future<Map<String, dynamic>> getRoom(String roomId) async => {
        'id': roomId,
        'title': '发布评审',
        'members': [
          {'human_id': 'hum_me', 'display_name': '黄治文', 'role': 'owner'},
          {'display_name': '林晓', 'role': 'member'},
          {'display_name': '周子航', 'role': 'member'},
          {'display_name': 'Mia Chen', 'role': 'member'},
        ],
      };

  oh.HistoryMessage _m(
    String conv,
    String id,
    String who,
    Duration ago,
    String text, {
    List<String> images = const [],
    Map<String, dynamic>? request,
  }) {
    final me = who == 'me';
    return oh.HistoryMessage(
      id: id,
      conversationId: conv,
      senderId: me ? 'hum_me' : 'agt_$conv',
      senderType: me ? 'human' : 'agent',
      senderName: me ? '黄治文' : who,
      text: text,
      images: images,
      createdAt: _ago(ago),
      request: request,
    );
  }

  oh.HistoryMessage _room(
          String id, String sid, String who, Duration ago, String text) =>
      oh.HistoryMessage(
        id: id,
        conversationId: 'room_1',
        senderId: sid,
        senderType: sid == 'hum_me' ? 'human' : 'agent',
        senderName: who,
        text: text,
        createdAt: _ago(ago),
      );

  @override
  Future<List<oh.HistoryMessage>> fetchMessages(
    String conversationId, {
    int limit = 100,
  }) async {
    final all = await _messagesFor(conversationId);
    return all.length > limit ? all.sublist(all.length - limit) : all;
  }

  Future<List<oh.HistoryMessage>> _messagesFor(String conversationId) async {
    const m = Duration(minutes: 1);
    switch (conversationId) {
      case 'cnv_lin':
        return [
          _m('cnv_lin', 'l1', linName, const Duration(hours: 20),
              '明天上午的评审你能来吗？想先跟你对一下发布时间。'),
          _m('cnv_lin', 'l2', 'me', const Duration(hours: 19, minutes: 58),
              '能来，十点前到。'),
          _m('cnv_lin', 'l3', linName, m * 52, sampleCode),
          _m('cnv_lin', 'l4', linName, m * 51, '对了，周末在海边拍的，给你看看',
              images: [samplePhoto]),
          _m('cnv_lin', 'l5', 'me', m * 40, '逻辑没问题。默认值记得写进文档。'),
          _m('cnv_lin', 'l6', 'me', m * 40, '照片好看！下次叫上我，我也想去吹吹海风。'),
          _m('cnv_lin', 'l7', linName, m * 3, '好，文档我补上。今晚吃饭的地方定了吗？'),
        ];
      case 'cnv_zhou':
        return [
          _m(
            'cnv_zhou',
            'z1',
            zhouName,
            const Duration(hours: 26),
            '帮我把这段开场白读一遍，我想听听语气：大家好，欢迎来到今天的分享。',
            request: {
              'kind': 'api',
              'api': 'audio.speech',
              'expected_format': 'audio (mp3)',
              'wants_files': true,
              'created_at':
                  _ago(const Duration(hours: 26)).millisecondsSinceEpoch ~/
                      1000,
              'timeout_secs': 900,
              'spec': {'voice': 'alloy', 'response_format': 'mp3'},
            },
          ),
          _m('cnv_zhou', 'z2', zhouName, m * 8, '昨天那个录音不用了，我自己录好了'),
          _m('cnv_zhou', 'z3', zhouName, m * 6, '下午三点能连个线吗？聊聊下周的排期。'),
        ];
      case 'cnv_mia':
        return [
          _m(
            'cnv_mia',
            'p1',
            miaName,
            m * 2,
            '帮我画一张海边日落的图，暖色调，放在活动海报上用。',
            request: {
              'kind': 'api',
              'api': 'images.generations',
              'expected_format': '1 png image(s), 1024x1024',
              'wants_files': true,
              'created_at': _ago(m * 2).millisecondsSinceEpoch ~/ 1000,
              'timeout_secs': 900,
              'spec': {'n': 1, 'size': '1024x1024', 'quality': 'high'},
            },
          ),
        ];
      case 'room_1':
        return [
          _room('r1', 'agt_lin', linName, const Duration(hours: 2, minutes: 9),
              '今天下午四点发版，大家还有要合的吗？'),
          _room('r2', 'agt_zhou', zhouName,
              const Duration(hours: 2, minutes: 7), '我那个修复刚合进去了。'),
          _room('r3', 'agt_zhou', zhouName,
              const Duration(hours: 2, minutes: 7), '@黄治文 帮忙确认下回滚脚本？'),
          _room('r4', 'agt_mia', miaName, const Duration(hours: 2, minutes: 5),
              '文案我这边 OK，海报晚点发群里。'),
          _room('r5', 'agt_anon', anonName,
              const Duration(hours: 2, minutes: 4), '测试全过了，可以发。'),
          _room('r6', 'hum_me', '黄治文', const Duration(hours: 2, minutes: 2),
              '回滚脚本我看过了，没问题。@林晓 四点见。'),
          _room('r7', 'agt_lin', linName, const Duration(hours: 2), '收到，四点见。'),
        ];
    }
    return const [];
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

const sampleCaps = oh.CapabilityUpdatedData(
  agentId: 'agt_lin',
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

/// Images decode off the fake clock; wait for every one on screen.
Future<void> settleImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pump();
}
