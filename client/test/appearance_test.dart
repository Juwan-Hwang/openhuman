import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_client/app/theme.dart';

void main() {
  tearDown(() => Dk.use(Brightness.dark));

  test('light and dark palettes swap the floor and the ink', () {
    themeFor(Brightness.light);
    expect(Dk.light, isTrue);
    expect(Dk.bg.computeLuminance(), greaterThan(0.8));
    expect(Dk.t1.computeLuminance(), lessThan(0.05));

    final dark = themeFor(Brightness.dark);
    expect(Dk.light, isFalse);
    expect(Dk.bg.computeLuminance(), lessThan(0.05));
    expect(dark.colorScheme.surface, Dk.bg);
  });

  test('body text stays readable on every floor', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final b in Brightness.values) {
      Dk.use(b);
      for (final floor in [Dk.bg, Dk.p1, Dk.p2, Dk.p3]) {
        expect(contrast(Dk.t1, floor), greaterThan(7), reason: '$b t1');
        expect(contrast(Dk.t2, floor), greaterThan(4.5), reason: '$b t2');
      }
    }
  });
}
