import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'models/app_settings.dart';
import 'models/call_info.dart';
import 'models/excel_fields.dart';
import 'models/modem_info.dart';
import 'models/operation_record.dart';
import 'models/scenario.dart';
import 'services/app_database.dart';
import 'services/app_paths.dart';
import 'services/excel_exporter.dart';
import 'services/modem_service.dart';
import 'services/settings_store.dart';
import 'services/sms_pdu.dart';
import 'services/ussd_codec.dart';
import 'services/voice_bridge.dart';
import 'services/winmm_audio.dart';

/// Результат выполнения одного шага.
class StepOutcome {
  const StepOutcome(this.text, {this.number, this.ok = true});
  final String text;
  final double? number;
  final bool ok;
}

/// Элемент серии USSD-команд.
class BatchItem {
  const BatchItem(this.code, this.delaySeconds);
  final String code;
  final int delaySeconds;
}

class _RunContext {
  double? lastBalance;
  String ownNumber = '';
  final Map<String, String> ussdResponses = {};
}

class AppController extends ChangeNotifier {
  AppController._({
    required this.paths,
    required this.database,
    required this.settingsStore,
    required this.modem,
    required this.settings,
  });

  final AppPaths paths;
  final AppDatabase database;
  final SettingsStore settingsStore;
  final ModemService modem;

  AppSettings settings;
  List<ModemPortInfo> availablePorts = [];
  ModemInfo modemInfo = const ModemInfo();
  List<Map<String, Object?>> operations = [];
  List<Map<String, Object?>> logs = [];

  bool isScanning = false;
  bool isRunning = false;
  bool isLoadingContacts = false;
  bool autoModeWaiting = false;
  String connectionMessage = 'Ожидание USB-модема';
  String currentStep = 'Ожидание';
  String lastUssdResponse = '';
  String contactsRaw = '';
  String callsRaw = '';
  String terminalOutput = '';
  String lastExportPath = '';
  String lastExcelPath = '';
  String excelMessage = '';
  int runCount = 0;

  // SIM и выполнение сценария
  String simId = '';
  String simPhone = '';
  String liveScenarioName = '';
  List<LiveStep> liveSteps = [];
  String balanceStatus = '';
  double? balanceDiff;

  // Серия USSD
  bool isBatchRunning = false;
  List<String> batchLog = [];

  // SMS
  bool isSyncingSms = false;
  int unreadSms = 0;
  Map<String, int> smsCounts = {};
  Map<String, String> simPhones = {};
  List<Map<String, Object?>> smsInbox = [];
  List<Map<String, Object?>> smsSent = [];
  List<Map<String, Object?>> smsTrash = [];

  // Вызовы
  CallPhase callPhase = CallPhase.idle;
  String callNumber = '';
  DateTime? callStartedAt;
  String callStatus = '';
  VoiceBridge? voice;

  // Фразы для звонков
  List<String> phrases = [];
  bool isRecordingPhrase = false;
  int recordedMillis = 0;
  WaveInRecorder? _phraseRecorder;
  Timer? _phraseTimer;
  final BytesBuilder _phraseBuffer = BytesBuilder(copy: false);

  Timer? _slowTimer;
  Timer? _fastTimer;
  bool _slowBusy = false;
  bool _fastBusy = false;
  bool _autoStartedForConnection = false;
  bool _abortRun = false;
  bool _abortBatch = false;
  bool _disposed = false;
  int _operatorWaitTicks = 0;
  int _noCallPolls = 0;
  DateTime? _lastStatusUpdate;
  DateTime? _lastSmsSync;
  String _seenSignature = '';
  String _failedSignature = '';
  DateTime? _lastFailedAt;

  static Future<AppController> create() async {
    final paths = await AppPaths.init();
    final database = await AppDatabase.open();
    final store = SettingsStore();
    var settings = await store.load();
    final prepared = _withDefaultScenario(settings);
    if (!identical(prepared, settings)) {
      settings = prepared;
      await store.save(settings);
    }
    final controller = AppController._(
      paths: paths,
      database: database,
      settingsStore: store,
      modem: ModemService(),
      settings: settings,
    );
    await controller.loadHistory();
    await controller.reloadSms();
    await controller.loadPhrases();
    await controller.refreshPorts();
    controller._startTimers();
    return controller;
  }

  /// Для старых настроек создаёт сценарий «Основной» из прежних параметров.
  static AppSettings _withDefaultScenario(AppSettings settings) {
    if (settings.scenarios.isNotEmpty) return settings;
    final steps = <ScenarioStep>[
      ScenarioStep(
        id: newId(),
        type: StepType.ownNumber,
        code: settings.numberUssd.trim().isEmpty ? '*161#' : settings.numberUssd.trim(),
      ),
      ScenarioStep(
        id: newId(),
        type: StepType.balance,
        code: settings.balanceUssd.trim().isEmpty ? '*100#' : settings.balanceUssd.trim(),
      ),
      if (settings.smsRecipient.trim().isNotEmpty)
        ScenarioStep(
          id: newId(),
          type: StepType.sms,
          recipient: settings.smsRecipient.trim(),
          text: settings.smsText,
        ),
      ScenarioStep(
        id: newId(),
        type: StepType.balance,
        code: settings.balanceUssd.trim().isEmpty ? '*100#' : settings.balanceUssd.trim(),
      ),
    ];
    return settings.copyWith(scenarios: [
      Scenario(
        id: newId(),
        name: 'Основной',
        steps: steps,
        autoRun: settings.autoStart,
      ),
    ]);
  }

  bool get isConnected => modem.isConnected;
  String get activePort => modem.connectedPort ?? settings.preferredPort;
  bool get isInCall => callPhase != CallPhase.idle;

  // ---------------------------------------------------------------------
  // Настройки, сценарии, сохранённые USSD
  // ---------------------------------------------------------------------

  Future<void> updateSettings(AppSettings value) async {
    settings = value;
    await settingsStore.save(value);
    _log('INFO', 'Настройки сохранены');
    notifyListeners();
  }

  Scenario? scenarioById(String? id) {
    for (final scenario in settings.scenarios) {
      if (scenario.id == id) return scenario;
    }
    return null;
  }

  Future<void> saveScenario(Scenario scenario) async {
    final list = [...settings.scenarios];
    final index = list.indexWhere((item) => item.id == scenario.id);
    if (index >= 0) {
      list[index] = scenario;
    } else {
      list.add(scenario);
    }
    await updateSettings(settings.copyWith(scenarios: list));
  }

  Future<void> deleteScenario(String id) async {
    final list = settings.scenarios.where((item) => item.id != id).toList();
    await updateSettings(settings.copyWith(scenarios: list));
  }

  Future<void> addSavedUssd(String name, String code) async {
    final cleanCode = code.trim();
    if (cleanCode.isEmpty) throw StateError('Введите USSD-код.');
    final cleanName = name.trim().isEmpty ? cleanCode : name.trim();
    final list = settings.savedUssd.where((item) => item.code != cleanCode).toList()
      ..add(SavedUssd(name: cleanName, code: cleanCode));
    await updateSettings(settings.copyWith(savedUssd: list));
  }

  Future<void> removeSavedUssd(String code) async {
    final list = settings.savedUssd.where((item) => item.code != code).toList();
    await updateSettings(settings.copyWith(savedUssd: list));
  }

  /// Проверка сценария перед запуском.
  List<String> validateScenario(Scenario scenario) {
    final problems = <String>[];
    if (scenario.steps.isEmpty) problems.add('В сценарии нет шагов.');
    for (var i = 0; i < scenario.steps.length; i++) {
      final step = scenario.steps[i];
      final label = 'Шаг ${i + 1} (${step.type.title})';
      switch (step.type) {
        case StepType.ownNumber:
        case StepType.ussd:
        case StepType.balance:
          if (step.code.trim().isEmpty) problems.add('$label: не задан USSD-код.');
          break;
        case StepType.sms:
          if (step.recipient.trim().isEmpty) problems.add('$label: не задан номер получателя.');
          if (step.text.trim().isEmpty) problems.add('$label: пустой текст SMS.');
          break;
        case StepType.call:
          if (step.recipient.trim().isEmpty) problems.add('$label: не задан номер для звонка.');
          for (final action in step.actions) {
            if (action.value.trim().isEmpty) {
              problems.add('$label: в действии на ${action.at} с не выбрана фраза/цифры.');
            } else if (action.isPhrase && !phrases.contains(action.value)) {
              problems.add('$label: фраза «${action.value}» не найдена.');
            }
            if (action.at > step.seconds) {
              problems.add('$label: действие на ${action.at} с позже конца разговора (${step.seconds} с).');
            }
          }
          break;
        case StepType.dtmf:
          if (step.digits.trim().isEmpty) problems.add('$label: не заданы цифры.');
          break;
        case StepType.pause:
          break;
      }
    }
    return problems;
  }

  // ---------------------------------------------------------------------
  // Подключение, опрос, извлечение модема
  // ---------------------------------------------------------------------

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
    runCount = await database.runCount();
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
      _operatorWaitTicks = 0;
      _lastSmsSync = null;
      _lastStatusUpdate = DateTime.now();
      _log('SUCCESS', 'Модем обнаружен на ${info.port}', raw: info.model);
      await _afterConnect(info);
      await refreshPorts();
    } catch (error) {
      connectionMessage = 'Ошибка подключения: $error';
      _log('ERROR', connectionMessage);
      await modem.disconnect();
    } finally {
      isScanning = false;
      notifyListeners();
    }
  }

  Future<void> _afterConnect(ModemInfo info) async {
    try {
      simId = await modem.readSimId();
    } catch (_) {
      simId = '';
    }
    try {
      final features = await modem.prepareFeatures();
      _log('INFO', 'Параметры модема настроены', raw: features);
    } catch (error) {
      _log('WARN', 'Не удалось настроить уведомления модема', raw: '$error');
    }
    simPhones = await database.simPhones();
    simPhone = simId.isEmpty ? '' : (simPhones[simId] ?? '');
    if (simId.isNotEmpty) {
      await database.upsertSim(simId: simId, operator: info.operatorName);
    }
  }

  Future<void> disconnect() async {
    await _stopVoice();
    await modem.disconnect();
    _resetConnectionState();
    connectionMessage = 'Модем отключён';
    _log('INFO', 'Соединение с модемом закрыто');
    notifyListeners();
  }

  void _resetConnectionState() {
    modemInfo = const ModemInfo();
    currentStep = 'Ожидание';
    _autoStartedForConnection = false;
    autoModeWaiting = false;
    simId = '';
    simPhone = '';
    _operatorWaitTicks = 0;
    _seenSignature = '';
    _failedSignature = '';
    _lastFailedAt = null;
    callPhase = CallPhase.idle;
    callNumber = '';
    callStartedAt = null;
  }

  /// Модем выдернули из USB: мгновенно освобождаем порт и ждём возвращения.
  void _handleUnplug() {
    if (!isConnected && modem.connectedPort == null) return;
    _log('WARN', 'Модем извлечён из USB');
    _abortRun = true;
    _abortBatch = true;
    modem.forceDisconnect();
    unawaited(_stopVoice());
    _resetConnectionState();
    connectionMessage = 'Модем извлечён. Ожидание USB-модема…';
    notifyListeners();
  }

  void _startTimers() {
    _slowTimer?.cancel();
    _fastTimer?.cancel();
    _slowTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_disposed || _slowBusy) return;
      unawaited(_slowTick());
    });
    _fastTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || _fastBusy) return;
      unawaited(_fastTick());
    });
  }

  /// Быстрый опрос (1 с): наличие порта, звонки, уведомления о SMS.
  Future<void> _fastTick() async {
    _fastBusy = true;
    try {
      if (!isConnected) return;
      if (!modem.isPortPresent()) {
        _handleUnplug();
        return;
      }
      if (isInCall) {
        await _callTick();
        return;
      }
      if (isRunning || isScanning || modem.isBusy || isBatchRunning) return;

      await modem.pollUrc();
      if (modem.isRinging && callPhase == CallPhase.idle) {
        callPhase = CallPhase.incoming;
        callNumber = modem.incomingNumber;
        callStartedAt = null;
        _noCallPolls = 0;
        modem.clearRinging();
        _log('INFO', 'Входящий вызов', raw: callNumber);
        notifyListeners();
        return;
      }

      if (settings.smsAutoReceive && !isSyncingSms) {
        final hint = modem.takeSmsHint();
        final now = DateTime.now();
        final due = settings.smsPollSeconds > 0 &&
            (_lastSmsSync == null ||
                now.difference(_lastSmsSync!) >=
                    Duration(seconds: settings.smsPollSeconds));
        if (hint || due) await syncSms(silent: true);
      }
    } catch (error) {
      if (!isConnected) return;
      if (!modem.isPortPresent()) {
        _handleUnplug();
      }
    } finally {
      _fastBusy = false;
    }
  }

  /// Медленный опрос (3 с): подключение, статус, автозапуск сценария.
  Future<void> _slowTick() async {
    _slowBusy = true;
    try {
      if (isRunning || isScanning || modem.isBusy || isInCall || isBatchRunning) {
        return;
      }
      if (!isConnected) {
        await _tryAutoConnect();
        return;
      }
      final registered = modemInfo.registration == 'Зарегистрирован в сети';
      final now = DateTime.now();
      if (!registered ||
          _lastStatusUpdate == null ||
          now.difference(_lastStatusUpdate!) >= const Duration(seconds: 15)) {
        _lastStatusUpdate = now;
        modemInfo = await modem.readModemInfo();
        connectionMessage = 'Подключён ${modemInfo.port}';
        notifyListeners();
      }
      _maybeAutoRun();
    } catch (error) {
      if (!isConnected) return;
      connectionMessage = 'Связь с модемом потеряна: $error';
      _log('ERROR', connectionMessage);
      modem.forceDisconnect();
      _resetConnectionState();
      notifyListeners();
    } finally {
      _slowBusy = false;
    }
  }

  Future<void> _tryAutoConnect() async {
    final names = modem.quickPortNames();
    if (names.isEmpty) {
      _seenSignature = '';
      if (connectionMessage != 'Ожидание USB-модема') {
        connectionMessage = 'Ожидание USB-модема';
        notifyListeners();
      }
      return;
    }
    if (!settings.autoConnect) return;
    final sorted = [...names]..sort();
    final signature = sorted.join(',');
    final now = DateTime.now();
    if (signature == _failedSignature &&
        _lastFailedAt != null &&
        now.difference(_lastFailedAt!) < const Duration(seconds: 30)) {
      return;
    }
    // Драйвер создаёт COM-порты по очереди — даём набору портов устояться.
    if (signature != _seenSignature) {
      _seenSignature = signature;
      connectionMessage = 'Обнаружено USB-устройство, подключение…';
      notifyListeners();
      return;
    }
    await connect();
    if (!isConnected) {
      _failedSignature = signature;
      _lastFailedAt = DateTime.now();
    }
  }

  // ---------------------------------------------------------------------
  // Автозапуск и выполнение сценария
  // ---------------------------------------------------------------------

  Scenario? pickAutoScenario(String operatorName) {
    final candidates = settings.scenarios
        .where((item) =>
            item.autoRun && item.steps.isNotEmpty && item.matchesOperator(operatorName))
        .toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final aSpecific = a.operator.trim().isNotEmpty ? 1 : 0;
      final bSpecific = b.operator.trim().isNotEmpty ? 1 : 0;
      return bSpecific.compareTo(aSpecific);
    });
    return candidates.first;
  }

  void _maybeAutoRun() {
    if (_autoStartedForConnection || isRunning || !isConnected) return;
    final any = settings.scenarios.any((item) => item.autoRun && item.steps.isNotEmpty);
    if (!any) {
      if (autoModeWaiting) {
        autoModeWaiting = false;
        notifyListeners();
      }
      return;
    }
    final registered = modemInfo.registration == 'Зарегистрирован в сети';
    if (!registered) {
      autoModeWaiting = true;
      notifyListeners();
      return;
    }
    // Название оператора может появиться чуть позже регистрации.
    if (modemInfo.operatorName.isEmpty && _operatorWaitTicks < 3) {
      _operatorWaitTicks++;
      return;
    }
    final pick = pickAutoScenario(modemInfo.operatorName);
    _autoStartedForConnection = true;
    autoModeWaiting = false;
    if (pick == null) {
      _log('WARN',
          'Сеть появилась, но нет автозапускаемого сценария для оператора «${modemInfo.operatorName}».');
      notifyListeners();
      return;
    }
    _log('INFO', 'Сеть обнаружена. Автозапуск сценария «${pick.name}».');
    unawaited(runScenario(scenarioId: pick.id, automatic: true)
        .catchError((Object error) {
      currentStep = 'Автозапуск не выполнен: $error';
      _log('ERROR', 'Автоматический сценарий не запущен', raw: '$error');
      notifyListeners();
    }));
  }

  void abortScenario() {
    if (isRunning) {
      _abortRun = true;
      currentStep = 'Остановка сценария…';
      notifyListeners();
    }
  }

  String _stepTitle(ScenarioStep step) {
    switch (step.type) {
      case StepType.ownNumber:
        return 'Номер SIM · ${step.code}';
      case StepType.ussd:
        return 'USSD · ${step.code}';
      case StepType.balance:
        return 'Баланс · ${step.code}';
      case StepType.sms:
        return 'SMS → ${step.recipient}';
      case StepType.pause:
        return 'Пауза ${step.seconds} с';
      case StepType.call:
        return 'Звонок → ${step.recipient} (${step.seconds} с)';
      case StepType.dtmf:
        return 'Цифры ${step.digits}';
    }
  }

  Future<void> runScenario({String? scenarioId, bool automatic = false}) async {
    if (isRunning) return;
    if (!isConnected) {
      _log('ERROR', 'Сценарий не запущен: модем не подключён');
      throw StateError('Сначала подключите Huawei E173.');
    }
    if (isInCall) throw StateError('Сначала завершите текущий вызов.');
    if (isBatchRunning) throw StateError('Выполняется серия USSD-команд.');
    final scenario = scenarioById(scenarioId) ??
        (settings.scenarios.isNotEmpty ? settings.scenarios.first : null);
    if (scenario == null) throw StateError('Сценарий не найден.');
    final problems = validateScenario(scenario);
    if (problems.isNotEmpty) {
      _log('ERROR', 'Сценарий «${scenario.name}» не запущен', raw: problems.join('\n'));
      throw StateError(problems.join('\n'));
    }

    isRunning = true;
    _abortRun = false;
    _autoStartedForConnection = true;
    autoModeWaiting = false;
    liveScenarioName = scenario.name;
    liveSteps = scenario.steps.map((step) => LiveStep(title: _stepTitle(step))).toList();
    balanceStatus = '';
    balanceDiff = null;
    currentStep = automatic ? 'Автоматический запуск' : 'Ручной запуск';
    notifyListeners();

    final startedAt = DateTime.now();
    final headers = scenario.columnHeaders();
    final stepCells = List<CellData?>.filled(scenario.steps.length, null);
    final errors = <String>[];
    final balances = <double>[];
    final smsStatuses = <String>[];
    final callStatuses = <String>[];
    final context = _RunContext();
    var firstBalanceText = '';
    var lastBalanceText = '';

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
        errors.add('Не удалось зарегистрироваться в сети за ${settings.networkWaitSeconds} секунд.');
        for (var i = 0; i < scenario.steps.length; i++) {
          liveSteps[i].status = LiveStatus.skipped;
          liveSteps[i].value = 'Пропущено: нет сети';
          if (headers[i] != null) stepCells[i] = const CellData('Нет сети');
        }
      } else {
        // Оператор мог появиться после регистрации.
        try {
          modemInfo = await modem.readModemInfo();
        } catch (_) {}

        for (var i = 0; i < scenario.steps.length; i++) {
          final step = scenario.steps[i];
          final live = liveSteps[i];
          if (_abortRun || !isConnected) {
            for (var j = i; j < scenario.steps.length; j++) {
              liveSteps[j].status = LiveStatus.skipped;
              liveSteps[j].value = isConnected ? 'Остановлено' : 'Модем отключён';
              if (headers[j] != null) {
                stepCells[j] = CellData(isConnected ? 'Остановлено' : 'Модем отключён');
              }
            }
            errors.add(isConnected ? 'Сценарий остановлен пользователем.' : 'Модем был отключён.');
            break;
          }
          live.status = LiveStatus.running;
          currentStep = 'Шаг ${i + 1} из ${scenario.steps.length} — ${live.title}';
          notifyListeners();

          StepOutcome outcome;
          try {
            outcome = await _executeStep(step, context);
          } catch (error) {
            final message = '$error'.replaceFirst('Bad state: ', '');
            outcome = StepOutcome('ОШИБКА: $message', ok: false);
          }
          live.status = outcome.ok ? LiveStatus.ok : LiveStatus.error;
          live.value = outcome.text;
          if (headers[i] != null) {
            stepCells[i] = CellData(outcome.text, number: outcome.number);
          }
          if (!outcome.ok) {
            errors.add('${live.title}: ${outcome.text}');
          }
          if (step.type == StepType.balance && outcome.number != null) {
            balances.add(outcome.number!);
            lastBalanceText = outcome.text;
            if (firstBalanceText.isEmpty) firstBalanceText = outcome.text;
          }
          if (step.type == StepType.sms) smsStatuses.add(outcome.text);
          if (step.type == StepType.call) callStatuses.add(outcome.text);
          _log(outcome.ok ? 'SUCCESS' : 'ERROR', 'Шаг: ${live.title}', raw: outcome.text);
          notifyListeners();

          if (!outcome.ok && scenario.stopOnError) {
            for (var j = i + 1; j < scenario.steps.length; j++) {
              liveSteps[j].status = LiveStatus.skipped;
              liveSteps[j].value = 'Пропущено после ошибки';
              if (headers[j] != null) stepCells[j] = const CellData('Пропущено');
            }
            break;
          }
        }
      }
    } catch (error) {
      errors.add('$error'.replaceFirst('Bad state: ', ''));
      _log('ERROR', 'Сбой сценария', raw: '$error');
    } finally {
      // Сверка баланса: первая проверка и последняя.
      var status = '—';
      double? diff;
      if (balances.length >= 2) {
        final delta = balances.first - balances.last;
        diff = double.parse(delta.toStringAsFixed(2));
        status = delta.abs() < 0.005 ? 'СОВПАЛ' : 'НЕ СОВПАЛ';
      } else if (scenario.steps.where((s) => s.type == StepType.balance).length >= 2) {
        status = 'НЕ ОПРЕДЕЛЕНО';
      }
      balanceStatus = status;
      balanceDiff = diff;

      final finishedAt = DateTime.now();
      final success = errors.isEmpty;
      final simDisplay = context.ownNumber.isNotEmpty
          ? context.ownNumber
          : (simPhone.isNotEmpty ? simPhone : simId);

      final fields = <String, CellData>{
        ExcelFields.sim: CellData(simDisplay),
        ExcelFields.iccid: CellData(simId),
        ExcelFields.operator: CellData(modemInfo.operatorName),
        ExcelFields.balanceFirst: balances.isEmpty
            ? const CellData('')
            : CellData(firstBalanceText, number: balances.first),
        ExcelFields.balanceLast: balances.isEmpty
            ? const CellData('')
            : CellData(lastBalanceText, number: balances.last),
        ExcelFields.balanceStatus: CellData(status),
        ExcelFields.balanceDiff: CellData(diff?.toStringAsFixed(2) ?? '', number: diff),
        ExcelFields.smsStatus: CellData(smsStatuses.join('; ')),
        ExcelFields.callStatus: CellData(callStatuses.join('; ')),
        ExcelFields.errors: CellData(errors.join('\n')),
      };
      for (var i = 0; i < scenario.steps.length; i++) {
        final header = headers[i];
        if (header == null) continue;
        fields[ExcelFields.stepId(i + 1)] = stepCells[i] ?? const CellData('');
        fields[ExcelFields.stepNameId(i + 1)] = CellData(header);
      }

      try {
        await database.insertRun(
          startedAt: startedAt,
          scenarioName: scenario.name,
          fieldsJson: RunRow.encodeFields(fields),
          balanceStatus: status,
          success: success,
        );
        if (simId.isNotEmpty) {
          await database.upsertSim(
            simId: simId,
            phone: context.ownNumber,
            operator: modemInfo.operatorName,
          );
          simPhones = await database.simPhones();
          if (context.ownNumber.isNotEmpty) simPhone = context.ownNumber;
        }
        await database.insertOperation(OperationRecord(
          startedAt: startedAt,
          finishedAt: finishedAt,
          phoneResponse: simDisplay,
          balanceBefore: firstBalanceText,
          smsStatus: smsStatuses.join('; '),
          balanceAfter: lastBalanceText,
          success: success,
          details: errors.isEmpty ? 'Все этапы выполнены.' : errors.join('\n'),
        ));
        await _writeExcel();
      } catch (error) {
        _log('ERROR', 'Не удалось сохранить результат сценария', raw: '$error');
      }

      isRunning = false;
            currentStep = success
          ? 'Сценарий завершён успешно · ${_formatDateTime(finishedAt)}'
          : 'Сценарий завершён с ошибками';
      _log(
        success ? 'SUCCESS' : 'WARN',
        'Сценарий «${scenario.name}» завершён',
        raw: errors.isEmpty ? 'Все шаги выполнены. Сверка баланса: $status' : errors.join('\n'),
      );
      await loadHistory();
      notifyListeners();
    }
  }

  Future<StepOutcome> _executeStep(ScenarioStep step, _RunContext context) async {
    switch (step.type) {
      case StepType.ownNumber:
        {
        final response = await _ussdInRun(step.code, context);
        final extracted = UssdCodec.extractPhoneNumber(response);
        if (extracted.isEmpty) {
          return StepOutcome('Номер не распознан: ${_oneLine(response)}', ok: false);
        }
        context.ownNumber = extracted;
        return StepOutcome(extracted);
        }

      case StepType.ussd:
        {
        final response = await _ussdInRun(step.code, context);
        return StepOutcome(_oneLine(response));
        }

      case StepType.balance:
        return _balanceStep(step, context);

      case StepType.sms:
        {
        final known = context.lastBalance;
        if (settings.smsMinBalance > 0 && known != null && known < settings.smsMinBalance) {
          return StepOutcome(
            'НЕДОСТАТОЧНО СРЕДСТВ (баланс $known, нужно от ${settings.smsMinBalance})',
            ok: false,
          );
        }
        try {
          await modem.sendSms(
            recipient: step.recipient,
            message: step.text,
            requestStatusReport: settings.smsRequireNetworkAck,
          );
          return const StepOutcome('Отправлено');
        } catch (error) {
          final message = '$error'.replaceFirst('Bad state: ', '');
          if (known != null && known <= 0) {
            return StepOutcome('НЕДОСТАТОЧНО СРЕДСТВ (баланс $known)', ok: false);
          }
          return StepOutcome('ОШИБКА: $message', ok: false);
        }
        }

      case StepType.pause:
        for (var i = 0; i < step.seconds; i++) {
          if (_abortRun || !isConnected) break;
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        return StepOutcome('Пауза ${step.seconds} с');

      case StepType.call:
        return _runCallStep(step);

      case StepType.dtmf:
        {
        final answer = await modem.sendDtmf(step.digits);
        if (answer.toUpperCase().contains('ERROR')) {
          return StepOutcome('ОШИБКА: ${_oneLine(answer)}', ok: false);
        }
        return StepOutcome('Отправлено: ${step.digits}');
        }
    }
  }

  /// Проверка баланса. Если USSD-ответ без суммы (оператор прислал баланс
  /// по SMS) — ждёт входящее SMS и берёт сумму из него.
  Future<StepOutcome> _balanceStep(ScenarioStep step, _RunContext context) async {
    final started = DateTime.now().subtract(const Duration(seconds: 2));
    if (step.waitSms) {
      try {
        await syncSms(silent: true); // фиксируем уже имеющиеся SMS
      } catch (_) {}
    }
    String response = '';
    String ussdError = '';
    try {
      response = await _ussdInRun(step.code, context);
    } catch (error) {
      ussdError = '$error'.replaceFirst('Bad state: ', '');
    }
    if (response.isNotEmpty) {
      final text = UssdCodec.extractBalance(response);
      final number = double.tryParse(text);
      if (number != null) {
        context.lastBalance = number;
        return StepOutcome(text, number: number);
      }
    }
    if (!step.waitSms) {
      return StepOutcome(
        response.isNotEmpty
            ? 'Баланс не распознан: ${_oneLine(response)}'
            : 'ОШИБКА: $ussdError',
        ok: false,
      );
    }

    final timeout = step.smsTimeout < 5 ? 5 : step.smsTimeout;
    final deadline = DateTime.now().add(Duration(seconds: timeout));
    final filter = step.smsSender.trim().toLowerCase();
    var lastSms = '';
    while (DateTime.now().isBefore(deadline)) {
      if (_abortRun || !isConnected) break;
      currentStep = 'Ожидание SMS с балансом…';
      notifyListeners();
      final rows = await database.incomingSince(started);
      for (final row in rows) {
        final sender = '${row['sender'] ?? ''}'.toLowerCase();
        if (filter.isNotEmpty && !sender.contains(filter)) continue;
        final body = '${row['body'] ?? ''}';
        lastSms = body;
        final text = UssdCodec.extractBalance(body);
        final number = double.tryParse(text);
        if (number != null) {
          context.lastBalance = number;
          return StepOutcome(text, number: number);
        }
      }
      await Future<void>.delayed(const Duration(seconds: 3));
      try {
        await syncSms(silent: true);
      } catch (_) {}
    }
    if (lastSms.isNotEmpty) {
      return StepOutcome('Баланс не распознан в SMS: ${_oneLine(lastSms)}', ok: false);
    }
    final reason = ussdError.isNotEmpty
        ? 'USSD: $ussdError. '
        : (response.isNotEmpty ? 'USSD без суммы: ${_oneLine(response)}. ' : '');
    return StepOutcome('${reason}SMS с балансом не пришло за $timeout с', ok: false);
  }

  /// Звонок в сценарии: набор → ожидание ответа → разговор N секунд → отбой.
  Future<StepOutcome> _runCallStep(ScenarioStep step) async {
    final actions = [...step.actions]..sort((x, y) => x.at.compareTo(y.at));
    final needAudio = actions.any((item) => item.isPhrase);
    final notes = <String>[];

    VoiceBridge? bridge;
    if (needAudio) {
      final port = settings.audioPort;
      if (port.isEmpty) {
        return const StepOutcome(
            'ОШИБКА: не выбран звуковой порт (Настройки → Голос)', ok: false);
      }
      if (port == modem.connectedPort) {
        return StepOutcome(
            'ОШИБКА: звуковой порт совпадает с портом команд ($port)', ok: false);
      }
    }

    await modem.dial(step.recipient);
    try {
      await modem.routeAudioToUsb();
    } catch (_) {}

    var connected = false;
    var emptyPolls = 0;
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      if (_abortRun || !isConnected) break;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final calls = await modem.currentCalls();
      if (calls.isEmpty) {
        emptyPolls++;
        if (emptyPolls >= 3) break;
        continue;
      }
      emptyPolls = 0;
      if (calls.any((call) => call.isActive)) {
        connected = true;
        break;
      }
    }
    if (!connected) {
      try {
        await modem.hangUp();
      } catch (_) {}
      return const StepOutcome('Не соединено (занято, нет ответа или сброс)', ok: false);
    }

    if (needAudio) {
      try {
        final created = VoiceBridge(portName: settings.audioPort);
        await created.start();
        bridge = created;
      } catch (error) {
        notes.add('звук не запущен: ${'$error'.replaceFirst('Bad state: ', '')}');
      }
    }

    final talkStart = DateTime.now();
    var endedEarly = false;
    var failed = false;
    var nextAction = 0;
    emptyPolls = 0;
    final talkLimit = Duration(seconds: step.seconds);
    while (DateTime.now().difference(talkStart) < talkLimit) {
      if (_abortRun || !isConnected) break;
      final elapsed = DateTime.now().difference(talkStart).inSeconds;
      while (nextAction < actions.length && actions[nextAction].at <= elapsed) {
        final action = actions[nextAction++];
        try {
          if (action.isPhrase) {
            final current = bridge;
            if (current == null) throw StateError('нет звука');
            final pcm = await WavLoader.loadAs8kMono(phrasePath(action.value));
            current.playPcm(pcm);
            notes.add('${action.at} с: «${action.value}»');
          } else {
            final answer = await modem.sendDtmf(action.value);
            if (answer.toUpperCase().contains('ERROR')) {
              throw StateError('DTMF отклонён модемом');
            }
            notes.add('${action.at} с: цифры ${action.value}');
          }
        } catch (error) {
          failed = true;
          notes.add('${action.at} с: ОШИБКА ${action.isPhrase ? '«${action.value}»' : action.value}: '
              '${'$error'.replaceFirst('Bad state: ', '')}');
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final calls = await modem.currentCalls();
      if (calls.isEmpty) {
        emptyPolls++;
        if (emptyPolls >= 3) {
          endedEarly = true;
          break;
        }
      } else {
        emptyPolls = 0;
      }
    }
    final talked = DateTime.now().difference(talkStart).inSeconds;
    // Если фраза ещё звучит — дослушиваем её до конца (не дольше 15 с).
    final waitEnd = DateTime.now().add(const Duration(seconds: 15));
    while (bridge != null &&
        bridge.isInjecting &&
        !endedEarly &&
        DateTime.now().isBefore(waitEnd)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (!endedEarly) {
      try {
        await modem.hangUp();
      } catch (_) {}
    }
    if (bridge != null) await bridge.stop();
    final detail = notes.where((n) => n.isNotEmpty).join('; ');
    return StepOutcome(
      '${endedEarly ? 'Соединено, абонент завершил вызов через $talked с' : 'Соединено, разговор $talked с'}'
      '${detail.isEmpty ? '' : '. Действия: $detail'}',
      ok: !failed,
    );
  }

  String _oneLine(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Выполняет USSD-команду с кэшированием ответа в рамках одного прогона
  /// сценария, чтобы одинаковый запрос (например *100#) не дублировался в сеть,
  /// если из него поочерёдно извлекаются баланс и номер.
  Future<String> _ussdInRun(String code, _RunContext context) async {
    final key = code.trim();
    final cached = context.ussdResponses[key];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    final response = await _ussdWithRetry(code);
    if (response.isNotEmpty) {
      context.ussdResponses[key] = response;
    }
    return response;
  }

  Future<String> _ussdWithRetry(String code) async {
    Object? lastError;
    for (var attempt = 0; attempt <= settings.retryCount; attempt++) {
      if (!isConnected) break;
      try {
        return await modem.sendUssd(
          code,
          dcs: settings.ussdDcs,
          timeout: Duration(seconds: settings.ussdTimeoutSeconds),
        );
      } catch (error) {
        lastError = error;
        if (!isConnected) break;
        if (attempt < settings.retryCount) {
          _log('WARN', 'Повтор USSD-запроса (${attempt + 1})', raw: '$error');
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    }
    throw StateError('$lastError'.replaceFirst('Bad state: ', ''));
  }

  // ---------------------------------------------------------------------
  // Excel
  // ---------------------------------------------------------------------

  Future<String> _writeExcel() async {
    final stored = await database.allRuns();
    final rows = <RunRow>[];
    for (final row in stored) {
      try {
        final fieldsRaw = '${row['fields_json'] ?? ''}';
        final fields = fieldsRaw.trim().isNotEmpty
            ? RunRow.decodeFields(fieldsRaw)
            : RunRow.fromLegacy('${row['columns_json']}', '${row['cells_json']}');
        rows.add(RunRow(
          startedAt: DateTime.tryParse('${row['started_at']}') ?? DateTime.now(),
          scenarioName: '${row['scenario_name']}',
          fields: fields,
          balanceStatus: '${row['balance_status'] ?? ''}',
          success: row['success'] == 1,
        ));
      } catch (_) {
        // повреждённую строку пропускаем
      }
    }
    final path = await ExcelExporter.write(
      path: paths.excelFile,
      rows: rows,
      selectedColumns: settings.excelColumns,
      customTitles: settings.excelColumnTitles,
    );
    lastExcelPath = path;
    excelMessage = path == paths.excelFile
        ? 'Таблица обновлена: ${rows.length} строк.'
        : 'Основной файл занят (открыт в Excel). Сохранено в резервный файл.';
    return path;
  }

  Future<String> exportExcel() async {
    final path = await _writeExcel();
    _log('SUCCESS', 'Excel-файл сохранён', raw: path);
    notifyListeners();
    return path;
  }

  Future<void> clearRunResults() async {
    await database.clearRuns();
    await _writeExcel();
    runCount = 0;
    _log('INFO', 'Таблица результатов очищена');
    notifyListeners();
  }

  Future<void> openPath(String path) async {
    try {
      await Process.start('explorer.exe', [path]);
    } catch (error) {
      throw StateError('Не удалось открыть: $error');
    }
  }

  Future<void> openExcelFile() async {
    final file = File(paths.excelFile);
    if (!await file.exists()) await _writeExcel();
    await openPath(paths.excelFile);
  }

  Future<void> openDataFolder() => openPath(paths.dataDir);

  // ---------------------------------------------------------------------
  // USSD вручную и серия команд
  // ---------------------------------------------------------------------

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

  /// Разбор текста серии: каждая строка "код" или "код;пауза_в_секундах".
  static List<BatchItem> parseBatch(String text) {
    final items = <BatchItem>[];
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final parts = line.split(';');
      final code = parts.first.trim();
      if (code.isEmpty) continue;
      final delay = parts.length > 1 ? int.tryParse(parts[1].trim()) ?? 0 : 0;
      items.add(BatchItem(code, delay < 0 ? 0 : delay));
    }
    return items;
  }

  Future<void> runUssdBatch(
    List<BatchItem> items, {
    int repeats = 1,
    int repeatPauseSeconds = 0,
  }) async {
    if (items.isEmpty) throw StateError('Список USSD-команд пуст.');
    if (!isConnected) throw StateError('Подключите модем.');
    if (isBatchRunning || isRunning) throw StateError('Модем занят сценарием или серией.');
    isBatchRunning = true;
    _abortBatch = false;
    batchLog = [];
    notifyListeners();
    try {
      for (var round = 1; round <= repeats; round++) {
        for (final item in items) {
          if (_abortBatch || !isConnected) return;
          String line;
          try {
            final response = await modem.sendUssd(
              item.code,
              dcs: settings.ussdDcs,
              timeout: Duration(seconds: settings.ussdTimeoutSeconds),
            );
            lastUssdResponse = response;
            line = '${item.code} → ${_oneLine(response)}';
            _log('INFO', 'Серия USSD: ${item.code}', raw: response);
          } catch (error) {
            line = '${item.code} → ОШИБКА: ${'$error'.replaceFirst('Bad state: ', '')}';
            _log('ERROR', 'Серия USSD: ${item.code}', raw: '$error');
          }
          final stamp = DateTime.now().toIso8601String().substring(11, 19);
          batchLog = ['[$stamp] ${repeats > 1 ? '(круг $round) ' : ''}$line', ...batchLog];
          notifyListeners();
          for (var s = 0; s < item.delaySeconds; s++) {
            if (_abortBatch || !isConnected) return;
            await Future<void>.delayed(const Duration(seconds: 1));
          }
        }
        if (round < repeats) {
          for (var s = 0; s < repeatPauseSeconds; s++) {
            if (_abortBatch || !isConnected) return;
            await Future<void>.delayed(const Duration(seconds: 1));
          }
        }
      }
    } finally {
      isBatchRunning = false;
      notifyListeners();
    }
  }

  void stopUssdBatch() {
    _abortBatch = true;
  }

  // ---------------------------------------------------------------------
  // SMS: хранилище, синхронизация, корзина
  // ---------------------------------------------------------------------

  Future<void> reloadSms() async {
    smsInbox = await database.smsByFolder('inbox');
    smsSent = await database.smsByFolder('sent');
    smsTrash = await database.smsByFolder('trash');
    smsCounts = await database.smsCounts();
    unreadSms = await database.unreadCount();
    simPhones = await database.simPhones();
    notifyListeners();
  }

  /// Выгружает SMS из памяти модема в локальную базу. Возвращает число новых.
  Future<int> syncSms({bool silent = false}) async {
    if (!isConnected) throw StateError('Подключите модем.');
    if (isSyncingSms) return 0;
    isSyncingSms = true;
    if (!silent) notifyListeners();
    try {
      final raws = await modem.readSmsPdu();
      final merged = SmsPduDecoder.decodeAndMerge(raws);
      final sim = simId.isNotEmpty
          ? simId
          : (modemInfo.imei.isNotEmpty ? modemInfo.imei : 'unknown');
      var added = 0;
      final saved = <String>[];
      for (final item in merged) {
        final folder = item.outgoing ? 'sent' : 'inbox';
        final key = '$sim|$folder|${item.sender}|${item.time}|${item.text}';
        final inserted = await database.insertSms(
          hash: key,
          simId: sim,
          folder: folder,
          sender: item.sender,
          body: item.text,
          smsTime: item.time,
          modemRefs: item.refs.join(','),
          isNew: !item.outgoing && item.unread,
        );
        if (inserted) added++;
        saved.addAll(item.refs);
      }
      if (settings.deleteSmsFromModem && saved.isNotEmpty) {
        await modem.deleteSmsFromModem(saved);
      }
      _lastSmsSync = DateTime.now();
      if (added > 0) {
        _log('SUCCESS', 'Получено новых SMS: $added');
        playSmsNotification(volume: settings.smsSoundVolume);
      }
      await reloadSms();
      return added;
    } catch (error) {
      _lastSmsSync = DateTime.now();
      if (!silent) rethrow;
      _log('WARN', 'Не удалось прочитать SMS', raw: '$error');
      return 0;
    } finally {
      isSyncingSms = false;
      notifyListeners();
    }
  }

  void playSmsNotification({double? volume}) {
    if (!Platform.isWindows) return;
    if (volume == null && !settings.smsSoundEnabled) return;
    final vol = (volume ?? settings.smsSoundVolume).clamp(0.0, 1.0);
    if (vol <= 0.001) return;
    try {
      playSmsNotificationSound(volume: vol);
    } catch (_) {
      // звук уведомления не должен прерывать работу приложения
    }
  }

  Future<void> trashSms(int id) async {
    await database.trashSms(id);
    await reloadSms();
  }

  Future<void> restoreSms(int id) async {
    await database.restoreSms(id);
    await reloadSms();
  }

  Future<void> purgeSms(int id) async {
    await database.deleteSmsForever(id);
    await reloadSms();
  }

  Future<void> emptySmsTrash() async {
    await database.emptyTrash();
    await reloadSms();
  }

  Future<void> markSmsRead(int id) async {
    await database.markSmsRead(id);
    await reloadSms();
  }

  Future<void> markAllSmsRead() async {
    await database.markAllSmsRead();
    await reloadSms();
  }

  Future<void> trashSmsBatch(List<int> ids) async {
    if (ids.isEmpty) return;
    await database.trashSmsBatch(ids);
    await reloadSms();
  }

  Future<void> restoreSmsBatch(List<int> ids) async {
    if (ids.isEmpty) return;
    await database.restoreSmsBatch(ids);
    await reloadSms();
  }

  Future<void> purgeSmsBatch(List<int> ids) async {
    if (ids.isEmpty) return;
    await database.deleteSmsForeverBatch(ids);
    await reloadSms();
  }

  Future<void> markSmsReadBatch(List<int> ids) async {
    if (ids.isEmpty) return;
    await database.markSmsReadBatch(ids);
    await reloadSms();
  }

  Future<String> sendSmsManually(String recipient, String text) async {
    final response = await modem.sendSms(
      recipient: recipient,
      message: text,
      requestStatusReport: settings.smsRequireNetworkAck,
    );
    _log('SUCCESS', 'SMS передана модему: $recipient', raw: response);
    final sim = simId.isNotEmpty ? simId : 'unknown';
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    await database.insertSms(
      hash: '$sim|sent|$recipient|$stamp|$text|${now.microsecondsSinceEpoch}',
      simId: sim,
      folder: 'sent',
      sender: recipient,
      body: text,
      smsTime: stamp,
      isNew: false,
    );
    await reloadSms();
    return response;
  }

  // ---------------------------------------------------------------------
  // Контакты и AT-терминал
  // ---------------------------------------------------------------------

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

  // ---------------------------------------------------------------------
  // Вызовы и голос
  // ---------------------------------------------------------------------

  Future<void> refreshCalls() async {
    callsRaw = await modem.listCalls();
    _log('INFO', 'Список активных вызовов', raw: callsRaw);
    notifyListeners();
  }

  Future<String> enableVoice() async {
    final result = await modem.enableVoice();
    _log('INFO', 'Голосовой режим', raw: result);
    return result;
  }

  Future<void> startCall(String number) async {
    if (!isConnected) throw StateError('Подключите модем.');
    if (isInCall) throw StateError('Вызов уже идёт.');
    if (isRunning || isBatchRunning) throw StateError('Модем занят сценарием.');
    final clean = number.trim();
    if (clean.isEmpty) throw StateError('Введите номер телефона.');
    final result = await modem.dial(clean);
    _log('INFO', 'Набор номера: $clean', raw: result);
    callNumber = clean;
    callPhase = CallPhase.dialing;
    callStartedAt = null;
    _noCallPolls = 0;
    callsRaw = result;
    notifyListeners();
    try {
      await modem.routeAudioToUsb();
    } catch (_) {}
    await _startVoice();
  }

  Future<void> answerIncoming() async {
    if (callPhase != CallPhase.incoming) return;
    final result = await modem.answerCall();
    _log('INFO', 'Ответ на входящий вызов', raw: result);
    callPhase = CallPhase.active;
    callStartedAt = DateTime.now();
    _noCallPolls = 0;
    notifyListeners();
    try {
      await modem.routeAudioToUsb();
    } catch (_) {}
    await _startVoice();
  }

  Future<void> hangUp() async {
    String result = '';
    try {
      result = await _retryBusy(() => modem.hangUp());
    } finally {
      _log('INFO', 'Завершение вызова', raw: result);
      callsRaw = result;
      await _endCallState();
    }
  }

  Future<void> sendDtmf(String digits) async {
    if (!isConnected) throw StateError('Подключите модем.');
    final result = await _retryBusy(() => modem.sendDtmf(digits));
    _log('INFO', 'DTMF: $digits', raw: result);
  }

  Future<T> _retryBusy<T>(Future<T> Function() action) async {
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        return await action();
      } on StateError catch (error) {
        if (!'$error'.contains('занят') || attempt == 5) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    return action();
  }

  Future<void> _callTick() async {
    if (modem.isBusy) return;
    final calls = await modem.currentCalls();
    if (calls.isEmpty) {
      _noCallPolls++;
      final ended = modem.takeCallEndedHint();
      if (_noCallPolls >= 2 || ended) await _endCallState();
      return;
    }
    _noCallPolls = 0;
    final call = calls.first;
    final previous = callPhase;
    switch (call.state) {
      case 0:
        callPhase = CallPhase.active;
        callStartedAt ??= DateTime.now();
        break;
      case 2:
        callPhase = CallPhase.dialing;
        break;
      case 3:
        callPhase = CallPhase.ringing;
        break;
      case 4:
      case 5:
        callPhase = CallPhase.incoming;
        break;
      default:
        break;
    }
    if (call.number.isNotEmpty) callNumber = call.number;
    if (previous != callPhase) notifyListeners();
  }

  Future<void> _endCallState() async {
    await _stopVoice();
    if (callPhase != CallPhase.idle) {
      _log('INFO', 'Вызов завершён', raw: callNumber);
    }
    callPhase = CallPhase.idle;
    callStartedAt = null;
    _noCallPolls = 0;
    modem.clearRinging();
    notifyListeners();
  }

  Future<void> _startVoice() async {
    await _stopVoice();
    final port = settings.audioPort;
    if (port.isEmpty) {
      callStatus = 'Звуковой порт не выбран (Настройки → Голос): звук не передаётся.';
      notifyListeners();
      return;
    }
    if (port == modem.connectedPort) {
      callStatus = 'Звуковой порт не должен совпадать с портом AT-команд ($port).';
      notifyListeners();
      return;
    }
    try {
      final bridge = VoiceBridge(portName: port);
      await bridge.start();
      voice = bridge;
      callStatus = bridge.micAvailable
          ? 'Звук: $port'
          : 'Звук: $port (микрофон недоступен — только прослушивание)';
    } catch (error) {
      voice = null;
      callStatus = 'Звук не запущен: ${'$error'.replaceFirst('Bad state: ', '')}';
    }
    notifyListeners();
  }

  Future<void> _stopVoice() async {
    final bridge = voice;
    voice = null;
    if (bridge != null) await bridge.stop();
  }

  void setMicMuted(bool value) {
    voice?.muted = value;
    notifyListeners();
  }

  void setSpeakerOn(bool value) {
    voice?.speakerOn = value;
    notifyListeners();
  }

  Future<void> playWavIntoCall(String path) async {
    final bridge = voice;
    if (bridge == null) {
      throw StateError('Звук вызова не запущен. Выберите звуковой порт в настройках.');
    }
    final pcm = await WavLoader.loadAs8kMono(path);
    bridge.playPcm(pcm);
  }

  // ---------------------------------------------------------------------
  // Фразы для звонков
  // ---------------------------------------------------------------------

  String phrasePath(String name) => p.join(paths.soundsDir, '$name.wav');

  String _cleanPhraseName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();
    if (cleaned.isEmpty) throw StateError('Введите название фразы.');
    return cleaned;
  }

  Future<void> loadPhrases() async {
    final dir = Directory(paths.soundsDir);
    final names = <String>[];
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.wav')) {
          names.add(p.basenameWithoutExtension(entity.path));
        }
      }
    }
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    phrases = names;
    notifyListeners();
  }

  Future<void> startPhraseRecording() async {
    if (isRecordingPhrase) return;
    final recorder = WaveInRecorder()..open();
    _phraseRecorder = recorder;
    _phraseBuffer.clear();
    recordedMillis = 0;
    isRecordingPhrase = true;
    _phraseTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
      final frames = _phraseRecorder?.poll() ?? const <Uint8List>[];
      for (final frame in frames) {
        _phraseBuffer.add(frame);
      }
      recordedMillis = _phraseBuffer.length ~/ 16; // 16 байт на мс
      if (frames.isNotEmpty) notifyListeners();
    });
    notifyListeners();
  }

  void _closePhraseRecorder() {
    _phraseTimer?.cancel();
    _phraseTimer = null;
    _phraseRecorder?.close();
    _phraseRecorder = null;
    isRecordingPhrase = false;
  }

  void cancelPhraseRecording() {
    _closePhraseRecorder();
    _phraseBuffer.clear();
    notifyListeners();
  }

  /// Останавливает запись и сохраняет фразу [name] в UserData/Sounds.
  Future<void> stopPhraseRecording(String name) async {
    final cleaned = _cleanPhraseName(name);
    _closePhraseRecorder();
    final pcm = _phraseBuffer.takeBytes();
    notifyListeners();
    if (pcm.length < 1600) throw StateError('Запись слишком короткая.');
    await File(phrasePath(cleaned)).writeAsBytes(WavLoader.encode(pcm), flush: true);
    await loadPhrases();
  }

  Future<void> importPhrase(String sourcePath, String name) async {
    final cleaned = _cleanPhraseName(name);
    final pcm = await WavLoader.loadAs8kMono(sourcePath);
    await File(phrasePath(cleaned)).writeAsBytes(WavLoader.encode(pcm), flush: true);
    await loadPhrases();
  }

  Future<void> deletePhrase(String name) async {
    final file = File(phrasePath(name));
    if (await file.exists()) await file.delete();
    await loadPhrases();
  }

  /// Прослушать фразу на динамиках компьютера.
  Future<void> previewPhrase(String name) async {
    final pcm = await WavLoader.loadAs8kMono(phrasePath(name));
    final player = WaveOutPlayer()..open();
    try {
      player.write(pcm);
      await Future<void>.delayed(
          Duration(milliseconds: pcm.length ~/ 16 + 400));
    } finally {
      player.close();
    }
  }

  Future<void> playPhraseIntoCall(String name) => playWavIntoCall(phrasePath(name));

  /// Диагностика приёма SMS (кнопка на странице SMS).
  Future<String> smsDiagnostics() async {
    if (!isConnected) throw StateError('Подключите модем.');
    final report = await modem.smsDiagnostics();
    final counts = await database.smsCounts();
    final last = _lastSmsSync;
    return [
      report.trim(),
      '',
      'Уведомлений о новых SMS (+CMTI) с запуска: ${modem.smsHintCount}',
      'Последняя выгрузка SMS: ${last == null ? 'ещё не было' : last.toIso8601String()}',
      'Автоприём: ${settings.smsAutoReceive ? 'включён' : 'выключен'}, опрос каждые ${settings.smsPollSeconds} с',
      'В локальной базе: входящих ${counts['inbox'] ?? 0}, отправленных ${counts['sent'] ?? 0}, корзина ${counts['trash'] ?? 0}',
      '',
      'Подсказка: AT+CNMI?  +CNMI: 2,1,… — модем присылает уведомления о новых SMS; '
          '0,… — не присылает (SMS придут только при опросе памяти).',
    ].join('\n');
  }

  // ---------------------------------------------------------------------
  // Экспорт журнала и служебное
  // ---------------------------------------------------------------------

  Future<String> exportOperationsCsv() async {
    final rows = <List<dynamic>>[
      [
        'Начало',
        'Окончание',
        'SIM / номер',
        'Баланс (первая проверка)',
        'Статус SMS',
        'Баланс (последняя проверка)',
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
    final folder = Directory(paths.exportDir);
    await folder.create(recursive: true);
    final file = File(p.join(
        folder.path, 'operations_${DateTime.now().millisecondsSinceEpoch}.csv'));
    await file.writeAsString('﻿$csvText', flush: true);
    lastExportPath = file.path;
    _log('SUCCESS', 'Экспорт завершён', raw: file.path);
    notifyListeners();
    return file.path;
  }

  Future<void> _log(String level, String message, {String raw = ''}) async {
    if (_disposed) return;
    try {
      await database.insertLog(
        at: DateTime.now(),
        level: level,
        message: message,
        raw: raw,
      );
      logs = await database.recentLogs();
      if (!_disposed) notifyListeners();
    } catch (_) {
      // журнал не должен ронять программу
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _slowTimer?.cancel();
    _fastTimer?.cancel();
    unawaited(_stopVoice());
    unawaited(modem.disconnect());
    unawaited(database.close());
    super.dispose();
  }
}
