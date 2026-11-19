import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Воспроизведение и запись звука через winmm.dll (без внешних плагинов).
/// Формат: PCM, 8000 Гц, 16 бит, моно — как выдаёт голосовой канал Huawei.

const int _waveMapper = 0xFFFFFFFF;
const int _whdrDone = 0x00000001;

typedef _OpenNative = Uint32 Function(Pointer<IntPtr> handle, Uint32 device,
    Pointer<Uint8> format, IntPtr callback, IntPtr instance, Uint32 flags);
typedef _OpenDart = int Function(Pointer<IntPtr> handle, int device,
    Pointer<Uint8> format, int callback, int instance, int flags);

typedef _HeaderNative = Uint32 Function(
    IntPtr handle, Pointer<Uint8> header, Uint32 size);
typedef _HeaderDart = int Function(int handle, Pointer<Uint8> header, int size);

typedef _HandleNative = Uint32 Function(IntPtr handle);
typedef _HandleDart = int Function(int handle);

class _Winmm {
  _Winmm._() {
    final lib = DynamicLibrary.open('winmm.dll');
    waveOutOpen = lib.lookupFunction<_OpenNative, _OpenDart>('waveOutOpen');
    waveOutPrepare =
        lib.lookupFunction<_HeaderNative, _HeaderDart>('waveOutPrepareHeader');
    waveOutUnprepare = lib
        .lookupFunction<_HeaderNative, _HeaderDart>('waveOutUnprepareHeader');
    waveOutWrite = lib.lookupFunction<_HeaderNative, _HeaderDart>('waveOutWrite');
    waveOutReset = lib.lookupFunction<_HandleNative, _HandleDart>('waveOutReset');
    waveOutClose = lib.lookupFunction<_HandleNative, _HandleDart>('waveOutClose');

    waveInOpen = lib.lookupFunction<_OpenNative, _OpenDart>('waveInOpen');
    waveInPrepare =
        lib.lookupFunction<_HeaderNative, _HeaderDart>('waveInPrepareHeader');
    waveInUnprepare =
        lib.lookupFunction<_HeaderNative, _HeaderDart>('waveInUnprepareHeader');
    waveInAddBuffer =
        lib.lookupFunction<_HeaderNative, _HeaderDart>('waveInAddBuffer');
    waveInStart = lib.lookupFunction<_HandleNative, _HandleDart>('waveInStart');
    waveInStop = lib.lookupFunction<_HandleNative, _HandleDart>('waveInStop');
    waveInReset = lib.lookupFunction<_HandleNative, _HandleDart>('waveInReset');
    waveInClose = lib.lookupFunction<_HandleNative, _HandleDart>('waveInClose');
  }

  static final _Winmm instance = _Winmm._();

  late final _OpenDart waveOutOpen;
  late final _HeaderDart waveOutPrepare;
  late final _HeaderDart waveOutUnprepare;
  late final _HeaderDart waveOutWrite;
  late final _HandleDart waveOutReset;
  late final _HandleDart waveOutClose;

  late final _OpenDart waveInOpen;
  late final _HeaderDart waveInPrepare;
  late final _HeaderDart waveInUnprepare;
  late final _HeaderDart waveInAddBuffer;
  late final _HandleDart waveInStart;
  late final _HandleDart waveInStop;
  late final _HandleDart waveInReset;
  late final _HandleDart waveInClose;
}

/// Выделяет WAVEFORMATEX для PCM 8 кГц / 16 бит / моно.
Pointer<Uint8> _allocFormat() {
  final format = calloc<Uint8>(18);
  final data = ByteData.sublistView(format.asTypedList(18));
  data.setUint16(0, 1, Endian.little); // WAVE_FORMAT_PCM
  data.setUint16(2, 1, Endian.little); // каналы
  data.setUint32(4, 8000, Endian.little); // частота
  data.setUint32(8, 16000, Endian.little); // байт/с
  data.setUint16(12, 2, Endian.little); // выравнивание
  data.setUint16(14, 16, Endian.little); // бит на отсчёт
  data.setUint16(16, 0, Endian.little); // cbSize
  return format;
}

/// Один буфер со структурой WAVEHDR (для 64-битной Windows).
class _Slot {
  _Slot(int capacity)
      : capacity = capacity,
        buffer = calloc<Uint8>(capacity),
        header = calloc<Uint8>(_headerSize);

  static final int _ptr = sizeOf<IntPtr>();
  static final int _headerSize = 4 * _ptr + 16;
  static final int _lengthOffset = _ptr;
  static final int _recordedOffset = _ptr + 4;
  static final int _flagsOffset = 2 * _ptr + 8;

  final int capacity;
  final Pointer<Uint8> buffer;
  final Pointer<Uint8> header;
  bool prepared = false;
  bool queued = false;

  ByteData get _view => ByteData.sublistView(header.asTypedList(_headerSize));

  void reset(int length) {
    final view = _view;
    for (var i = 0; i < _headerSize; i++) {
      header[i] = 0;
    }
    if (_ptr == 8) {
      view.setUint64(0, buffer.address, Endian.little);
    } else {
      view.setUint32(0, buffer.address, Endian.little);
    }
    view.setUint32(_lengthOffset, length, Endian.little);
  }

  int get flags => _view.getUint32(_flagsOffset, Endian.little);
  int get recorded => _view.getUint32(_recordedOffset, Endian.little);
  bool get done => (flags & _whdrDone) != 0;

  void free() {
    calloc.free(buffer);
    calloc.free(header);
  }

  static int get headerSize => _headerSize;
}

/// Вывод звука на динамики по умолчанию.
class WaveOutPlayer {
  WaveOutPlayer({this.slotCount = 12, this.frameBytes = 640});

  final int slotCount;
  final int frameBytes;
  final List<_Slot> _slots = [];
  int _handle = 0;
  Pointer<Uint8>? _format;
  bool get isOpen => _handle != 0;

  void open() {
    final winmm = _Winmm.instance;
    final handle = calloc<IntPtr>();
    final format = _allocFormat();
    final result = winmm.waveOutOpen(handle, _waveMapper, format, 0, 0, 0);
    if (result != 0) {
      calloc.free(handle);
      calloc.free(format);
      throw StateError('Не удалось открыть устройство вывода звука (код $result).');
    }
    _handle = handle.value;
    calloc.free(handle);
    _format = format;
    for (var i = 0; i < slotCount; i++) {
      _slots.add(_Slot(frameBytes));
    }
  }

  /// Ставит данные в очередь воспроизведения. Лишнее отбрасывается.
  void write(Uint8List data) {
    if (!isOpen || data.isEmpty) return;
    final winmm = _Winmm.instance;
    var offset = 0;
    while (offset < data.length) {
      final remaining = data.length - offset;
      final length = remaining < frameBytes ? remaining : frameBytes;
      _Slot? slot;
      for (final candidate in _slots) {
        if (!candidate.queued) {
          slot = candidate;
          break;
        }
        if (candidate.done) {
          winmm.waveOutUnprepare(_handle, candidate.header, _Slot.headerSize);
          candidate.prepared = false;
          candidate.queued = false;
          slot = candidate;
          break;
        }
      }
      if (slot == null) return; // очередь переполнена — отбрасываем кадр
      slot.buffer
          .asTypedList(frameBytes)
          .setRange(0, length, data, offset);
      slot.reset(length);
      winmm.waveOutPrepare(_handle, slot.header, _Slot.headerSize);
      slot.prepared = true;
      winmm.waveOutWrite(_handle, slot.header, _Slot.headerSize);
      slot.queued = true;
      offset += length;
    }
  }

  void close() {
    if (!isOpen) return;
    final winmm = _Winmm.instance;
    winmm.waveOutReset(_handle);
    for (final slot in _slots) {
      if (slot.prepared) {
        winmm.waveOutUnprepare(_handle, slot.header, _Slot.headerSize);
      }
      slot.free();
    }
    _slots.clear();
    winmm.waveOutClose(_handle);
    _handle = 0;
    final format = _format;
    if (format != null) calloc.free(format);
    _format = null;
  }
}

/// Запись звука с микрофона по умолчанию кадрами по [frameBytes] байт.
class WaveInRecorder {
  WaveInRecorder({this.slotCount = 8, this.frameBytes = 320});

  final int slotCount;
  final int frameBytes;
  final List<_Slot> _slots = [];
  int _handle = 0;
  Pointer<Uint8>? _format;
  bool get isOpen => _handle != 0;

  void open() {
    final winmm = _Winmm.instance;
    final handle = calloc<IntPtr>();
    final format = _allocFormat();
    final result = winmm.waveInOpen(handle, _waveMapper, format, 0, 0, 0);
    if (result != 0) {
      calloc.free(handle);
      calloc.free(format);
      throw StateError('Не удалось открыть микрофон (код $result).');
    }
    _handle = handle.value;
    calloc.free(handle);
    _format = format;
    for (var i = 0; i < slotCount; i++) {
      final slot = _Slot(frameBytes);
      _slots.add(slot);
      _queue(slot);
    }
    winmm.waveInStart(_handle);
  }

  void _queue(_Slot slot) {
    final winmm = _Winmm.instance;
    if (slot.prepared) {
      winmm.waveInUnprepare(_handle, slot.header, _Slot.headerSize);
      slot.prepared = false;
    }
    slot.reset(frameBytes);
    winmm.waveInPrepare(_handle, slot.header, _Slot.headerSize);
    slot.prepared = true;
    winmm.waveInAddBuffer(_handle, slot.header, _Slot.headerSize);
  }

  /// Возвращает готовые кадры и ставит буферы на запись снова.
  List<Uint8List> poll() {
    final frames = <Uint8List>[];
    if (!isOpen) return frames;
    for (final slot in _slots) {
      if (slot.done) {
        final recorded = slot.recorded;
        final size = recorded < frameBytes ? recorded : frameBytes;
        if (size > 0) {
          frames.add(Uint8List.fromList(slot.buffer.asTypedList(size)));
        }
        _queue(slot);
      }
    }
    return frames;
  }

  void close() {
    if (!isOpen) return;
    final winmm = _Winmm.instance;
    winmm.waveInStop(_handle);
    winmm.waveInReset(_handle);
    for (final slot in _slots) {
      if (slot.prepared) {
        winmm.waveInUnprepare(_handle, slot.header, _Slot.headerSize);
      }
      slot.free();
    }
    _slots.clear();
    winmm.waveInClose(_handle);
    _handle = 0;
    final format = _format;
    if (format != null) calloc.free(format);
    _format = null;
  }
}

/// Воспроизводит короткую мелодию уведомления (PCM 8 кГц / 16 бит / моно)
/// с заданной громкостью [volume] в диапазоне от 0.0 до 1.0.
void playSmsNotificationSound({required double volume}) {
  final clamped = volume.clamp(0.0, 1.0);
  if (clamped <= 0.001) return;

  const sampleRate = 8000;
  // Короткая трёхнотная мелодия (C5 -> E5 -> G5), ~0.42 с.
  const notes = <(double, double, double)>[
    (523.25, 0.11, 0.45),
    (659.25, 0.11, 0.45),
    (783.99, 0.20, 0.40),
  ];

  final samples = <int>[];
  for (final note in notes) {
    final freq = note.$1;
    final dur = note.$2;
    final baseAmp = note.$3 * clamped;
    final total = (sampleRate * dur).round();
    for (var i = 0; i < total; i++) {
      final t = i / sampleRate;
      final attack = (i / (sampleRate * 0.012)).clamp(0.0, 1.0);
      final decay = (1.0 - (i / total) * 0.65).clamp(0.0, 1.0);
      final val = baseAmp * attack * decay * math.sin(2.0 * math.pi * freq * t);
      final pcm = (val * 32767).round().clamp(-32767, 32767);
      samples.add(pcm);
    }
  }

  final bytes = Uint8List(samples.length * 2);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < samples.length; i++) {
    view.setInt16(i * 2, samples[i], Endian.little);
  }

  final winmm = _Winmm.instance;
  final handlePtr = calloc<IntPtr>();
  final format = _allocFormat();
  final openRes = winmm.waveOutOpen(handlePtr, _waveMapper, format, 0, 0, 0);
  if (openRes != 0) {
    calloc.free(handlePtr);
    calloc.free(format);
    return;
  }
  final handle = handlePtr.value;
  calloc.free(handlePtr);

  final slot = _Slot(bytes.length);
  try {
    slot.buffer.asTypedList(bytes.length).setAll(0, bytes);
    slot.reset(bytes.length);
    winmm.waveOutPrepare(handle, slot.header, _Slot.headerSize);
    slot.prepared = true;
    winmm.waveOutWrite(handle, slot.header, _Slot.headerSize);
    slot.queued = true;

    final waitMs = ((samples.length / sampleRate) * 1000).ceil() + 120;
    final deadline = DateTime.now().add(Duration(milliseconds: waitMs));
    while (!slot.done && DateTime.now().isBefore(deadline)) {
      sleep(const Duration(milliseconds: 20));
    }
  } finally {
    winmm.waveOutReset(handle);
    if (slot.prepared) {
      winmm.waveOutUnprepare(handle, slot.header, _Slot.headerSize);
    }
    slot.free();
    winmm.waveOutClose(handle);
    calloc.free(format);
  }
}
