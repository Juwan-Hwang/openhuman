import 'dart:async';

import 'package:openhuman_client/app/adaptive.dart';
import 'package:openhuman_client/app/tokens.dart';

/// Ambient loops (the mark's wink, the breathing state dot) never settle,
/// so widget tests run with them off.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Mo.ambient = false;
  // The test platform reports Android; tests opt into touch explicitly.
  Touch.debugOverride = false;
  await testMain();
}
