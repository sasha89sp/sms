import 'dart:async';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models/app_settings.dart';
import 'models/modem_info.dart';
import 'models/operation_record.dart';
import 'models/sms_item.dart';
import 'services/app_database.dart';
import 'services/modem_service.dart';
import 'services/settings_store.dart';
import 'services/ussd_codec.dart';

class AppController extends ChangeNotifier {
  AppController._({
    required this.database,
    required this.settingsStore,
    required this.modem,
    required this.settings,
  });

  final AppDatabase database;
  final SettingsStore settingsStore;
  final ModemService modem;

  AppSettings settings;
  List<ModemPortInfo> availablePorts = [];
  ModemInfo modemInfo = const ModemInfo();
  List<Map<String, Object?>> operations = [];
  List<Map<String, Object?>> logs = [];
  List<SmsItem> messages = [];

  bool isScanning = false;
  bool isRunning = false;
  bool isLoadingMessages = false;
  bool isLoadingContacts = false;
  bool autoModeWaiting = false;
  String connectionMessage = 'Ожидание USB-модема';
  String currentStep = 'Ожидание';
  String lastUssdResponse = '';
  String contactsRaw = '';
  String callsRaw = '';
  String terminalOutput = '';
  String lastExportPath = '';
  final Map<String, String> scenarioResults = {
    'Номер': 'Ожидает выполнения',
    'Баланс до SMS': 'Ожидает выполнения',
    'Отправка SMS': 'Ожидает выполнения',
    'Баланс после SMS': 'Ожидает выполнения',
  };

  Timer? _pollTimer;
  bool _polling = false;
  bool _autoStartedForConnection = false;
  bool _disposed = false;
  DateTime? _lastStatusUpdate;

  static Future<AppController> create() async {
    final database = await AppDatabase.open();
    final store = SettingsStore();
    final settings = await store.load();
    final controller = AppController._(
      database: database,
      settingsStore: store,
      modem: ModemService(),
      settings: settings,
    );
    await controller.loadHistory();
    await controller.refreshPorts();
    controller._startPolling();
    return controller;
  }

  bool get isConnected => modem.isConnected;
  String get activePort => modem.connectedPort ?? settings.preferredPort;

  List<String> get configurationProblems {
    final problems = <String>[];
    if (settings.numberUssd.trim().isEmpty) {
      problems.add('Не задан USSD-код определения номера.');
    }
    if (settings.balanceUssd.trim().isEmpty) {
      problems.add('Не задан USSD-код проверки баланса.');
    }
    if (settings.smsRecipient.trim().isEmpty) {
      problems.add('Не задан номер получателя SMS.');
    }
    if (settings.smsText.trim().isEmpty) {
      problems.add('Не задан текст SMS.');
    }
    return problems;
  }

  Future<void> updateSettings(AppSettings value) async {
    final previousProblems = configurationProblems;
    settings = value;
    await settingsStore.save(value);
    if (settings.autoStart && previousProblems.isNotEmpty && configurationProblems.isEmpty) {
      _autoStartedForConnection = false;
    }
    _log('INFO', 'Настройки сохранены');
    notifyListeners();
  }

  Future<void> refreshModemStatus() async {
    if (!isConnected) throw StateError('Модем не подключён.');
    modemInfo = await modem.readModemInfo();
    connectionMessage = 'Подключён ${modemInfo.port}';
    _lastStatusUpdate = DateTime.now();
    notifyListeners();
  }

  Future<void> loadHistory() async {
    operations = await database.recentOperations();
    logs = await database.recentLogs();
    notifyListeners();
  }

  Future<void> refreshPorts() async {
    try {
      availablePorts = modem.listPorts();
      if (availablePorts.isEmpty && !isConnected) {
        connectionMessage = 'COM-порты не найдены';
      }
    } catch (error) {
      connectionMessage = 'Ошибка поиска портов: $error';
    }
    notifyListeners();
  }

  Future<void> connect({String? portName}) async {
    if (isScanning) return;
    isScanning = true;
    connectionMessage = 'Проверка COM-портов…';
    notifyListeners();
    try {
      bool connected;
      if (portName != null && portName.isNotEmpty) {
        connected = await modem.connectToPort(
          portName,
          baudRate: settings.baudRate,
          verifyHuawei: false,
        );
      } else {
        final found = await modem.autoConnect(
          baudRate: settings.baudRate,
          preferredPort: settings.preferredPort,
        );
        connected = found != null;
      }
      if (!connected) {
        connectionMessage = 'Huawei-модем не найден на доступных COM-портах. Проверьте USB и драйвер.';
        return;
      }
      final info = await modem.readModemInfo();
      modemInfo = info;
      settings = settings.copyWith(preferredPort: info.port);
      await settingsStore.save(settings);
      connectionMessage = 'Подключён ${info.port}';
      _autoStartedForConnection = false;
      _log('SUCCESS', 'Модем обнаружен на ${info.port}', raw: info.model);
      await refreshPorts();
      if (settings.autoStart && await modem.isNetworkRegistered()) {
        _startAutoScenario();
      }
    } catch (error) {
      connectionMessage = 'Ошибка подключения: $error';
      _log('ERROR', connectionMessage);
      await modem.disconnect();
    } finally {
      isScanning = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await modem.disconnect();
    modemInfo = const ModemInfo();
    connectionMessage = 'Модем отключён';
    currentStep = 'Ожидание';
    _autoStartedForConnection = false;
    _log('INFO', 'Соединение с модемом закрыто');
    notifyListeners();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_disposed || _polling) return;
      unawaited(_pollDevice());
    });
  }

  Future<void> _pollDevice() async {
    _polling = true;
    try {
      // Never issue background AT commands while the scenario owns the modem.
      if (isRunning || isScanning || modem.isBusy) return;
      if (!isConnected) {
        availablePorts = modem.listPorts();
        if (settings.autoConnect && availablePorts.isNotEmpty) {
          await connect();
        } else {
          if (availablePorts.isEmpty) connectionMessage = 'Ожидание USB-модема';
          notifyListeners();
        }
        return;
      }
      final now = DateTime.now();
      if (_lastStatusUpdate == null ||
          now.difference(_lastStatusUpdate!) >= const Duration(seconds: 15)) {
        _lastStatusUpdate = now;
        modemInfo = await modem.readModemInfo();
        connectionMessage = 'Подключён ${modemInfo.port}';
        notifyListeners();
      }
      final registered = modemInfo.registration == 'Зарегистрирован в сети';
      if (!registered) {
        _autoStartedForConnection = false;
        autoModeWaiting = settings.autoStart;
        notifyListeners();
      } else if (settings.autoStart && !_autoStartedForConnection && !isRunning) {
        _startAutoScenario();
      }
    } catch (error) {
      connectionMessage = 'Связь с модемом потеряна: $error';
      _log('ERROR', connectionMessage);
      await modem.disconnect();
      modemInfo = const ModemInfo();
      notifyListeners();
    } finally {
      _polling = false;
    }
  }

  void _startAutoScenario() {
    if (_autoStartedForConnection || isRunning) return;
    _autoStartedForConnection = true;
    autoModeWaiting = false;
    _log('INFO', 'Сеть обнаружена. Автоматический запуск сценария.');
    unawaited(runScenario(automatic: true).catchError((Object error) {
      currentStep = 'Автозапуск не выполнен: $error';
      _log('ERROR', 'Автоматический сценарий не запущен', raw: '$error');
      notifyListeners();
    }));
  }

  Future<void> runScenario({bool automatic = false}) async {
    if (isRunning) return;
    if (!isConnected) {
      _log('ERROR', 'Сценарий не запущен: модем не подключён');
      throw StateError('Сначала подключите Huawei E173.');
    }
    final problems = configurationProblems;
    if (problems.isNotEmpty) {
      _log('ERROR', 'Не заполнены настройки сценария: ${problems.join(' ')}');
      throw StateError(problems.join('\n'));
    }

    isRunning = true;
    if (settings.autoStart) _autoStartedForConnection = true;
    autoModeWaiting = false;
    currentStep = automatic ? 'Автоматический запуск' : 'Ручной запуск';
    final startedAt = DateTime.now();
    final errors = <String>[];
    var phoneResponse = '';
    var balanceBefore = '';
    var smsStatus = '';
    var balanceAfter = '';
    var phoneOk = false;
    var beforeOk = false;
    var smsOk = false;
    var afterOk = false;
    for (final key in scenarioResults.keys.toList()) {
      scenarioResults[key] = 'Ожидает выполнения';
    }
    notifyListeners();

    try {
      currentStep = 'Ожидание регистрации в сети';
      notifyListeners();
      final networkReady = modemInfo.registration == 'Зарегистрирован в сети' ||
          await modem.waitForNetwork(
            timeout: Duration(seconds: settings.networkWaitSeconds),
            onProgress: (message) {
              currentStep = message;
              notifyListeners();
            },
          );
      if (!networkReady) {
        errors.add('Не удалось зарегистрироваться в сети за '
            '${settings.networkWaitSeconds} секунд.');
        for (final key in scenarioResults.keys.toList()) {
          scenarioResults[key] = 'Пропущено: нет сети';
        }
        return;
      }

      currentStep = '1/4 — Запрос номера';
      scenarioResults['Номер'] = 'Выполняется…';
      notifyListeners();
      try {
        phoneResponse = await _ussdWithRetry(settings.numberUssd);
        final extracted = UssdCodec.extractPhoneNumber(phoneResponse);
        scenarioResults['Номер'] = extracted.isNotEmpty
            ? extracted
            : phoneResponse;
        phoneOk = extracted.isNotEmpty;
        if (!phoneOk) errors.add('Ответ получен, но номер телефона не удалось распознать: $phoneResponse');
        _log('SUCCESS', 'Запрос номера выполнен', raw: phoneResponse);
      } catch (error) {
        scenarioResults['Номер'] = 'ОШИБКА: $error';
        errors.add('Запрос номера: $error');
        _log('ERROR', 'Не удалось получить номер', raw: '$error');
      }

      currentStep = '2/4 — Проверка начального баланса';
      scenarioResults['Баланс до SMS'] = 'Выполняется…';
      notifyListeners();
      try {
        balanceBefore = await _ussdWithRetry(settings.balanceUssd);
        scenarioResults['Баланс до SMS'] = balanceBefore;
        beforeOk = balanceBefore.trim().isNotEmpty;
        if (!beforeOk) errors.add('Пустой ответ при первой проверке баланса.');
        _log('SUCCESS', 'Начальный баланс получен', raw: balanceBefore);
      } catch (error) {
        scenarioResults['Баланс до SMS'] = 'ОШИБКА: $error';
        errors.add('Начальный баланс: $error');
        _log('ERROR', 'Ошибка первой проверки баланса', raw: '$error');
      }

      currentStep = '3/4 — Отправка SMS';
      scenarioResults['Отправка SMS'] = 'Выполняется…';
      notifyListeners();
      try {
        final response = await modem.sendSms(
          recipient: settings.smsRecipient,
          message: settings.smsText,
          requestStatusReport: settings.smsRequireNetworkAck,
        );
        smsStatus = 'Принято модемом; доставка адресату не подтверждена';
        scenarioResults['Отправка SMS'] = smsStatus;
        smsOk = response.toUpperCase().contains('+CMGS:');
        _log('SUCCESS', 'SMS принята модемом', raw: response);
      } catch (error) {
        smsStatus = 'НЕ ОТПРАВЛЕНО: $error';
        scenarioResults['Отправка SMS'] = smsStatus;
        errors.add('Отправка SMS: $error');
        _log('ERROR', 'Ошибка отправки SMS', raw: '$error');
      }

      currentStep = '4/4 — Проверка конечного баланса';
      scenarioResults['Баланс после SMS'] = 'Выполняется…';
      notifyListeners();
      try {
        balanceAfter = await _ussdWithRetry(settings.balanceUssd);
        scenarioResults['Баланс после SMS'] = balanceAfter;
        afterOk = balanceAfter.trim().isNotEmpty;
        if (!afterOk) errors.add('Пустой ответ при повторной проверке баланса.');
        _log('SUCCESS', 'Конечный баланс получен', raw: balanceAfter);
      } catch (error) {
        scenarioResults['Баланс после SMS'] = 'ОШИБКА: $error';
        errors.add('Конечный баланс: $error');
        _log('ERROR', 'Ошибка повторной проверки баланса', raw: '$error');
      }
    } finally {
      final finishedAt = DateTime.now();
      final success = phoneOk && beforeOk && smsOk && afterOk;
      final details = errors.isEmpty ? 'Все этапы выполнены.' : errors.join('\n');
      final record = OperationRecord(
        startedAt: startedAt,
        finishedAt: finishedAt,
        phoneResponse: phoneResponse,
        balanceBefore: balanceBefore,
        smsStatus: smsStatus,
        balanceAfter: balanceAfter,
        success: success,
        details: details,
      );
      await database.insertOperation(record);
      operations = await database.recentOperations();
      isRunning = false;
      currentStep = success ? 'Операция завершена успешно' : 'Операция завершена с ошибками';
      _log(
        success ? 'SUCCESS' : 'WARN',
        success ? 'Сценарий завершён успешно' : 'Сценарий завершён с ошибками',
        raw: details,
      );
      await loadHistory();
      notifyListeners();
    }
  }

  Future<String> _ussdWithRetry(String code) async {
    Object? lastError;
    for (var attempt = 0; attempt <= settings.retryCount; attempt++) {
      try {
        return await modem.sendUssd(
          code,
          dcs: settings.ussdDcs,
          timeout: Duration(seconds: settings.ussdTimeoutSeconds),
        );
      } catch (error) {
        lastError = error;
        if (attempt < settings.retryCount) {
          _log('WARN', 'Повтор USSD-запроса (${attempt + 1})', raw: '$error');
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    }
    throw StateError('$lastError');
  }

  Future<String> runUssdManually(String code) async {
    final response = await modem.sendUssd(
      code,
      dcs: settings.ussdDcs,
      timeout: Duration(seconds: settings.ussdTimeoutSeconds),
    );
    lastUssdResponse = response;
    _log('INFO', 'Ручной USSD-запрос: $code', raw: response);
    notifyListeners();
    return response;
  }

  Future<String> sendSmsManually(String recipient, String text) async {
    final response = await modem.sendSms(
      recipient: recipient,
      message: text,
      requestStatusReport: settings.smsRequireNetworkAck,
    );
    _log('SUCCESS', 'SMS передана модему: $recipient', raw: response);
    return response;
  }

  Future<void> refreshMessages() async {
    if (!isConnected) throw StateError('Подключите модем.');
    isLoadingMessages = true;
    notifyListeners();
    try {
      messages = await modem.readSms();
      _log('INFO', 'Список SMS обновлён: ${messages.length}');
    } finally {
      isLoadingMessages = false;
      notifyListeners();
    }
  }

  Future<void> deleteMessage(int index) async {
    final response = await modem.deleteSms(index);
    _log('INFO', 'Удаление SMS #$index', raw: response);
    await refreshMessages();
  }

  Future<void> refreshContacts() async {
    if (!isConnected) throw StateError('Подключите модем.');
    isLoadingContacts = true;
    notifyListeners();
    try {
      contactsRaw = await modem.readContacts();
      _log('INFO', 'Телефонная книга SIM прочитана');
    } finally {
      isLoadingContacts = false;
      notifyListeners();
    }
  }

  Future<void> writeContact({
    required int index,
    required String number,
    required String name,
  }) async {
    final response = await modem.writeContact(
      index: index,
      number: number,
      name: name,
    );
    _log('SUCCESS', 'Контакт записан в ячейку SIM $index', raw: response);
  }

  Future<void> deleteContact(int index) async {
    final response = await modem.deleteContact(index);
    _log('INFO', 'Контакт удалён из ячейки SIM $index', raw: response);
  }

  Future<void> refreshCalls() async {
    callsRaw = await modem.listCalls();
    _log('INFO', 'Журнал активных вызовов обновлён', raw: callsRaw);
    notifyListeners();
  }

  Future<void> dial(String number) async {
    final result = await modem.dial(number);
    _log('INFO', 'Команда набора номера: $number', raw: result);
    callsRaw = result;
    notifyListeners();
  }

  Future<void> hangUp() async {
    final result = await modem.hangUp();
    _log('INFO', 'Команда завершения вызова', raw: result);
    callsRaw = result;
    notifyListeners();
  }

  Future<void> executeTerminalCommand(String command) async {
    if (command.trim().isEmpty) return;
    final response = await modem.sendAt(command.trim());
    terminalOutput = '${DateTime.now().toLocal()}  > ${command.trim()}\n'
        '$response\n\n$terminalOutput';
    _log('AT', command.trim(), raw: response);
    notifyListeners();
  }

  void clearTerminal() {
    terminalOutput = '';
    notifyListeners();
  }

  Future<String> exportOperationsCsv() async {
    final rows = <List<dynamic>>[
      [
        'Начало',
        'Окончание',
        'Ответ номера',
        'Баланс до SMS',
        'Статус SMS',
        'Баланс после SMS',
        'Успех',
        'Детали',
      ],
      ...operations.map((row) => [
            row['started_at'] ?? '',
            row['finished_at'] ?? '',
            row['phone_response'] ?? '',
            row['balance_before'] ?? '',
            row['sms_status'] ?? '',
            row['balance_after'] ?? '',
            row['success'] == 1 ? 'Да' : 'Нет',
            row['details'] ?? '',
          ]),
    ];
    final csvText = const ListToCsvConverter(fieldDelimiter: ';').convert(rows);
    final documents = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(documents.path, 'HuaweiModemManager'));
    await folder.create(recursive: true);
    final file = File(p.join(folder.path,
        'operations_${DateTime.now().millisecondsSinceEpoch}.csv'));
    await file.writeAsString('\uFEFF$csvText', flush: true);
    lastExportPath = file.path;
    _log('SUCCESS', 'Экспорт завершён', raw: file.path);
    notifyListeners();
    return file.path;
  }

  Future<void> _log(String level, String message, {String raw = ''}) async {
    final now = DateTime.now();
    await database.insertLog(
      at: now,
      level: level,
      message: message,
      raw: raw,
    );
    logs = await database.recentLogs();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    unawaited(modem.disconnect());
    unawaited(database.close());
    super.dispose();
  }
}
