import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_client/core/files_io.dart';
import 'package:openhuman_client/features/chat/stream/attachments.dart';
import 'package:openhuman_client/features/chat/stream/video_viewer.dart';

void main() {
  test('clock reads like a player', () {
    expect(clock(const Duration(seconds: 7)), '0:07');
    expect(clock(const Duration(minutes: 1, seconds: 23)), '1:23');
    expect(clock(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });

  testWidgets('a clip the app cannot decode goes to the system player', (
    tester,
  ) async {
    String? opened;
    final oldOpen = FilesIo.open;
    final oldCtl = videoControllerFor;
    FilesIo.open = (name, Uint8List bytes) async {
      opened = name;
      return true;
    };
    videoControllerFor = (name, uri) async => null;
    addTearDown(() {
      FilesIo.open = oldOpen;
      videoControllerFor = oldCtl;
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VideoTile(name: 'clip.mp4', uri: 'data:video/mp4;base64,AAAA'),
        ),
      ),
    );
    await tester.tap(find.byType(VideoTile));
    await tester.pumpAndSettle();
    expect(opened, 'clip.mp4');
    expect(find.byType(VideoViewer), findsNothing);
  });
}
