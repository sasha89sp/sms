class ModemInfo {
  const ModemInfo({
    this.port = '',
    this.model = 'Не определён',
    this.manufacturer = 'Huawei',
    this.imei = '',
    this.firmware = '',
    this.operatorName = '',
    this.registration = 'Неизвестно',
    this.signalPercent = 0,
    this.signalDbm,
    this.simStatus = 'Не проверена',
    this.networkType = 'Неизвестно',
    this.connected = false,
  });

  final String port;
  final String model;
  final String manufacturer;
  final String imei;
  final String firmware;
  final String operatorName;
  final String registration;
  final int signalPercent;
  final int? signalDbm;
  final String simStatus;
  final String networkType;
  final bool connected;

  ModemInfo copyWith({
    String? port,
    String? model,
    String? manufacturer,
    String? imei,
    String? firmware,
    String? operatorName,
    String? registration,
    int? signalPercent,
    int? signalDbm,
    String? simStatus,
    String? networkType,
    bool? connected,
  }) =>
      ModemInfo(
        port: port ?? this.port,
        model: model ?? this.model,
        manufacturer: manufacturer ?? this.manufacturer,
        imei: imei ?? this.imei,
        firmware: firmware ?? this.firmware,
        operatorName: operatorName ?? this.operatorName,
        registration: registration ?? this.registration,
        signalPercent: signalPercent ?? this.signalPercent,
        signalDbm: signalDbm ?? this.signalDbm,
        simStatus: simStatus ?? this.simStatus,
        networkType: networkType ?? this.networkType,
        connected: connected ?? this.connected,
      );
}

class ModemPortInfo {
  const ModemPortInfo({
    required this.name,
    this.friendlyName = '',
    this.hardwareId = '',
    this.manufacturer = '',
  });

  final String name;
  final String friendlyName;
  final String hardwareId;
  final String manufacturer;

  bool get looksLikeHuawei =>
      '$friendlyName $hardwareId $manufacturer'.toLowerCase().contains('huawei') ||
      hardwareId.toUpperCase().contains('VID_12D1');
}
