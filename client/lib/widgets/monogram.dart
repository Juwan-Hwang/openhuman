/// Identity marks for callers and rooms.
library;

import 'package:flutter/material.dart';

import '../app/tokens.dart';

/// A two-letter monogram on a hue derived from the name, so the same
/// caller always wears the same colour across sessions.
class Monogram extends StatelessWidget {
  const Monogram(this.name, {super.key, this.size = 22, this.group = false});
  final String name;
  final double size;

  /// A group room: shows a people glyph instead of letters.
  final bool group;

  static const _hues = [
    Color(0xFFD97757), // warm clay
    Color(0xFF6E8BE0),
    Color(0xFF8BBF5E),
    Color(0xFFC9A44A),
    Color(0xFFB07AD6),
    Color(0xFF4FB3A9),
  ];

  @override
  Widget build(BuildContext context) {
    final h = name.codeUnits.fold<int>(0, (a, c) => (a * 31 + c) & 0xffff);
    final hue = _hues[h % _hues.length];
    final latin = RegExp(r'[A-Za-z0-9]').allMatches(name).toList();
    final letters = latin.isNotEmpty
        ? latin.take(2).map((m) => m.group(0)!).join().toUpperCase()
        : name.characters.take(1).toString();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hue,
        borderRadius: BorderRadius.circular(size * 0.27),
      ),
      child: group
          ? Icon(Icons.groups_rounded,
              size: size * 0.62, color: const Color(0xFF14110E))
          : Text(
              letters,
              style: Ty.name.copyWith(
                fontSize: size * 0.45,
                color: const Color(0xFF14110E),
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
    );
  }
}
