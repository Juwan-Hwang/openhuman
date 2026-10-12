/// OpenHuman Dart SDK — Human-as-an-API runtime.
///
/// Thin transport layer for the OpenHuman protocol.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:openhuman_sdk_dart/openhuman.dart';
///
/// final client = OpenHumanClient();
/// client.messages.listen((msg) => print(msg.text));
/// await client.connect('ws://localhost:8080/ws', 'ohk_xxx');
/// await client.sendReply('cnv_xxx', 'Hello!');
/// ```
///
/// See `example/human_client.dart` for a complete CLI example.
library openhuman;

// auth.dart is a Phase 2 stub — not exported until implemented.
// export 'src/auth.dart';

export 'src/client.dart';
export 'src/history.dart';
export 'src/connection.dart';
export 'src/events.dart';
export 'src/messages.dart';
export 'src/capabilities.dart';
export 'src/version.dart';
