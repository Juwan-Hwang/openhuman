/// The message stream: two people talking, at equal weight.
///
/// The other person types in their own AI tool, which is only the
/// transport, so their messages read as theirs: on the left, with their
/// avatar and name (and a small "经由 Claude Code" tag) on the first
/// message of a run. Mine sit on the right, on a floor a breath warmer
/// than theirs, with their delivery state under the last of a run.
///
/// * A run is one person's messages close together; it shares one
///   avatar and one name line.
/// * Clocks are Beijing time. On a desktop a continuation shows its
///   time when the pointer is over it; on touch the run's head says it.
/// * Something someone asked of you through an API (a picture, a
///   recording…) is a [TaskCard]; files ride with the message they came
///   with, as an [AttachmentList].
/// * A failed send stays in place, says why, and offers 重试.
///
/// Built on a reversed lazy [ListView], so a stream of thousands of
/// messages lays out only what is on screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;

import '../../../app/adaptive.dart';
import '../../../app/tokens.dart';
import '../../../core/identity.dart';
import '../../../core/tasks.dart';
import '../../../widgets/avatar.dart';
import '../../../widgets/brand.dart';
import '../../../widgets/controls.dart';
import '../../../widgets/glyphs.dart';
import '../../../widgets/motion.dart';
import '../message_adapter.dart';
import 'attachments.dart';
import 'rich_text.dart';
import 'task_card.dart';

/// Messages closer than this from one person fold into one run.
const Duration _runWindow = Duration(minutes: 3);

/// Files sent with a message land a moment apart at most.
const Duration _withWindow = Duration(seconds: 2);

/// The wall clock in Beijing for an epoch time. China keeps one zone
/// and no daylight saving, so this is a fixed eight hours.
DateTime beijing(int epochMs) =>
    DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true)
        .add(const Duration(hours: 8));

String hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// The day marker for wall time [t], seen on day [now].
String dayLabel(DateTime t, DateTime now) {
  final d = DateTime(t.year, t.month, t.day);
  final n = DateTime(now.year, now.month, now.day);
  final diff = n.difference(d).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  if (t.year == now.year) return '${t.month} 月 ${t.day} 日';
  return '${t.year} 年 ${t.month} 月 ${t.day} 日';
}

final _attachmentId = RegExp(r'^(.+)-(img|file)\d+$');

/// One thing in the stream: a message, the files that came with it, or
/// a task card.
class StreamItem {
  StreamItem({this.text, List<types.Message>? files})
      : files = files ?? <types.Message>[];

  /// The written part, when there is one.
  types.TextMessage? text;

  /// Pictures and files sent with it (or on their own).
  final List<types.Message> files;

  /// First of a run: avatar and name line.
  bool head = true;

  /// Last of a run: my delivery state goes under it.
  bool tail = true;

  /// First of a calendar day (Beijing): a day marker above.
  bool dayBreak = true;

  /// A reply of mine follows this task.
  bool answered = false;

  types.Message get lead => text ?? files.first;
  String get id => lead.id;
  types.User get author => lead.author;
  int get at => lead.createdAt ?? 0;

  /// What was asked of me, if this is a task.
  late final ApiTask? task = text == null ? null : taskOf(text!);

  /// The worst delivery state among the parts: one failed file fails
  /// the whole message.
  types.Status? get status {
    final all = [if (text != null) text!, ...files];
    for (final s in [types.Status.error, types.Status.sending]) {
      if (all.any((m) => m.status == s)) return s;
    }
    if (all.every((m) => m.status == types.Status.delivered)) {
      return types.Status.delivered;
    }
    return all.first.status;
  }

  /// Why it did not go out.
  String? get failure {
    for (final m in [if (text != null) text!, ...files]) {
      final f = m.metadata?[kFailure];
      if (f is String) return f;
    }
    return null;
  }
}

/// Groups [newestFirst] into stream items, newest first. Pure, so it
/// is unit-tested.
List<StreamItem> buildItems(List<types.Message> newestFirst, {String? meId}) {
  final out = <StreamItem>[];
  for (final m in newestFirst.reversed) {
    final last = out.isEmpty ? null : out.last;
    final near = last != null &&
        last.author.id == m.author.id &&
        ((m.createdAt ?? 0) - last.at).abs() <= _withWindow.inMilliseconds;
    if (m is types.ImageMessage || m is types.FileMessage) {
      final base = _attachmentId.firstMatch(m.id)?.group(1);
      final belongs = last != null &&
          last.author.id == m.author.id &&
          (base != null && last.id == base || near);
      if (belongs) {
        last.files.add(m);
      } else {
        out.add(StreamItem(files: [m]));
      }
    } else if (m is types.TextMessage) {
      // My answer to a task: the files go first, the words after.
      if (last != null && last.text == null && near && taskOf(m) == null) {
        last.text = m;
      } else {
        out.add(StreamItem(text: m));
      }
    }
  }

  for (var i = 0; i < out.length; i++) {
    final it = out[i];
    final prev = i > 0 ? out[i - 1] : null;
    final t = beijing(it.at);
    final pt = prev == null ? null : beijing(prev.at);
    it.dayBreak = pt == null ||
        pt.year != t.year ||
        pt.month != t.month ||
        pt.day != t.day;
    it.head = it.dayBreak ||
        prev!.author.id != it.author.id ||
        it.task != null ||
        prev.task != null ||
        (it.at - prev.at).abs() > _runWindow.inMilliseconds;
    if (prev != null) prev.tail = it.head;
  }

  // A task is answered once a message of mine follows it.
  var mineAfter = false;
  for (final it in out.reversed) {
    if (it.task != null) it.answered = mineAfter;
    if (meId != null && it.author.id == meId) mineAfter = true;
  }
  return out.reversed.toList();
}

class MessageStream extends StatefulWidget {
  const MessageStream({
    super.key,
    required this.messages,
    required this.meId,
    this.mentions = const [],
    this.waitingOnMe = false,
    this.onRetry,
    this.now,
  });

  /// Newest first, as the controller keeps them.
  final List<types.Message> messages;
  final String meId;

  /// Room members, so "@名字" lights up.
  final List<String> mentions;

  /// The newest message is theirs and I have not answered it.
  final bool waitingOnMe;

  /// Send a failed message of mine again.
  final void Function(String messageId)? onRetry;

  /// Pins the clock (tests and screenshots).
  final DateTime? now;

  @override
  State<MessageStream> createState() => _MessageStreamState();
}

class _MessageStreamState extends State<MessageStream> {
  final _scroll = ScrollController();
  bool _away = false;
  int _unseen = 0;
  String? _newestId;

  @override
  void initState() {
    super.initState();
    _newestId = widget.messages.firstOrNull?.id;
    _scroll.addListener(() {
      final away = _scroll.hasClients && _scroll.offset > 240;
      if (away != _away) {
        setState(() {
          _away = away;
          if (!away) _unseen = 0;
        });
      }
    });
  }

  @override
  void didUpdateWidget(MessageStream old) {
    super.didUpdateWidget(old);
    final newest = widget.messages.firstOrNull;
    if (newest == null || newest.id == _newestId) return;
    // Count what arrived since the newest one I had.
    var added = 0;
    for (final m in widget.messages) {
      if (m.id == _newestId) break;
      added++;
    }
    _newestId = newest.id;
    if (newest.author.id == widget.meId) {
      _toBottom();
    } else if (_away) {
      setState(() => _unseen += added);
    }
  }

  void _toBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0, duration: Mo.of(context, Mo.slow), curve: Mo.expo);
    setState(() => _unseen = 0);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.messages.isEmpty) return const _EmptyStream();
    final g = StreamScope.of(context);
    final items = buildItems(widget.messages, meId: widget.meId);
    final now = beijing((widget.now ?? DateTime.now()).millisecondsSinceEpoch);
    final hotId = widget.waitingOnMe
        ? items.where((i) => i.author.id != widget.meId).firstOrNull?.id
        : null;
    final newestMine =
        items.where((i) => i.author.id == widget.meId).firstOrNull?.id;

    return Stack(
      children: [
        ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: true),
          child: ListView.builder(
            controller: _scroll,
            reverse: true,
            padding: EdgeInsets.only(
              top: Sp.x6,
              bottom: g.phone ? Sp.x4 : Sp.x6,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final it = items[i];
              return Column(
                key: ValueKey(it.id),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (it.dayBreak) _DayMarker(dayLabel(beijing(it.at), now)),
                  Enter(
                    // Only the newest row animates in.
                    enabled: i == 0,
                    child: _Item(
                      item: it,
                      mine: it.author.id == widget.meId,
                      hot: it.id == hotId,
                      showState: it.id == newestMine,
                      mentions: widget.mentions,
                      onRetry: widget.onRetry,
                      now: widget.now,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Positioned(
          right: g.side,
          bottom: Sp.x3,
          child: Swap(
            value: _away,
            child: _away
                ? _JumpPill(count: _unseen, onTap: _toBottom)
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

/// One item, laid out on its side of the stream.
class _Item extends StatefulWidget {
  const _Item({
    required this.item,
    required this.mine,
    required this.hot,
    required this.showState,
    required this.mentions,
    required this.onRetry,
    required this.now,
  });

  final StreamItem item;
  final bool mine;

  /// Theirs, newest, and waiting on me.
  final bool hot;

  /// My newest message: its delivery state stays visible.
  final bool showState;
  final List<String> mentions;
  final void Function(String)? onRetry;
  final DateTime? now;

  @override
  State<_Item> createState() => _ItemState();
}

class _ItemState extends State<_Item> {
  bool _hover = false;

  StreamItem get it => widget.item;

  @override
  Widget build(BuildContext context) {
    final g = StreamScope.of(context);
    final time = hm(beijing(it.at));
    final caller = Caller.parse(it.author.firstName ?? it.author.id);
    final hoverClock = !Touch.primary && _hover && !it.head;

    final Widget row = widget.mine
        ? _mine(g, time, hoverClock)
        : _theirs(g, caller, time, hoverClock);

    final padded = Padding(
      padding: EdgeInsets.fromLTRB(
        g.side,
        it.head ? (g.phone ? Sp.x4 : Sp.x5) : Sp.x1,
        g.side,
        0,
      ),
      child: row,
    );
    if (Touch.primary) return padded;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: padded,
    );
  }

  Widget _theirs(
    StreamMetrics g,
    Caller caller,
    String time,
    bool hoverClock,
  ) {
    final task = it.task;
    final Widget body;
    if (task != null) {
      body = TaskCard(
        messageId: it.text!.id,
        task: task,
        person: caller.name,
        prompt: it.text!.text,
        inputs: it.files,
        answeredBefore: it.answered,
        now: widget.now,
      );
    } else {
      body = _Body(
        item: it,
        mine: false,
        hot: widget.hot,
        head: it.head,
        mentions: widget.mentions,
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: g.lane,
          child: it.head
              ? Align(
                  alignment: Alignment.topLeft,
                  child: PersonAvatar(
                    name: caller.name,
                    anonymous: caller.anonymous,
                    size: g.avatar,
                  ),
                )
              : _HoverClock(time: time, on: hoverClock),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (it.head) _NameLine(caller: caller, time: time),
              body,
            ],
          ),
        ),
        // Leave the far side to my messages, so a long message of
        // theirs never runs the full width and reads as mine.
        SizedBox(width: g.phone ? Sp.x6 : Sp.x12),
      ],
    );
  }

  Widget _mine(StreamMetrics g, String time, bool hoverClock) {
    final status = it.status;
    final failed = status == types.Status.error;
    final showState = it.tail &&
        (widget.showState || failed || status == types.Status.sending);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: g.lane + (g.phone ? Sp.x6 : Sp.x12)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!Touch.primary)
                    Padding(
                      padding: const EdgeInsets.only(
                        right: Sp.x2,
                        bottom: Sp.x15,
                      ),
                      child: _HoverClock(
                        time: time,
                        on: _hover && !showState,
                      ),
                    ),
                  Flexible(
                    child: _Body(
                      item: it,
                      mine: true,
                      hot: false,
                      head: it.head,
                      mentions: widget.mentions,
                    ),
                  ),
                ],
              ),
              if (showState)
                _DeliveryLine(
                  status: status,
                  time: time,
                  failure: it.failure,
                  onRetry: failed &&
                          it.text != null &&
                          it.files.isEmpty &&
                          widget.onRetry != null
                      ? () => widget.onRetry!(it.text!.id)
                      : null,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Name, tool, session tag and clock over the first message of a run.
class _NameLine extends StatelessWidget {
  const _NameLine({required this.caller, required this.time});
  final Caller caller;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.x15),
      child: Row(
        children: [
          Flexible(
            child: Text(
              caller.name,
              style:
                  caller.anonymous ? Ty.name.copyWith(color: Dk.t2) : Ty.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (caller.via != null) ...[
            const SizedBox(width: Sp.x2),
            Flexible(
              child: Text(
                caller.via!,
                style: Ty.small.copyWith(fontSize: 11.5, color: Dk.t3),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (caller.tag != null) ...[
            const SizedBox(width: Sp.x15),
            Tag(caller.tag!, mono: true, color: Dk.t3),
          ],
          const SizedBox(width: Sp.x2),
          Text(time, style: Ty.meta.copyWith(fontSize: 10.5)),
        ],
      ),
    );
  }
}

/// A clock that appears beside a continuation while the pointer is on
/// it.
class _HoverClock extends StatelessWidget {
  const _HoverClock({required this.time, required this.on});
  final String time;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: Mo.of(context, Mo.instant),
      opacity: on ? 1 : 0,
      child: Padding(
        padding: const EdgeInsets.only(top: Sp.x25),
        child: Text(
          time,
          style: Ty.meta.copyWith(fontSize: 10, color: Dk.t4),
        ),
      ),
    );
  }
}

/// The words and files of one message.
class _Body extends StatelessWidget {
  const _Body({
    required this.item,
    required this.mine,
    required this.hot,
    required this.head,
    required this.mentions,
  });
  final StreamItem item;
  final bool mine;
  final bool hot;
  final bool head;
  final List<String> mentions;

  @override
  Widget build(BuildContext context) {
    final text = item.text?.text.trim() ?? '';
    final parts = <Widget>[
      if (item.files.isNotEmpty) AttachmentList(items: item.files),
      if (text.isNotEmpty)
        _Bubble(
          text: text,
          mine: mine,
          hot: hot,
          head: head,
          failed: item.status == types.Status.error && mine,
          mentions: mentions,
        ),
    ];
    if (parts.length == 1) return parts.first;
    return Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [parts[0], const SizedBox(height: Sp.x15), parts[1]],
    );
  }
}

/// Text longer than this folds behind 展开全文.
const int _foldChars = 900;
const int _foldLines = 16;

class _Bubble extends StatefulWidget {
  const _Bubble({
    required this.text,
    required this.mine,
    required this.hot,
    required this.head,
    required this.failed,
    required this.mentions,
  });
  final String text;
  final bool mine;
  final bool hot;
  final bool head;
  final bool failed;
  final List<String> mentions;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> {
  bool _open = false;

  bool get _long {
    // Count prose only: a code block folds on its own.
    final prose = widget.text.replaceAll(RegExp(r'```[\s\S]*?```'), '');
    return prose.length > _foldChars ||
        '\n'.allMatches(prose).length > _foldLines;
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.mine;
    final hasCode = widget.text.contains('```');
    final floor = mine ? Dk.mineFloor : Dk.p2;
    final edge = widget.failed
        ? Dk.dangerEdge
        : widget.hot
            ? Dk.signalEdge
            : mine
                ? Dk.mineEdge
                : Dk.line;
    const r = Radius.circular(Rd.lg);
    const tight = Radius.circular(Rd.xs);
    final radius = BorderRadius.only(
      topLeft: !mine && widget.head ? tight : r,
      topRight: mine && widget.head ? tight : r,
      bottomLeft: r,
      bottomRight: r,
    );

    Widget text = RichMessageText(
      widget.text,
      mentions: widget.mentions,
      style: Ty.prose.copyWith(height: 1.62, fontSize: 14.5),
    );

    final long = _long;
    if (long) {
      text = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: Mo.of(context, Mo.base),
            curve: Mo.expo,
            alignment: Alignment.topCenter,
            child: _open
                ? text
                : ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (b) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.7, 1],
                      colors: [Dk.t1, Colors.transparent],
                    ).createShader(b),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: ClipRect(
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: text,
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: Sp.x15),
          _TextLink(
            label: _open ? '收起' : '展开全文 · ${widget.text.length} 字',
            onTap: () => setState(() => _open = !_open),
          ),
        ],
      );
    }

    final bubble = AnimatedContainer(
      duration: Mo.of(context, Mo.base),
      curve: Mo.soft,
      width: hasCode || long ? double.infinity : null,
      padding: const EdgeInsets.fromLTRB(Sp.x35, Sp.x25, Sp.x35, Sp.x25),
      decoration: BoxDecoration(
        color: floor,
        borderRadius: radius,
        border: Border.all(color: edge),
        boxShadow: widget.hot
            ? const [
                BoxShadow(
                  color: Dk.signalGlow,
                  blurRadius: 24,
                  spreadRadius: -4,
                ),
              ]
            : null,
      ),
      child: text,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Sz.measure),
      child: bubble,
    );
  }
}

class _TextLink extends StatelessWidget {
  const _TextLink({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      semanticLabel: label,
      onTap: onTap,
      radius: Rd.xs,
      builder: (context, s) => Text(
        label,
        style: Ty.small.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: s.lit ? Dk.t1 : Dk.blue,
        ),
      ),
    );
  }
}

/// Under my newest message: 发送中 / 已发出 / 已送达, or why it failed.
class _DeliveryLine extends StatelessWidget {
  const _DeliveryLine({
    required this.status,
    required this.time,
    required this.failure,
    required this.onRetry,
  });
  final types.Status? status;
  final String time;
  final String? failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final Widget line;
    if (status == types.Status.error) {
      line = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GlyphIcon(Glyph.alert, size: Sz.glyphXs, color: Dk.danger),
          const SizedBox(width: Sp.x15),
          Flexible(
            child: Text(
              failure ?? '没发出去',
              style: Ty.small.copyWith(fontSize: 12, color: Dk.dangerInk),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: Sp.x2),
            DkButton(
              key: const ValueKey('message-retry'),
              label: '重试',
              glyph: Glyph.retry,
              dense: true,
              kind: DkButtonKind.danger,
              onTap: onRetry,
            ),
          ],
        ],
      );
    } else {
      final (label, glyph, color) = switch (status) {
        types.Status.sending => ('发送中…', Glyph.clock, Dk.t3),
        types.Status.delivered => ('已送达', Glyph.delivered, Dk.t3),
        _ => ('已发出', Glyph.check, Dk.t3),
      };
      line = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlyphIcon(glyph, size: Sz.glyphXs - 1, color: color),
          const SizedBox(width: Sp.x1),
          Text(
            status == types.Status.sending ? label : '$label · $time',
            style: Ty.small.copyWith(fontSize: 11, color: color),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: Sp.x15, right: Sp.x05),
      child: Semantics(liveRegion: true, child: line),
    );
  }
}

class _DayMarker extends StatelessWidget {
  const _DayMarker(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final g = StreamScope.of(context);
    const rule = Expanded(child: Divider(height: 1, color: Dk.line));
    return Padding(
      padding: EdgeInsets.fromLTRB(g.side, Sp.x6, g.side, Sp.x1),
      child: Row(
        children: [
          rule,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.x3),
            child: Text(
              label,
              style: Ty.small.copyWith(
                fontSize: 11,
                color: Dk.t3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          rule,
        ],
      ),
    );
  }
}

class _JumpPill extends StatelessWidget {
  const _JumpPill({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasNew = count > 0;
    final label = hasNew ? '$count 条新消息' : '回到最新';
    final ink = hasNew ? Dk.signalInk : Dk.t1;
    return Pressable(
      key: const ValueKey('jump-latest'),
      semanticLabel: label,
      onTap: onTap,
      radius: Rd.pill,
      builder: (context, s) => AnimatedContainer(
        duration: Mo.of(context, Mo.instant),
        padding: const EdgeInsets.symmetric(
          horizontal: Sp.x35,
          vertical: Sp.x2,
        ),
        decoration: BoxDecoration(
          color: hasNew ? (s.lit ? Dk.signalCode : Dk.signal) : Dk.p3,
          borderRadius: BorderRadius.circular(Rd.pill),
          border: Border.all(color: hasNew ? Dk.signal : Dk.line2),
          boxShadow: const [BoxShadow(color: Dk.shadow, blurRadius: 18)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlyphIcon(Glyph.arrowDown, size: Sz.glyphSm, color: ink),
            const SizedBox(width: Sp.x15),
            Text(
              label,
              style: Ty.small.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyStream extends StatelessWidget {
  const _EmptyStream();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Sp.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 220,
              height: 150,
              child: BrandHalo(
                radius: 110,
                child: Center(
                  child: BrandMark(size: 64, wink: BrandWink.idle),
                ),
              ),
            ),
            Text('这里还没有消息', style: Ty.title.copyWith(fontSize: 17)),
            const SizedBox(height: Sp.x2),
            Text(
              '对方在自己的工具里写下第一句话，就会出现在这里。',
              textAlign: TextAlign.center,
              style: Ty.small.copyWith(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
