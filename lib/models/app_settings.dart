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
  });

  final String preferredPort;
  final int baudRate;
  final String numberUssd;
  final String balanceUssd;
  final String smsRecipient;
  final String smsText;
  final int ussdDcs;
  final bool autoStart;
  final bool autoConnect;
  final int networkWaitSeconds;
  final int ussdTimeoutSeconds;
  final int retryCount;
  final bool smsRequireNetworkAck;

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
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        preferredPort: json['preferredPort'] as String? ?? '',
        baudRate: json['baudRate'] as int? ?? 115200,
        numberUssd: json['numberUssd'] as String? ?? '',
        balanceUssd: json['balanceUssd'] as String? ?? '*100#',
        smsRecipient: json['smsRecipient'] as String? ?? '',
        smsText: json['smsText'] as String? ?? '',
        ussdDcs: json['ussdDcs'] as int? ?? 15,
        autoStart: json['autoStart'] as bool? ?? false,
        autoConnect: json['autoConnect'] as bool? ?? true,
        networkWaitSeconds: json['networkWaitSeconds'] as int? ?? 180,
        ussdTimeoutSeconds: json['ussdTimeoutSeconds'] as int? ?? 45,
        retryCount: json['retryCount'] as int? ?? 1,
        smsRequireNetworkAck:
            json['smsRequireNetworkAck'] as bool? ?? false,
      );
}
