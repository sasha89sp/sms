class UssdCodec {
  static String decodeHuaweiResponse(String response) {
    final status = int.tryParse(
          RegExp(r'\+CUSD:\s*(\d+)', caseSensitive: false)
                  .firstMatch(response)
                  ?.group(1) ??
              '',
        ) ??
        0;
    if (status == 2 || status == 4) {
      return 'Ошибка USSD (статус сети: $status)';
    }

    final match = RegExp(
      r'\+CUSD:\s*\d+\s*,\s*"([^"]*)"\s*(?:,\s*(\d+))?',
      caseSensitive: false,
    ).firstMatch(response);
    if (match == null) return response.trim();

    final payload = match.group(1) ?? '';
    final dcs = int.tryParse(match.group(2) ?? '') ?? 15;
    if (dcs == 72 || (payload.isNotEmpty && _looksLikeUcs2Hex(payload))) {
      final decoded = _decodeUcs2Hex(payload);
      if (decoded.isNotEmpty) return decoded;
    }
    return payload.replaceAll(r'\r', '\n').replaceAll(r'\n', '\n').trim();
  }

  static bool _looksLikeUcs2Hex(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), '');
    return compact.length >= 4 &&
        compact.length % 4 == 0 &&
        RegExp(r'^[0-9A-Fa-f]+$').hasMatch(compact);
  }

  static String _decodeUcs2Hex(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), '');
    if (compact.length % 4 != 0 ||
        !RegExp(r'^[0-9A-Fa-f]+$').hasMatch(compact)) {
      return '';
    }
    final units = <int>[];
    for (var i = 0; i + 3 < compact.length; i += 4) {
      units.add(int.parse(compact.substring(i, i + 4), radix: 16));
    }
    return String.fromCharCodes(units).replaceAll('\u0000', '').trim();
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
    final matches = RegExp(r'(?<!\d)(\d{1,8}(?:\.\d{1,2})?)(?!\d)')
        .allMatches(normalized)
        .toList();
    if (matches.isEmpty) return '';
    return matches.last.group(1) ?? '';
  }
}
