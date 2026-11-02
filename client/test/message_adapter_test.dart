import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_client/features/chat/message_adapter.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

void main() {
  const me = types.User(id: 'hum_alice', firstName: 'Alice');

  oh.MessageReceivedData event({
    required String senderId,
    required String senderType,
    String? senderName,
    String text = 'hi',
  }) {
    return oh.MessageReceivedData(
      conversationId: 'cnv_1',
      messageId: 'msg_1',
      senderId: senderId,
      senderType: senderType,
      senderName: senderName,
      text: text,
    );
  }

  test('"me" is judged by senderId, not senderType (§10.1)', () {
    // My own message comes back over the socket: lands on my side.
    final mine = messageReceivedToMessages(
      event(senderId: 'hum_alice', senderType: 'human'),
      eventTimestamp: DateTime.now(),
      humanUser: me,
    );
    expect(mine.single.author.id, 'hum_alice');

    // Another human in a room: same senderType, but NOT me — must keep
    // their own author (and name), never collapse onto the local user.
    final other = messageReceivedToMessages(
      event(senderId: 'hum_bob', senderType: 'human', senderName: 'Bob'),
      eventTimestamp: DateTime.now(),
      humanUser: me,
    );
    expect(other.single.author.id, 'hum_bob');
    expect(other.single.author.firstName, 'Bob');
  });

  test('caller display name with session tag is shown as-is (§10.2)', () {
    final caller = messageReceivedToMessages(
      event(
        senderId: 'agt_claude',
        senderType: 'agent',
        senderName: '小明的 Claude Code · a3f9',
      ),
      eventTimestamp: DateTime.now(),
      humanUser: me,
    );
    expect(caller.single.author.firstName, '小明的 Claude Code · a3f9');
  });

  test('history follows the same senderId rule', () {
    final other = historyMessageToMessages(
      const oh.HistoryMessage(
        id: 'msg_9',
        conversationId: 'cnv_1',
        senderId: 'hum_bob',
        senderType: 'human',
        senderName: 'Bob',
        text: 'earlier',
      ),
      humanUser: me,
    );
    expect(other.single.author.id, 'hum_bob');

    final mine = historyMessageToMessages(
      const oh.HistoryMessage(
        id: 'msg_8',
        conversationId: 'cnv_1',
        senderId: 'hum_alice',
        senderType: 'human',
        text: 'mine',
      ),
      humanUser: me,
    );
    expect(mine.single.author.id, 'hum_alice');
  });
}
