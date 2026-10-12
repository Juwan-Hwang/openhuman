/// Route definitions for the OpenHuman client.
///
/// Uses [go_router] for declarative routing. Two routes:
/// - `/auth` → [AuthScreen] (connect to server)
/// - `/` → [ChatScreen] (main chat)
///
/// The initial location is `/auth` — the user must enter server URL
/// and API key before reaching the chat.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_screen.dart';
import '../features/chat/chat_screen.dart';

/// Router configuration provider.
///
/// Exposed as a Riverpod provider so the router can be accessed
/// via `ref.watch(routerProvider)`.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/auth',
    routes: [
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const ChatScreen(),
      ),
    ],
  );
});
