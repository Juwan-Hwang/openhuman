/// Attachments in the timeline: pictures, recordings, clips and other
/// files — from either person, previewed in place, with save and open.
library;

import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;

import '../../../app/adaptive.dart';
import '../../../app/tokens.dart';
import '../../../core/files_io.dart';
import '../../../core/tasks.dart';
import '../../../widgets/controls.dart';
import '../../../widgets/glyphs.dart';
import '../../../widgets/motion.dart';
import 'video_viewer.dart';

/// The image provider for an attachment URI, or null when unreadable.
ImageProvider? imageFor(String uri) {
  final d = decodeDataUrl(uri);
  if (d != null) return MemoryImage(Uint8List.fromList(d.$2));
  if (uri.startsWith('http://') || uri.startsWith('https://')) {
    return NetworkImage(uri);
  }
  return null;
}

/// Lays out a run of attachments: pictures as a grid, everything else as
/// a column of tiles.
class AttachmentList extends StatelessWidget {
  const AttachmentList({super.key, required this.items, this.maxWidth});
  final List<types.Message> items;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final images = items.whereType<types.ImageMessage>().toList();
    final files = items.whereType<types.FileMessage>().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (images.isNotEmpty) ImageGrid(images: images),
        for (final f in files) ...[
          if (images.isNotEmpty || f != files.first)
            const SizedBox(height: Sp.x2),
          FileAttachment(file: f),
        ],
      ],
    );
  }
}

class ImageGrid extends StatelessWidget {
  const ImageGrid({super.key, required this.images});
  final List<types.ImageMessage> images;

  @override
  Widget build(BuildContext context) {
    if (images.length == 1) {
      return ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: Sz.imageMax,
          maxHeight: Sz.imageMax,
        ),
        child: _Thumb(uri: images.first.uri, index: 0, all: images),
      );
    }
    final cols = images.length == 2 || images.length == 4 ? 2 : 3;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Sz.imageGridMax),
      child: LayoutBuilder(
        builder: (context, c) {
          final edge = (c.maxWidth - (cols - 1) * Sp.x1) / cols;
          return Wrap(
            spacing: Sp.x1,
            runSpacing: Sp.x1,
            children: [
              for (var i = 0; i < images.length; i++)
                SizedBox.square(
                  dimension: edge,
                  child: _Thumb(
                    uri: images[i].uri,
                    index: i,
                    all: images,
                    cover: true,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.uri,
    required this.index,
    required this.all,
    this.cover = false,
  });
  final String uri;
  final int index;
  final List<types.ImageMessage> all;
  final bool cover;

  @override
  Widget build(BuildContext context) {
    final p = imageFor(uri);
    final broken = Container(
      padding: const EdgeInsets.all(Sp.x3),
      color: Dk.imageFloor,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlyphIcon(Glyph.image, size: Sz.glyphSm, color: Dk.t3),
          const SizedBox(width: Sp.x2),
          Text('图片无法显示', style: Ty.small),
        ],
      ),
    );
    return Pressable(
      semanticLabel: '查看图片 ${index + 1}',
      cursor: SystemMouseCursors.zoomIn,
      radius: Rd.lg,
      onTap: p == null ? null : () => _openViewer(context, index),
      builder: (context, s) => AnimatedContainer(
        duration: Mo.of(context, Mo.instant),
        decoration: BoxDecoration(
          color: Dk.imageFloor,
          borderRadius: BorderRadius.circular(Rd.lg),
          border: Border.all(color: s.lit ? Dk.line2 : Dk.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: p == null
            ? broken
            : Image(
                image: p,
                fit: cover ? BoxFit.cover : BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => broken,
              ),
      ),
    );
  }

  void _openViewer(BuildContext context, int start) {
    showDialog<void>(
      context: context,
      barrierColor: Dk.scrimDeep,
      builder: (c) => _Viewer(images: all, start: start),
    );
  }
}

/// Full-window picture viewer: arrows step through, Esc closes.
class _Viewer extends StatefulWidget {
  const _Viewer({required this.images, required this.start});
  final List<types.ImageMessage> images;
  final int start;

  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  late int _i = widget.start;

  @override
  Widget build(BuildContext context) {
    final img = widget.images[_i];
    final p = imageFor(img.uri);
    final many = widget.images.length > 1;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            setState(() => _i = (_i + 1) % widget.images.length),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => setState(
              () => _i = (_i - 1 + widget.images.length) % widget.images.length,
            ),
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: InteractiveViewer(
                  maxScale: 6,
                  child: Center(
                    child: p == null ? const SizedBox() : Image(image: p),
                  ),
                ),
              ),
            ),
            Positioned(
              top: Sp.x4,
              right: Sp.x4,
              child: Row(
                children: [
                  if (many)
                    Padding(
                      padding: const EdgeInsets.only(right: Sp.x3),
                      child: Text(
                        '${_i + 1} / ${widget.images.length}',
                        style: Ty.meta.copyWith(color: Dk.t2),
                      ),
                    ),
                  DkIconButton(
                    glyph: Glyph.save,
                    label: '保存图片',
                    onTap: () => saveAttachment(context, img.name, img.uri),
                  ),
                  DkIconButton(
                    glyph: Glyph.close,
                    label: '关闭',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Save an attachment, saying where it went.
Future<void> saveAttachment(
    BuildContext context, String name, String uri) async {
  final bytes = await bytesOf(uri);
  if (!context.mounted) return;
  if (bytes == null) {
    toast(context, '文件不可用');
    return;
  }
  try {
    final where = await FilesIo.save(_safeName(name, uri), bytes);
    if (!context.mounted || where == null) return;
    toast(context, '已保存');
  } catch (_) {
    if (context.mounted) toast(context, '无法保存');
  }
}

/// Open an attachment with the system's own app.
Future<void> openAttachment(
    BuildContext context, String name, String uri) async {
  final bytes = await bytesOf(uri);
  if (!context.mounted) return;
  if (bytes == null) {
    toast(context, '文件不可用');
    return;
  }
  final ok = await FilesIo.open(_safeName(name, uri), bytes);
  if (!ok && context.mounted) toast(context, '没有可打开此文件的应用');
}

String _safeName(String name, String uri) {
  if (name.contains('.')) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
  }
  final mime = decodeDataUrl(uri)?.$1 ?? '';
  final ext = switch (mime) {
    'image/png' => 'png',
    'image/jpeg' => 'jpg',
    'image/webp' => 'webp',
    'audio/mpeg' => 'mp3',
    'audio/wav' => 'wav',
    'video/mp4' => 'mp4',
    'application/json' => 'json',
    _ => 'bin',
  };
  return '${name.replaceAll(RegExp(r'\s'), '_')}.$ext';
}

/// A non-picture attachment: recording, clip, data or anything else.
class FileAttachment extends StatelessWidget {
  const FileAttachment({super.key, required this.file});
  final types.FileMessage file;

  @override
  Widget build(BuildContext context) {
    final media = mediaOf(mime: file.mimeType, name: file.name);
    return switch (media) {
      AnswerMedia.audio =>
        AudioTile(name: file.name, uri: file.uri, size: file.size.toInt()),
      AnswerMedia.video =>
        VideoTile(name: file.name, uri: file.uri, size: file.size.toInt()),
      _ => DataTile(
          name: file.name,
          uri: file.uri,
          size: file.size.toInt(),
          mime: file.mimeType,
        ),
    };
  }
}

/// The shell every file tile shares: glyph, name and size, actions.
class _TileShell extends StatelessWidget {
  const _TileShell({
    required this.glyph,
    required this.name,
    required this.meta,
    required this.actions,
    this.lead,
    this.below,
  });
  final Glyph glyph;
  final String name;
  final String meta;
  final List<Widget> actions;
  final Widget? lead;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Sz.imageGridMax),
      child: Container(
        decoration: BoxDecoration(
          color: Dk.p2,
          borderRadius: BorderRadius.circular(Rd.lg),
          border: Border.all(color: Dk.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.x25, Sp.x2, Sp.x1, Sp.x2),
              child: Row(
                children: [
                  lead ??
                      Container(
                        width: Sz.avatar,
                        height: Sz.avatar,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Dk.p3,
                          borderRadius: BorderRadius.circular(Rd.md),
                        ),
                        child: GlyphIcon(glyph, size: Sz.glyph, color: Dk.t2),
                      ),
                  const SizedBox(width: Sp.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: Ty.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: Sp.x05),
                          Text(meta, style: Ty.meta),
                        ],
                      ],
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
            if (below != null) below!,
          ],
        ),
      ),
    );
  }
}

/// A recording: play in place, scrub, save.
class AudioTile extends StatefulWidget {
  const AudioTile({
    super.key,
    required this.name,
    required this.uri,
    this.size = 0,
  });
  final String name;
  final String uri;
  final int size;

  @override
  State<AudioTile> createState() => _AudioTileState();
}

class _AudioTileState extends State<AudioTile> {
  AudioPlayer? _player;
  final _subs = <StreamSubscription<Object?>>[];
  PlayerState _state = PlayerState.stopped;
  Duration _pos = Duration.zero;
  Duration? _len;
  bool _failed = false;

  Future<void> _toggle() async {
    try {
      final p = _player ??= _make();
      if (_state == PlayerState.playing) {
        await p.pause();
        return;
      }
      if (_state == PlayerState.paused) {
        await p.resume();
        return;
      }
      final d = decodeDataUrl(widget.uri);
      await p.play(
        d != null
            ? BytesSource(Uint8List.fromList(d.$2), mimeType: d.$1)
            : UrlSource(widget.uri),
      );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  AudioPlayer _make() {
    final p = AudioPlayer();
    _subs
      ..add(p.onPlayerStateChanged.listen((s) => setState(() => _state = s)))
      ..add(p.onPositionChanged.listen((d) => setState(() => _pos = d)))
      ..add(p.onDurationChanged.listen((d) => setState(() => _len = d)));
    return p;
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  String _t(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final playing = _state == PlayerState.playing;
    final len = _len;
    final v = len == null || len.inMilliseconds == 0
        ? 0.0
        : (_pos.inMilliseconds / len.inMilliseconds).clamp(0.0, 1.0);
    final meta = [
      if (len != null) '${_t(_pos)} / ${_t(len)}',
      if (len == null) sizeLabel(widget.size),
      if (_failed) '无法播放',
    ].where((s) => s.isNotEmpty).join(' · ');
    return _TileShell(
      glyph: Glyph.bell,
      name: widget.name,
      meta: meta,
      lead: Tooltip(
        message: playing ? '暂停' : '播放',
        child: Pressable(
          semanticLabel: playing ? '暂停' : '播放 ${widget.name}',
          radius: Rd.pill,
          onTap: _failed ? null : _toggle,
          builder: (context, s) => AnimatedContainer(
            duration: Mo.of(context, Mo.instant),
            width: Sz.avatar,
            height: Sz.avatar,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: s.lit ? Dk.mineCode : Dk.paper,
            ),
            child: Center(
              child: CustomPaint(
                size: const Size.square(Sz.glyphXs),
                painter: PlayGlyph(playing: playing),
              ),
            ),
          ),
        ),
      ),
      actions: [
        DkIconButton(
          glyph: Glyph.save,
          label: '保存录音',
          onTap: () => saveAttachment(context, widget.name, widget.uri),
        ),
      ],
      below: Padding(
        padding: const EdgeInsets.fromLTRB(Sp.x25, 0, Sp.x25, Sp.x25),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Rd.pill),
          child: SizedBox(
            height: 3,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: Dk.p4)),
                FractionallySizedBox(
                  widthFactor: v,
                  child: ColoredBox(color: Dk.t1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PlayGlyph extends CustomPainter {
  PlayGlyph({required this.playing});
  final bool playing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Dk.ink;
    final w = size.width;
    if (playing) {
      final r = Radius.circular(w * 0.08);
      canvas.drawRRect(
        RRect.fromLTRBR(w * 0.18, 0, w * 0.4, w, r),
        paint,
      );
      canvas.drawRRect(
        RRect.fromLTRBR(w * 0.6, 0, w * 0.82, w, r),
        paint,
      );
    } else {
      final path = Path()
        ..moveTo(w * 0.22, 0)
        ..lineTo(w, w / 2)
        ..lineTo(w * 0.22, w)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(PlayGlyph old) => old.playing != playing;
}

/// A clip: shown as a dark frame with a play mark; plays in the app,
/// or in the system player when it cannot be decoded here.
class VideoTile extends StatelessWidget {
  const VideoTile({
    super.key,
    required this.name,
    required this.uri,
    this.size = 0,
  });
  final String name;
  final String uri;
  final int size;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Sz.imageMax),
      child: Pressable(
        semanticLabel: '打开 $name',
        radius: Rd.lg,
        onTap: () async {
          final played = await playVideo(
            context,
            name: name,
            uri: uri,
            onSave: () => saveAttachment(context, name, uri),
          );
          if (!played && context.mounted) {
            await openAttachment(context, name, uri);
          }
        },
        builder: (context, s) => AspectRatio(
          aspectRatio: 16 / 9,
          child: AnimatedContainer(
            duration: Mo.of(context, Mo.instant),
            decoration: BoxDecoration(
              color: Dk.codeFloor,
              borderRadius: BorderRadius.circular(Rd.lg),
              border: Border.all(color: s.lit ? Dk.line2 : Dk.line),
            ),
            child: Stack(
              children: [
                Center(
                  child: AnimatedContainer(
                    duration: Mo.of(context, Mo.instant),
                    width: Sz.avatarMd + Sp.x2,
                    height: Sz.avatarMd + Sp.x2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: s.lit ? Dk.paper : Dk.p3,
                    ),
                    child: Center(
                      child: CustomPaint(
                        size: const Size.square(Sz.glyphSm),
                        painter: _PlayGlyphColor(s.lit ? Dk.ink : Dk.t1),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: Sp.x3,
                  right: Sp.x1,
                  bottom: Sp.x1,
                  child: Row(
                    children: [
                      GlyphIcon(
                        Glyph.image,
                        size: Sz.glyphXs,
                        color: Dk.t3,
                      ),
                      const SizedBox(width: Sp.x15),
                      Expanded(
                        child: Text(
                          [name, sizeLabel(size)]
                              .where((x) => x.isNotEmpty)
                              .join(' · '),
                          style: Ty.meta.copyWith(color: Dk.t2),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DkIconButton(
                        glyph: Glyph.save,
                        label: '保存视频',
                        onTap: () => saveAttachment(context, name, uri),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayGlyphColor extends CustomPainter {
  _PlayGlyphColor(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.22, 0)
        ..lineTo(w, w / 2)
        ..lineTo(w * 0.22, w)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_PlayGlyphColor old) => old.color != color;
}

/// Data and other files: name, size, a peek at the first lines of text,
/// save.
class DataTile extends StatefulWidget {
  const DataTile({
    super.key,
    required this.name,
    required this.uri,
    this.size = 0,
    this.mime,
  });
  final String name;
  final String uri;
  final int size;
  final String? mime;

  @override
  State<DataTile> createState() => _DataTileState();
}

class _DataTileState extends State<DataTile> {
  bool _open = false;

  String? get _peek {
    final d = decodeDataUrl(widget.uri);
    if (d == null) return null;
    final media = mediaOf(mime: d.$1, name: widget.name);
    if (media != AnswerMedia.json && media != AnswerMedia.text) return null;
    try {
      var t = utf8.decode(d.$2);
      if (media == AnswerMedia.json && !widget.name.endsWith('.jsonl')) {
        try {
          t = const JsonEncoder.withIndent('  ').convert(jsonDecode(t));
        } catch (_) {}
      }
      final lines = t.split('\n');
      return lines.length > 24
          ? '${lines.take(24).join('\n')}\n…（共 ${lines.length} 行）'
          : t;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final peek = _peek;
    final media = mediaOf(mime: widget.mime, name: widget.name);
    return _TileShell(
      glyph: media == AnswerMedia.json || media == AnswerMedia.text
          ? Glyph.terminal
          : Glyph.save,
      name: widget.name,
      meta: sizeLabel(widget.size),
      actions: [
        if (peek != null)
          DkIconButton(
            glyph: _open ? Glyph.eyeOff : Glyph.eye,
            label: _open ? '收起' : '预览',
            onTap: () => setState(() => _open = !_open),
          ),
        DkIconButton(
          glyph: Glyph.save,
          label: '保存',
          onTap: () => saveAttachment(context, widget.name, widget.uri),
        ),
      ],
      below: peek == null
          ? null
          : Reveal(
              open: _open,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(Sp.x25, 0, Sp.x25, Sp.x25),
                padding: const EdgeInsets.all(Sp.x3),
                decoration: BoxDecoration(
                  color: Dk.codeFloor,
                  borderRadius: BorderRadius.circular(Rd.md),
                ),
                child: SelectableText(
                  peek,
                  style: Ty.code.copyWith(fontSize: 12, height: 1.6),
                ),
              ),
            ),
    );
  }
}

/// A compact chip for a file waiting to be sent with an answer.
class DraftChip extends StatelessWidget {
  const DraftChip({
    super.key,
    required this.file,
    required this.onRemove,
  });
  final OutgoingFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final media = mediaOf(mime: file.mime, name: file.name);
    final touch = Touch.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.x1, Sp.x1, Sp.x05, Sp.x1),
      decoration: BoxDecoration(
        color: Dk.p3,
        borderRadius: BorderRadius.circular(Rd.md),
        border: Border.all(color: Dk.line2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Rd.sm),
            child: SizedBox.square(
              dimension: Sz.avatarSm,
              child: media == AnswerMedia.image
                  ? Image.memory(file.bytes,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => ColoredBox(color: Dk.p4))
                  : ColoredBox(
                      color: Dk.p4,
                      child: Center(
                        child: GlyphIcon(
                          media == AnswerMedia.audio
                              ? Glyph.bell
                              : media == AnswerMedia.video
                                  ? Glyph.image
                                  : Glyph.terminal,
                          size: Sz.glyphXs,
                          color: Dk.t2,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: Sp.x2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  file.name,
                  style: Ty.small.copyWith(color: Dk.t1, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(sizeLabel(file.bytes.length),
                    style: Ty.meta.copyWith(fontSize: 10)),
              ],
            ),
          ),
          SizedBox(width: touch ? 0 : Sp.x05),
          DkIconButton(
            glyph: Glyph.close,
            glyphSize: Sz.glyphXs,
            label: '移除 ${file.name}',
            onTap: onRemove,
          ),
        ],
      ),
    );
  }
}
