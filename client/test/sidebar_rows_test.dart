import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_client/core/sdk_provider.dart';
import 'package:openhuman_client/core/tray_service.dart';
import 'package:openhuman_client/features/chat/conversation_sidebar.dart';

ConversationInfo _c({
  String? last,
  bool mine = false,
  bool failed = false,
  bool group = false,
  String name = '周子航 via Cursor',
}) =>
    ConversationInfo(
      id: 'c',
      agentId: 'a',
      agentName: name,
      lastMessage: last,
      lastFromMe: mine,
      lastFailed: failed,
      isGroup: group,
      title: group ? '发布评审' : null,
    );

void main() {
  test('their last word reads as is', () {
    expect(rowPreview(_c(last: '下午三点能连个线吗？')), '下午三点能连个线吗？');
  });

  test('my last word is marked as mine', () {
    expect(rowPreview(_c(last: '可以', mine: true)), '你：可以');
  });

  test('a reply that never left does not read as said', () {
    expect(
      rowPreview(_c(last: '可以', mine: true, failed: true)),
      '未发出：可以',
    );
  });

  test('no message yet names the tool, never a false "no messages"', () {
    expect(rowPreview(_c()), '经由 Cursor');
    expect(rowPreview(_c(group: true)), '群聊');
  });

  test('a remark name keeps the tool it came through', () {
    final stored = remarkToStoredName('小周', 'Cursor');
    final c = _c(name: stored);
    expect(c.caller.name, '小周');
    expect(c.caller.tool, 'Cursor');
    expect(remarkToStoredName('小周', null), '小周');
  });

  test('the tray says how many people are waiting', () {
    expect(trayTooltip(0), 'OpenHuman · 没有人在等你回复');
    expect(trayTooltip(2), 'OpenHuman · 2 人在等你回复');
  });

  test('markdown is flattened to one line', () {
    expect(rowPreview(_c(last: '**看**\n```rust\nfn a() {}\n```')), '看 fn a() {}');
  });
}
