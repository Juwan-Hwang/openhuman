/// OpenHuman Client — Human Endpoint Runtime
///
/// Entry point for the Flutter application. Wraps the app in a
/// [ProviderScope] (Riverpod) and launches [OpenHumanApp].
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

import 'core/notification_service.dart';
import 'core/tray_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  await TrayService.instance.initialize();

  // Without this, a single unhandled error — a send over a socket that
  // was reaped upstream, say — takes the whole application down rather
  // than failing the action that caused it. Report and carry on.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[OpenHuman] uncaught: ${details.exception}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[OpenHuman] uncaught: $error');
    return true;
  };

  runApp(
    const ProviderScope(
      child: OpenHumanApp(),
    ),
  );
}
