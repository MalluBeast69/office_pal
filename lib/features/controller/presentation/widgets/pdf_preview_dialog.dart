import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;
import 'package:flutter/foundation.dart' show kIsWeb;

class ExcelPreviewDialog extends StatelessWidget {
  final List<int> excelBytes;
  final String fileName;

  const ExcelPreviewDialog({
    super.key,
    required this.excelBytes,
    this.fileName = 'exam_timetable.xlsx',
  });

  Future<void> _downloadExcel() async {
    if (kIsWeb) {
      final blob = html.Blob([excelBytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      try {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Save exam timetable',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
        );

        if (outputFile != null) {
          final file = File(outputFile);
          await file.writeAsBytes(excelBytes);
        }
      } catch (e) {
        debugPrint('Error saving Excel: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Exam Timetable'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.table_chart, size: 64, color: Colors.green),
          SizedBox(height: 16),
          Text('Excel file has been generated successfully!'),
          SizedBox(height: 8),
          Text(
            'Click the download button to save the timetable.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: _downloadExcel,
          icon: const Icon(Icons.download),
          label: const Text('Download Excel'),
        ),
      ],
    );
  }
}
