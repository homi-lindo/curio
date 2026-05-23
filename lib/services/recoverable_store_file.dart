import 'dart:io';

bool isRecoverableStoreFormatError(Object error) {
  return error is FormatException ||
      error is TypeError ||
      error is ArgumentError ||
      error is StateError;
}

Future<void> preserveInvalidStoreFile(File file) async {
  if (!await file.exists()) {
    return;
  }

  final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
  final archive = File('${file.path}.invalid-$stamp');
  try {
    await file.rename(archive.path);
  } on FileSystemException {
    try {
      await file.copy(archive.path);
      await file.delete();
    } on FileSystemException {
      // A corrupt auxiliary store must not block startup. The caller will
      // continue with safe defaults if archival is unavailable.
    }
  }
}
