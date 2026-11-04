/// The message stream: the console's centre pane.
///
/// A timeline, not a chat: a gutter on the left carries the clock and a
/// rail with one node per speaker turn. Agent requests are wide reading
/// cards (they are the work); the human's replies are compact paper
/// bubbles on the right. The node of the newest agent request glows
/// signal-orange while it waits on the human.
///
/// Built on a reversed lazy [ListView], so a stream of thousands of
/// messages lays out only what is on screen.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;

import '../../../app/tokens.dart';
import 'rich_text.dart';

/// Messages closer than this from one author fold into one turn.
const Duration _foldWindow = Duration(minutes: 3);

/// One rendered row of the stream: a turn head or a continuation.
class StreamRow {
  StreamRow(this.message, {required this.head, required this.dayBreak});
  final types.Message message;

  /// First message of a speaker turn: shows name, time and rail node.
  final bool head;

  /// First message of a calendar day: shows a day marker above.
  final bool dayBreak;
}

/// Groups [newestFirst] into rows. Pure, so it is unit-tested.
List<StreamRow> buildRows(List<types.Message> newestFirst) {
  final rows = <StreamRow>[];
  for (var i = 0; i < newestFirst.length; i++) {
    final m = newestFirst[i];
    final older = i + 1 < newestFirst.length ? newestFirst[i + 1] : null;
    final t = DateTime.fromMillisecondsSinceEpoch(m.createdAt ?? 0);
    final ot = older == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(older.createdAt ?? 0);
    final dayBreak = ot == null ||
        ot.year != t.year ||
        ot.month != t.month ||
        ot.day != t.day;
    final head = dayBreak ||
        older!.author.id != m.author.id ||
        t.difference(ot).abs() > _foldWindow;
    rows.add(StreamRow(m, head: head, dayBreak: dayBreak));
  }
  return rows;
}

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String dayLabel(DateTime t, DateTime now) {
  final d = DateTime(t.year, t.month, t.day);
  final n = DateTime(now.year, now.month, now.day);
  final diff = n.difference(d).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  if (t.year == now.year) return '${t.month} 月 ${t.day} 日';
  return '${t.year} 年 ${t.month} 月 ${t.day} 日';
}

class MessageStream extends StatefulWidget {
  const MessageStream({
    super.key,
    required this.messages,
    required this.meId,
    this.mentions = const [],
    this.waitingOnMe = false,
  });

  /// Newest first, as the controller keeps them.
  final List<types.Message> messages;
  final String meId;
  final List<String> mentions;

  /// The newest message is an agent request still waiting on the human.
  final bool waitingOnMe;

  @override
  State<MessageStream> createState() => _MessageStreamState();
}

class _MessageStreamState extends State<MessageStream> {
  final _scroll = ScrollController();
  bool _away = false;
  int _unseen = 0;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _lastCount = widget.messages.length;
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
    final added = widget.messages.length - _lastCount;
    _lastCount = widget.messages.length;
    if (added > 0) {
      final mineNewest = widget.messages.isNotEmpty &&
          widget.messages.first.author.id == widget.meId;
      if (mineNewest) {
        _toBottom();
      } else if (_away) {
        setState(() => _unseen += added);
      }
    }
  }

  void _toBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0, duration: Mo.slow, curve: Mo.expo);
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
    final rows = buildRows(widget.messages);
    final now = DateTime.now();
    String? newestAgentId;
    for (final m in widget.messages) {
      if (m.author.id != widget.meId) {
        newestAgentId = m.id;
        break;
      }
    }

    return Stack(
      children: [
        // The rail runs the full height behind the rows.
        const Positioned(
          left: Sp.gutter - 17,
          top: 0,
          bottom: 0,
          child: SizedBox(width: 1, child: ColoredBox(color: Dk.line)),
        ),
        ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: true),
          child: ListView.builder(
            controller: _scroll,
            reverse: true,
            padding: const EdgeInsets.only(top: Sp.x6, bottom: Sp.x9),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final r = rows[i];
              final hot = widget.waitingOnMe && r.message.id == newestAgentId;
              return Column(
                key: ValueKey(r.message.id),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (r.dayBreak)
                    _DayMarker(
                      dayLabel(
                        DateTime.fromMillisecondsSinceEpoch(
                          r.message.createdAt ?? 0,
                        ),
                        now,
                      ),
                    ),
                  _Row(
                    row: r,
                    mine: r.message.author.id == widget.meId,
                    hot: hot,
                    mentions: widget.mentions,
                    // Only the newest row animates in.
                    fresh: i == 0,
                  ),
                ],
              );
            },
          ),
        ),
        Positioned(
          right: Sp.x9,
          bottom: Sp.x4,
          child: AnimatedSwitcher(
            duration: Mo.base,
            switchInCurve: Mo.expo,
            child: _away
                ? _JumpPill(count: _unseen, onTap: _toBottom)
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.row,
    required this.mine,
    required this.hot,
    required this.mentions,
    required this.fresh,
  });

  final StreamRow row;
  final bool mine;
  final bool hot;
  final List<String> mentions;
  final bool fresh;

  @override
  Widget build(BuildContext context) {
    final m = row.message;
    final t = DateTime.fromMillisecondsSinceEpoch(m.createdAt ?? 0);
    final body = mine ? _mineBody(m) : _agentBody(m);

    Widget content = Padding(
      padding: EdgeInsets.only(
        right: Sp.x9,
        top: row.head ? Sp.x5 : Sp.x2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: Sp.gutter,
            child:
                row.head ? _Gutter(time: _hm(t), mine: mine, hot: hot) : null,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (row.head && !mine) _Who(author: m.author),
                body,
              ],
            ),
          ),
        ],
      ),
    );

    if (fresh) {
      content = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Mo.slow,
        curve: Mo.expo,
        builder: (context, v, child) => Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, (1 - v) * 10),
            child: child,
          ),
        ),
        child: content,
      );
    }
    return content;
  }

  Widget _agentBody(types.Message m) {
    if (m is types.ImageMessage) {
      return Align(
        alignment: Alignment.centerLeft,
        child: _ImageTile(uri: m.uri),
      );
    }
    final text = m is types.TextMessage ? m.text : '';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Sp.measure + 50),
      child: _RequestCard(hot: hot, text: text, mentions: mentions),
    );
  }

  Widget _mineBody(types.Message m) {
    if (m is types.ImageMessage) return _ImageTile(uri: m.uri);
    final text = m is types.TextMessage ? m.text : '';
    final sending = m.status == types.Status.sending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: const BoxDecoration(
              color: Dk.mine,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: RichMessageText(
              text,
              inverted: true,
              mentions: mentions,
              codeInk: Dk.onMine,
              codeFloor: Dk.mineCode,
              style: Ty.prose.copyWith(
                color: Dk.onMine,
                fontWeight: FontWeight.w500,
                height: 1.65,
              ),
            ),
          ),
        ),
        if (row.head || sending)
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 2),
            child: Text(
              sending ? '发送中…' : '已送达',
              style: Ty.small.copyWith(fontSize: 11, color: Dk.t3),
            ),
          ),
      ],
    );
  }
}

class _Gutter extends StatelessWidget {
  const _Gutter({required this.time, required this.mine, required this.hot});
  final String time;
  final bool mine;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: 34,
            top: 2,
            child: Text(time, style: Ty.meta.copyWith(fontSize: 11)),
          ),
          Positioned(
            right: 13,
            top: 5,
            child: _Node(mine: mine, hot: hot),
          ),
        ],
      ),
    );
  }
}

/// The rail node. When a request starts waiting on the human it pulses
/// three times, then holds a steady halo: enough to catch the eye, not
/// a light that blinks all afternoon.
class _Node extends StatefulWidget {
  const _Node({required this.mine, required this.hot});
  final bool mine;
  final bool hot;

  @override
  State<_Node> createState() => _NodeState();
}

class _NodeState extends State<_Node> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.hot) _beat();
  }

  Future<void> _beat() async {
    for (var i = 0; i < 3 && mounted && widget.hot; i++) {
      await _pulse.forward(from: 0).orCancel.catchError((_) {});
    }
  }

  @override
  void didUpdateWidget(_Node old) {
    super.didUpdateWidget(old);
    if (widget.hot && !old.hot) _beat();
    if (!widget.hot && _pulse.isAnimating) _pulse.stop();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fill = widget.hot
        ? Dk.signal
        : widget.mine
            ? Dk.t1
            : Dk.bg;
    final ring = widget.hot
        ? Dk.signal
        : widget.mine
            ? Dk.t1
            : Dk.line2;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final v = widget.hot ? _pulse.value : 0.0;
        final settled = widget.hot && !_pulse.isAnimating;
        return SizedBox(
          width: 9,
          height: 9,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (settled)
                Container(
                  width: 17,
                  height: 17,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Dk.signalRing,
                  ),
                ),
              if (widget.hot && !settled)
                Container(
                  width: 9 + 14 * v,
                  height: 9 + 14 * v,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Dk.signal.withValues(alpha: 0.28 * (1 - v)),
                  ),
                ),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fill,
                  border: Border.all(color: ring, width: 1.5),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Who extends StatelessWidget {
  const _Who({required this.author});
  final types.User author;

  @override
  Widget build(BuildContext context) {
    // Server names callers like "小明的 Claude Code · a3f9": the part
    // after the dot is a session tag, shown as a mono chip.
    final full = author.firstName ?? author.id;
    final dot = full.lastIndexOf(' · ');
    final name = dot > 0 ? full.substring(0, dot) : full;
    final tag = dot > 0 ? full.substring(dot + 3) : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Monogram(name),
          const SizedBox(width: 10),
          Text(name, style: Ty.name),
          if (tag != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Dk.p3,
                borderRadius: BorderRadius.circular(Rd.xs),
              ),
              child: Text(tag, style: Ty.meta.copyWith(color: Dk.t2)),
            ),
          ],
        ],
      ),
    );
  }
}

/// A two-letter monogram on a hue derived from the name, so the same
/// caller always wears the same colour across sessions.
class _Monogram extends StatelessWidget {
  const _Monogram(this.name);
  final String name;

  static const _hues = [
    Color(0xFFD97757), // warm clay
    Color(0xFF6E8BE0),
    Color(0xFF8BBF5E),
    Color(0xFFC9A44A),
    Color(0xFFB07AD6),
    Color(0xFF4FB3A9),
  ];

  @override
  Widget build(BuildContext context) {
    final h = name.codeUnits.fold<int>(0, (a, c) => (a * 31 + c) & 0xffff);
    final hue = _hues[h % _hues.length];
    final latin = RegExp(r'[A-Za-z0-9]').allMatches(name).toList();
    final letters = latin.isNotEmpty
        ? latin.take(2).map((m) => m.group(0)!).join().toUpperCase()
        : name.characters.take(1).toString();
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hue,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        letters,
        style: Ty.name.copyWith(
          fontSize: 10,
          color: const Color(0xFF14110E),
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.hot,
    required this.text,
    required this.mentions,
  });
  final bool hot;
  final String text;
  final List<String> mentions;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Mo.base,
      curve: Mo.soft,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Dk.p2, Dk.p1],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hot ? const Color(0x55FF5B1F) : Dk.line,
        ),
        boxShadow: hot
            ? const [
                BoxShadow(
                  color: Color(0x14FF5B1F),
                  blurRadius: 32,
                  spreadRadius: -6,
                ),
              ]
            : null,
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: RichMessageText(text, style: Ty.prose, mentions: mentions),
          ),
          Positioned(
            left: 0,
            top: 22,
            child: AnimatedContainer(
              duration: Mo.base,
              width: 3,
              height: 24,
              decoration: BoxDecoration(
                color: hot ? Dk.signal : Dk.line2,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(3),
                  bottomRight: Radius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.uri});
  final String uri;

  ImageProvider? get _provider {
    if (uri.startsWith('data:')) {
      final comma = uri.indexOf(',');
      if (comma != -1 && comma < uri.length - 1) {
        try {
          return MemoryImage(base64Decode(uri.substring(comma + 1)));
        } catch (_) {
          return null;
        }
      }
      return null;
    }
    if (uri.startsWith('http://') || uri.startsWith('https://')) {
      return NetworkImage(uri);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = _provider;
    if (p == null) {
      return const Text('图片无法显示', style: Ty.small);
    }
    return MouseRegion(
      cursor: SystemMouseCursors.zoomIn,
      child: GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          barrierColor: const Color(0xE6000000),
          builder: (c) => GestureDetector(
            onTap: () => Navigator.of(c).pop(),
            child: InteractiveViewer(
              maxScale: 6,
              child: Center(child: Image(image: p)),
            ),
          ),
        ),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 340, maxWidth: 520),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Rd.lg),
            border: Border.all(color: Dk.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image(
            image: p,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Padding(
              padding: EdgeInsets.all(Sp.x3),
              child: Text('图片无法显示', style: Ty.small),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayMarker extends StatelessWidget {
  const _DayMarker(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Sp.x6, bottom: Sp.x1),
      child: Row(
        children: [
          SizedBox(
            width: Sp.gutter - 17 + 0.5,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                margin: const EdgeInsets.only(right: 0),
                decoration: BoxDecoration(
                  color: Dk.bg,
                  border: Border.all(color: Dk.line),
                  borderRadius: BorderRadius.circular(Rd.pill),
                ),
                child: Text(label, style: Ty.small.copyWith(fontSize: 11)),
              ),
            ),
          ),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: Sp.x3, right: Sp.x9),
              child: Divider(height: 1, color: Dk.line),
            ),
          ),
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
    return Material(
      color: hasNew ? Dk.signal : Dk.p3,
      borderRadius: BorderRadius.circular(Rd.pill),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rd.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Rd.pill),
            border: Border.all(color: hasNew ? Dk.signal : Dk.line2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_downward_rounded,
                size: 15,
                color: hasNew ? Dk.signalInk : Dk.t1,
              ),
              const SizedBox(width: 6),
              Text(
                hasNew ? '$count 条新消息' : '回到最新',
                style: Ty.small.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: hasNew ? Dk.signalInk : Dk.t1,
                ),
              ),
            ],
          ),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Dk.line2, width: 2),
                  ),
                ),
                Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Dk.t4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Sp.x5),
          Text('还没有请求', style: Ty.title.copyWith(fontSize: 17)),
          const SizedBox(height: Sp.x2),
          Text(
            'AI 发来的第一条请求会出现在这里。',
            style: Ty.small.copyWith(fontSize: 13),
          ),
        ],
      ),
    );
  }
}
