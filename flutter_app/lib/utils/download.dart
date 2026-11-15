/// Save a file to the user's device. Real implementation on web;
/// mobile/desktop builds get a stub that reports it is unsupported.
library;

export 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart';
