import 'dart:async';
import 'dart:convert';

import 'package:serial_port_win32/serial_port_win32.dart';

import '../models/modem_info.dart';
import '../models/call_info.dart';
import 'sms_pdu.dart';
import 'ussd_codec.dart';

class ModemService {
  SerialPort? _port;
  String? _portName;
  bool _busy = false;

  // Нештатные сообщения модема (URC), замеченные при чтении порта.
  bool _smsHint = false;
  int smsHintCount = 0;
  bool _ringing = false;
  String _incomingNumber = '';
  bool _callEndedHint = false;

  bool get isConnected => _port?.isOpened ?? false;

  /// Модем сообщил (+CMTI) о новом SMS.
  bool takeSmsHint() {
    final value = _smsHint;
    _smsHint = false;
    return value;
  }

  bool get isRinging => _ringing;
  String get incomingNumber => _incomingNumber;

  bool takeCallEndedHint() {
    final value = _callEndedHint;
    _callEndedHint = false;
    return value;
  }

  void clearRinging() {
    _ringing = false;
    _incomingNumber = '';
  }

  /// Быстрый список имён COM-портов (без обращения к SetupAPI).
  List<String> quickPortNames() {
    try {
      return SerialPort.getAvailablePorts();
    } catch (_) {
      return const [];
    }
  }

  /// Пока порт модема есть в системе. При ошибке опроса считаем, что есть.
  bool isPortPresent() {
    final name = _portName;
    if (name == null) return false;
    try {
      return SerialPort.getAvailablePorts().contains(name);
    } catch (_) {
      return true;
    }
  }

  /// Мгновенно «отпускает» порт после извлечения модема из USB.
  /// Все ожидающие операции получают ошибку и завершаются.
  void forceDisconnect() {
    final current = _port;
    _port = null;
    _portName = null;
    _busy = false;
    _ringing = false;
    _incomingNumber = '';
    if (current != null) {
      try {
        if (current.isOpened) current.close();
      } catch (_) {
        // Порт уже недоступен.
      }
    }
  }
  bool get isBusy => _busy;
  String? get connectedPort => _portName;

  List<ModemPortInfo> listPorts() {
    final result = <String, ModemPortInfo>{};
    try {
      for (final name in SerialPort.getAvailablePorts()) {
        result[name] = ModemPortInfo(name: name);
      }
    } catch (_) {
      // The basic port list remains useful even when device metadata fails.
    }
    try {
      for (final info in SerialPort.getPortsWithFullMessages()) {
        result[info.portName] = ModemPortInfo(
          name: info.portName,
          friendlyName: info.friendlyName,
          hardwareId: info.hardwareID,
          manufacturer: info.manufactureName,
        );
      }
    } catch (_) {
      // Some Windows driver stacks expose COM ports but not SetupAPI metadata.
    }
    final ports = result.values.toList();
    ports.sort((a, b) {
      final role = a.autoConnectPriority.compareTo(b.autoConnectPriority);
      if (role != 0) return role;
      return _compareComNames(a.name, b.name);
    });
    return ports;
  }

  Future<ModemPortInfo?> autoConnect({
    int baudRate = 115200,
    String preferredPort = '',
  }) async {
    if (isConnected) {
      return ModemPortInfo(name: _portName ?? '', friendlyName: 'Уже подключён');
    }
    final ports = listPorts();
    // Port role is more important than a previously saved generic port:
    // E173's PC UI interface (COM22 in the user's setup) must be tried before
    // the modem/application interfaces. Within the same role, keep the saved
    // preference first.
    ports.sort((a, b) {
      final role = a.autoConnectPriority.compareTo(b.autoConnectPriority);
      if (role != 0) return role;
      if (preferredPort.isNotEmpty) {
        if (a.name == preferredPort) return -1;
        if (b.name == preferredPort) return 1;
      }
      return _compareComNames(a.name, b.name);
    });
    for (final candidate in ports) {
      try {
        final recognized = await connectToPort(
          candidate.name,
          baudRate: baudRate,
          verifyHuawei: true,
        );
        if (recognized) return candidate;
      } catch (_) {
        await disconnect();
      }
    }
    return null;
  }

  Future<bool> connectToPort(
    String portName, {
    int baudRate = 115200,
    bool verifyHuawei = true,
  }) async {
    await disconnect();
    final port = SerialPort(
      portName,
      openNow: false,
      ByteSize: 8,
      BaudRate: baudRate,
    );
    port.open();
    if (!port.isOpened) {
      throw StateError('Не удалось открыть $portName. Возможно, порт занят.');
    }
    _port = port;
    _portName = portName;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final answer = await _writeAndRead('AT', timeout: const Duration(seconds: 3));
    if (!answer.toUpperCase().contains('OK')) {
      await disconnect();
      if (verifyHuawei) return false;
      throw StateError('Порт $portName не отвечает на AT-команды.');
    }
    await _writeAndRead('ATE0', timeout: const Duration(seconds: 2));
    await _writeAndRead('AT+CMEE=2', timeout: const Duration(seconds: 2));
    final identity = await _writeAndRead('ATI', timeout: const Duration(seconds: 3));
    final isHuawei = identity.toLowerCase().contains('huawei') ||
        identity.toLowerCase().contains('e173') ||
        !verifyHuawei;
    if (verifyHuawei && !isHuawei) {
      await disconnect();
      return false;
    }
    return true;
  }

  Future<void> disconnect() async {
    final current = _port;
    _port = null;
    _portName = null;
    if (current != null && current.isOpened) {
      try {
        current.close();
      } catch (_) {
        // Ignore close errors after USB removal.
      }
    }
  }

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    _ensureConnected();
    if (_busy) throw StateError('Модем занят другой операцией.');
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }

  /// Диагностика приёма SMS: настройки модема и состояние памяти.
  Future<String> smsDiagnostics() => _exclusive(() async {
        final buffer = StringBuffer();
        for (final command in const [
          'AT+CMGF?',
          'AT+CNMI?',
          'AT+CPMS?',
          'AT+CSCA?',
          'AT+CREG?',
          'AT+CSQ',
        ]) {
          try {
            final answer = await _writeAndRead(command,
                timeout: const Duration(seconds: 4));
            buffer.writeln('> $command');
            buffer.writeln(answer.trim());
          } catch (error) {
            buffer.writeln('> $command');
            buffer.writeln('ОШИБКА: $error');
          }
        }
        return buffer.toString();
      });

  Future<String> sendAt(
    String command, {
    Duration timeout = const Duration(seconds: 5),
  }) =>
      _exclusive(() => _writeAndRead(command, timeout: timeout));

  Future<String> _writeAndRead(
    String command, {
    Duration timeout = const Duration(seconds: 5),
    bool waitForUssd = false,
    bool waitForPrompt = false,
  }) async {
    _ensureConnected();
    final port = _port!;
    await _drainInput();
    await port.writeBytesFromString(
      '$command\r',
      includeZeroTerminator: false,
      stringConverter: StringConverter.nativeUtf8,
    );
    return _readResponse(
      timeout: timeout,
      waitForUssd: waitForUssd,
      waitForPrompt: waitForPrompt,
    );
  }

  Future<String> _readResponse({
    required Duration timeout,
    bool waitForUssd = false,
    bool waitForPrompt = false,
    bool waitForSmsAck = false,
  }) async {
    final port = _port!;
    final stopwatch = Stopwatch()..start();
    final buffer = StringBuffer();
    var quietAfterData = 0;
    while (stopwatch.elapsed < timeout) {
      if (_port == null) throw StateError('Модем отключён.');
      final remaining = timeout - stopwatch.elapsed;
      final waitMs = remaining.inMilliseconds.clamp(30, 220).toInt();
      final bytes = await port.readBytes(
        512,
        timeout: Duration(milliseconds: waitMs),
      );
      if (bytes.isNotEmpty) {
        final chunk = latin1.decode(bytes, allowInvalid: true);
        _scanUrc(chunk);
        buffer.write(chunk);
        quietAfterData = 0;
      } else if (buffer.isNotEmpty) {
        quietAfterData++;
      }
      final result = buffer.toString();
      final upper = result.toUpperCase();
      if (waitForPrompt && result.contains('>')) break;
      if (waitForSmsAck) {
        // Подтверждение отправки приходит как "+CMGS: N" и "OK" спустя секунды;
        // служебные строки (^RSSI и т. п.) игнорируем.
        if (_isModemError(result) || upper.contains('+CMS ERROR')) break;
        if (upper.contains('+CMGS:') &&
            (upper.contains('OK') || quietAfterData >= 3)) {
          break;
        }
        continue;
      }
      if (waitForUssd) {
        if (upper.contains('+CUSD:') || _isModemError(result)) {
          // Wait for a brief quiet period to allow the rest of a multiline reply.
          if (quietAfterData >= 2) break;
        }
      } else if (upper.contains('\nOK') ||
          upper.trim().endsWith('OK') ||
          upper.contains('ERROR') ||
          upper.contains('+CME ERROR') ||
          upper.contains('+CMS ERROR')) {
        if (quietAfterData >= 1) break;
      }
      if (!waitForUssd && !waitForPrompt &&
          quietAfterData >= 3 && buffer.isNotEmpty) {
        break;
      }
    }
    return buffer.toString().trim();
  }

  Future<void> _drainInput() async {
    final port = _port;
    if (port == null || !port.isOpened) return;
    for (var i = 0; i < 3; i++) {
      try {
        final bytes = await port.readBytes(
          512,
          timeout: const Duration(milliseconds: 30),
        );
        if (bytes.isEmpty) break;
        _scanUrc(latin1.decode(bytes, allowInvalid: true));
      } catch (_) {
        break;
      }
    }
  }

  Future<ModemInfo> readModemInfo() => _exclusive(() async {
    final ati = await _writeAndRead('ATI');
    final modelResponse = await _writeAndRead('AT+CGMM');
    final imeiResponse = await _writeAndRead('AT+CGSN');
    final cpin = await _writeAndRead('AT+CPIN?');
    final creg = await _writeAndRead('AT+CREG?');
    final cops = await _writeAndRead('AT+COPS?');
    final csq = await _writeAndRead('AT+CSQ');
    final signalMatch = RegExp(r'\+CSQ:\s*(\d+)').firstMatch(csq);
    final signal = int.tryParse(signalMatch?.group(1) ?? '') ?? 99;
    final signalPercent = signal == 99 ? 0 : ((signal / 31) * 100).round();
    final dbm = signal == 99 ? null : -113 + (2 * signal);
    final registered = RegExp(r'\+CREG:\s*\d+\s*,\s*[15]').hasMatch(creg);
    final operatorMatch = RegExp(r'\+COPS:\s*\d+\s*,\s*\d+\s*,\s*"([^"]+)"')
        .firstMatch(cops);
    final cpinReady = cpin.toUpperCase().contains('READY');
    final model = _firstUsefulLine(modelResponse) ??
        _firstUsefulLine(ati) ??
        'Huawei E173 / совместимый модем';
    final imei = RegExp(r'\b\d{15}\b').firstMatch(imeiResponse)?.group(0) ?? '';
    return ModemInfo(
      port: _portName ?? '',
      model: model,
      imei: imei,
      firmware: _extractFirmware(ati),
      operatorName: operatorMatch?.group(1) ?? '',
      registration: registered ? 'Зарегистрирован в сети' : 'Нет регистрации',
      signalPercent: signalPercent,
      signalDbm: dbm,
      simStatus: cpinReady ? 'SIM готова' : _friendlySimStatus(cpin),
      networkType: 'GSM/UMTS (точный режим не определён)',
      connected: true,
    );
  });

  Future<bool> isNetworkRegistered() => _exclusive(() async {
    final cpin = await _writeAndRead('AT+CPIN?');
    if (!cpin.toUpperCase().contains('READY')) return false;
    final registration = await _writeAndRead('AT+CREG?');
    return RegExp(r'\+CREG:\s*\d+\s*,\s*[15]').hasMatch(registration);
  });

  Future<bool> waitForNetwork({
    required Duration timeout,
    void Function(String message)? onProgress,
  }) => _exclusive(() async {
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < timeout) {
      try {
        final cpin = await _writeAndRead('AT+CPIN?', timeout: const Duration(seconds: 3));
        if (!cpin.toUpperCase().contains('READY')) {
          onProgress?.call('Ожидание готовности SIM-карты…');
        } else {
          final creg = await _writeAndRead('AT+CREG?', timeout: const Duration(seconds: 3));
          if (RegExp(r'\+CREG:\s*\d+\s*,\s*[15]').hasMatch(creg)) {
            return true;
          }
          onProgress?.call('SIM готова. Ожидание регистрации в сети…');
        }
      } catch (error) {
        onProgress?.call('Проверка сети: $error');
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    return false;
  });

  static bool _isModemError(String response) {
    final upper = response.toUpperCase();
    return upper.contains('+CME ERROR') ||
        RegExp(r'^\s*ERROR\s*$', multiLine: true).hasMatch(upper);
  }

  Future<String> sendUssd(
    String code, {
    int dcs = 15,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    _ensureConnected();
    if (_busy) throw StateError('Модем занят другой операцией.');
    if (code.trim().isEmpty) throw ArgumentError('USSD-код не задан.');
    _busy = true;
    try {
      final plain = code.trim().replaceAll('"', '');

      // Закрываем возможную «зависшую» USSD-сессию, иначе E173 отвечает ERROR
      // или молча игнорирует новый запрос.
      await _writeAndRead('AT+CUSD=2', timeout: const Duration(seconds: 3));
      // Стандартный набор символов GSM для строки запроса.
      await _writeAndRead('AT+CSCS="GSM"', timeout: const Duration(seconds: 3));

      // Варианты запроса: сначала обычный текст, затем 7-bit hex (формат,
      // который E173 чаще всего ожидает), затем UCS-2 hex.
      final attempts = <String>[
        'AT+CUSD=1,"$plain",$dcs',
        if (dcs != 15) 'AT+CUSD=1,"$plain",15',
      ];
      try {
        attempts.add('AT+CUSD=1,"${UssdCodec.encodeGsm7PackedHex(plain)}",15');
      } catch (_) {
        // Код с нестандартными символами — hex-вариант пропускаем.
      }

      final errors = <String>[];
      for (final command in attempts) {
        final response = await _writeAndRead(
          command,
          timeout: timeout,
          waitForUssd: true,
        );
        if (response.contains('+CUSD:')) {
          final decoded = UssdCodec.decodeHuaweiResponse(response);
          if (decoded.startsWith('Ошибка USSD')) {
            errors.add('$command → $response');
            // Сеть ответила — повторять в другом формате бессмысленно.
            throw StateError('$decoded\nОтвет модема: $response');
          }
          return decoded;
        }
        if (_isModemError(response)) {
          errors.add('$command → $response');
          await _writeAndRead('AT+CUSD=2', timeout: const Duration(seconds: 3));
          continue; // пробуем следующий формат
        }
        if (response.isEmpty) {
          throw StateError(
              'Модем не ответил на USSD за ${timeout.inSeconds} с (порт ${_portName ?? '?'}). '
              'Если это порт «Modem» — переключитесь на «3G PC UI Interface».');
        }
        throw StateError(
            'Модем принял команду, но сеть не прислала +CUSD за ${timeout.inSeconds} с.\n'
            'Порт: ${_portName ?? 'неизвестно'}. Ответ: $response\n'
            'Ответ мог прийти на другой COM-порт модема — попробуйте другой порт.');
      }
      throw StateError('Модем отклонил все варианты AT+CUSD на порту ${_portName ?? 'неизвестно'}:\n'
          '${errors.join('\n')}');
    } finally {
      _busy = false;
    }
  }

  Future<String> sendSms({
    required String recipient,
    required String message,
    bool requestStatusReport = true,
  }) async {
    _ensureConnected();
    if (_busy) throw StateError('Модем занят другой операцией.');
    _busy = true;
    try {
      final modeResponse = await _writeAndRead('AT+CMGF=0', timeout: const Duration(seconds: 3));
      if (modeResponse.toUpperCase().contains('ERROR')) {
        throw StateError('Модем не переключился в PDU-режим SMS: $modeResponse');
      }
      final segments = SmsPduEncoder.encodeUcs2(
        recipient: recipient,
        message: message,
        requestStatusReport: requestStatusReport,
        reference: DateTime.now().millisecondsSinceEpoch & 0xFF,
      );
      final confirmations = <String>[];
      for (final segment in segments) {
        final prompt = await _writeAndRead(
          'AT+CMGS=${segment.tpduLength}',
          timeout: const Duration(seconds: 10),
          waitForPrompt: true,
        );
        if (!prompt.contains('>')) {
          throw StateError('Модем не выдал приглашение для SMS: $prompt');
        }
        await _port!.writeBytesFromString(
          '${segment.pdu}\x1A',
          includeZeroTerminator: false,
          stringConverter: StringConverter.nativeUtf8,
        );
        final response = await _readResponse(
          timeout: const Duration(seconds: 40),
          waitForSmsAck: true,
        );
        if (!response.toUpperCase().contains('+CMGS:') ||
            _isModemError(response) ||
            response.toUpperCase().contains('+CMS ERROR')) {
          throw StateError('Ошибка отправки SMS: $response');
        }
        confirmations.add(response);
      }
      return confirmations.join('\n');
    } finally {
      _busy = false;
    }
  }

  /// Читает все SMS из памяти модема (SIM и память модема) в PDU-режиме.
  Future<List<RawSms>> readSmsPdu() => _exclusive(() async {
    final result = <RawSms>[];
    final mode = await _writeAndRead('AT+CMGF=0');
    if (_isModemError(mode)) {
      throw StateError('Модем не поддержал PDU-режим SMS.');
    }
    for (final storage in const ['SM', 'ME']) {
      final select = await _writeAndRead(
        'AT+CPMS="$storage"',
        timeout: const Duration(seconds: 5),
      );
      if (!select.toUpperCase().contains('+CPMS:')) continue;
      final response = await _writeAndRead(
        'AT+CMGL=4',
        timeout: const Duration(seconds: 25),
      );
      final lines = response.split(RegExp(r'\r?\n'));
      for (var i = 0; i < lines.length; i++) {
        final header =
            RegExp(r'^\+CMGL:\s*(\d+)\s*,\s*(\d+)').firstMatch(lines[i].trim());
        if (header == null) continue;
        var j = i + 1;
        while (j < lines.length && lines[j].trim().isEmpty) {
          j++;
        }
        if (j >= lines.length) break;
        final pdu = lines[j].trim();
        if (!RegExp(r'^[0-9A-Fa-f]+$').hasMatch(pdu)) continue;
        result.add(RawSms(
          storage: storage,
          index: int.tryParse(header.group(1) ?? '') ?? 0,
          stat: int.tryParse(header.group(2) ?? '') ?? 1,
          pdu: pdu,
        ));
        i = j;
      }
    }
    // Возвращаем память по умолчанию.
    await _writeAndRead('AT+CPMS="SM"', timeout: const Duration(seconds: 3));
    return result;
  });

  /// Удаляет SMS из памяти модема. [ref] имеет вид "SM:3".
  Future<void> deleteSmsFromModem(Iterable<String> refs) => _exclusive(() async {
    for (final ref in refs) {
      final parts = ref.split(':');
      if (parts.length != 2) continue;
      await _writeAndRead('AT+CPMS="${parts[0]}"', timeout: const Duration(seconds: 3));
      await _writeAndRead('AT+CMGD=${parts[1]}', timeout: const Duration(seconds: 5));
    }
    await _writeAndRead('AT+CPMS="SM"', timeout: const Duration(seconds: 3));
  });

  Future<String> readContacts({int first = 1, int last = 250}) => _exclusive(() async {
    await _writeAndRead('AT+CPBS="SM"');
    return _writeAndRead('AT+CPBR=$first,$last', timeout: const Duration(seconds: 20));
  });

  Future<String> writeContact({
    required int index,
    required String number,
    required String name,
  }) async {
    if (index < 1 || index > 250) {
      throw ArgumentError('Номер ячейки SIM должен быть от 1 до 250.');
    }
    if (number.trim().isEmpty) {
      throw ArgumentError('Введите номер контакта.');
    }
    final trimmedNumber = number.trim();
    final safeNumber = trimmedNumber.startsWith('+')
        ? '+${trimmedNumber.substring(1).replaceAll(RegExp(r'\D'), '')}'
        : trimmedNumber.replaceAll(RegExp(r'\D'), '');
    final typeOfAddress = safeNumber.startsWith('+') ? 145 : 129;
    final safeName = name.replaceAll('\"', '').replaceAll('\r', ' ').replaceAll('\n', ' ');
    return _exclusive(() async {
      await _writeAndRead('AT+CPBS="SM"');
      return _writeAndRead('AT+CPBW=$index,\"$safeNumber\",$typeOfAddress,\"$safeName\"',
          timeout: const Duration(seconds: 10));
    });
  }

  Future<String> deleteContact(int index) async {
    if (index < 1 || index > 250) {
      throw ArgumentError('Номер ячейки SIM должен быть от 1 до 250.');
    }
    return _exclusive(() async {
      await _writeAndRead('AT+CPBS="SM"');
      return _writeAndRead('AT+CPBW=$index');
    });
  }

  /// Подготовка модема: уведомления о SMS, АОН, голос. Ошибки игнорируются.
  Future<String> prepareFeatures() => _exclusive(() async {
    final log = StringBuffer();
    Future<void> run(String command) async {
      try {
        final answer =
            await _writeAndRead(command, timeout: const Duration(seconds: 3));
        log.writeln('$command → ${answer.replaceAll(RegExp(r'\s+'), ' ')}');
      } catch (error) {
        log.writeln('$command → $error');
      }
    }

    await run('AT+CMGF=0');
    await run('AT+CNMI=2,1,0,0,0');
    await run('AT+CLIP=1');
    await run('AT+CRC=1');
    await run('AT^CVOICE?');
    return log.toString().trim();
  });

  /// Включает голосовой режим (PCM по USB), если он выключен.
  Future<String> enableVoice() => _exclusive(() async {
    final state = await _writeAndRead('AT^CVOICE?', timeout: const Duration(seconds: 3));
    if (RegExp(r'\^CVOICE:\s*0').hasMatch(state)) return state;
    final answer = await _writeAndRead('AT^CVOICE=0', timeout: const Duration(seconds: 3));
    return '$state\n$answer';
  });

  static String _cleanDialString(String value) =>
      value.replaceAll(RegExp(r'[^0-9+*#pPwW,]'), '');

  /// Набирает номер (голосовой вызов).
  Future<String> dial(String number) async {
    final clean = _cleanDialString(number);
    if (clean.isEmpty) throw ArgumentError('Введите номер телефона.');
    final answer = await sendAt('ATD$clean;', timeout: const Duration(seconds: 10));
    if (_isModemError(answer)) {
      throw StateError('Модем не смог начать вызов: $answer');
    }
    return answer;
  }

  /// Направляет звук вызова в USB (PCM по отдельному COM-порту).
  Future<String> routeAudioToUsb() =>
      sendAt('AT^DDSETEX=2', timeout: const Duration(seconds: 3));

  Future<String> hangUp() async {
    final first = await sendAt('ATH', timeout: const Duration(seconds: 5));
    if (_isModemError(first)) {
      return sendAt('AT+CHUP', timeout: const Duration(seconds: 5));
    }
    return first;
  }

  Future<String> answerCall() =>
      sendAt('ATA', timeout: const Duration(seconds: 8));

  /// Отправляет DTMF-цифры во время разговора.
  Future<String> sendDtmf(String digits) => _exclusive(() async {
    final out = StringBuffer();
    for (final rune in digits.runes) {
      final ch = String.fromCharCode(rune);
      if (!RegExp(r'^[0-9*#A-Da-d]$').hasMatch(ch)) continue;
      final answer = await _writeAndRead('AT+VTS=$ch', timeout: const Duration(seconds: 3));
      out.writeln('$ch → ${answer.replaceAll(RegExp(r'\s+'), ' ')}');
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return out.toString().trim();
  });

  Future<String> listCalls() =>
      sendAt('AT+CLCC', timeout: const Duration(seconds: 5));

  Future<List<CallLine>> currentCalls() async =>
      CallLine.parse(await listCalls());

  /// Идентификатор SIM-карты: ICCID, иначе IMSI.
  Future<String> readSimId() => _exclusive(() async {
    for (final command in const ['AT+CCID', 'AT^ICCID?', 'AT+CIMI']) {
      try {
        final answer = await _writeAndRead(command, timeout: const Duration(seconds: 3));
        if (_isModemError(answer)) continue;
        final match = RegExp(r'\d{15,22}').firstMatch(answer);
        if (match != null) return match.group(0)!;
      } catch (_) {
        // пробуем следующую команду
      }
    }
    return '';
  });

  /// Считывает «лишние» данные порта, чтобы заметить RING / +CMTI в простое.
  Future<void> pollUrc() async {
    if (!isConnected || _busy) return;
    _busy = true;
    try {
      final port = _port;
      if (port == null) return;
      final bytes = await port.readBytes(
        512,
        timeout: const Duration(milliseconds: 40),
      );
      if (bytes.isNotEmpty) _scanUrc(latin1.decode(bytes, allowInvalid: true));
    } finally {
      _busy = false;
    }
  }

  void _scanUrc(String chunk) {
    final upper = chunk.toUpperCase();
    if (upper.contains('+CMTI:')) {
      _smsHint = true;
      smsHintCount++;
    }
    if (RegExp(r'(^|\n)\s*RING').hasMatch(upper) || upper.contains('+CLIP:')) {
      _ringing = true;
    }
    final clip = RegExp(r'\+CLIP:\s*"([^"]*)"', caseSensitive: false).firstMatch(chunk);
    if (clip != null) _incomingNumber = clip.group(1) ?? '';
    if (upper.contains('^CEND') || upper.contains('NO CARRIER')) {
      _callEndedHint = true;
      _ringing = false;
    }
  }

  String? _firstUsefulLine(String text) {
    for (final line in text.split(RegExp(r'\r?\n'))) {
      final clean = line.trim();
      if (clean.isEmpty ||
          clean.toUpperCase() == 'OK' ||
          clean.toUpperCase() == 'ATI' ||
          clean.toUpperCase() == 'AT+CGMM' ||
          clean.startsWith('AT')) {
        continue;
      }
      return clean;
    }
    return null;
  }

  String _extractFirmware(String text) {
    final match = RegExp(r'(Revision|Firmware|Ver(?:sion)?)[^\r\n]*',
            caseSensitive: false)
        .firstMatch(text);
    return match?.group(0)?.trim() ?? '';
  }

  String _friendlySimStatus(String response) {
    if (response.toUpperCase().contains('SIM PIN')) return 'Требуется PIN-код';
    if (response.toUpperCase().contains('SIM PUK')) return 'Требуется PUK-код';
    if (response.toUpperCase().contains('NOT INSERTED')) return 'SIM не обнаружена';
    return response.trim().isEmpty ? 'Нет ответа' : response.trim();
  }

  int _compareComNames(String a, String b) {
    final aNumber = int.tryParse(RegExp(r'COM(\d+)', caseSensitive: false)
            .firstMatch(a)?.group(1) ?? '');
    final bNumber = int.tryParse(RegExp(r'COM(\d+)', caseSensitive: false)
            .firstMatch(b)?.group(1) ?? '');
    if (aNumber != null && bNumber != null) return aNumber.compareTo(bNumber);
    return a.compareTo(b);
  }

  void _ensureConnected() {
    if (!isConnected) {
      throw StateError('Модем не подключён. Проверьте USB и COM-порт.');
    }
  }
}
