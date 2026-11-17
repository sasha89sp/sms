import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;

import '../models/scenario.dart';

/// Строит xlsx-файл со всеми запусками сценариев.
///
/// Файл всегда пересобирается из базы данных, поэтому каждый запуск
/// сценария — это новая строка, а старые строки не теряются.
class ExcelExporter {
  static const _sameColor = '#FFC7CE'; // красный — баланс совпал
  static const _changedColor = '#C6EFCE'; // зелёный — баланс не совпал
  static const _headerColor = '#246BCE';

  /// Имя листа: сценарий (до 31 символа, без запрещённых символов).
  static String sheetName(String scenarioName, int variant) {
    var name = scenarioName.replaceAll(RegExp(r'[\\/*?:\[\]]'), ' ').trim();
    if (name.isEmpty) name = 'Сценарий';
    final suffix = variant > 1 ? ' v$variant' : '';
    final maxBase = 31 - suffix.length;
    if (name.length > maxBase) name = name.substring(0, maxBase);
    return '$name$suffix';
  }

  /// Записывает файл [path]. Возвращает фактический путь (если основной файл
  /// занят Excel, пишется резервный файл рядом).
  static Future<String> write({
    required String path,
    required List<RunRow> rows,
    required bool includeDate,
  }) async {
    final excel = Excel.createExcel();

    // Группировка: один лист на (сценарий + набор столбцов).
    final groups = <String, List<RunRow>>{};
    final order = <String>[];
    final variantsByName = <String, List<String>>{};
    for (final row in rows) {
      final signature = row.columns.join('\u0001');
      final variants = variantsByName.putIfAbsent(row.scenarioName, () => []);
      if (!variants.contains(signature)) variants.add(signature);
      final variant = variants.indexOf(signature) + 1;
      final key = sheetName(row.scenarioName, variant);
      if (!groups.containsKey(key)) {
        groups[key] = [];
        order.add(key);
      }
      groups[key]!.add(row);
    }

    if (order.isEmpty) {
      excel.rename('Sheet1', 'Результаты');
    }

    var first = true;
    for (final key in order) {
      if (first) {
        excel.rename('Sheet1', key);
        first = false;
      }
      final sheet = excel[key];
      final items = groups[key]!;
      final columns = items.first.columns;

      final headers = <CellValue?>[
        if (includeDate) TextCellValue('Дата и время'),
        ...columns.map<CellValue?>((name) => TextCellValue(name)),
      ];
      sheet.appendRow(headers);
      for (var c = 0; c < headers.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
            .cellStyle = CellStyle(
          bold: true,
          fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
          backgroundColorHex: ExcelColor.fromHexString(_headerColor),
        );
        sheet.setColumnWidth(c, c == 0 && includeDate ? 20.0 : 22.0);
      }

      for (var r = 0; r < items.length; r++) {
        final item = items[r];
        final values = <CellValue?>[
          if (includeDate) TextCellValue(_formatDate(item.startedAt)),
          ...item.cells.map<CellValue?>((cell) => cell.number != null
              ? DoubleCellValue(cell.number!)
              : TextCellValue(cell.text)),
        ];
        sheet.appendRow(values);

        // Подсветка столбца «Сверка баланса».
        final statusColumn = columns.indexOf('Сверка баланса');
        if (statusColumn >= 0) {
          final colorHex = item.balanceStatus == 'СОВПАЛ'
              ? _sameColor
              : item.balanceStatus == 'НЕ СОВПАЛ'
                  ? _changedColor
                  : null;
          if (colorHex != null) {
            sheet
                .cell(CellIndex.indexByColumnRow(
                  columnIndex: statusColumn + (includeDate ? 1 : 0),
                  rowIndex: r + 1,
                ))
                .cellStyle = CellStyle(
              bold: true,
              backgroundColorHex: ExcelColor.fromHexString(colorHex),
            );
          }
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
