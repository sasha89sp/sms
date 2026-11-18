import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;

import '../models/excel_fields.dart';
import '../models/scenario.dart';

/// Строит xlsx-файл со всеми запусками сценариев.
///
/// Всегда ОДИН лист «Результаты». Файл пересобирается из базы, поэтому
/// каждый запуск — новая строка, а набор и порядок столбцов можно менять
/// задним числом.
class ExcelExporter {
  static const sheetTitle = 'Результаты';
  static const _sameColor = '#FFC7CE'; // красный — баланс совпал
  static const _changedColor = '#C6EFCE'; // зелёный — баланс не совпал
  static const _headerColor = '#246BCE';

  /// Максимальный номер шага среди строк.
  static int maxStep(List<RunRow> rows) {
    var max = 0;
    for (final row in rows) {
      for (final key in row.fields.keys) {
        if (ExcelFields.isStep(key)) {
          final n = ExcelFields.stepNumber(key);
          if (n > max) max = n;
        }
      }
    }
    return max;
  }

  /// Итоговый список столбцов.
  static List<String> columns(List<String> selected, List<RunRow> rows) =>
      ExcelFields.resolve(selected, maxStep(rows));

  /// Заголовок столбца.
  static String header(String id, List<RunRow> rows) {
    if (!ExcelFields.isStep(id)) return ExcelFields.title(id);
    final number = ExcelFields.stepNumber(id);
    final names = <String>{};
    for (final row in rows) {
      final name = row.fields[ExcelFields.stepNameId(number)]?.text;
      if (name != null && name.isNotEmpty) names.add(name);
    }
    return names.length == 1
        ? 'Шаг $number — ${names.first}'
        : 'Шаг $number';
  }

  /// Значение ячейки для поля [id].
  static CellValue? value(RunRow row, String id) {
    switch (id) {
      case ExcelFields.date:
        return TextCellValue(_formatDate(row.startedAt));
      case ExcelFields.scenario:
        return TextCellValue(row.scenarioName);
      case ExcelFields.success:
        return TextCellValue(row.success ? 'Да' : 'Нет');
      case ExcelFields.balanceStatus:
        final cell = row.fields[id];
        return TextCellValue(cell?.text ?? row.balanceStatus);
    }
    final cell = row.fields[id];
    if (cell == null) return null;
    return cell.number != null
        ? DoubleCellValue(cell.number!)
        : TextCellValue(cell.text);
  }

  /// Записывает файл [path]. Возвращает фактический путь (если основной файл
  /// занят Excel, пишется резервный файл рядом).
  static Future<String> write({
    required String path,
    required List<RunRow> rows,
    required List<String> selectedColumns,
  }) async {
    final excel = Excel.createExcel();
    excel.rename('Sheet1', sheetTitle);
    final sheet = excel[sheetTitle];

    final ids = columns(selectedColumns, rows);
    sheet.appendRow(
        ids.map<CellValue?>((id) => TextCellValue(header(id, rows))).toList());
    for (var c = 0; c < ids.length; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
          .cellStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        backgroundColorHex: ExcelColor.fromHexString(_headerColor),
      );
      sheet.setColumnWidth(c, ids[c] == ExcelFields.date ? 20.0 : 22.0);
    }

    final statusColumn = ids.indexOf(ExcelFields.balanceStatus);
    for (var r = 0; r < rows.length; r++) {
      final item = rows[r];
      sheet.appendRow(ids.map<CellValue?>((id) => value(item, id)).toList());
      if (statusColumn >= 0) {
        final colorHex = item.balanceStatus == 'СОВПАЛ'
            ? _sameColor
            : item.balanceStatus == 'НЕ СОВПАЛ'
                ? _changedColor
                : null;
        if (colorHex != null) {
          sheet
              .cell(CellIndex.indexByColumnRow(
                  columnIndex: statusColumn, rowIndex: r + 1))
              .cellStyle = CellStyle(
            bold: true,
            backgroundColorHex: ExcelColor.fromHexString(colorHex),
          );
        }
      }
    }

    final bytes = excel.save();
    if (bytes == null) throw StateError('Не удалось сформировать Excel-файл.');

    try {
      await File(path).writeAsBytes(bytes, flush: true);
      return path;
    } on FileSystemException {
      // Файл открыт в Excel — пишем резервную копию рядом.
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[^0-9]'), '')
          .substring(0, 14);
      final backup = p.join(
        p.dirname(path),
        '${p.basenameWithoutExtension(path)}_backup_$stamp.xlsx',
      );
      await File(backup).writeAsBytes(bytes, flush: true);
      return backup;
    }
  }

  static String _formatDate(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}.${two(value.month)}.${value.year} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }
}
