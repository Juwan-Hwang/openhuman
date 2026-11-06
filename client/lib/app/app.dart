/// The root [MaterialApp] for the OpenHuman client.
///
/// Uses [go_router] for navigation and Material 3 theming.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'appearance.dart';
import 'routes.dart';
import '../widgets/window_chrome.dart';
import 'theme.dart';

/// The root widget of the OpenHuman client app.
class OpenHumanApp extends ConsumerStatefulWidget {
  const OpenHumanApp({super.key});

  @override
  ConsumerState<OpenHumanApp> createState() => _OpenHumanAppState();
}

class _OpenHumanAppState extends ConsumerState<OpenHumanApp>
    with WidgetsBindingObserver {
  Brightness? _drawn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (ref.read(appearanceProvider) == ThemeMode.system) setState(() {});
  }

  Brightness _brightness(ThemeMode mode) => switch (mode) {
        ThemeMode.light => Brightness.light,
        ThemeMode.dark => Brightness.dark,
        ThemeMode.system =>
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
      };

  /// Widgets read [Dk] while they build, so a palette change has to reach
  /// every one of them, not only those whose inputs changed. Rebuilding
  /// in place keeps navigation, scroll and text where they are.
  void _repaintAll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      void mark(Element e) {
        e.markNeedsBuild();
        e.visitChildren(mark);
      }

      WidgetsBinding.instance.rootElement?.visitChildren(mark);
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final b = _brightness(ref.watch(appearanceProvider));
    final theme = themeFor(b);
    if (_drawn != null && _drawn != b) _repaintAll();
    _drawn = b;
    SystemChrome.setSystemUIOverlayStyle(
      b == Brightness.light
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
    );

    return MaterialApp.router(
      title: 'OpenHuman',
      theme: theme,
      themeMode: ThemeMode.light,
      themeAnimationDuration: Duration.zero,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // ThemeData has no fontFamilyFallback, so anything that inherits
      // the default text style — rather than naming a style from the
      // theme — would otherwise resolve Chinese to the system face and
      // the two scripts would stop looking like one product.
      builder: (context, child) => DefaultTextStyle(
        style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
            .copyWith(fontFamilyFallback: const ['NotoSansSC']),
        child: WindowChrome(child: child!),
      ),
    );
  }
}
