# ROOT_MAP.md — Структура проекта Huawei Modem Manager

## Обзор репозитория
- `AGENTS.md` — главные правила разработки, архитектура и регламент работы ИИ-агентов.
- `ROOT_MAP.md` — навигационная карта верхнего уровня.
- `MAP.md` — детальная карта текущего пакета `huawei_modem_manager`.
- `HANDOFF.yaml` — актуальное состояние задачи, список изменений и следующий шаг.
- `pubspec.yaml` — манифест Flutter-пакета и зависимости (`provider`, `serial_port_win32`, `sqflite_common_ffi`, `excel`, `ffi`, `window_manager`, `tray_manager`).
- `analysis_options.yaml` — правила статического анализа (`flutter_lints`, `avoid_print`, `prefer_final_locals`).
- `README.md` — пользовательская документация, инструкция по сборке и настройке Huawei E173.
- `lib/` — исходный код приложения (контроллер, модели, экраны, сервисы).
- `test/` — модульные тесты (`sms_pdu_test.dart`, `modem_port_priority_test.dart`, `scenario_test.dart`).
- `assets/` — ресурсы приложения (`app_icon.ico`).
- `tool/` — вспомогательные скрипты сборки (`create_windows_runner.ps1`).
- `.github/workflows/` — пайплайны GitHub Actions (`pr-checks.yml`, `windows-build.yml`, `main-validation.yml`).
