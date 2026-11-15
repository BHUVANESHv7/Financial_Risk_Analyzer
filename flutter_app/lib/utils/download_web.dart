import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

const bool canSaveFiles = true;

/// Triggers a browser download of [bytes] named [name].
Future<void> saveFile(String name, Uint8List bytes, String mimeType) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = name
    ..style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
