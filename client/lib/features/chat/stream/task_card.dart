/// A task someone asked of you, as a card in the conversation.
///
/// Someone's tool called a non-chat endpoint — make a picture, read a
/// text aloud, moderate some posts — and the server handed the request
/// to you. The card says it in people's terms ("林晓 请你生成一张图片"),
/// shows the spec as chips, counts down to the moment the asker stops
/// waiting, and holds the right editor for the answer: files for media,
/// pickers for structured answers, a text box for text. The answer is
/// checked the way the server will check it before it goes.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/adaptive.dart';
import '../../../app/tokens.dart';
import '../../../core/files_io.dart';
import '../../../core/tasks.dart';
import '../../../widgets/controls.dart';
import '../../../widgets/glyphs.dart';
import '../../../widgets/motion.dart';
import '../chat_controller.dart';
import 'attachments.dart';
import 'rich_text.dart';
import '../../../widgets/haptics.dart';

Glyph glyphForTask(ApiTask t) => switch (t.kind) {
      TaskKind.imageGenerate ||
      TaskKind.imageEdit ||
      TaskKind.imageVariation =>
        Glyph.image,
      TaskKind.speech => Glyph.speaker,
      TaskKind.transcription || TaskKind.translation => Glyph.mic,
      TaskKind.video => Glyph.film,
      TaskKind.moderation => Glyph.shield,
      TaskKind.decision || TaskKind.grader => Glyph.quiz,
      TaskKind.vectorSearch => Glyph.search,
      TaskKind.completion || TaskKind.other => Glyph.edit,
    };

class TaskCard extends ConsumerStatefulWidget {
  const TaskCard({
    super.key,
    required this.messageId,
    required this.task,
    required this.person,
    required this.prompt,
    this.inputs = const [],
    this.answeredBefore = false,
    this.now,
  });

  final String messageId;
  final ApiTask task;

  /// Who asked, as the conversation names them.
  final String person;

  /// What they wrote with the request.
  final String prompt;

  /// Files that came with it (the picture to edit, the audio to
  /// transcribe, the inputs to moderate).
  final List<types.Message> inputs;

  /// A reply of mine already follows this task (reopened history).
  final bool answeredBefore;

  /// Pins the clock (tests and screenshots).
  final DateTime? now;

  @override
  ConsumerState<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends ConsumerState<TaskCard> {
  final _text = TextEditingController();
  final _files = <OutgoingFile>[];
  Timer? _tick;
  String? _note;
  bool _noteIsError = true;
  bool _rawJson = false;

  // Structured answers.
  late List<Set<String>> _moderation =
      List.generate(widget.task.count, (_) => <String>{});
  late List<Object?> _decisions =
      List.filled(widget.task.questionCount, _unset);
  String? _gradeLabel;

  static const _unset = Object();

  ApiTask get t => widget.task;

  @override
  void initState() {
    super.initState();
    if (Mo.loops && widget.now == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
    if (t.kind == TaskKind.vectorSearch) _text.text = '[]';
  }

  @override
  void dispose() {
    _tick?.cancel();
    _text.dispose();
    super.dispose();
  }

  DateTime get _now => widget.now ?? DateTime.now();

  TaskState _state(TaskOutcome? o) {
    if (o != null && o.state != TaskState.open) return o.state;
    if (widget.answeredBefore) return TaskState.answered;
    if (t.expiredAt(_now)) return TaskState.expired;
    return TaskState.open;
  }

  /// The answer text, built from the structured editors where there is
  /// one.
  String _answerText() {
    if (_rawJson) return _text.text;
    switch (t.kind) {
      case TaskKind.moderation:
        return moderationAnswer(_moderation);
      case TaskKind.decision:
        if (_decisions.any((d) => identical(d, _unset))) return '';
        return encodeJson(_decisions);
      case TaskKind.grader:
        final labels = t.spec['labels'];
        if (labels is List) {
          return _gradeLabel == null ? '' : encodeJson({'label': _gradeLabel});
        }
        final v = num.tryParse(_text.text.trim());
        return v == null ? _text.text : encodeJson({'score': v});
      default:
        return _text.text;
    }
  }

  Future<void> _pick() async {
    try {
      final picked = await FilesIo.pick(t.acceptExtensions);
      if (!mounted || picked.isEmpty) return;
      setState(() {
        _files.addAll(picked);
        _check(quiet: true);
      });
    } catch (_) {
      if (mounted) toast(context, '无法打开文件');
    }
  }

  AnswerCheck _check({bool quiet = false}) {
    final c = checkAnswer(t, _answerText(), [for (final f in _files) f.draft]);
    if (!quiet) {
      _note = c.error ?? c.warning;
      _noteIsError = c.error != null;
    } else if (_note != null) {
      _note = c.error ?? c.warning;
      _noteIsError = c.error != null;
    }
    return c;
  }

  Future<void> _send({bool decline = false}) async {
    if (!decline) {
      final c = _check();
      setState(() {});
      if (!c.ok) {
        Haptic.warn();
        return;
      }
      if (c.refusal) {
        final ok = await _confirmRefusal();
        if (ok != true) return;
      }
    }
    final out = await ref.read(chatControllerProvider.notifier).answerTask(
          taskMessageId: widget.messageId,
          task: t,
          text: decline ? _text.text : _answerText(),
          files: decline ? const [] : List.of(_files),
          decline: decline,
        );
    if (!mounted) return;
    setState(() {
      _note = out.note;
      _noteIsError = out.state == TaskState.open;
      if (out.state == TaskState.answered || out.state == TaskState.declined) {
        _files.clear();
        _text.clear();
      }
    });
  }

  Future<bool?> _confirmRefusal() => showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('未添加文件'),
          content: const Text(
            '仅发送文字将视为拒绝此请求。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('发送'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final outcome = ref.watch(
      taskOutcomesProvider.select((m) => m[widget.messageId]),
    );
    final state = _state(outcome);
    final open = state == TaskState.open || state == TaskState.sending;
    final hot = state == TaskState.open;
    final note = _note ?? (state == TaskState.open ? null : outcome?.note);

    final card = AnimatedContainer(
      duration: Mo.of(context, Mo.base),
      curve: Mo.soft,
      decoration: BoxDecoration(
        color: Dk.p2,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(color: hot ? Dk.signalEdge : Dk.line),
        boxShadow: hot
            ? [
                BoxShadow(
                    color: Dk.signalGlow, blurRadius: 28, spreadRadius: -6),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Head(task: t, person: widget.person, state: state, now: _now),
          if (t.chips.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x3),
              child: Wrap(
                spacing: Sp.x15,
                runSpacing: Sp.x15,
                children: [
                  for (final c in t.chips) Tag(c, color: Dk.t2, floor: Dk.p3),
                ],
              ),
            ),
          Divider(height: 1, color: Dk.line),
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x3, Sp.x4, Sp.x3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('原始请求', style: Ty.label),
                const SizedBox(height: Sp.x15),
                _Folded(text: widget.prompt),
                if (widget.inputs.isNotEmpty) ...[
                  const SizedBox(height: Sp.x3),
                  AttachmentList(items: widget.inputs),
                ],
              ],
            ),
          ),
          Reveal(
            open: open,
            child: _answerArea(context, state),
          ),
          if (!open && note == null) const SizedBox(height: Sp.x05),
          if (note != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                Sp.x4,
                open ? 0 : Sp.x05,
                Sp.x4,
                Sp.x3,
              ),
              child: _Note(text: note, error: _noteIsError && open),
            ),
        ],
      ),
    );

    return Semantics(
      container: true,
      label: '${widget.person}${t.ask}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Sz.measure),
        child: card,
      ),
    );
  }

  Widget _answerArea(BuildContext context, TaskState state) {
    final sending = state == TaskState.sending;
    return Container(
      decoration: BoxDecoration(
        color: Dk.p1,
        border: Border(top: BorderSide(color: Dk.line)),
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(Rd.xl)),
      ),
      padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x3, Sp.x4, Sp.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('回复', style: Ty.label),
              const Spacer(),
              if (t.media == AnswerMedia.json &&
                  t.kind != TaskKind.vectorSearch)
                _LinkButton(
                  label: _rawJson ? '选项' : 'JSON',
                  onTap: () => setState(() {
                    if (!_rawJson) _text.text = _answerText();
                    _rawJson = !_rawJson;
                  }),
                ),
            ],
          ),
          if (t.howTo.isNotEmpty) ...[
            const SizedBox(height: Sp.x1),
            Text(t.howTo, style: Ty.small.copyWith(color: Dk.t2)),
          ],
          const SizedBox(height: Sp.x3),
          _editor(),
          const SizedBox(height: Sp.x3),
          Row(
            children: [
              if (t.media == AnswerMedia.image ||
                  t.media == AnswerMedia.audio ||
                  t.media == AnswerMedia.video)
                DkButton(
                  label: switch (t.media) {
                    AnswerMedia.image => '添加图片',
                    AnswerMedia.audio => '添加音频',
                    _ => '添加视频',
                  },
                  glyph: Glyph.attach,
                  dense: true,
                  onTap: sending ? null : _pick,
                ),
              const Spacer(),
              DkButton(
                label: '拒绝',
                kind: DkButtonKind.quiet,
                dense: true,
                semanticLabel: '拒绝请求',
                onTap: sending ? null : () => _send(decline: true),
              ),
              const SizedBox(width: Sp.x2),
              DkButton(
                key: ValueKey('task-send-${widget.messageId}'),
                label: '发送',
                kind: DkButtonKind.signal,
                trailing: Glyph.send,
                dense: true,
                busy: sending,
                onTap: () => _send(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _editor() {
    final textBox = _AnswerField(
      controller: _text,
      hint: switch (t.media) {
        AnswerMedia.image => '说明（可选）',
        AnswerMedia.audio || AnswerMedia.video => '说明（可选）',
        AnswerMedia.json => '[ … ]',
        AnswerMedia.text =>
          t.wantsSrt ? '1\n00:00:00,000 --> 00:00:02,000\n第一句话' : '回答',
      },
      mono: t.media == AnswerMedia.json || t.wantsSrt,
      minLines:
          t.media == AnswerMedia.text || t.media == AnswerMedia.json ? 3 : 1,
      onChanged: () => setState(() => _check(quiet: true)),
    );
    if (_rawJson || t.kind == TaskKind.vectorSearch) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (t.kind == TaskKind.vectorSearch) _storeFiles(),
          textBox,
        ],
      );
    }
    switch (t.media) {
      case AnswerMedia.image || AnswerMedia.audio || AnswerMedia.video:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_files.isNotEmpty) ...[
              Wrap(
                spacing: Sp.x2,
                runSpacing: Sp.x2,
                children: [
                  for (final f in _files)
                    DraftChip(
                      file: f,
                      onRemove: () => setState(() {
                        _files.remove(f);
                        _check(quiet: true);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: Sp.x2),
            ],
            textBox,
          ],
        );
      case AnswerMedia.json:
        return switch (t.kind) {
          TaskKind.moderation => _moderationEditor(),
          TaskKind.decision => _decisionEditor(),
          TaskKind.grader => _gradeEditor(textBox),
          _ => textBox,
        };
      case AnswerMedia.text:
        return textBox;
    }
  }

  Widget _storeFiles() {
    final files = (t.spec['files'] as List?) ?? const [];
    if (files.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.x2),
      child: Wrap(
        spacing: Sp.x15,
        runSpacing: Sp.x15,
        children: [
          for (final f in files.whereType<Map>())
            Tag('${f['filename'] ?? f['id']}', mono: true, glyph: Glyph.folder),
        ],
      ),
    );
  }

  Widget _moderationEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _moderation.length; i++) ...[
          if (i > 0) const SizedBox(height: Sp.x3),
          Text(
            '第 ${i + 1} 条 · ${_moderation[i].isEmpty ? '没问题' : '${_moderation[i].length} 项违规'}',
            style: Ty.name.copyWith(fontSize: 12.5),
          ),
          const SizedBox(height: Sp.x15),
          Wrap(
            spacing: Sp.x15,
            runSpacing: Sp.x15,
            children: [
              for (final c in moderationCategories)
                _Choice(
                  label: moderationLabels[c] ?? c,
                  on: _moderation[i].contains(c),
                  onTap: () => setState(() {
                    final s = _moderation[i];
                    s.contains(c) ? s.remove(c) : s.add(c);
                    _moderation = [..._moderation];
                    _check(quiet: true);
                  }),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _decisionEditor() {
    final qs = (t.spec['questions'] as List?) ?? const [];
    // The questions as the person wrote them, from the message.
    final lines = RegExp(r'^\d+\. \([^)]*\) (.*)$', multiLine: true)
        .allMatches(widget.prompt)
        .map((m) => m.group(1)!)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < qs.length; i++) ...[
          if (i > 0) const SizedBox(height: Sp.x3),
          Text(
            '${i + 1}. ${i < lines.length ? lines[i] : (qs[i] is Map ? (qs[i]['name'] ?? '') : '')}',
            style: Ty.name.copyWith(fontSize: 12.5),
          ),
          const SizedBox(height: Sp.x15),
          Wrap(
            spacing: Sp.x15,
            runSpacing: Sp.x15,
            children: [
              ..._optionsFor(qs[i] is Map ? qs[i] as Map : const {})
                  .map((o) => _Choice(
                        label: o.$1,
                        on: !identical(_decisions[i], _unset) &&
                            _decisions[i] == o.$2,
                        onTap: () => setState(() {
                          _decisions = [..._decisions]..[i] = o.$2;
                          _check(quiet: true);
                        }),
                      )),
              _Choice(
                label: '跳过',
                on: _decisions[i] == null,
                quiet: true,
                onTap: () => setState(() {
                  _decisions = [..._decisions]..[i] = null;
                  _check(quiet: true);
                }),
              ),
            ],
          ),
        ],
      ],
    );
  }

  List<(String, Object?)> _optionsFor(Map q) => switch (q['type']) {
        'predicate' => const [('是', true), ('否', false)],
        'choice' => [
            for (final v in (q['values'] as List?) ?? const []) ('$v', v),
          ],
        'score' => [
            for (final l in (q['labels'] as List?) ?? const []) ('$l', l),
          ],
        _ => const [],
      };

  Widget _gradeEditor(Widget textBox) {
    final labels = t.spec['labels'];
    if (labels is List) {
      return Wrap(
        spacing: Sp.x15,
        runSpacing: Sp.x15,
        children: [
          for (final l in labels)
            _Choice(
              label: '$l',
              on: _gradeLabel == l,
              onTap: () => setState(() {
                _gradeLabel = '$l';
                _check(quiet: true);
              }),
            ),
        ],
      );
    }
    return textBox;
  }
}

String encodeJson(Object? v) => jsonEncode(v);

class _Head extends StatelessWidget {
  const _Head({
    required this.task,
    required this.person,
    required this.state,
    required this.now,
  });
  final ApiTask task;
  final String person;
  final TaskState state;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final left = task.left(now);
    final soon = left != null && left.inMinutes < 2;
    final (label, fg, bg) = switch (state) {
      TaskState.open => (
          left == null ? '待回答' : '剩余 ${countdown(left)}',
          soon ? Dk.warn : Dk.signal,
          soon ? Dk.warnSoft : Dk.signalSoft,
        ),
      TaskState.sending => ('正在发送…', Dk.t2, Dk.p3),
      TaskState.answered => ('已回答', Dk.ok, Dk.okSoft),
      TaskState.declined => ('已拒绝', Dk.t2, Dk.p3),
      TaskState.expired => ('已过期', Dk.t3, Dk.p3),
      TaskState.failed => ('失败', Dk.danger, Dk.dangerSoft),
    };
    final compact = Fit.of(context).isCompact;
    final title = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: task.ask,
            style: Ty.name.copyWith(
              fontSize: 14.5,
              color: state == TaskState.expired ? Dk.t3 : Dk.t1,
            ),
          ),
        ],
      ),
    );
    final pill = Swap(
      value: label,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: Sp.x25, vertical: Sp.x1),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Rd.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state == TaskState.open) ...[
              BreathingDot(color: fg, size: Sz.dotSm),
              const SizedBox(width: Sp.x15),
            ],
            Text(
              label,
              style: Ty.meta.copyWith(
                color: fg,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
    final icon = Container(
      width: Sz.avatar,
      height: Sz.avatar,
      decoration: BoxDecoration(
        color: state == TaskState.open ? Dk.signalSoft : Dk.p3,
        borderRadius: BorderRadius.circular(Rd.md),
      ),
      child: Center(
        child: GlyphIcon(
          glyphForTask(task),
          size: Sz.glyph,
          color: state == TaskState.open ? Dk.signal : Dk.t2,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x35, Sp.x3, Sp.x3),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [icon, const Spacer(), pill]),
                const SizedBox(height: Sp.x25),
                title,
              ],
            )
          : Row(
              children: [
                icon,
                const SizedBox(width: Sp.x3),
                Expanded(child: title),
                const SizedBox(width: Sp.x3),
                pill,
              ],
            ),
    );
  }
}

/// The asker's words, folded when long.
class _Folded extends StatefulWidget {
  const _Folded({required this.text});
  final String text;

  @override
  State<_Folded> createState() => _FoldedState();
}

class _FoldedState extends State<_Folded> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final long =
        widget.text.length > 420 || '\n'.allMatches(widget.text).length > 10;
    final body =
        RichMessageText(widget.text, style: Ty.body.copyWith(color: Dk.prose));
    if (!long) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: Mo.of(context, Mo.base),
          curve: Mo.expo,
          alignment: Alignment.topLeft,
          child: _open
              ? body
              : SizedBox(
                  height: 120,
                  child: ShaderMask(
                    shaderCallback: (r) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white, Colors.transparent],
                      stops: [0.55, 1],
                    ).createShader(r),
                    blendMode: BlendMode.dstIn,
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: body,
                    ),
                  ),
                ),
        ),
        _LinkButton(
          label: _open ? '收起' : '显示更多',
          onTap: () => setState(() => _open = !_open),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, required this.error});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: Sp.x05),
            child: GlyphIcon(
              Glyph.alert,
              size: Sz.glyphXs,
              color: error ? Dk.danger : Dk.t3,
            ),
          ),
          const SizedBox(width: Sp.x15),
          Expanded(
            child: Text(
              text,
              style: Ty.small.copyWith(color: error ? Dk.dangerInk : Dk.t2),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnswerField extends StatelessWidget {
  const _AnswerField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.mono = false,
    this.minLines = 1,
  });
  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;
  final bool mono;
  final int minLines;

  @override
  Widget build(BuildContext context) {
    final style = mono
        ? Ty.code.copyWith(color: Dk.t1, height: 1.6)
        : Ty.body.copyWith(color: Dk.t1);
    OutlineInputBorder edge(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rd.md),
          borderSide: BorderSide(color: c),
        );
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: 12,
      style: style,
      cursorColor: Dk.signal,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Dk.bg,
        hintText: hint,
        hintStyle: style.copyWith(color: Dk.t4),
        contentPadding: const EdgeInsets.all(Sp.x3),
        border: edge(Dk.line2),
        enabledBorder: edge(Dk.line2),
        focusedBorder: edge(Dk.focus),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.on,
    required this.onTap,
    this.quiet = false,
  });
  final String label;
  final bool on;
  final VoidCallback onTap;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      semanticLabel: label,
      selected: on,
      radius: Rd.pill,
      onTap: onTap,
      builder: (context, s) => AnimatedContainer(
        duration: Mo.of(context, Mo.instant),
        padding: EdgeInsets.symmetric(
          horizontal: Sp.x3,
          vertical: Touch.primary ? Sp.x25 : Sp.x1 + 1,
        ),
        decoration: BoxDecoration(
          color: on ? Dk.paper : (s.lit ? Dk.p3 : Dk.p2),
          borderRadius: BorderRadius.circular(Rd.pill),
          border: Border.all(color: on ? Dk.paper : Dk.line2),
        ),
        child: Text(
          label,
          style: Ty.small.copyWith(
            fontSize: 12.5,
            color: on ? Dk.ink : (quiet ? Dk.t3 : Dk.t1),
            fontWeight: on ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      semanticLabel: label,
      radius: Rd.xs,
      onTap: onTap,
      builder: (context, s) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.x1),
        child: Text(
          label,
          style: Ty.small.copyWith(
            fontSize: 12,
            color: s.lit ? Dk.t1 : Dk.t2,
            decoration: s.lit ? TextDecoration.underline : null,
            decorationColor: Dk.t2,
          ),
        ),
      ),
    );
  }
}
