/// Every keyboard shortcut on one card, opened with Ctrl/⌘ + /.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/tokens.dart';
import '../../widgets/sheet.dart';

bool get _mac =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

String get _mod => _mac ? '⌘' : 'Ctrl';
String get _alt => _mac ? '⌥' : 'Alt';

/// (what it does, the keys).
List<(String, List<String>)> get shortcutRows => [
      ('搜索', [_mod, 'K']),
      ('下一个待回复', [_mod, 'J']),
      ('上一个对话', [_alt, '↑']),
      ('下一个对话', [_alt, '↓']),
      ('发送', ['Enter']),
      ('换行', ['Shift', 'Enter']),
      ('发送并结束本轮', [_mod, 'Enter']),
      ('显示或隐藏列表', [_mod, 'B']),
      ('详情', [_mod, 'I']),
      ('快捷键', [_mod, '/']),
    ];

Future<void> showShortcuts(BuildContext context) => showDkSheet<void>(
      context,
      maxWidth: 520,
      builder: (_) => const ShortcutsSheet(),
    );

class ShortcutsSheet extends StatelessWidget {
  const ShortcutsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.x6, Sp.x2, Sp.x6, Sp.x6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('快捷键', style: Ty.title),
          const SizedBox(height: Sp.x4),
          for (final (what, keys) in shortcutRows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.x15),
              child: Row(
                children: [
                  Expanded(child: Text(what, style: Ty.body)),
                  for (final k in keys) ...[
                    const SizedBox(width: Sp.x1),
                    _Key(k),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 26),
      padding: const EdgeInsets.symmetric(horizontal: Sp.x2, vertical: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Dk.p3,
        borderRadius: BorderRadius.circular(Rd.sm),
        border: Border.all(color: Dk.line2),
      ),
      child: Text(label, style: Ty.meta.copyWith(color: Dk.t1)),
    );
  }
}
