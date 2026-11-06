/// Native file plumbing: temp files, the save dialog, the system opener.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

bool get _desktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Save to a place the person picks (desktop) or the app's documents
/// folder (phones). Returns where it went, or null when cancelled.
Future<String?> saveBytes(String name, Uint8List bytes, String mime) async {
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

Future<File> _temp(String name, Uint8List bytes) async {
  final dir = await getTemporaryDirectory();
  final f = File(p.join(dir.path, 'openhuman-$name'));
  await f.writeAsBytes(bytes);
  return f;
}

/// Write to a temp file and hand it to the system player or viewer.
Future<bool> openBytes(String name, Uint8List bytes, String mime) async =>
    launchUrl(Uri.file((await _temp(name, bytes)).path));

/// A player for bytes already in memory.
Future<VideoPlayerController> videoFromBytes(
  String name,
  Uint8List bytes,
  String mime,
) async =>
    VideoPlayerController.file(await _temp(name, bytes));

/// video_player has no Windows or Linux backend of its own; fvp (libmdk)
/// plays clips there.
void registerVideoBackends() {
  if (Platform.isWindows || Platform.isLinux) {
    fvp.registerWith(options: {
      'platforms': ['windows', 'linux'],
    });
  }
}
