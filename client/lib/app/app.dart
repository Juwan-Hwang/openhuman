/// The root [MaterialApp] for the OpenHuman client.
///
/// Uses [go_router] for navigation and Material 3 theming.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'routes.dart';
import '../widgets/window_chrome.dart';
import 'theme.dart';

/// The root widget of the OpenHuman client app.
class OpenHumanApp extends ConsumerWidget {
  const OpenHumanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'OpenHuman',
      theme: lightTheme,
      darkTheme: darkTheme,
      // Dark only: the Darkroom palette is built around a dark floor.
      themeMode: ThemeMode.dark,
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
