/// Bottom-sheet parts shared by every sheet in the console.
library;

import 'package:flutter/material.dart';

import '../app/tokens.dart';

/// The grip at the top of a sheet: a short Paper-tinted bar, with room
/// above and below so a thumb finds it.
class SheetGrip extends StatelessWidget {
  const SheetGrip({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 10, bottom: 6),
      child: Center(
        child: SizedBox(
          width: 36,
          height: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Dk.line2,
              borderRadius: BorderRadius.all(Radius.circular(Rd.pill)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens [child] as a console sheet: Darkroom floor, rounded top, grip,
/// and room for the keyboard and the phone's home indicator.
Future<T?> showDkSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxWidth = 760,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: BoxConstraints(maxWidth: maxWidth),
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Dk.p1,
          borderRadius: BorderRadius.vertical(top: Radius.circular(Rd.xl)),
          // A uniform hairline: Flutter cannot round a border whose
          // sides differ in colour.
          border: Border.fromBorderSide(BorderSide(color: Dk.line2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetGrip(),
            Flexible(child: builder(c)),
            SizedBox(height: MediaQuery.viewPaddingOf(c).bottom),
          ],
        ),
      ),
    ),
  );
}
