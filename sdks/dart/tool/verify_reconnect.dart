// Watches the connection for a few minutes to see whether the SDK
// reconnects on its own after the upstream reaps the socket.
//
// Run:  dart run tool/verify_reconnect.dart <ws-url> <api-key>
import 'dart:async';
import 'package:openhuman_sdk_dart/openhuman.dart';

Future<void> main(List<String> args) async {
  final client = OpenHumanClient();
  final stopwatch = Stopwatch()..start();

  client.connectionState.listen((s) {
    print('  [${stopwatch.elapsed.inSeconds.toString().padLeft(3)}s] state -> ${s.name}');
  });

  await client.connect(args[0], args[1]);

  // Watch long enough for the upstream to reap an idle socket.
  await Future<void>.delayed(const Duration(seconds: 210));

  print('  最终状态: ${client.currentState.name}');
  client.dispose();
}
