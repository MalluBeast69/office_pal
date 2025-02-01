import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:universal_html/html.dart' as html;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class PdfService {
  static Future<void> savePdfFile(List<int> bytes, String fileName) async {
    if (kIsWeb) {
      // For web platform, use Blob with type application/pdf
      final blob = html.Blob([bytes], 'application/pdf');

      // Create a download URL
      final url = html.Url.createObjectUrlFromBlob(blob);

      // Create an invisible link and trigger download
      final anchor = html.document.createElement('a') as html.AnchorElement
        ..href = url
        ..style.display = 'none'
        ..download = fileName;

      html.document.body!.children.add(anchor);
      anchor.click();

      // Clean up
      html.document.body!.children.remove(anchor);
      html.Url.revokeObjectUrl(url);
    } else {
      // For mobile/desktop platforms
      final output = await getTemporaryDirectory();
      final file = File('${output.path}/$fileName');
      await file.writeAsBytes(bytes);

      final uri = Uri.file(file.path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        throw 'Could not open the PDF file';
      }
    }
  }
}
