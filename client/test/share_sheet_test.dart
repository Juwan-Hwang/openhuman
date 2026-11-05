import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_client/features/chat/share_sheet.dart';

void main() {
  test('the note for a friend carries all three fields, by name', () {
    final note = friendNote(
      baseUrl: 'https://oh.example.com/v1',
      apiKey: 'ohk_x',
      modelName: 'huang-zhiwen',
      me: '黄治文',
    );
    expect(note, contains('我（黄治文）在用 OpenHuman'));
    expect(note, contains('https://oh.example.com/v1'));
    expect(note, contains('ohk_x'));
    expect(note, contains('模型：huang-zhiwen'));
    expect(note, contains('请别转发'));
  });
}
