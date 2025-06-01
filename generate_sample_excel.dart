import 'dart:io';
import 'package:excel/excel.dart';

void main() {
  final excel = Excel.createExcel();
  final sheet = excel.sheets[excel.getDefaultSheet()!]!;

  // Add headers
  final headers = ['Course Code', 'Date', 'Session', 'Time', 'Duration'];
  for (var i = 0; i < headers.length; i++) {
    final cell =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
    cell.value = TextCellValue(headers[i]);
    cell.cellStyle = CellStyle(bold: true);
  }

  // Add sample data with actual course codes and durations
  final sampleData = [
    [
      'DPCS101',
      '2024-02-01',
      'MORNING',
      '09:00:00',
      '150'
    ], // Introduction to Programming
    [
      'DPCS102',
      '2024-02-01',
      'AFTERNOON',
      '14:00:00',
      '150'
    ], // Data Structures
    [
      'DPCS103',
      '2024-02-02',
      'MORNING',
      '09:00:00',
      '120'
    ], // Operating Systems
    [
      'DPCS104',
      '2024-02-02',
      'AFTERNOON',
      '14:00:00',
      '120'
    ], // Database Systems
    [
      'DPCE101',
      '2024-02-05',
      'MORNING',
      '09:00:00',
      '150'
    ], // Structural Mechanics
    ['DPCE102', '2024-02-05', 'AFTERNOON', '14:00:00', '120'], // Hydraulics
  ];

  for (var i = 0; i < sampleData.length; i++) {
    for (var j = 0; j < sampleData[i].length; j++) {
      final cell = sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: j, rowIndex: i + 1));
      cell.value = TextCellValue(sampleData[i][j]);
    }
  }

  // Auto-fit columns
  for (var i = 0; i < headers.length; i++) {
    sheet.setColumnWidth(i, 15.0);
  }

  // Save the file
  final bytes = excel.encode()!;
  File('sample_exam_schedule.xlsx').writeAsBytesSync(bytes);
  print('Sample Excel file created: sample_exam_schedule.xlsx');
}
