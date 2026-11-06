import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_client/core/sdk_provider.dart';

void main() {
  test('every server refusal reads as a sentence, never a code', () {
    for (final code in [
      'not_a_member',
      'owner_only',
      'tool_not_found',
      'target_not_found',
      'target_required',
      'queued',
      'serialize_failed',
      'something_new',
    ]) {
      final t = serverNotice(code, 'English detail');
      expect(t, isNotNull, reason: code);
      expect(t, isNot(contains('_')), reason: code);
      expect(t, isNot(contains('English')), reason: code);
    }
  });
}
