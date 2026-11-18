import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:serial_port_win32/serial_port_win32.dart';

import 'winmm_audio.dart';

/// Мост «модем ⇄ компьютер» для голосового вызова.
///
/// Huawei E173 с голосовой прошивкой отдаёт звук вызова как поток PCM
/// (8000 Гц, 16 бит, моно, кадры по 20 мс = 320 байт) через отдельный
/// COM-порт. Мост читает этот поток и выводит его на динамики, а звук
/// микрофона отправляет обратно в тот же порт.
class VoiceBridge {
  VoiceBridge({required this.portName, this.baudRate = 115200});

  final String portName;
  final int baudRate;

  SerialPort? _port;
  WaveOutPlayer? _player;
  WaveInRecorder? _recorder;
  Timer? _timer;
  bool _tickBusy = false;
  final List<Uint8List> _injected = [];

  bool muted = false;
  bool speakerOn = true;
  bool micAvailable = false;
  int rxBytes = 0;
  int txBytes = 0;
  String lastError = '';

  bool get isRunning => _timer != null;

  Future<void> start() async {
    if (isRunning) return;
    final port = SerialPort(
      portName,
      openNow: false,
      ByteSize: 8,
      BaudRate: baudRate,
    );
    port.open();
    if (!port.isOpened) {
      throw StateError('Не удалось открыть звуковой порт $portName.');
    }
    _port = port;
    rxBytes = 0;
    txBytes = 0;
    lastError = '';

    try {
      final player = WaveOutPlayer()..open();
      _player = player;
    } catch (error) {
      lastError = 'Динамики: $error';
    }
    try {
      final recorder = WaveInRecorder()..open();
      _recorder = recorder;
      micAvailable = true;
    } catch (error) {
      micAvailable = false;
      lastError = '$lastError Микрофон: $error'.trim();
    }
    _timer = Timer.periodic(const Duration(milliseconds: 20), (_) => _tick());
  }

  Future<void> _tick() async {
    if (_tickBusy) return;
    final port = _port;
    if (port == null) return;
    _tickBusy = true;
    try {
      final received = await port.readBytes(
        640,
        timeout: const Duration(milliseconds: 5),
      );
      if (received.isNotEmpty) {
        final data = Uint8List.fromList(received);
        rxBytes += data.length;
        if (speakerOn) _player?.write(data);
      }

      final micFrames = _recorder?.poll() ?? const <Uint8List>[];
      final outgoing = <Uint8List>[];
      if (_injected.isNotEmpty) {
        outgoing.add(_injected.removeAt(0));
      } else if (micFrames.isNotEmpty) {
        for (final frame in micFrames) {
          outgoing.add(muted ? Uint8List(frame.length) : frame);
        }
      } else if (_recorder == null) {
        outgoing.add(Uint8List(320)); // тишина, чтобы канал не простаивал
      }
      for (final frame in outgoing) {
        // dynamic: имя метода записи байтов зависит от версии serial_port_win32.
        await (port as dynamic).writeBytesFromUint8List(frame);
        txBytes += frame.length;
      }
    } catch (error) {
      lastError = '$error';
    } finally {
      _tickBusy = false;
    }
  }

  /// Отправляет в вызов готовый PCM (8 кГц, 16 бит, моно), например «да».
  void playPcm(Uint8List pcm) {
    for (var offset = 0; offset < pcm.length; offset += 320) {
      final end = offset + 320 < pcm.length ? offset + 320 : pcm.length;
      final frame = Uint8List(320);
      frame.setRange(0, end - offset, pcm, offset);
      _injected.add(frame);
    }
  }

  bool get isInjecting => _injected.isNotEmpty;

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    _injected.clear();
    try {
      _recorder?.close();
    } catch (_) {}
    try {
      _player?.close();
    } catch (_) {}
    _recorder = null;
    _player = null;
    final port = _port;
    _port = null;
    try {
      if (port != null && port.isOpened) port.close();
    } catch (_) {}
  }
}

/// Загрузка WAV-файла и приведение к PCM 8 кГц / 16 бит / моно.
class WavLoader {
  /// Упаковывает PCM (8000 Гц, 16 бит, моно) в WAV-файл.
  static Uint8List encode(Uint8List pcm) {
    final header = ByteData(44);
    void text(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        header.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    text(0, 'RIFF');
    header.setUint32(4, 36 + pcm.length, Endian.little);
    text(8, 'WAVE');
    text(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, 8000, Endian.little);
    header.setUint32(28, 16000, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    text(36, 'data');
    header.setUint32(40, pcm.length, Endian.little);
    final result = BytesBuilder(copy: false)
      ..add(header.buffer.asUint8List())
      ..add(pcm);
    return result.toBytes();
  }

  static Future<Uint8List> loadAs8kMono(String path) async {
    final bytes = await File(path).readAsBytes();
    return convert(bytes);
  }

  static Uint8List convert(Uint8List bytes) {
    final view = ByteData.sublistView(bytes);
    if (bytes.length < 44 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw StateError('Это не WAV-файл.');
    }
    var channels = 1;
    var sampleRate = 8000;
    var bits = 16;
    var format = 1;
    int? dataOffset;
    var dataLength = 0;
    var pos = 12;
    while (pos + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final size = view.getUint32(pos + 4, Endian.little);
      final body = pos + 8;
      if (id == 'fmt ' && body + 16 <= bytes.length) {
        format = view.getUint16(body, Endian.little);
        channels = view.getUint16(body + 2, Endian.little);
        sampleRate = view.getUint32(body + 4, Endian.little);
        bits = view.getUint16(body + 14, Endian.little);
      } else if (id == 'data') {
        dataOffset = body;
        dataLength = size;
        if (body + dataLength > bytes.length) {
          dataLength = bytes.length - body;
        }
        break;
      }
      pos = body + size + (size.isOdd ? 1 : 0);
    }
    if (dataOffset == null) throw StateError('В WAV-файле нет данных.');
    if (format != 1 || bits != 16) {
      throw StateError('Нужен несжатый WAV 16 бит (PCM).');
    }
    if (channels < 1) throw StateError('Неверное число каналов в WAV.');

    final frames = dataLength ~/ (2 * channels);
    final mono = List<int>.filled(frames, 0);
    for (var i = 0; i < frames; i++) {
      var sum = 0;
      for (var c = 0; c < channels; c++) {
        sum += view.getInt16(dataOffset + (i * channels + c) * 2, Endian.little);
      }
      mono[i] = sum ~/ channels;
    }

    final outLength = (frames * 8000 / sampleRate).floor();
    final out = Uint8List(outLength * 2);
    final outView = ByteData.sublistView(out);
    for (var i = 0; i < outLength; i++) {
      final source = i * sampleRate / 8000;
      final index = source.floor();
      final fraction = source - index;
      final a = mono[index < frames ? index : frames - 1];
      final b = mono[index + 1 < frames ? index + 1 : frames - 1];
      final value = (a + (b - a) * fraction).round();
      outView.setInt16(i * 2, value.clamp(-32768, 32767).toInt(), Endian.little);
    }
    return out;
  }
}
