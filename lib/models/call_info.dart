/// Строка ответа AT+CLCC.
class CallLine {
  const CallLine({
    required this.index,
    required this.incoming,
    required this.state,
    required this.number,
  });

  final int index;

  /// true — входящий вызов (dir = 1).
  final bool incoming;

  /// 0 — активен, 1 — удержание, 2 — набор, 3 — идёт вызов абоненту,
  /// 4 — входящий, 5 — ожидающий.
  final int state;
  final String number;

  bool get isActive => state == 0;

  static List<CallLine> parse(String response) {
    final result = <CallLine>[];
    final pattern = RegExp(
      r'\+CLCC:\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*"([^"]*)")?',
    );
    for (final match in pattern.allMatches(response)) {
      result.add(CallLine(
        index: int.tryParse(match.group(1) ?? '') ?? 0,
        incoming: match.group(2) == '1',
        state: int.tryParse(match.group(3) ?? '') ?? 0,
        number: match.group(6) ?? '',
      ));
    }
    return result;
  }
}

enum CallPhase { idle, dialing, ringing, active, incoming }

extension CallPhaseText on CallPhase {
  String get title {
    switch (this) {
      case CallPhase.idle:
        return 'Нет вызова';
      case CallPhase.dialing:
        return 'Набор номера…';
      case CallPhase.ringing:
        return 'Идёт вызов абоненту…';
      case CallPhase.active:
        return 'Разговор';
      case CallPhase.incoming:
        return 'Входящий вызов';
    }
  }
}
