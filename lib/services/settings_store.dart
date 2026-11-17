import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';
import 'app_paths.dart';

/// Настройки хранятся в settings.json рядом с программой (портативно).
class SettingsStore {
  File get _file => File(AppPaths.instance.settingsFile);

  Future<AppSettings> load() async {
    try {
      final file = _file;
      if (!await file.exists()) return const AppSettings();
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const AppSettings();
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    final file = _file;
    final temp = File('${file.path}.tmp');
    const encoder = JsonEncoder.withIndent('  ');
    await temp.writeAsString(encoder.convert(settings.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }
}
