import 'ussd_codec.dart';

class SmsPduSegment {
  const SmsPduSegment({required this.pdu, required this.tpduLength});
  final String pdu;
  final int tpduLength;
}

class SmsPduEncoder {
  static List<SmsPduSegment> encodeUcs2({
    required String recipient,
    required String message,
    int reference = 0x4A,
    bool requestStatusReport = true,
  }) {
    final digits = _normalizeNumber(recipient);
    if (digits.length < 7 || digits.length > 15) {
      throw ArgumentError('Проверьте номер получателя SMS.');
    }
    if (message.trim().isEmpty) {
      throw ArgumentError('Текст SMS не должен быть пустым.');
    }

    final units = message.codeUnits;
    final chunks = <List<int>>[];
    if (units.length <= 70) {
      chunks.add(units);
    } else {
      var offset = 0;
      while (offset < units.length) {
        var end = (offset + 67).clamp(0, units.length);
        // Do not split a UTF-16 surrogate pair between SMS parts.
        if (end < units.length &&
            units[end - 1] >= 0xD800 &&
            units[end - 1] <= 0xDBFF &&
            units[end] >= 0xDC00 &&
            units[end] <= 0xDFFF) {
          end--;
        }
        chunks.add(units.sublist(offset, end));
        offset = end;
      }
    }

    return List.generate(chunks.length, (index) {
      final multipart = chunks.length > 1;
      final bodyHex = chunks[index]
          .map((unit) => unit.toRadixString(16).padLeft(4, '0'))
          .join()
          .toUpperCase();
      final header = multipart
          ? '050003${reference.toRadixString(16).padLeft(2, '0')}'
              '${chunks.length.toRadixString(16).padLeft(2, '0')}'
              '${(index + 1).toRadixString(16).padLeft(2, '0')}'
          : '';
      final userData = '$header$bodyHex';
      final firstOctet = (multipart ? 0x40 : 0) |
          (requestStatusReport ? 0x20 : 0) |
          0x01; // SMS-SUBMIT
      final typeOfAddress = recipient.trim().startsWith('+') ? '91' : '81';
      final semiOctets = _semiOctetAddress(digits);
      final dataLength = (userData.length ~/ 2);
      final userDataLength = dataLength.toRadixString(16).padLeft(2, '0');
      final pdu = '00' // SMSC length: use the modem's configured SMSC.
          '${firstOctet.toRadixString(16).padLeft(2, '0')}'
          '00' // TP-MR
          '${digits.length.toRadixString(16).padLeft(2, '0')}'
          '$typeOfAddress'
          '$semiOctets'
          '00' // TP-PID
          '08' // TP-DCS: UCS2
          '$userDataLength'
          '$userData';
      final tpduLength = (pdu.length ~/ 2) - 1;
      return SmsPduSegment(
        pdu: pdu.toUpperCase(),
        tpduLength: tpduLength,
      );
    });
  }

  static String _normalizeNumber(String value) {
    var digits = value.replaceAll(RegExp(r'\D'), '');
    if (!value.trim().startsWith('+') && digits.length == 11 && digits[0] == '8') {
      digits = '7${digits.substring(1)}';
    }
    return digits;
  }

  static String _semiOctetAddress(String digits) {
    final padded = digits.length.isOdd ? '${digits}F' : digits;
    final result = StringBuffer();
    for (var i = 0; i < padded.length; i += 2) {
      result.write(padded[i + 1]);
      result.write(padded[i]);
    }
    return result.toString();
  }
}


/// Сообщение, прочитанное из памяти модема в PDU-виде.
class RawSms {
  const RawSms({
    required this.storage,
    required this.index,
    required this.stat,
    required this.pdu,
  });

  final String storage;
  final int index;

  /// 0 — REC UNREAD, 1 — REC READ, 2 — STO UNSENT, 3 — STO SENT.
  final int stat;
  final String pdu;

  String get ref => '$storage:$index';
}

/// Результат разбора одного PDU.
class DecodedSms {
  const DecodedSms({
    required this.sender,
    required this.text,
    required this.time,
    required this.outgoing,
    this.concatRef,
    this.concatTotal = 1,
    this.concatSeq = 1,
  });

  final String sender;
  final String text;
  final String time;
  final bool outgoing;
  final int? concatRef;
  final int concatTotal;
  final int concatSeq;
}

/// Готовое сообщение (части длинного SMS уже склеены).
class MergedSms {
  const MergedSms({
    required this.sender,
    required this.text,
    required this.time,
    required this.outgoing,
    required this.unread,
    required this.refs,
  });

  final String sender;
  final String text;
  final String time;
  final bool outgoing;
  final bool unread;
  final List<String> refs;
}

class SmsPduDecoder {
  /// Разбирает PDU (SMS-DELIVER или SMS-SUBMIT). Null — если не удалось.
  static DecodedSms? decode(String pduHex) {
    try {
      return _decode(pduHex);
    } catch (_) {
      return null;
    }
  }

  static DecodedSms? _decode(String hex) {
    final clean = hex.replaceAll(RegExp(r'\s'), '');
    final b = <int>[
      for (var i = 0; i + 1 < clean.length; i += 2)
        int.parse(clean.substring(i, i + 2), radix: 16),
    ];
    var pos = 0;
    final smscLength = b[pos++];
    pos += smscLength;
    final first = b[pos++];
    final mti = first & 0x03;
    final hasHeader = (first & 0x40) != 0;

    String address;
    var time = '';
    final bool outgoing;
    int dcs;
    if (mti == 0) {
      outgoing = false;
      final length = b[pos++];
      final toa = b[pos++];
      final octets = (length + 1) ~/ 2;
      address = _decodeAddress(b.sublist(pos, pos + octets), length, toa);
      pos += octets;
      pos++; // PID
      dcs = b[pos++];
      time = _decodeTimestamp(b.sublist(pos, pos + 7));
      pos += 7;
    } else if (mti == 1) {
      outgoing = true;
      pos++; // MR
      final length = b[pos++];
      final toa = b[pos++];
      final octets = (length + 1) ~/ 2;
      address = _decodeAddress(b.sublist(pos, pos + octets), length, toa);
      pos += octets;
      pos++; // PID
      dcs = b[pos++];
      final validity = (first >> 3) & 0x03;
      if (validity == 2) {
        pos += 1;
      } else if (validity == 1 || validity == 3) {
        pos += 7;
      }
    } else {
      return null; // отчёты о доставке и прочее
    }

    final udl = b[pos++];
    final ud = b.sublist(pos);

    var alphabet = 0; // 0 — GSM 7 bit, 1 — 8 bit, 2 — UCS-2
    if ((dcs & 0xC0) == 0x00) {
      alphabet = (dcs >> 2) & 0x03;
    } else if ((dcs & 0xF0) == 0xF0) {
      alphabet = (dcs & 0x04) != 0 ? 1 : 0;
    } else if ((dcs & 0xF0) == 0xE0) {
      alphabet = 2;
    }
    if (alphabet == 3) alphabet = 0;

    int? concatRef;
    var concatTotal = 1;
    var concatSeq = 1;
    var headerLength = 0; // байт, включая байт длины UDH
    if (hasHeader && ud.isNotEmpty) {
      final udhl = ud[0];
      headerLength = udhl + 1;
      var i = 1;
      final end = (1 + udhl).clamp(0, ud.length).toInt();
      while (i + 1 < end) {
        final iei = ud[i];
        final len = ud[i + 1];
        if (iei == 0x00 && len == 3 && i + 4 < ud.length) {
          concatRef = ud[i + 2];
          concatTotal = ud[i + 3];
          concatSeq = ud[i + 4];
        } else if (iei == 0x08 && len == 4 && i + 5 < ud.length) {
          concatRef = (ud[i + 2] << 8) | ud[i + 3];
          concatTotal = ud[i + 4];
          concatSeq = ud[i + 5];
        }
        i += 2 + len;
      }
    }

    String text;
    if (alphabet == 2) {
      final endByte = udl.clamp(0, ud.length).toInt();
      final units = <int>[];
      for (var i = headerLength; i + 1 < endByte; i += 2) {
        units.add((ud[i] << 8) | ud[i + 1]);
      }
      text = String.fromCharCodes(units);
    } else if (alphabet == 1) {
      final endByte = udl.clamp(0, ud.length).toInt();
      text = String.fromCharCodes(ud.sublist(headerLength.clamp(0, endByte).toInt(), endByte));
    } else {
      final headerBits = headerLength * 8;
      final headerSeptets = (headerBits + 6) ~/ 7;
      final count = (udl - headerSeptets).clamp(0, 1000).toInt();
      final septets = <int>[];
      for (var k = 0; k < count; k++) {
        final bit = (headerSeptets + k) * 7;
        final byteIndex = bit ~/ 8;
        if (byteIndex >= ud.length) break;
        final shift = bit % 8;
        var value = ud[byteIndex] >> shift;
        if (byteIndex + 1 < ud.length) {
          value |= ud[byteIndex + 1] << (8 - shift);
        }
        septets.add(value & 0x7F);
      }
      text = UssdCodec.gsmSeptetsToString(septets);
    }

    return DecodedSms(
      sender: address,
      text: text,
      time: time,
      outgoing: outgoing,
      concatRef: concatRef,
      concatTotal: concatTotal,
      concatSeq: concatSeq,
    );
  }

  static String _decodeAddress(List<int> octets, int length, int toa) {
    final type = (toa >> 4) & 0x07;
    if (type == 5) {
      // Буквенный отправитель (например, "MTS") — 7-bit GSM.
      final count = (length * 4) ~/ 7;
      final septets = <int>[];
      for (var k = 0; k < count; k++) {
        final bit = k * 7;
        final byteIndex = bit ~/ 8;
        if (byteIndex >= octets.length) break;
        final shift = bit % 8;
        var value = octets[byteIndex] >> shift;
        if (byteIndex + 1 < octets.length) {
          value |= octets[byteIndex + 1] << (8 - shift);
        }
        septets.add(value & 0x7F);
      }
      return UssdCodec.gsmSeptetsToString(septets);
    }
    const digits = '0123456789*#abc';
    final buffer = StringBuffer();
    for (final octet in octets) {
      for (final nibble in [octet & 0x0F, octet >> 4]) {
        if (buffer.length >= length) break;
        if (nibble == 0x0F) continue;
        buffer.write(nibble < digits.length ? digits[nibble] : '');
      }
    }
    final number = buffer.toString();
    return type == 1 && number.isNotEmpty ? '+$number' : number;
  }

  static String _decodeTimestamp(List<int> octets) {
    int bcd(int value) => (value & 0x0F) * 10 + (value >> 4);
    String two(int value) => value.toString().padLeft(2, '0');
    final year = 2000 + bcd(octets[0]);
    return '$year-${two(bcd(octets[1]))}-${two(bcd(octets[2]))} '
        '${two(bcd(octets[3]))}:${two(bcd(octets[4]))}:${two(bcd(octets[5]))}';
  }

  /// Разбирает все PDU и склеивает части длинных SMS.
  /// Неполные группы не возвращаются — они дождутся недостающих частей.
  static List<MergedSms> decodeAndMerge(List<RawSms> raws) {
    final result = <MergedSms>[];
    final groups = <String, List<_Part>>{};
    final groupOrder = <String>[];

    for (final raw in raws) {
      final decoded = decode(raw.pdu);
      if (decoded == null) continue;
      final outgoing = decoded.outgoing || raw.stat == 2 || raw.stat == 3;
      final unread = raw.stat == 0;
      if (decoded.concatRef != null && decoded.concatTotal > 1) {
        final key =
            '$outgoing|${decoded.sender}|${decoded.concatRef}|${decoded.concatTotal}';
        if (!groups.containsKey(key)) {
          groups[key] = [];
          groupOrder.add(key);
        }
        groups[key]!.add(_Part(raw, decoded, outgoing, unread));
      } else {
        result.add(MergedSms(
          sender: decoded.sender,
          text: decoded.text,
          time: decoded.time,
          outgoing: outgoing,
          unread: unread,
          refs: [raw.ref],
        ));
      }
    }

    for (final key in groupOrder) {
      final parts = groups[key]!;
      final bySeq = <int, _Part>{};
      for (final part in parts) {
        bySeq[part.decoded.concatSeq] = part;
      }
      final total = parts.first.decoded.concatTotal;
      var complete = true;
      for (var seq = 1; seq <= total; seq++) {
        if (!bySeq.containsKey(seq)) complete = false;
      }
      if (!complete) continue;
      final ordered = [for (var seq = 1; seq <= total; seq++) bySeq[seq]!];
      result.add(MergedSms(
        sender: ordered.first.decoded.sender,
        text: ordered.map((part) => part.decoded.text).join(),
        time: ordered.first.decoded.time,
        outgoing: ordered.first.outgoing,
        unread: ordered.any((part) => part.unread),
        refs: ordered.map((part) => part.raw.ref).toList(),
      ));
    }
    return result;
  }
}

class _Part {
  const _Part(this.raw, this.decoded, this.outgoing, this.unread);
  final RawSms raw;
  final DecodedSms decoded;
  final bool outgoing;
  final bool unread;
}
