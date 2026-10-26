import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'app_state.dart';

/// Writes a backup to a file and opens the share sheet (Files, Drive, email…).
Future<void> shareBackup(AppState app) async {
  final stamp = DateTime.now().toIso8601String().substring(0, 10);
  final file = File('${Directory.systemTemp.path}/helium-backup-$stamp.json');
  await file.writeAsString(app.exportBackup());
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/json')], subject: 'Helium backup $stamp'));
}

/// Lets the user pick a backup file and restores it. Returns false if they cancelled.
Future<bool> pickAndRestoreBackup(AppState app) async {
  final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
  if (files.isEmpty) return false;
  final text = utf8.decode(await files.first.readAsBytes());
  await app.importBackup(text);
  return true;
}
