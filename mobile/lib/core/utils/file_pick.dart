import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class PickedFile {
  const PickedFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  String get sizeLabel {
    final kb = bytes.length / 1024;
    return kb < 1024 ? '${kb.toStringAsFixed(1)} KB' : '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}

/// Lets the user pick a CSV or Excel file and reads it into memory.
/// Bytes (not paths) are used so this also works on web.
Future<PickedFile?> pickSpreadsheet() async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Select a CSV or Excel file',
    type: FileType.custom,
    allowedExtensions: const ['csv', 'xlsx'],
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  return PickedFile(name: file.name, bytes: bytes);
}
