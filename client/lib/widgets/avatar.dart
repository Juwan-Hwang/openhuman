/// Avatars: people are round, rooms are rounded squares.
///
/// A person's colour is derived from the person's name, never from the
/// tool they write in, so 林晓 looks like 林晓 whether she writes from
/// Claude Code today or Cursor tomorrow.
library;

import 'package:flutter/material.dart';

import '../app/tokens.dart';
import '../core/identity.dart';
import 'glyphs.dart';

/// The hue for [name], stable across sessions.
Color hueFor(String name) {
  // FNV-1a: names that differ by one character land far apart.
  var h = 0x811c9dc5;
  for (final c in name.trim().toLowerCase().codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return Dk.hues[h % Dk.hues.length];
}

class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.name,
    this.size = Sz.avatar,
    this.me = false,
    this.anonymous = false,
    this.waiting = false,
  });

  final String name;
  final double size;

  /// The signed-in person: Paper, the brand's own face.
  final bool me;

  /// Nobody to name yet: an outline with a person glyph.
  final bool anonymous;

  /// A small Apricot badge: this person is waiting on you.
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    final Widget face;
    if (anonymous) {
      face = Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Dk.p3,
          border: Border.all(color: Dk.line2),
        ),
        child: GlyphIcon(Glyph.person, size: size * 0.56, color: Dk.t3),
      );
    } else {
      final all = initialsOf(name);
      final cjk = RegExp(r'[\u3400-\u9fff]').hasMatch(all);
      // Two characters only fit a face big enough to read them.
      final letters = cjk && size < 30 && all.characters.length > 1
          ? all.characters.last
          : all;
      face = Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: me ? Dk.paper : hueFor(name),
        ),
        child: Text(
          letters,
          maxLines: 1,
          // The face is a fixed size; the system text size must not
          // push its letters past the edge.
          textScaler: TextScaler.noScaling,
          style: Ty.name.copyWith(
            fontSize: size * (cjk && letters.length > 1 ? 0.33 : 0.4),
            color: me ? Dk.ink : Dk.onHue,
            fontWeight: FontWeight.w700,
            height: 1,
            letterSpacing: cjk ? 0 : -0.2,
          ),
        ),
      );
    }
    if (!waiting) return face;
    final b = (size * 0.3).clamp(Sz.dotSm + 2, 14.0);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          face,
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: b,
              height: b,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Dk.signal,
                border: Border.all(color: Dk.p1, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A room: up to four members' faces in a rounded square, or a people
/// glyph when the members are not known yet.
class RoomAvatar extends StatelessWidget {
  const RoomAvatar({
    super.key,
    required this.title,
    this.members = const [],
    this.size = Sz.avatar,
    this.waiting = false,
  });

  final String title;
  final List<String> members;
  final double size;
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    final shown = members.take(4).toList();
    Widget inner;
    if (shown.length < 2) {
      inner = Center(
        child: GlyphIcon(Glyph.people, size: size * 0.56, color: Dk.onHue),
      );
    } else {
      final cell = (size - 6) / 2;
      inner = Padding(
        padding: const EdgeInsets.all(2),
        child: Wrap(
          spacing: 2,
          runSpacing: 2,
          children: [
            for (final m in shown)
              Container(
                width: cell,
                height: cell,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hueFor(m),
                  borderRadius: BorderRadius.circular(cell * 0.3),
                ),
                child: Text(
                  initialsOf(m).characters.first,
                  textScaler: TextScaler.noScaling,
                  style: Ty.name.copyWith(
                    fontSize: cell * 0.52,
                    height: 1,
                    color: Dk.onHue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      );
    }
    final face = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: shown.length < 2 ? hueFor(title) : Dk.p3,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: inner,
    );
    if (!waiting) return face;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          face,
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: (size * 0.3).clamp(Sz.dotSm + 2, 14.0),
              height: (size * 0.3).clamp(Sz.dotSm + 2, 14.0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Dk.signal,
                border: Border.all(color: Dk.p1, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
