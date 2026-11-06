/// Touch feedback for the moments that change something: a message
/// leaving, a menu opening, a turn ending, a check that failed. Only on
/// touch screens; a desk has nothing to buzz.
library;

import 'package:flutter/services.dart';

import '../app/adaptive.dart';

class Haptic {
  static void _go(Future<void> Function() f) {
    if (Touch.primary) f();
  }

  /// A message or answer went out.
  static void sent() => _go(HapticFeedback.lightImpact);

  /// A long press opened a menu.
  static void menu() => _go(HapticFeedback.mediumImpact);

  /// A state flipped: a turn ended, a toggle moved.
  static void tick() => _go(HapticFeedback.selectionClick);

  /// Something could not go through.
  static void warn() => _go(HapticFeedback.heavyImpact);
}
