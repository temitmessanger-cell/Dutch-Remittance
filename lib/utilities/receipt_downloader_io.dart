import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Saves the receipt text to the app's documents directory (mobile/
/// desktop) and returns the path it was saved to, or null on failure.
Future<String?> downloadReceiptText(String content, String fileName) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(content);
    return file.path;
  } catch (e) {
    return null;
  }
}
