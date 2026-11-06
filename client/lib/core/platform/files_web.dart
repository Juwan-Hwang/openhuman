/// Browser file plumbing: a Blob for every file, a download for saving,
/// a new tab for opening.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

String _blobUrl(Uint8List bytes, String mime) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mime),
  );
  return web.URL.createObjectURL(blob);
}

/// Hands the file to the browser as a download. Returns its name.
Future<String?> saveBytes(String name, Uint8List bytes, String mime) async {
  final url = _blobUrl(bytes, mime);
  final a = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = name;
  web.document.body?.append(a);
  a.click();
  a.remove();
  Future.delayed(
    const Duration(minutes: 1),
    () => web.URL.revokeObjectURL(url),
  );
  return name;
}

/// Opens the file in a new tab; the browser shows what it can.
Future<bool> openBytes(String name, Uint8List bytes, String mime) async {
  final url = _blobUrl(bytes, mime);
  return web.window.open(url, '_blank') != null;
}

/// A player for bytes already in memory.
Future<VideoPlayerController> videoFromBytes(
  String name,
  Uint8List bytes,
  String mime,
) async =>
    VideoPlayerController.networkUrl(Uri.parse(_blobUrl(bytes, mime)));

/// The browser plays video itself.
void registerVideoBackends() {}
