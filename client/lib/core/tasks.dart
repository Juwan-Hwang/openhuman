/// API tasks, as the person answering them sees them.
///
/// Someone can ask you, through their own AI tool, for more than a chat
/// reply: a picture (`/v1/images/generations`), a recording of text read
/// aloud (`/v1/audio/speech`), a transcript, a video, a moderation
/// verdict… The server turns each such request into one message in a
/// conversation of its own, with an answer contract (`expected_format`),
/// a spec it will check the answer against, and a deadline after which
/// the asker stops waiting.
///
/// [ApiTask] reads that from the message's `request` metadata and says it
/// in people's terms ("林晓 请你生成一张图片 · 1024×1024"). [checkAnswer]
/// mirrors the server's own answer checks (`check_reply`, and the parsers
/// the endpoints run on the answer), so a malformed answer is caught
/// before it is sent rather than failing the person who asked.
///
/// Pure Dart, unit-tested.
library;

import 'dart:convert';
import 'dart:typed_data';

/// What kind of work a task is.
enum TaskKind {
  imageGenerate,
  imageEdit,
  imageVariation,
  speech,
  transcription,
  translation,
  completion,
  moderation,
  decision,
  video,
  vectorSearch,
  grader,
  other,
}

/// What the answer is made of.
enum AnswerMedia { image, audio, video, text, json }

/// Where a task stands.
enum TaskState {
  /// Waiting on you, inside its deadline.
  open,

  /// Your answer is on its way.
  sending,

  /// Delivered to the person who asked.
  answered,

  /// You declined (text only, which the contract reads as a refusal).
  declined,

  /// The deadline passed; nobody is waiting any more.
  expired,

  /// The server refused or lost it.
  failed,
}

class ApiTask {
  ApiTask({
    required this.api,
    required this.expected,
    required this.wantsFiles,
    this.spec = const {},
    this.taskId,
    this.createdAt,
    this.timeout = const Duration(seconds: 900),
    this.model,
  });

  /// The endpoint, e.g. `images.generations`.
  final String api;

  /// The server's answer contract, verbatim (English, for agent seats).
  final String expected;

  /// Whether the answer must carry files.
  final bool wantsFiles;

  /// What the server will check the answer against.
  final Map<String, dynamic> spec;
  final String? taskId;

  /// When the server opened the task; the deadline counts from here.
  final DateTime? createdAt;
  final Duration timeout;
  final String? model;

  /// Read a task from a message's `request` metadata, or null when the
  /// message is ordinary chat.
  static ApiTask? fromRequest(Map<String, dynamic>? r, {DateTime? receivedAt}) {
    if (r == null || r['kind'] != 'api') return null;
    final api = r['api'];
    if (api is! String || api.isEmpty) return null;
    final created = r['created_at'];
    final secs = r['timeout_secs'];
    final spec = r['spec'];
    return ApiTask(
      api: api,
      expected: (r['expected_format'] as String?) ?? '',
      wantsFiles: r['wants_files'] == true,
      spec: spec is Map<String, dynamic> ? spec : const {},
      taskId: r['task_id'] as String?,
      createdAt: created is num
          ? DateTime.fromMillisecondsSinceEpoch(created.toInt() * 1000)
          : receivedAt,
      timeout: Duration(seconds: secs is num && secs > 0 ? secs.toInt() : 900),
      model: r['model'] as String?,
    );
  }

  TaskKind get kind => switch (api) {
        'images.generations' => TaskKind.imageGenerate,
        'images.edits' => TaskKind.imageEdit,
        'images.variations' => TaskKind.imageVariation,
        'audio.speech' => TaskKind.speech,
        'audio.transcriptions' => TaskKind.transcription,
        'audio.translations' => TaskKind.translation,
        'completions' => TaskKind.completion,
        'moderations' => TaskKind.moderation,
        'decisions' => TaskKind.decision,
        'videos' => TaskKind.video,
        'vector_stores.search' => TaskKind.vectorSearch,
        'graders' => TaskKind.grader,
        _ => TaskKind.other,
      };

  /// What the answer is made of.
  AnswerMedia get media => switch (kind) {
        TaskKind.imageGenerate ||
        TaskKind.imageEdit ||
        TaskKind.imageVariation =>
          AnswerMedia.image,
        TaskKind.speech => AnswerMedia.audio,
        TaskKind.video => AnswerMedia.video,
        TaskKind.moderation ||
        TaskKind.decision ||
        TaskKind.vectorSearch ||
        TaskKind.grader =>
          AnswerMedia.json,
        _ => wantsFiles ? AnswerMedia.image : AnswerMedia.text,
      };

  bool get videoEdit => expected.contains('edit the attached video');
  bool get videoExtend => expected.contains('continue the attached video');
  bool get videoRemix => expected.contains('remix the attached video');

  /// The verb phrase after a person's name: "请你生成一张图片".
  String get ask => switch (kind) {
        TaskKind.imageGenerate => count > 1 ? '生成 $count 张图片' : '生成图片',
        TaskKind.imageEdit => '编辑图片',
        TaskKind.imageVariation => '生成图片变体',
        TaskKind.speech => '朗读文字',
        TaskKind.transcription => '转写录音',
        TaskKind.translation => '将录音翻译为英文',
        TaskKind.completion => count > 1 ? '续写 $count 个版本' : '续写',
        TaskKind.moderation => '内容审核',
        TaskKind.decision =>
          questionCount > 1 ? '回答 $questionCount 个问题' : '回答问题',
        TaskKind.video => videoExtend
            ? '延长视频'
            : videoEdit
                ? '编辑视频'
                : videoRemix
                    ? '重制视频'
                    : '生成视频',
        TaskKind.vectorSearch => '检索资料',
        TaskKind.grader => '评分',
        TaskKind.other => '处理请求',
      };

  /// A short noun for lists and notifications: "图片", "语音".
  String get noun => switch (kind) {
        TaskKind.imageGenerate ||
        TaskKind.imageEdit ||
        TaskKind.imageVariation =>
          '图片',
        TaskKind.speech => '语音',
        TaskKind.transcription => '转写',
        TaskKind.translation => '翻译',
        TaskKind.completion => '续写',
        TaskKind.moderation => '审核',
        TaskKind.decision => '问答',
        TaskKind.video => '视频',
        TaskKind.vectorSearch => '检索',
        TaskKind.grader => '打分',
        TaskKind.other => '请求',
      };

  /// How many items the answer should hold (images, continuations).
  int get count {
    final m = RegExp(r'^(\d+) \w+ image\(s\)').firstMatch(expected);
    if (m != null) return int.parse(m.group(1)!);
    final c = RegExp(r'(\d+) different continuations').firstMatch(expected);
    if (c != null) return int.parse(c.group(1)!);
    final n = spec['count'];
    if (n is num) return n.toInt();
    return 1;
  }

  int get questionCount {
    final q = spec['questions'];
    return q is List ? q.length : 0;
  }

  /// Image format the asker wants: png, jpeg, webp.
  String? get imageFormat =>
      RegExp(r'^\d+ (\w+) image\(s\)').firstMatch(expected)?.group(1);

  /// Audio format for a speech task: mp3, wav, opus, aac, flac, pcm.
  String? get audioFormat {
    final m = RegExp(r'^voice [^,]+, (\w+)').firstMatch(expected);
    return m?.group(1);
  }

  String? _field(RegExp re) => re.firstMatch(expected)?.group(1)?.trim();

  /// A timed transcript (SRT cues) is required.
  bool get wantsSrt => expected.contains('as SRT');

  /// Speaker labels on each cue.
  bool get wantsSpeakers => expected.contains('starting with its speaker');

  /// The spec as chips: "1024×1024", "PNG", "高质量", "声音 alloy".
  List<String> get chips {
    final out = <String>[];
    switch (kind) {
      case TaskKind.imageGenerate ||
            TaskKind.imageEdit ||
            TaskKind.imageVariation:
        final size = _field(RegExp(r'size (\d+x\d+)'));
        if (size != null) out.add(size.replaceAll('x', '×'));
        if (count > 1) out.add('$count 张');
        final f = imageFormat;
        if (f != null) out.add(f.toUpperCase());
        final q = _field(RegExp(r'quality (\w+)'));
        if (q != null) {
          out.add(const {
                'high': '高质量',
                'medium': '中等质量',
                'low': '草稿质量',
                'hd': '高清',
                'standard': '标准质量',
              }[q] ??
              '质量 $q');
        }
        final bg = _field(RegExp(r'(\w+) background'));
        if (bg != null) {
          out.add(const {
                'transparent': '透明背景',
                'opaque': '不透明背景',
              }[bg] ??
              '$bg 背景');
        }
        final st = _field(RegExp(r'(\w+) style'));
        if (st != null) {
          out.add(const {'vivid': '鲜明风格', 'natural': '自然风格'}[st] ?? st);
        }
      case TaskKind.speech:
        final v = _field(RegExp(r'^voice ([^,]+)'));
        if (v != null) out.add('声音 $v');
        final f = audioFormat;
        if (f != null) out.add(f.toUpperCase());
        final sp = _field(RegExp(r'speed ([\d.]+)'));
        if (sp != null) out.add('$sp 倍速');
      case TaskKind.transcription || TaskKind.translation:
        final l = _field(RegExp(r'\(language ([^)]+)\)'));
        if (l != null) out.add('语言 $l');
        out.add(wantsSrt ? 'SRT 字幕' : '纯文字');
        if (wantsSpeakers) out.add('区分说话人');
      case TaskKind.completion:
        if (count > 1) out.add('$count 个版本');
      case TaskKind.moderation:
        out.add('$count 条内容');
      case TaskKind.decision:
        out.add('$questionCount 个问题');
      case TaskKind.video:
        final s = _field(RegExp(r'^(\d+)s video'));
        if (s != null) out.add('$s 秒');
        final size = _field(RegExp(r'video, (\d+x\d+)'));
        if (size != null) out.add(size.replaceAll('x', '×'));
        out.add('MP4');
      case TaskKind.vectorSearch:
        final max = spec['max'];
        if (max is num) out.add('最多 ${max.toInt()} 条');
        final files = spec['files'];
        if (files is List) out.add('${files.length} 份资料');
      case TaskKind.grader:
        final labels = spec['labels'];
        final range = spec['range'];
        if (labels is List) out.add('选 1 个标签');
        if (range is List && range.length == 2) {
          out.add('分数 ${_num(range[0])}–${_num(range[1])}');
        }
      case TaskKind.other:
        break;
    }
    return out;
  }

  /// A plain-language hint about how to answer.
  String get howTo => switch (media) {
        AnswerMedia.image => '附加 $count 张图片',
        AnswerMedia.audio =>
          '附加音频${audioFormat == null ? '' : '（${audioFormat!.toUpperCase()}）'}',
        AnswerMedia.video => '附加 1 段 MP4 视频',
        AnswerMedia.json => switch (kind) {
            TaskKind.moderation => '为每条内容选择类别',
            TaskKind.decision => '逐题作答，可跳过',
            TaskKind.vectorSearch => '按相关度排序',
            TaskKind.grader => '选择标签或打分',
            _ => '按指定格式作答',
          },
        AnswerMedia.text => switch (kind) {
            TaskKind.transcription ||
            TaskKind.translation =>
              wantsSrt ? 'SRT 格式' : '仅填写文字',
            TaskKind.completion =>
              count > 1 ? '$count 个版本，用单独一行 @@@ 分隔' : '仅填写续写部分',
            _ => '',
          },
      };

  /// File extensions this task accepts as an answer.
  List<String> get acceptExtensions => switch (media) {
        AnswerMedia.image => const ['png', 'jpg', 'jpeg', 'webp', 'gif'],
        AnswerMedia.audio => const [
            'mp3',
            'wav',
            'opus',
            'ogg',
            'aac',
            'flac',
            'm4a',
            'pcm'
          ],
        AnswerMedia.video => const [
            'mp4',
            'webm',
            'mov',
            'png',
            'jpg',
            'jpeg',
            'webp'
          ],
        _ => const [],
      };

  /// When the asker stops waiting.
  DateTime? get deadline => createdAt?.add(timeout);

  /// Time left on [now]'s clock; negative once expired.
  Duration? left(DateTime now) => deadline?.difference(now);

  bool expiredAt(DateTime now) {
    final l = left(now);
    return l != null && l.isNegative;
  }
}

String _num(Object? v) {
  if (v is num) return v == v.roundToDouble() ? v.toInt().toString() : '$v';
  return '$v';
}

/// "14:32" for a countdown, "1:02:05" past an hour.
String countdown(Duration d) {
  if (d.isNegative) return '0:00';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  String two(int x) => x.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${d.inMinutes}:${two(s)}';
}

// ═══════════════════════════════════════════════════════════════
//  Media types
// ═══════════════════════════════════════════════════════════════

/// A file's broad type from its mime or name.
AnswerMedia? mediaOf({String? mime, String? name}) {
  final m = (mime ?? '').toLowerCase();
  if (m.startsWith('image/')) return AnswerMedia.image;
  if (m.startsWith('audio/')) return AnswerMedia.audio;
  if (m.startsWith('video/')) return AnswerMedia.video;
  if (m == 'application/json' || m == 'application/jsonl') {
    return AnswerMedia.json;
  }
  if (m.startsWith('text/')) return AnswerMedia.text;
  final ext = (name ?? '').split('.').last.toLowerCase();
  if (const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'].contains(ext)) {
    return AnswerMedia.image;
  }
  if (const ['mp3', 'wav', 'opus', 'ogg', 'aac', 'flac', 'm4a', 'pcm']
      .contains(ext)) {
    return AnswerMedia.audio;
  }
  if (const ['mp4', 'webm', 'mov', 'mkv'].contains(ext)) {
    return AnswerMedia.video;
  }
  if (const ['json', 'jsonl'].contains(ext)) return AnswerMedia.json;
  if (const ['txt', 'md', 'srt', 'vtt', 'csv'].contains(ext)) {
    return AnswerMedia.text;
  }
  return null;
}

/// The mime for a file name, for attachments the server should not have
/// to sniff.
String mimeForName(String name) {
  final ext = name.split('.').last.toLowerCase();
  return const {
        'png': 'image/png',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'webp': 'image/webp',
        'gif': 'image/gif',
        'mp3': 'audio/mpeg',
        'wav': 'audio/wav',
        'opus': 'audio/opus',
        'ogg': 'audio/ogg',
        'aac': 'audio/aac',
        'flac': 'audio/flac',
        'm4a': 'audio/mp4',
        'pcm': 'audio/pcm',
        'mp4': 'video/mp4',
        'webm': 'video/webm',
        'mov': 'video/quicktime',
        'json': 'application/json',
        'jsonl': 'application/jsonl',
        'txt': 'text/plain',
        'srt': 'application/x-subrip',
        'vtt': 'text/vtt',
      }[ext] ??
      'application/octet-stream';
}

/// A `data:` URL split into (mime, bytes), or null.
(String, List<int>)? decodeDataUrl(String url) {
  if (!url.startsWith('data:')) return null;
  final comma = url.indexOf(',');
  if (comma < 0) return null;
  final head = url.substring(5, comma);
  if (!head.endsWith(';base64')) return null;
  try {
    final bytes = base64Decode(url.substring(comma + 1));
    return (head.split(';').first, bytes);
  } catch (_) {
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════
//  Answer checks (mirror the server)
// ═══════════════════════════════════════════════════════════════

/// A file ready to send with an answer.
class DraftFile {
  const DraftFile({required this.name, required this.size, this.mime});
  final String name;
  final int size;
  final String? mime;
  AnswerMedia? get media => mediaOf(mime: mime, name: name);
}

/// A file I picked to send.
class OutgoingFile {
  const OutgoingFile({required this.name, required this.bytes, this.mime});
  final String name;
  final Uint8List bytes;
  final String? mime;

  DraftFile get draft => DraftFile(name: name, size: bytes.length, mime: mime);
}

/// What [checkAnswer] found.
class AnswerCheck {
  const AnswerCheck._(this.error, this.warning, this.refusal);
  const AnswerCheck.ok() : this._(null, null, false);
  const AnswerCheck.error(String e) : this._(e, null, false);
  const AnswerCheck.warn(String w) : this._(null, w, false);
  const AnswerCheck.refusal() : this._(null, null, true);

  /// Blocks sending.
  final String? error;

  /// Worth a second look, but allowed.
  final String? warning;

  /// A file task answered with text only: the contract reads it as a
  /// refusal, so the UI should say so before sending.
  final bool refusal;

  bool get ok => error == null;
}

/// Check an answer before it is sent, the way the server will.
AnswerCheck checkAnswer(ApiTask t, String text, List<DraftFile> files) {
  final body = text.trim();
  switch (t.media) {
    case AnswerMedia.image || AnswerMedia.audio || AnswerMedia.video:
      if (files.isEmpty) {
        return body.isEmpty
            ? const AnswerCheck.error('请添加文件或文字。')
            : const AnswerCheck.refusal();
      }
      final want = t.media;
      if (want == AnswerMedia.video) {
        final videos = files.where((f) => f.media == AnswerMedia.video).length;
        final other = files.where(
          (f) => f.media != AnswerMedia.video && f.media != AnswerMedia.image,
        );
        if (other.isNotEmpty) {
          return AnswerCheck.error('“${other.first.name}”不是视频或图片。');
        }
        if (videos == 0) return const AnswerCheck.error('需要 1 段视频。');
        if (videos > 1) return const AnswerCheck.warn('仅使用第一段视频。');
        return const AnswerCheck.ok();
      }
      final wrong = files.where((f) => f.media != want).toList();
      if (wrong.isNotEmpty) {
        final what = want == AnswerMedia.image ? '图片' : '音频';
        return AnswerCheck.error('“${wrong.first.name}”不是$what文件。');
      }
      if (want == AnswerMedia.image && files.length != t.count) {
        return AnswerCheck.warn(
          '需要 ${t.count} 张，已添加 ${files.length} 张。',
        );
      }
      if (want == AnswerMedia.audio && files.length > 1) {
        return const AnswerCheck.warn('仅使用第一个音频文件。');
      }
      final fmt = want == AnswerMedia.image ? t.imageFormat : t.audioFormat;
      if (fmt != null) {
        final norm = fmt == 'jpeg' ? const ['jpg', 'jpeg'] : [fmt];
        final off = files.where(
          (f) => !norm.contains(f.name.split('.').last.toLowerCase()),
        );
        if (off.isNotEmpty) {
          return AnswerCheck.warn('需要 ${fmt.toUpperCase()} 格式。');
        }
      }
      return const AnswerCheck.ok();
    case AnswerMedia.json:
      if (body.isEmpty) return const AnswerCheck.error('请作答。');
      final e = switch (t.kind) {
        TaskKind.moderation => checkModeration(body, t.spec),
        TaskKind.decision => checkDecisions(body, t.spec),
        TaskKind.vectorSearch => checkHits(body, t.spec),
        TaskKind.grader => checkGrade(body, t.spec),
        _ => null,
      };
      return e == null ? const AnswerCheck.ok() : AnswerCheck.error(e);
    case AnswerMedia.text:
      if (body.isEmpty) return const AnswerCheck.error('请输入回复。');
      if (t.wantsSrt) {
        final e = checkSrt(body);
        if (e != null) return AnswerCheck.error(e);
      }
      if (t.kind == TaskKind.completion && t.count > 1) {
        final parts = body.split(RegExp(r'^\s*@@@\s*$', multiLine: true));
        if (parts.length != t.count) {
          return AnswerCheck.warn(
            '需要 ${t.count} 个版本，当前 ${parts.length} 个。',
          );
        }
      }
      return const AnswerCheck.ok();
  }
}

/// Moderation categories, as the server knows them.
const moderationCategories = [
  'harassment',
  'harassment/threatening',
  'hate',
  'hate/threatening',
  'illicit',
  'illicit/violent',
  'self-harm',
  'self-harm/intent',
  'self-harm/instructions',
  'sexual',
  'sexual/minors',
  'violence',
  'violence/graphic',
];

/// Chinese names for the moderation categories.
const moderationLabels = {
  'harassment': '骚扰',
  'harassment/threatening': '骚扰（含威胁）',
  'hate': '仇恨',
  'hate/threatening': '仇恨（含威胁）',
  'illicit': '违法',
  'illicit/violent': '违法（暴力）',
  'self-harm': '自我伤害',
  'self-harm/intent': '自伤意图',
  'self-harm/instructions': '自伤方法',
  'sexual': '色情',
  'sexual/minors': '涉及未成年人的色情',
  'violence': '暴力',
  'violence/graphic': '血腥暴力',
};

Object? _json(String s) {
  try {
    return jsonDecode(s.trim());
  } catch (_) {
    return const _Bad();
  }
}

class _Bad {
  const _Bad();
}

/// Mirrors `moderations::parse_verdicts`.
String? checkModeration(String text, Map<String, dynamic> spec) {
  final count = (spec['count'] as num?)?.toInt() ?? 1;
  var v = _json(text);
  if (v is _Bad) return '需要 JSON 格式，例如 [[], ["violence"]]。';
  if (v is Map && v.containsKey('results')) v = v['results'];
  List list;
  if (v is List && count == 1 && v.every((x) => x is String)) {
    list = [v];
  } else if (v is Map && count == 1) {
    list = [v];
  } else if (v is List) {
    list = v;
  } else {
    return '需要 JSON 列表。';
  }
  if (list.length != count) {
    return '共 $count 条内容，当前 ${list.length} 项。';
  }
  bool known(String c) {
    final k = c.trim().toLowerCase().replaceAll('_', '-').replaceAll('/', '-');
    return moderationCategories.any((x) => x.replaceAll('/', '-') == k);
  }

  for (var i = 0; i < list.length; i++) {
    final e = list[i];
    final n = i + 1;
    if (e == null) continue;
    if (e is List) {
      for (final c in e) {
        if (c is! String) return '第 $n 项：类别名称无效。';
        if (!known(c)) return '第 $n 项：未知类别“$c”。';
      }
    } else if (e is Map) {
      final o = e['categories'] is Map ? e['categories'] as Map : e;
      for (final entry in o.entries) {
        final s = entry.value;
        final score =
            s is bool ? (s ? 1.0 : 0.0) : (s is num ? s.toDouble() : null);
        if (score == null) return '第 $n 项：“${entry.key}”需为分数或 true/false。';
        if (score < 0 || score > 1) {
          return '第 $n 项：“${entry.key}”需在 0 到 1 之间。';
        }
        if (!known('${entry.key}')) return '第 $n 项：未知类别“${entry.key}”。';
      }
    } else {
      return '第 $n 项：格式无效。';
    }
  }
  return null;
}

/// Mirrors `decisions::parse_answers`.
String? checkDecisions(String text, Map<String, dynamic> spec) {
  final qs = (spec['questions'] as List?) ?? const [];
  var v = _json(text);
  if (v is _Bad) return '需要 JSON 列表。';
  if (v is Map && v.containsKey('answers')) v = v['answers'];
  final List list;
  if (v is List) {
    list = v;
  } else if (qs.length == 1) {
    list = [v];
  } else {
    return '需要 JSON 列表。';
  }
  if (list.length != qs.length) {
    return '共 ${qs.length} 个问题，当前 ${list.length} 项。';
  }
  for (var i = 0; i < qs.length; i++) {
    final n = i + 1;
    final q = qs[i] is Map ? qs[i] as Map : const {};
    var a = list[i];
    double? conf;
    if (a is Map && a.containsKey('answer')) {
      final c = a['confidence'];
      conf = c is num ? c.toDouble() : null;
      a = a['answer'];
    }
    if (conf != null && (conf < 0 || conf > 1)) {
      return '第 $n 题：需在 0 到 1 之间。';
    }
    if (a == null) continue;
    switch (q['type']) {
      case 'predicate':
        final p = a is bool ? 0.5 : (a is num ? a.toDouble() : -1.0);
        if (p < 0 || p > 1) return '第 $n 题：需为 0 到 1 或 true/false。';
      case 'choice':
        final values = (q['values'] as List?) ?? const [];
        final hit = values.any(
          (x) =>
              x == a ||
              (x is String &&
                  a is String &&
                  x.toLowerCase() == a.trim().toLowerCase()),
        );
        if (!hit) return '第 $n 题：请选择 ${values.join('、')}。';
      case 'score':
        final labels = (q['labels'] as List?) ?? const [];
        final hit = a is String
            ? labels.any(
                (l) => l is String && l.toLowerCase() == a.trim().toLowerCase())
            : a is int && a >= 0 && a < labels.length;
        if (!hit) return '第 $n 题：请选择 ${labels.join('、')}。';
      default:
        return '第 $n 题：不支持的题型。';
    }
  }
  return null;
}

/// Mirrors `vector_stores::parse_hits`.
String? checkHits(String text, Map<String, dynamic> spec) {
  final max = (spec['max'] as num?)?.toInt() ?? 10;
  final files = (spec['files'] as List?) ?? const [];
  var v = _json(text);
  if (v is _Bad) {
    return '需要 JSON 格式：[{"file": "…", "score": 0.9, "text": "…"}]。';
  }
  if (v is Map) v = v['data'] ?? v['results'] ?? v;
  if (v is! List) return '需要 JSON 列表。';
  if (v.length > max) return '最多 $max 条，当前 ${v.length} 条。';
  for (var i = 0; i < v.length; i++) {
    final h = v[i];
    final n = i + 1;
    if (h is! Map) return '第 $n 条：格式无效。';
    final f = h['file'] ?? h['file_id'] ?? h['filename'];
    if (f is! String) return '第 $n 条：缺少 file。';
    final ok =
        files.any((x) => x is Map && (x['id'] == f || x['filename'] == f));
    if (!ok) return '第 $n 条：未找到“$f”。';
    final t = h['text'] ?? h['content'];
    if (t is! String) return '第 $n 条：缺少 text。';
    final s = h['score'];
    if (s != null && (s is! num || s < 0 || s > 1)) {
      return '第 $n 条：score 需在 0 到 1 之间。';
    }
  }
  return null;
}

/// Mirrors `evals::check_grade`.
String? checkGrade(String text, Map<String, dynamic> spec) {
  final v = _json(text);
  if (v is! Map) return '需要 JSON 格式，例如 {"score": 0.8}。';
  final labels = spec['labels'];
  if (labels is List) {
    final l = v['label'];
    if (l is! String) return '缺少 label。';
    if (!labels.contains(l)) return '标签需为 ${labels.join('、')}。';
    return null;
  }
  final s = v['score'];
  if (s is! num) return '缺少 score。';
  final r = spec['range'];
  if (r is List && r.length == 2 && r[0] is num && r[1] is num) {
    if (s < (r[0] as num) || s > (r[1] as num)) {
      return '分数需在 ${_num(r[0])} 到 ${_num(r[1])} 之间。';
    }
  }
  return null;
}

/// A transcript in SRT: numbered cues with `HH:MM:SS,mmm --> HH:MM:SS,mmm`.
String? checkSrt(String text) {
  final cues = text
      .replaceAll('\r\n', '\n')
      .trim()
      .split(RegExp(r'\n\s*\n'))
      .where((c) => c.trim().isNotEmpty)
      .toList();
  if (cues.isEmpty) return '请输入字幕。';
  final time = RegExp(
    r'^\d{1,2}:\d{2}:\d{2}[,.]\d{1,3}\s*-->\s*\d{1,2}:\d{2}:\d{2}[,.]\d{1,3}',
  );
  for (var i = 0; i < cues.length; i++) {
    final lines = cues[i].trim().split('\n');
    final tl = lines.indexWhere((l) => time.hasMatch(l.trim()));
    if (tl < 0) {
      return '第 ${i + 1} 段：缺少时间轴。';
    }
    if (tl >= lines.length - 1) return '第 ${i + 1} 段：缺少文字。';
  }
  return null;
}

/// Build the moderation answer from per-item category picks.
String moderationAnswer(List<Set<String>> picks) =>
    jsonEncode([for (final p in picks) p.toList()]);
