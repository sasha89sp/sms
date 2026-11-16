import 'dart:async';
import 'dart:convert';

import 'package:serial_port_win32/serial_port_win32.dart';

import '../models/modem_info.dart';
import '../models/sms_item.dart';
import 'sms_pdu.dart';
import 'ussd_codec.dart';

class ModemService {
  SerialPort? _port;
  String? _portName;
  bool _busy = false;

  bool get isConnected => _port?.isOpened ?? false;
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
      if (a.looksLikeHuawei != b.looksLikeHuawei) {
        return a.looksLikeHuawei ? -1 : 1;
      }
      return a.name.compareTo(b.name);
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
    if (preferredPort.isNotEmpty) {
      ports.sort((a, b) {
        if (a.name == preferredPort) return -1;
        if (b.name == preferredPort) return 1;
        if (a.looksLikeHuawei != b.looksLikeHuawei) {
          return a.looksLikeHuawei ? -1 : 1;
        }
        return a.name.compareTo(b.name);
      });
    }
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
  }) async {
    final port = _port!;
    final stopwatch = Stopwatch()..start();
    final buffer = StringBuffer();
    var quietAfterData = 0;
    while (stopwatch.elapsed < timeout) {
      final remaining = timeout - stopwatch.elapsed;
      final waitMs = remaining.inMilliseconds.clamp(30, 220).toInt();
      final bytes = await port.readBytes(
        512,
        timeout: Duration(milliseconds: waitMs),
      );
      if (bytes.isNotEmpty) {
        buffer.write(latin1.decode(bytes, allowInvalid: true));
        quietAfterData = 0;
      } else if (buffer.isNotEmpty) {
        quietAfterData++;
      }
      final result = buffer.toString();
      final upper = result.toUpperCase();
      if (waitForPrompt && result.contains('>')) break;
      if (waitForUssd) {
        if (upper.contains('+CUSD:') ||
            upper.contains('+CME ERROR') ||
            upper.contains('ERROR')) {
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
      final escaped = code.trim().replaceAll('"', '');
      final response = await _writeAndRead(
        'AT+CUSD=1,"$escaped",$dcs',
        timeout: timeout,
        waitForUssd: true,
      );
      if (response.isEmpty || response.toUpperCase().contains('ERROR')) {
        throw StateError('Сеть не вернула ответ USSD. Ответ модема: $response');
      }
      final decoded = UssdCodec.decodeHuaweiResponse(response);
      if (decoded.startsWith('Ошибка USSD')) throw StateError(decoded);
      if (decoded == response && !response.contains('+CUSD:')) return response;
      return decoded;
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
          timeout: const Duration(seconds: 35),
        );
        if (!response.toUpperCase().contains('+CMGS:') ||
            response.toUpperCase().contains('ERROR')) {
          throw StateError('Ошибка отправки SMS: $response');
        }
        confirmations.add(response);
      }
      return confirmations.join('\n');
    } finally {
      _busy = false;
    }
  }

  Future<List<SmsItem>> readSms() => _exclusive(() async {
    final mode = await _writeAndRead('AT+CMGF=1');
    if (mode.toUpperCase().contains('ERROR')) {
      throw StateError('Модем не поддержал текстовый режим чтения SMS.');
    }
    final response = await _writeAndRead(
      'AT+CMGL="ALL"',
      timeout: const Duration(seconds: 25),
    );
    final items = <SmsItem>[];
    final lines = response.split(RegExp(r'\r?\n'));
    for (var i = 0; i < lines.length; i++) {
      final header = RegExp(
        r'^\+CMGL:\s*(\d+)\s*,\s*"([^"]*)"\s*,\s*"?([^",]*)"?(?:,.*)?$',
      ).firstMatch(lines[i].trim());
      if (header == null) continue;
      final body = i + 1 < lines.length ? lines[i + 1].trim() : '';
      final timestamp = RegExp(r'\d{2}/\d{2}/\d{2},\d{2}:\d{2}:\d{2}(?:[+-]\d{2})?')
          .firstMatch(lines[i])
          ?.group(0) ?? '';
      items.add(SmsItem(
        index: int.tryParse(header.group(1) ?? '') ?? 0,
        status: header.group(2) ?? '',
        sender: header.group(3) ?? '',
        timestamp: timestamp,
        body: body,
      ));
    }
    return items;
  });

  Future<String> deleteSms(int index) => sendAt('AT+CMGD=$index');

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

  Future<String> dial(String number) async {
    if (number.trim().isEmpty) throw ArgumentError('Введите номер телефона.');
    return sendAt('ATD${number.trim()};', timeout: const Duration(seconds: 8));
  }

  Future<String> hangUp() => sendAt('ATH', timeout: const Duration(seconds: 5));

  Future<String> listCalls() =>
      sendAt('AT+CLCC', timeout: const Duration(seconds: 5));


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

  void _ensureConnected() {
    if (!isConnected) {
      throw StateError('Модем не подключён. Проверьте USB и COM-порт.');
    }
  }
}
