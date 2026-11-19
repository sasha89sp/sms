# MAP.md — Карта пакета `huawei_modem_manager`

## Точка входа и управление состоянием
- `lib/main.dart` — инициализация `window_manager` (иконка окна/панели задач `assets/app_icon.ico`), системного трея (`tray_manager`), загрузка `AppController` и запуск `HuaweiModemManagerApp`.
- `lib/app_controller.dart` — центральный `ChangeNotifier`-контроллер: автопоиск и переподключение USB-модема, таймеры опроса (`_fastTick` 1 с, `_slowTick` 3 с), выполнение сценариев (включая кэширование USSD-ответов в рамках прогона), серия USSD, синхронизация SMS, управление голосовыми вызовами и записью фраз, экспорт в Excel и CSV.

## Модели данных (`lib/models/`)
- `lib/models/app_settings.dart` — настройки приложения (`AppSettings`), сериализация в JSON.
- `lib/models/modem_info.dart` — информация о модеме (`ModemInfo`) и приоритеты COM-портов (`ModemPortInfo`, приоритет `3G PC UI Interface`).
- `lib/models/scenario.dart` — конструктор сценариев (`Scenario`, `ScenarioStep`, `StepType`, `CallAction`, `RunRow`, `CellData`, `LiveStep`).
- `lib/models/excel_fields.dart` — идентификаторы, порядок и заголовки столбцов отчёта Excel (`ExcelFields`).
- `lib/models/call_info.dart` — разбор `AT+CLCC` (`CallLine`) и фазы звонка (`CallPhase`).
- `lib/models/sms_item.dart` — базовая модель SMS-элемента (`SmsItem`).
- `lib/models/operation_record.dart` — запись истории выполнения операций для SQLite (`OperationRecord`).

## Сервисы (`lib/services/`)
- `lib/services/modem_service.dart` — работа с COM-портом через `serial_port_win32`, AT-команды, USSD, отправка/чтение SMS в PDU, контакты SIM, вызовы, отслеживание URC (`+CMTI`, `RING`, `^CEND`).
- `lib/services/sms_pdu.dart` — кодирование (`SmsPduEncoder`, UCS-2 с разбиением на сегменты) и декодирование/склейка (`SmsPduDecoder`) SMS PDU.
- `lib/services/ussd_codec.dart` — декодирование ответов `+CUSD` (plain, UCS-2 hex, packed 7-bit GSM hex), извлечение номера телефона и баланса.
- `lib/services/voice_bridge.dart` — голосовой мост PCM 8 кГц / 16 бит / моно между звуковым COM-портом модема и аудиоустройствами ПК, конвертация WAV (`WavLoader`).
- `lib/services/winmm_audio.dart` — FFI-обёртка над `winmm.dll` (`WaveOutPlayer`, `WaveInRecorder`, мелодия уведомления об SMS с регулировкой громкости).
- `lib/services/app_database.dart` — локальная БД SQLite (`sqflite_common_ffi`): таблицы `operations`, `logs`, `scenario_runs`, `sims`, `sms_store`.
- `lib/services/app_paths.dart` — портативные пути хранения данных (`UserData/` рядом с `.exe` с fallback в `ApplicationSupportDirectory`).
- `lib/services/settings_store.dart` — атомарное сохранение `settings.json`.
- `lib/services/excel_exporter.dart` — генерация `.xlsx` отчёта (лист «Результаты», цветовая подсветка сверки баланса, резервное сохранение при блокировке файла).

## Экранные формы (`lib/screens/`)
- `lib/screens/home_shell.dart` — боковая навигация и верхняя панель статуса подключения.
- `lib/screens/pages.dart` — общие UI-компоненты и страницы: `DashboardPage` (Подключение), `ContactsPage` (Контакты SIM), `StatisticsPage` (Статистика), `LogsPage` (Журнал), `AtTerminalPage` (AT-терминал).
- `lib/screens/scenario_page.dart` — конструктор сценариев (`ScenariosPage`), ход выполнения и настройка столбцов Excel.
- `lib/screens/sms_page.dart` — входящие/отправленные/корзина SMS (`SmsPage`) с выборочным/массовым выделением и действиями, а также диагностика `AT+CNMI`.
- `lib/screens/calls_page.dart` — голосовые вызовы (`CallsPage`), DTMF-клавиатура, выбор звукового порта и запись фраз.
- `lib/screens/ussd_page.dart` — ручные USSD-запросы, сохранённые команды и пакетная серия (`UssdPage`).
- `lib/screens/settings_page.dart` — настройки портов, таймаутов, SMS и сворачивания в трей (`SettingsPage`).

## Тесты и сборка
- `test/sms_pdu_test.dart` — тесты кодирования PDU и USSD-кодека.
- `test/modem_port_priority_test.dart` — тесты приоритета `PC UI Interface`.
- `test/scenario_test.dart` — тесты декодирования/склейки PDU, извлечения баланса, конструктора сценариев и Excel-раскладки.
- `tool/create_windows_runner.ps1` — генерация каталога `windows/` для сборки под Windows.
