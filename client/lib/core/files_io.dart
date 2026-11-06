/// Getting files in and out: picking attachments for an answer, reading
/// the bytes behind an attachment (inline `data:` URL or a link), saving
/// them, and opening them with the system's own app.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

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

  static bool get _desktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// Save to a place the person picks (desktop) or the app's documents
  /// folder (phones). Returns where it went, or null when cancelled.
  static Future<String?> _save(String name, Uint8List bytes) async {
    if (_desktop) {
      final loc = await getSaveLocation(suggestedName: name);
      if (loc == null) return null;
      await File(loc.path).writeAsBytes(bytes);
      return loc.path;
    }
    final dir = await getApplicationDocumentsDirectory();
    final f = File(p.join(dir.path, name));
    await f.writeAsBytes(bytes);
    return f.path;
  }

  /// Write to a temp file and hand it to the system player or viewer.
  static Future<bool> _open(String name, Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final f = File(p.join(dir.path, 'openhuman-$name'));
    await f.writeAsBytes(bytes);
    return launchUrl(Uri.file(f.path));
  }
}

/// The bytes behind an attachment URI.
Future<Uint8List?> bytesOf(String uri) async {
  final d = decodeDataUrl(uri);
  if (d != null) return Uint8List.fromList(d.$2);
  if (!uri.startsWith('http://') && !uri.startsWith('https://')) return null;
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(uri));
    final res = await req.close();
    if (res.statusCode != 200) return null;
    final b = BytesBuilder(copy: false);
    await for (final c in res) {
      b.add(c);
    }
    return b.takeBytes();
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
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
