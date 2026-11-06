/// Plays a clip inside the app: a dark sheet with the picture, a play
/// button, a scrubber and the time. Falls back to the system player when
/// the clip cannot be decoded here.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme.dart';
import '../../../app/tokens.dart';
import '../../../core/files_io.dart';
import '../../../core/platform/files_platform.dart' as plat;
import '../../../core/tasks.dart';
import '../../../widgets/controls.dart';
import '../../../widgets/glyphs.dart';
import 'attachments.dart';

/// Test seam: tests swap this out, since no decoder runs under test.
Future<VideoPlayerController?> Function(String name, String uri)
    videoControllerFor = _controllerFor;

Future<VideoPlayerController?> _controllerFor(String name, String uri) async {
  try {
    final VideoPlayerController c;
    if (uri.startsWith('http://') || uri.startsWith('https://')) {
      c = VideoPlayerController.networkUrl(Uri.parse(uri));
    } else {
      final bytes = await bytesOf(uri);
      if (bytes == null) return null;
      final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
      c = await plat.videoFromBytes(
        safe.contains('.') ? safe : '$safe.mp4',
        bytes,
        decodeDataUrl(uri)?.$1 ?? 'video/mp4',
      );
    }
    await c.initialize();
    return c;
  } catch (_) {
    return null;
  }
}

/// Opens [uri] in the in-app player. Returns false when it could not be
/// decoded, so the caller can hand it to the system instead.
Future<bool> playVideo(
  BuildContext context, {
  required String name,
  required String uri,
  required VoidCallback onSave,
}) async {
  final c = await videoControllerFor(name, uri);
  if (c == null || !context.mounted) {
    await c?.dispose();
    return false;
  }
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.86),
    builder: (_) => VideoViewer(controller: c, name: name, onSave: onSave),
  );
  await c.dispose();
  return true;
}

class VideoViewer extends StatefulWidget {
  const VideoViewer({
    super.key,
    required this.controller,
    required this.name,
    required this.onSave,
  });
  final VideoPlayerController controller;
  final String name;
  final VoidCallback onSave;

  @override
  State<VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<VideoViewer> {
  VideoPlayerController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_tick);
    _c.play();
  }

  @override
  void dispose() {
    _c.removeListener(_tick);
    _c.pause();
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  void _toggle() {
    final v = _c.value;
    if (v.isPlaying) {
      _c.pause();
    } else {
      if (v.duration > Duration.zero && v.position >= v.duration) {
        _c.seekTo(Duration.zero);
      }
      _c.play();
    }
  }

  void _skip(int seconds) {
    final v = _c.value;
    var to = v.position + Duration(seconds: seconds);
    if (to < Duration.zero) to = Duration.zero;
    if (to > v.duration) to = v.duration;
    _c.seekTo(to);
  }

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    final total = v.duration.inMilliseconds;
    final at = v.position.inMilliseconds.clamp(0, total == 0 ? 0 : total);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): _toggle,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _skip(-5),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _skip(5),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(Sp.x8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.name,
                      style: Ty.name.copyWith(color: Dk.t1),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DkIconButton(
                    glyph: Glyph.save,
                    label: '保存视频',
                    onTap: widget.onSave,
                  ),
                  DkIconButton(
                    glyph: Glyph.close,
                    label: '关闭',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: Sp.x3),
              Flexible(
                child: GestureDetector(
                  onTap: _toggle,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Rd.lg),
                    child: AspectRatio(
                      aspectRatio: v.aspectRatio > 0 ? v.aspectRatio : 16 / 9,
                      child: ColoredBox(
                        color: Colors.black,
                        child: VideoPlayer(_c),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Sp.x3),
              Row(
                children: [
                  Tooltip(
                    message: v.isPlaying ? '暂停' : '播放',
                    child: Pressable(
                      key: const ValueKey('video-toggle'),
                      semanticLabel: v.isPlaying ? '暂停' : '播放',
                      radius: Rd.pill,
                      onTap: _toggle,
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
                            painter: PlayGlyph(playing: v.isPlaying),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: Sp.x2),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        activeTrackColor: Dk.paper,
                        inactiveTrackColor: Dk.line2,
                        thumbColor: Dk.paper,
                        overlayShape: SliderComponentShape.noOverlay,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        value: at.toDouble(),
                        max: total <= 0 ? 1 : total.toDouble(),
                        onChanged: total <= 0
                            ? null
                            : (x) =>
                                _c.seekTo(Duration(milliseconds: x.round())),
                      ),
                    ),
                  ),
                  const SizedBox(width: Sp.x3),
                  Text(
                    '${clock(v.position)} / ${clock(v.duration)}',
                    style: Ty.meta.copyWith(color: Dk.t2),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 0:07, 1:23, 1:02:03.
String clock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}
