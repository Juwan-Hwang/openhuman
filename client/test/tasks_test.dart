import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_client/core/tasks.dart';

ApiTask _t(String api, String expected,
        {bool files = false, Map<String, dynamic> spec = const {}}) =>
    ApiTask.fromRequest({
      'kind': 'api',
      'api': api,
      'expected_format': expected,
      'wants_files': files,
      'spec': spec,
      'created_at': 1700000000,
      'timeout_secs': 900,
    })!;

const imgContract =
    '2 png image(s), size 1024x1024, quality high, transparent background: make the picture the message describes and attach the file (one file per image): `oh-seat reply -a out.png`; any text you add becomes the revised prompt, text alone (no file) is a refusal';

void main() {
  group('ApiTask.fromRequest', () {
    test('chat messages are not tasks', () {
      expect(ApiTask.fromRequest(null), isNull);
      expect(ApiTask.fromRequest({'kind': 'chat'}), isNull);
      expect(ApiTask.fromRequest({'kind': 'api'}), isNull);
    });

    test('image generation reads as a person-sized ask with chips', () {
      final t = _t('images.generations', imgContract, files: true);
      expect(t.kind, TaskKind.imageGenerate);
      expect(t.media, AnswerMedia.image);
      expect(t.count, 2);
      expect(t.ask, '请你生成 2 张图片');
      expect(t.chips, ['1024×1024', '2 张', 'PNG', '高质量', '透明背景']);
      expect(t.deadline,
          DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000 + 900000));
    });

    test('deadline falls back to when the message arrived', () {
      final at = DateTime(2026, 11, 4, 12);
      final t = ApiTask.fromRequest(
        {'kind': 'api', 'api': 'audio.speech', 'expected_format': ''},
        receivedAt: at,
      )!;
      expect(t.deadline, at.add(const Duration(seconds: 900)));
      expect(t.expiredAt(at.add(const Duration(minutes: 16))), isTrue);
      expect(t.expiredAt(at.add(const Duration(minutes: 14))), isFalse);
    });

    test('speech, transcription, video, completion chips', () {
      final s = _t('audio.speech',
          'voice alloy, mp3, speed 1.25: speak the message text aloud',
          files: true);
      expect(s.ask, '请你把一段文字读出来');
      expect(s.chips, ['声音 alloy', 'MP3', '1.25 倍速']);
      expect(s.audioFormat, 'mp3');

      final tr = _t('audio.transcriptions',
          'transcribe the attached audio (language zh); answer with the text as SRT (numbered cues with HH:MM:SS,mmm --> HH:MM:SS,mmm timings), each cue starting with its speaker and a colon (A: ...)');
      expect(tr.wantsSrt, isTrue);
      expect(tr.chips, ['语言 zh', '带时间轴（SRT）', '标出说话人']);

      final v = _t('videos',
          '8s video, 720x1280: continue the attached video as the message says (attach the whole extended video) and attach it',
          files: true);
      expect(v.ask, '请你把一段视频接着拍下去');
      expect(v.chips, ['8 秒', '720×1280', 'MP4']);

      final c = _t('completions',
          'max 40 tokens; 3 different continuations, separated by a line `@@@`: answer with the continuation only');
      expect(c.count, 3);
      expect(c.ask, '请你续写 3 个版本');
    });

    test('countdown', () {
      expect(countdown(const Duration(minutes: 14, seconds: 32)), '14:32');
      expect(countdown(const Duration(hours: 1, minutes: 2, seconds: 5)),
          '1:02:05');
      expect(countdown(const Duration(seconds: -3)), '0:00');
    });
  });

  group('checkAnswer: files', () {
    final img = _t('images.generations', imgContract, files: true);

    test('text alone on a file task is a refusal, nothing at all an error', () {
      expect(checkAnswer(img, '', const []).ok, isFalse);
      final r = checkAnswer(img, '这个我画不了', const []);
      expect(r.ok, isTrue);
      expect(r.refusal, isTrue);
    });

    test('wrong media blocks, wrong count or format warns', () {
      expect(
        checkAnswer(img, '', const [DraftFile(name: 'a.mp3', size: 1)]).error,
        contains('不是图片'),
      );
      final one =
          checkAnswer(img, '', const [DraftFile(name: 'a.png', size: 1)]);
      expect(one.ok, isTrue);
      expect(one.warning, contains('2 张'));
      final fmt = checkAnswer(img, '', const [
        DraftFile(name: 'a.jpg', size: 1),
        DraftFile(name: 'b.png', size: 1),
      ]);
      expect(fmt.warning, contains('PNG'));
      final good = checkAnswer(img, '', const [
        DraftFile(name: 'a.png', size: 1),
        DraftFile(name: 'b.png', size: 1),
      ]);
      expect((good.ok, good.warning, good.refusal), (true, null, false));
    });

    test('video takes a video plus an optional cover picture', () {
      final v = _t('videos', '4s video, 720x1280: make the video', files: true);
      expect(
          checkAnswer(v, '', const [DraftFile(name: 'c.png', size: 1)]).error,
          contains('视频'));
      expect(
        checkAnswer(v, '', const [
          DraftFile(name: 'c.png', size: 1),
          DraftFile(name: 'v.mp4', size: 1),
        ]).ok,
        isTrue,
      );
    });
  });

  group('checkAnswer: structured (mirrors the server)', () {
    test('moderation: one entry per input, known categories, 0..1', () {
      final t = _t('moderations', 'moderate 2 input(s)', spec: {'count': 2});
      expect(checkAnswer(t, '[[], ["violence"]]', const []).ok, isTrue);
      expect(checkAnswer(t, '[{"violence": 0.9}, null]', const []).ok, isTrue);
      expect(checkModeration('[[]]', {'count': 2}), contains('2 条'));
      expect(checkModeration('[["nope"], []]', {'count': 2}), contains('nope'));
      expect(checkModeration('[{"hate": 2}, []]', {'count': 2}),
          contains('0 到 1'));
      expect(checkModeration('not json', {'count': 1}), contains('JSON'));
      // A single input may be answered without the outer list.
      expect(checkModeration('["self_harm_intent"]', {'count': 1}), isNull);
    });

    test('decisions: per question type', () {
      final spec = {
        'questions': [
          {'type': 'predicate', 'name': 'p'},
          {
            'type': 'choice',
            'name': 'c',
            'values': ['red', 'blue'],
          },
          {
            'type': 'score',
            'name': 's',
            'labels': ['low', 'high'],
          },
        ],
      };
      expect(checkDecisions('[0.7, "Blue", "high"]', spec), isNull);
      expect(
          checkDecisions(
              '[true, {"answer": "red", "confidence": 0.8}, 1]', spec),
          isNull);
      expect(checkDecisions('[null, null, null]', spec), isNull);
      expect(checkDecisions('[2, "red", "low"]', spec), contains('第 1 题'));
      expect(checkDecisions('[0.5, "green", "low"]', spec), contains('第 2 题'));
      expect(checkDecisions('[0.5, "red", "mid"]', spec), contains('第 3 题'));
      expect(checkDecisions('[0.5]', spec), contains('3 个问题'));
      expect(
          checkDecisions(
              '[{"answer": 0.5, "confidence": 3}, "red", "low"]', spec),
          contains('把握'));
    });

    test('vector search hits name a file of the store', () {
      final spec = {
        'max': 2,
        'files': [
          {'id': 'file-1', 'filename': 'a.txt'},
        ],
      };
      expect(checkHits('[{"file": "a.txt", "score": 0.8, "text": "x"}]', spec),
          isNull);
      expect(checkHits('[]', spec), isNull);
      expect(
          checkHits('[{"file": "b.txt", "text": "x"}]', spec), contains('不在'));
      expect(checkHits('[{"file": "a.txt"}]', spec), contains('段落'));
      expect(
          checkHits(
              '[{"file":"a.txt","text":"x"},{"file":"a.txt","text":"x"},{"file":"a.txt","text":"x"}]',
              spec),
          contains('最多 2'));
    });

    test('grader: label from the list or score in range', () {
      expect(
          checkGrade('{"label": "pass"}', {
            'labels': ['pass', 'fail'],
          }),
          isNull);
      expect(
          checkGrade('{"label": "meh"}', {
            'labels': ['pass', 'fail'],
          }),
          contains('pass'));
      expect(
          checkGrade('{"score": 0.4}', {
            'range': [0, 1],
          }),
          isNull);
      expect(
          checkGrade('{"score": 4}', {
            'range': [0, 1],
          }),
          contains('0 到 1'));
    });

    test('SRT needs timed cues with text', () {
      expect(
          checkSrt('1\n00:00:01,000 --> 00:00:02,500\n你好\n\n'
              '2\n00:00:03,000 --> 00:00:04,000\nA: 再见'),
          isNull);
      expect(checkSrt('你好'), contains('时间轴'));
      expect(checkSrt('1\n00:00:01,000 --> 00:00:02,500'), contains('没有文字'));
    });

    test('completion versions are counted by @@@ lines', () {
      final t = _t('completions',
          '2 different continuations, separated by a line `@@@`');
      expect(checkAnswer(t, 'a\n@@@\nb', const []).warning, isNull);
      expect(checkAnswer(t, 'a', const []).warning, contains('2 个版本'));
    });
  });

  test('media and mime helpers', () {
    expect(mediaOf(name: 'x.WAV'), AnswerMedia.audio);
    expect(mediaOf(mime: 'video/mp4'), AnswerMedia.video);
    expect(mediaOf(name: 'batch.jsonl'), AnswerMedia.json);
    expect(mimeForName('a.jpg'), 'image/jpeg');
    final d = decodeDataUrl('data:audio/mpeg;base64,aGVsbG8=')!;
    expect(d.$1, 'audio/mpeg');
    expect(d.$2, 'hello'.codeUnits);
    expect(decodeDataUrl('https://x'), isNull);
    expect(
        moderationAnswer([
          {},
          {'violence'}
        ]),
        '[[],["violence"]]');
  });
}
