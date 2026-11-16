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
