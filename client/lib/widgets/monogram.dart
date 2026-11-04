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

  /// The callers people run most get fixed, distinct hues, so the usual
  /// pair (say Claude Code and Codex) never share a colour by hash luck.
  static const _fixed = <String, int>{
    'claude': 3, // lilac
    'codex': 1, // moss
    'opencode': 0, // slate
    'gemini': 6, // steel
    'cursor': 7, // olive
    'grok': 4, // teal
    'reasonix': 5, // rose
    'pi': 2, // brass
  };

  static Color? _known(String name) {
    final n = name.toLowerCase();
    for (final e in _fixed.entries) {
      if (e.key == 'pi'
          ? n == 'pi' || n.startsWith('pi ')
          : n.contains(e.key)) {
        return Dk.hues[e.value];
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // FNV-1a: short names that differ by a letter land far apart, so a
    // sidebar of three agents does not come out three shades of green.
    var h = 0x811c9dc5;
    for (final c in name.toLowerCase().codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    final hue = _known(name) ?? Dk.hues[h % Dk.hues.length];
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
          ? Icon(Icons.groups_rounded, size: size * 0.62, color: Dk.onHue)
          : Text(
              letters,
              style: Ty.name.copyWith(
                fontSize: size * 0.45,
                color: Dk.onHue,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
    );
  }
}
