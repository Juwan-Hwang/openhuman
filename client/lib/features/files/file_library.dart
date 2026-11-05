/// 文件库: every file this account holds on the server — what was sent to
/// you, and what you answered with — to open, save, or remove.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

import '../../app/adaptive.dart';
import '../../app/theme.dart';
import '../../core/files_io.dart';
import '../../core/sdk_provider.dart';
import '../../core/tasks.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/sheet.dart';
import '../chat/conversation_sidebar.dart' show rowTime;

/// The library, newest first. Refreshed by invalidating it.
final fileLibraryProvider =
    FutureProvider.autoDispose<List<oh.StoredFileInfo>>((ref) async {
  final files = await ref.read(openHumanClientProvider).listFiles();
  files.sort((a, b) {
    final x = a.createdAt, y = b.createdAt;
    if (x == null || y == null) return 0;
    return y.compareTo(x);
  });
  return files;
});

class FileLibrarySheet extends ConsumerStatefulWidget {
  const FileLibrarySheet({super.key});

  static Future<void> show(BuildContext context) => showDkSheet<void>(
        context,
        maxWidth: 680,
        builder: (_) => const FileLibrarySheet(),
      );

  @override
  ConsumerState<FileLibrarySheet> createState() => _FileLibrarySheetState();
}

class _FileLibrarySheetState extends ConsumerState<FileLibrarySheet> {
  /// Files with an action in flight, so their row shows it.
  final _busy = <String>{};
  bool _uploading = false;

  Future<void> _withRow(String id, Future<void> Function() action) async {
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      await action();
    } catch (e) {
      if (mounted) toast(context, '没成功，稍后再试');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _save(oh.StoredFileInfo f) => _withRow(f.id, () async {
        final bytes =
            await ref.read(openHumanClientProvider).fileContent(f.id);
        final where = await FilesIo.save(f.filename, bytes);
        if (where != null && mounted) toast(context, '已保存「${f.filename}」');
      });

  Future<void> _open(oh.StoredFileInfo f) => _withRow(f.id, () async {
        final bytes =
            await ref.read(openHumanClientProvider).fileContent(f.id);
        final ok = await FilesIo.open(f.filename, bytes);
        if (!ok && mounted) toast(context, '这台设备打不开这种文件，可以先保存');
      });

  Future<void> _delete(oh.StoredFileInfo f) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('「${f.filename}」会从服务器上删掉，已经发出去的消息里也就打不开了。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _withRow(f.id, () async {
      final ok = await ref.read(openHumanClientProvider).deleteFile(f.id);
      if (!ok) throw StateError('refused');
      ref.invalidate(fileLibraryProvider);
      if (mounted) toast(context, '已删除');
    });
  }

  Future<void> _upload() async {
    if (_uploading) return;
    final picked = await FilesIo.pick(const []);
    if (picked.isEmpty) return;
    setState(() => _uploading = true);
    try {
      final client = ref.read(openHumanClientProvider);
      for (final f in picked) {
        await client.uploadFile(f.name, f.bytes, mime: f.mime);
      }
      ref.invalidate(fileLibraryProvider);
      if (mounted) {
        toast(context,
            picked.length == 1 ? '已上传「${picked.first.name}」' : '已上传 ${picked.length} 个文件');
      }
    } catch (_) {
      if (mounted) toast(context, '上传没成功，稍后再试');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final files = ref.watch(fileLibraryProvider);
    final list = files.valueOrNull ?? const <oh.StoredFileInfo>[];
    final total = list.fold<int>(0, (s, f) => s + f.bytes);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.x6, Sp.x2, Sp.x3, Sp.x4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('文件库', style: Ty.title.copyWith(fontSize: 18)),
                    const SizedBox(height: 4),
                    Text(
                      files.hasValue && list.isNotEmpty
                          ? '${list.length} 个文件 · ${sizeLabel(total)}'
                          : '别人发给你的、你在回答里交出去的文件都在这里',
                      style: Ty.small,
                    ),
                  ],
                ),
              ),
              DkButton(
                key: const ValueKey('files-upload'),
                label: '上传',
                glyph: Glyph.plus,
                dense: true,
                busy: _uploading,
                onTap: _upload,
              ),
              const SizedBox(width: Sp.x1),
              DkIconButton(
                glyph: Glyph.close,
                label: '关闭',
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Flexible(
          child: files.when(
            loading: () => const _Note(loading: true, title: '正在读取文件库…'),
            error: (_, __) => _Note(
              icon: Icons.cloud_off_outlined,
              title: '没能读取文件库',
              subtitle: '文件都还在，网络好些时再打开看看',
              action: DkButton(
                label: '重试',
                glyph: Glyph.retry,
                dense: true,
                onTap: () => ref.invalidate(fileLibraryProvider),
              ),
            ),
            data: (list) => list.isEmpty
                ? const _Note(
                    icon: Icons.folder_open_outlined,
                    title: '还没有文件',
                    subtitle: '有人发来文件，或者你用文件回答请求后，会出现在这里',
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x5),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                    itemBuilder: (_, i) {
                      final f = list[i];
                      return _FileRow(
                        key: ValueKey('file-${f.id}'),
                        file: f,
                        busy: _busy.contains(f.id),
                        onOpen: () => _open(f),
                        onSave: () => _save(f),
                        onDelete: () => _delete(f),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

/// Where a file came from, in words.
String fileOrigin(oh.StoredFileInfo f) {
  final p = (f.purpose ?? '').toLowerCase();
  if (p.contains('answer') || p.contains('output') || p.contains('result')) {
    return '你交出去的';
  }
  if (p == 'user_data' || p.isEmpty) return '上传的';
  if (p.contains('vision') || p.contains('assistants')) return '对方发来的';
  return p;
}

class _FileRow extends StatefulWidget {
  const _FileRow({
    super.key,
    required this.file,
    required this.busy,
    required this.onOpen,
    required this.onSave,
    required this.onDelete,
  });

  final oh.StoredFileInfo file;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onSave;
  final VoidCallback onDelete;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.file;
    final mime = f.mime ?? mimeForName(f.filename);
    final when = f.createdAt == null
        ? null
        : rowTime(f.createdAt!.toLocal(), DateTime.now());
    final meta = [
      if (sizeLabel(f.bytes).isNotEmpty) sizeLabel(f.bytes),
      if (when != null) when,
      fileOrigin(f),
    ].join(' · ');
    final showActions = widget.busy || _hover || Touch.primary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.busy ? null : widget.onOpen,
          borderRadius: BorderRadius.circular(Rd.md),
          hoverColor: Dk.p2,
          splashFactory: NoSplash.splashFactory,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Sp.x2,
              vertical: Sp.x25,
            ),
            child: Row(
              children: [
                _KindBadge(mime: mime, name: f.filename),
                const SizedBox(width: Sp.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.filename.isEmpty ? f.id : f.filename,
                        style: Ty.name.copyWith(color: Dk.t1Soft),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        style: Ty.small.copyWith(fontSize: 11.5, color: Dk.t3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Sp.x2),
                if (widget.busy)
                  const SizedBox.square(
                    dimension: Sz.glyphSm,
                    child: CircularProgressIndicator(
                      strokeWidth: Sz.stroke,
                      color: Dk.t2,
                    ),
                  )
                else
                  AnimatedOpacity(
                    duration: Mo.fast,
                    opacity: showActions ? 1 : 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DkIconButton(
                          glyph: Glyph.save,
                          label: '保存到本机',
                          glyphSize: Sz.glyphSm,
                          onTap: showActions ? widget.onSave : null,
                        ),
                        DkIconButton(
                          glyph: Glyph.trash,
                          label: '删除',
                          glyphSize: Sz.glyphSm,
                          onTap: showActions ? widget.onDelete : null,
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

/// A file's kind at a glance: a tinted square with its extension.
class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.mime, required this.name});
  final String mime;
  final String name;

  @override
  Widget build(BuildContext context) {
    final (icon, tint) = switch (mime.split('/').first) {
      'image' => (Icons.image_outlined, Dk.blue),
      'audio' => (Icons.graphic_eq_rounded, Dk.ok),
      'video' => (Icons.movie_outlined, Dk.warn),
      _ => (Icons.description_outlined, Dk.t2),
    };
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Rd.md),
        border: Border.all(color: tint.withValues(alpha: 0.22)),
      ),
      child: Icon(icon, size: 18, color: tint),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({
    required this.title,
    this.icon,
    this.subtitle,
    this.action,
    this.loading = false,
  });

  final String title;
  final IconData? icon;
  final String? subtitle;
  final Widget? action;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.x6, Sp.x8, Sp.x6, Sp.x10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: Sz.stroke,
                color: Dk.t2,
              ),
            )
          else if (icon != null)
            Icon(icon, size: 22, color: Dk.t3),
          const SizedBox(height: Sp.x3),
          Text(title, style: Ty.small.copyWith(color: Dk.t2)),
          if (subtitle != null) ...[
            const SizedBox(height: Sp.x15),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: Ty.small.copyWith(color: Dk.t3, fontSize: 12),
            ),
          ],
          if (action != null) ...[const SizedBox(height: Sp.x4), action!],
        ],
      ),
    );
  }
}
