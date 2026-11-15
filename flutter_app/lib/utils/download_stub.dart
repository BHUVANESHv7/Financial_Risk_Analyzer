import 'dart:typed_data';

const bool canSaveFiles = false;

Future<void> saveFile(String name, Uint8List bytes, String mimeType) async {
  throw UnsupportedError('Export is available in the web app.');
}
