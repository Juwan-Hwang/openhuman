/// Picks the native or the browser file plumbing at compile time.
library;

export 'files_native.dart' if (dart.library.js_interop) 'files_web.dart';
