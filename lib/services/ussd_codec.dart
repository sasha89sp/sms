class UssdCodec {
  /// Разбирает ответ модема на AT+CUSD.
  ///
  /// Huawei может вернуть текст в трёх видах:
  ///  * обычный текст (DCS 15 + CSCS="GSM"/"IRA");
  ///  * UCS-2 в hex (DCS 72, типично для русского языка);
  ///  * 7-bit GSM, упакованный в hex (DCS 15 / 0) — самый частый случай на E173.
  static String decodeHuaweiResponse(String response) {
    final match = RegExp(
      r'\+CUSD:\s*(\d+)\s*(?:,\s*"([^"]*)"\s*(?:,\s*(\d+))?)?',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(response);
    if (match == null) return response.trim();

    final status = int.tryParse(match.group(1) ?? '') ?? 0;
    final payload = (match.group(2) ?? '').trim();
    final dcs = int.tryParse(match.group(3) ?? '') ?? 15;

    if (status == 4) return 'Ошибка USSD (статус сети: 4 — операция не поддерживается)';
    if (status == 5) return 'Ошибка USSD (статус сети: 5 — сеть не ответила вовремя)';
    if (payload.isEmpty) {
      if (status == 2) return 'Ошибка USSD (статус сети: 2 — сеть завершила сеанс без текста)';
      if (status == 3) return 'Ошибка USSD (статус сети: 3 — ответил другой клиент)';
      return 'Ошибка USSD (пустой ответ сети, статус $status)';
    }

    return _decodePayload(payload, dcs);
  }

  static String _decodePayload(String payload, int dcs) {
    final compact = payload.replaceAll(RegExp(r'\s+'), '');
    final isHex = compact.length >= 2 &&
        compact.length.isEven &&
        RegExp(r'^[0-9A-Fa-f]+$').hasMatch(compact);

    if (isHex) {
      final ucs2 = _decodeUcs2Hex(compact);
      final ucs2Ok = ucs2.isNotEmpty && _isPlausibleText(ucs2);
      // DCS 72 (0x48) — UCS-2 по стандарту.
      if (dcs == 72 && ucs2.isNotEmpty) return ucs2;
      if (ucs2Ok && compact.length % 4 == 0) return ucs2;
      final gsm = decodeGsm7PackedHex(compact);
      if (gsm.isNotEmpty && _isPlausibleText(gsm)) return gsm;
      if (ucs2.isNotEmpty) return ucs2;
    }
    return payload.replaceAll(r'\r', '\n').replaceAll(r'\n', '\n').trim();
  }

  /// Текст «правдоподобен», если состоит из латиницы, кириллицы, цифр и
  /// обычной пунктуации. Отсекает мусор (например, hangul/CJK), который
  /// получается при неверной трактовке упакованного 7-bit как UCS-2.
  static bool _isPlausibleText(String text) {
    if (text.isEmpty) return false;
    for (final u in text.runes) {
      final ok = u == 0x0A ||
          u == 0x0D ||
          (u >= 0x20 && u <= 0x7E) ||
          (u >= 0xA0 && u <= 0xFF) ||
          (u >= 0x0400 && u <= 0x04FF) ||
          (u >= 0x2010 && u <= 0x20FF) ||
          u == 0x20AC;
      if (!ok) return false;
    }
    return true;
  }

  static String _decodeUcs2Hex(String compact) {
    if (compact.length % 4 != 0) return '';
    final units = <int>[];
    for (var i = 0; i + 3 < compact.length; i += 4) {
      units.add(int.parse(compact.substring(i, i + 4), radix: 16));
    }
    return String.fromCharCodes(units).replaceAll('\u0000', '').trim();
  }

  static const _gsmBasic =
      '@£\$¥èéùìòÇ\n' 'Øø\r' 'ÅåΔ_ΦΓΛΩΠΨΣΘΞ\u001b' 'ÆæßÉ !"#¤%&\'()*+,-./0123456789:;<=>?'
      '¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà';

  /// Декодирует 7-bit GSM, упакованный в октеты и записанный как hex.
  static String decodeGsm7PackedHex(String hex) {
    final compact = hex.replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty ||
        compact.length.isOdd ||
        !RegExp(r'^[0-9A-Fa-f]+$').hasMatch(compact)) {
      return '';
    }
    final bytes = <int>[
      for (var i = 0; i < compact.length; i += 2)
        int.parse(compact.substring(i, i + 2), radix: 16),
    ];
    final septets = <int>[];
    var carry = 0;
    var carryBits = 0;
    for (final b in bytes) {
      septets.add(((b << carryBits) | carry) & 0x7F);
      carry = b >> (7 - carryBits);
      carryBits++;
      if (carryBits == 7) {
        septets.add(carry & 0x7F);
        carry = 0;
        carryBits = 0;
      }
    }
    return gsmSeptetsToString(septets).trim();
  }

  /// Переводит последовательность septet-кодов GSM 03.38 в строку.
  static String gsmSeptetsToString(List<int> septets) {
    final out = StringBuffer();
    var escape = false;
    for (final s in septets) {
      if (escape) {
        out.write(_gsmExt[s] ?? ' ');
        escape = false;
      } else if (s == 0x1B) {
        escape = true;
      } else {
        out.write(s < _gsmBasic.length ? _gsmBasic[s] : '?');
      }
    }
    return out.toString();
  }

  static const _gsmExt = {
    0x0A: '\f', 0x14: '^', 0x28: '{', 0x29: '}', 0x2F: '\\',
    0x3C: '[', 0x3D: '~', 0x3E: ']', 0x40: '|', 0x65: '€',
  };

  /// Кодирует USSD-код в 7-bit GSM, упакованный в hex (для E173 с DCS 15).
  /// Пример: "*100#" -> "AA180C3602".
  static String encodeGsm7PackedHex(String text) {
    final septets = <int>[];
    for (final ch in text.runes.map(String.fromCharCode)) {
      final idx = _gsmBasic.indexOf(ch);
      if (idx < 0 || idx == 0x1B) {
        throw ArgumentError('Символ "$ch" нельзя передать в 7-bit GSM.');
      }
      septets.add(idx);
    }
    final out = <int>[];
    var i = 0;
    while (i < septets.length) {
      final shift = i % 8;
      if (shift == 7) {
        i++;
        continue;
      }
      var byte = septets[i] >> shift;
      if (i + 1 < septets.length) {
        byte |= (septets[i + 1] << (7 - shift)) & 0xFF;
      }
      out.add(byte & 0xFF);
      i++;
    }
    return out
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join();
  }

  static String extractPhoneNumber(String text) {
    final match = RegExp(r'(?:\+7|7|8)\D*\d{3}\D*\d{3}\D*\d{2}\D*\d{2}')
        .firstMatch(text);
    if (match == null) return '';
    final digits = match.group(0)!.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 11) return match.group(0)!.trim();
    return '+7${digits.substring(1)}';
  }

  static String extractBalance(String text) {
    final normalized = text.replaceAll(',', '.');
    final lower = normalized.toLowerCase();

    // 1) число рядом со словом «баланс / остаток».
    final labeled = RegExp(
      r'(?:баланс|balance|остаток|на счету|на счёте)\D{0,15}?(-?\d{1,8}(?:\.\d{1,2})?)',
    ).firstMatch(lower);
    if (labeled != null) return labeled.group(1) ?? '';

    // 2) число перед обозначением валюты.
    final currency = RegExp(
      r'(-?\d{1,8}(?:\.\d{1,2})?)\s*(?:р(?![а-яё])|руб|rub|₽)',
    ).firstMatch(lower);
    if (currency != null) return currency.group(1) ?? '';

    // 3) последнее число в тексте.
    final matches = RegExp(r'(?<!\d)(-?\d{1,8}(?:\.\d{1,2})?)(?!\d)')
        .allMatches(normalized)
        .toList();
    if (matches.isEmpty) return '';
    return matches.last.group(1) ?? '';
  }
}
