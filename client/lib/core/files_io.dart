/// Getting files in and out: picking attachments for an answer, reading
/// the bytes behind an attachment (inline `data:` URL or a link), saving
/// them, and opening them with the system's own app.
library;

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;

import 'platform/files_platform.dart' as plat;

import 'tasks.dart';

/// Test seam: swap the platform pieces out.
class FilesIo {
  static Future<List<OutgoingFile>> Function(List<String> extensions) pick =
      _pick;
  static Future<String?> Function(String name, Uint8List bytes) save = _save;
  static Future<bool> Function(String name, Uint8List bytes) open = _open;

  static Future<List<OutgoingFile>> _pick(List<String> extensions) async {
    final groups = extensions.isEmpty
        ? const <XTypeGroup>[]
        : [XTypeGroup(label: '支持的文件', extensions: extensions)];
    final picked = await openFiles(acceptedTypeGroups: groups);
    final out = <OutgoingFile>[];
    for (final f in picked) {
      out.add(
        OutgoingFile(
          name: f.name,
          bytes: await f.readAsBytes(),
          mime: mimeForName(f.name),
        ),
      );
    }
    return out;
  }

  static Future<String?> _save(String name, Uint8List bytes) =>
      plat.saveBytes(name, bytes, mimeForName(name));

  static Future<bool> _open(String name, Uint8List bytes) =>
      plat.openBytes(name, bytes, mimeForName(name));
}

/// The bytes behind an attachment URI.
Future<Uint8List?> bytesOf(String uri) async {
  final d = decodeDataUrl(uri);
  if (d != null) return Uint8List.fromList(d.$2);
  if (!uri.startsWith('http://') && !uri.startsWith('https://')) return null;
  try {
    final res = await http.get(Uri.parse(uri));
    return res.statusCode == 200 ? res.bodyBytes : null;
  } catch (_) {
    return null;
  }
}

/// "1.2 MB", "340 KB".
String sizeLabel(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  final mb = bytes / (1024 * 1024);
  return '${mb < 10 ? mb.toStringAsFixed(1) : mb.round()} MB';
}
