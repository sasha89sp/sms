import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Расположение данных программы.
///
/// Программа портативная: база, настройки и Excel-файл лежат в папке
/// `UserData` рядом с exe. Если рядом с exe писать нельзя (например,
/// Program Files), используется папка профиля пользователя.
class AppPaths {
  AppPaths._(this.dataDir, this.portable);

  final String dataDir;
  final bool portable;

  static AppPaths? _instance;
  static AppPaths get instance {
    final value = _instance;
    if (value == null) {
      throw StateError('AppPaths.init() не был вызван.');
    }
    return value;
  }

  String get dbFile => p.join(dataDir, 'huawei_modem_manager.db');
  String get settingsFile => p.join(dataDir, 'settings.json');
  String get excelDir => p.join(dataDir, 'Excel');
  String get excelFile => p.join(excelDir, 'scenario_results.xlsx');
  String get exportDir => p.join(dataDir, 'Export');
  String get soundsDir => p.join(dataDir, 'Sounds');

  static Future<AppPaths> init() async {
    final existing = _instance;
    if (existing != null) return existing;

    AppPaths? result;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final candidate = Directory(p.join(exeDir, 'UserData'));
      await candidate.create(recursive: true);
      final probe = File(p.join(candidate.path, '.write_test'));
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      result = AppPaths._(candidate.path, true);
    } catch (_) {
      result = null;
    }
    if (result == null) {
      final support = await getApplicationSupportDirectory();
      await support.create(recursive: true);
      result = AppPaths._(support.path, false);
    }
    for (final dir in [result.excelDir, result.exportDir, result.soundsDir]) {
      await Directory(dir).create(recursive: true);
    }
    _instance = result;
    return result;
  }
}
