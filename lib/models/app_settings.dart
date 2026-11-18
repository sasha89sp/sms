import 'scenario.dart';

class AppSettings {
  const AppSettings({
    this.preferredPort = '',
    this.baudRate = 115200,
    this.numberUssd = '',
    this.balanceUssd = '*100#',
    this.smsRecipient = '',
    this.smsText = '',
    this.ussdDcs = 15,
    this.autoStart = false,
    this.autoConnect = true,
    this.networkWaitSeconds = 180,
    this.ussdTimeoutSeconds = 45,
    this.retryCount = 1,
    this.smsRequireNetworkAck = false,
    this.scenarios = const [],
    this.savedUssd = const [],
<<<<<<< HEAD
    this.excelColumns = const [],
=======
<<<<<<< HEAD
    this.excelColumns = const [],
=======
    this.excelIncludeDate = true,
>>>>>>> a25f356dea16092df8cedcd76460a90b086cf782
>>>>>>> 887366133c493cb7455998e386988932333c2e18
    this.smsMinBalance = 0,
    this.smsAutoReceive = true,
    this.smsPollSeconds = 15,
    this.deleteSmsFromModem = false,
    this.audioPort = '',
    this.closeToTray = true,
  });

  final String preferredPort;
  final int baudRate;
  final String numberUssd;
  final String balanceUssd;
  final String smsRecipient;
  final String smsText;
  final int ussdDcs;

  /// Устарело: автозапуск задаётся в каждом сценарии. Поле оставлено для
  /// совместимости со старым файлом настроек.
  final bool autoStart;
  final bool autoConnect;
  final int networkWaitSeconds;
  final int ussdTimeoutSeconds;
  final int retryCount;
  final bool smsRequireNetworkAck;

  final List<Scenario> scenarios;
  final List<SavedUssd> savedUssd;

  /// Добавлять в Excel столбец с датой и временем запуска.
<<<<<<< HEAD
  /// Столбцы Excel по порядку; пусто — все.
  final List<String> excelColumns;
=======
<<<<<<< HEAD
  /// Столбцы Excel по порядку; пусто — все.
  final List<String> excelColumns;
=======
  final bool excelIncludeDate;
>>>>>>> a25f356dea16092df8cedcd76460a90b086cf782
>>>>>>> 887366133c493cb7455998e386988932333c2e18

  /// Если известный баланс ниже этой суммы — SMS не отправляется,
  /// шаг помечается «Недостаточно средств». 0 — проверка выключена.
  final double smsMinBalance;

  final bool smsAutoReceive;
  final int smsPollSeconds;
  final bool deleteSmsFromModem;

  /// COM-порт, по которому модем передаёт голос (PCM).
  final String audioPort;

  final bool closeToTray;

  AppSettings copyWith({
    String? preferredPort,
    int? baudRate,
    String? numberUssd,
    String? balanceUssd,
    String? smsRecipient,
    String? smsText,
    int? ussdDcs,
    bool? autoStart,
    bool? autoConnect,
    int? networkWaitSeconds,
    int? ussdTimeoutSeconds,
    int? retryCount,
    bool? smsRequireNetworkAck,
    List<Scenario>? scenarios,
    List<SavedUssd>? savedUssd,
<<<<<<< HEAD
    List<String>? excelColumns,
=======
<<<<<<< HEAD
    List<String>? excelColumns,
=======
    bool? excelIncludeDate,
>>>>>>> a25f356dea16092df8cedcd76460a90b086cf782
>>>>>>> 887366133c493cb7455998e386988932333c2e18
    double? smsMinBalance,
    bool? smsAutoReceive,
    int? smsPollSeconds,
    bool? deleteSmsFromModem,
    String? audioPort,
    bool? closeToTray,
  }) {
    return AppSettings(
      preferredPort: preferredPort ?? this.preferredPort,
      baudRate: baudRate ?? this.baudRate,
      numberUssd: numberUssd ?? this.numberUssd,
      balanceUssd: balanceUssd ?? this.balanceUssd,
      smsRecipient: smsRecipient ?? this.smsRecipient,
      smsText: smsText ?? this.smsText,
      ussdDcs: ussdDcs ?? this.ussdDcs,
      autoStart: autoStart ?? this.autoStart,
      autoConnect: autoConnect ?? this.autoConnect,
      networkWaitSeconds: networkWaitSeconds ?? this.networkWaitSeconds,
      ussdTimeoutSeconds: ussdTimeoutSeconds ?? this.ussdTimeoutSeconds,
      retryCount: retryCount ?? this.retryCount,
      smsRequireNetworkAck:
          smsRequireNetworkAck ?? this.smsRequireNetworkAck,
      scenarios: scenarios ?? this.scenarios,
      savedUssd: savedUssd ?? this.savedUssd,
<<<<<<< HEAD
      excelColumns: excelColumns ?? this.excelColumns,
=======
<<<<<<< HEAD
      excelColumns: excelColumns ?? this.excelColumns,
=======
      excelIncludeDate: excelIncludeDate ?? this.excelIncludeDate,
>>>>>>> a25f356dea16092df8cedcd76460a90b086cf782
>>>>>>> 887366133c493cb7455998e386988932333c2e18
      smsMinBalance: smsMinBalance ?? this.smsMinBalance,
      smsAutoReceive: smsAutoReceive ?? this.smsAutoReceive,
      smsPollSeconds: smsPollSeconds ?? this.smsPollSeconds,
      deleteSmsFromModem: deleteSmsFromModem ?? this.deleteSmsFromModem,
      audioPort: audioPort ?? this.audioPort,
      closeToTray: closeToTray ?? this.closeToTray,
    );
  }

  Map<String, Object?> toJson() => {
        'preferredPort': preferredPort,
        'baudRate': baudRate,
        'numberUssd': numberUssd,
        'balanceUssd': balanceUssd,
        'smsRecipient': smsRecipient,
        'smsText': smsText,
        'ussdDcs': ussdDcs,
        'autoStart': autoStart,
        'autoConnect': autoConnect,
        'networkWaitSeconds': networkWaitSeconds,
        'ussdTimeoutSeconds': ussdTimeoutSeconds,
        'retryCount': retryCount,
        'smsRequireNetworkAck': smsRequireNetworkAck,
        'scenarios': scenarios.map((item) => item.toJson()).toList(),
        'savedUssd': savedUssd.map((item) => item.toJson()).toList(),
<<<<<<< HEAD
        'excelColumns': excelColumns,
=======
<<<<<<< HEAD
        'excelColumns': excelColumns,
=======
        'excelIncludeDate': excelIncludeDate,
>>>>>>> a25f356dea16092df8cedcd76460a90b086cf782
>>>>>>> 887366133c493cb7455998e386988932333c2e18
        'smsMinBalance': smsMinBalance,
        'smsAutoReceive': smsAutoReceive,
        'smsPollSeconds': smsPollSeconds,
        'deleteSmsFromModem': deleteSmsFromModem,
        'audioPort': audioPort,
        'closeToTray': closeToTray,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        preferredPort: json['preferredPort'] as String? ?? '',
        baudRate: (json['baudRate'] as num?)?.toInt() ?? 115200,
        numberUssd: json['numberUssd'] as String? ?? '',
        balanceUssd: json['balanceUssd'] as String? ?? '*100#',
        smsRecipient: json['smsRecipient'] as String? ?? '',
        smsText: json['smsText'] as String? ?? '',
        ussdDcs: (json['ussdDcs'] as num?)?.toInt() ?? 15,
        autoStart: json['autoStart'] as bool? ?? false,
        autoConnect: json['autoConnect'] as bool? ?? true,
        networkWaitSeconds: (json['networkWaitSeconds'] as num?)?.toInt() ?? 180,
        ussdTimeoutSeconds: (json['ussdTimeoutSeconds'] as num?)?.toInt() ?? 45,
        retryCount: (json['retryCount'] as num?)?.toInt() ?? 1,
        smsRequireNetworkAck: json['smsRequireNetworkAck'] as bool? ?? false,
        scenarios: ((json['scenarios'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => Scenario.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
        savedUssd: ((json['savedUssd'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => SavedUssd.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
<<<<<<< HEAD
        excelColumns: ((json['excelColumns'] as List?) ?? const []).map((e) => '$e').toList(),
=======
<<<<<<< HEAD
        excelColumns: ((json['excelColumns'] as List?) ?? const []).map((e) => '$e').toList(),
=======
        excelIncludeDate: json['excelIncludeDate'] as bool? ?? true,
>>>>>>> a25f356dea16092df8cedcd76460a90b086cf782
>>>>>>> 887366133c493cb7455998e386988932333c2e18
        smsMinBalance: (json['smsMinBalance'] as num?)?.toDouble() ?? 0,
        smsAutoReceive: json['smsAutoReceive'] as bool? ?? true,
        smsPollSeconds: (json['smsPollSeconds'] as num?)?.toInt() ?? 15,
        deleteSmsFromModem: json['deleteSmsFromModem'] as bool? ?? false,
        audioPort: json['audioPort'] as String? ?? '',
        closeToTray: json['closeToTray'] as bool? ?? true,
      );
}
