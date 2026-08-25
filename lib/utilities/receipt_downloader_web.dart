import 'dart:convert';
import 'dart:html' as html;

/// Triggers a real browser download of the receipt as a .txt file.
Future<String?> downloadReceiptText(String content, String fileName) async {
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes], 'text/plain');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
  return fileName;
}
