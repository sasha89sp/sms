import 'dart:convert';

/// Тип шага сценария.
enum StepType { ownNumber, ussd, balance, sms, pause, call, dtmf }

extension StepTypeInfo on StepType {
  String get title {
    switch (this) {
      case StepType.ownNumber:
        return 'Номер SIM (USSD)';
      case StepType.ussd:
        return 'USSD-команда';
      case StepType.balance:
        return 'Проверка баланса';
      case StepType.sms:
        return 'Отправка SMS';
      case StepType.pause:
        return 'Пауза';
      case StepType.call:
        return 'Звонок';
      case StepType.dtmf:
        return 'Набор цифр (DTMF)';
    }
  }

  String get key => name;

  static StepType parse(String? value) {
    for (final type in StepType.values) {
      if (type.name == value) return type;
    }
    return StepType.ussd;
  }
}

int _idCounter = 0;
String newId() => '${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

class ScenarioStep {
  const ScenarioStep({
    required this.id,
    required this.type,
    this.code = '',
    this.recipient = '',
    this.text = '',
    this.seconds = 5,
    this.digits = '',
  });

  factory ScenarioStep.create(StepType type) {
    switch (type) {
      case StepType.ownNumber:
        return ScenarioStep(id: newId(), type: type, code: '*161#');
      case StepType.ussd:
        return ScenarioStep(id: newId(), type: type, code: '*100#');
      case StepType.balance:
        return ScenarioStep(id: newId(), type: type, code: '*100#');
      case StepType.sms:
        return ScenarioStep(id: newId(), type: type, text: '');
      case StepType.pause:
        return ScenarioStep(id: newId(), type: type, seconds: 5);
      case StepType.call:
        return ScenarioStep(id: newId(), type: type, seconds: 8);
      case StepType.dtmf:
        return ScenarioStep(id: newId(), type: type, digits: '1');
    }
  }

  final String id;
  final StepType type;

  /// USSD-код (для ownNumber, ussd, balance).
  final String code;

  /// Номер получателя SMS или номер для звонка.
  final String recipient;

  /// Текст SMS.
  final String text;

  /// Пауза / длительность разговора после соединения, секунд.
  final int seconds;

  /// Цифры для DTMF.
  final String digits;

  ScenarioStep copyWith({
    StepType? type,
    String? code,
    String? recipient,
    String? text,
    int? seconds,
    String? digits,
  }) =>
      ScenarioStep(
        id: id,
        type: type ?? this.type,
        code: code ?? this.code,
        recipient: recipient ?? this.recipient,
        text: text ?? this.text,
        seconds: seconds ?? this.seconds,
        digits: digits ?? this.digits,
      );

  /// Краткое описание для списка.
  String get summary {
    switch (type) {
      case StepType.ownNumber:
      case StepType.ussd:
      case StepType.balance:
        return code;
      case StepType.sms:
        return '$recipient: $text';
      case StepType.pause:
        return '$seconds с';
      case StepType.call:
        return '$recipient, разговор $seconds с';
      case StepType.dtmf:
        return digits;
    }
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type.key,
        'code': code,
        'recipient': recipient,
        'text': text,
        'seconds': seconds,
        'digits': digits,
      };

  factory ScenarioStep.fromJson(Map<String, dynamic> json) => ScenarioStep(
        id: json['id'] as String? ?? newId(),
        type: StepTypeInfo.parse(json['type'] as String?),
        code: json['code'] as String? ?? '',
        recipient: json['recipient'] as String? ?? '',
        text: json['text'] as String? ?? '',
        seconds: (json['seconds'] as num?)?.toInt() ?? 5,
        digits: json['digits'] as String? ?? '',
      );
}

class Scenario {
  const Scenario({
    required this.id,
    required this.name,
    this.steps = const [],
    this.operator = '',
    this.autoRun = false,
    this.stopOnError = false,
  });

  factory Scenario.empty(String name) =>
      Scenario(id: newId(), name: name, steps: const []);

  final String id;
  final String name;
  final List<ScenarioStep> steps;

  /// Подстрока названия оператора (МТС, Билайн…). Пусто — для любого.
  final String operator;

  /// Выполнять автоматически после появления сети.
  final bool autoRun;

  /// Прерывать сценарий при первой ошибке.
  final bool stopOnError;

  Scenario copyWith({
    String? name,
    List<ScenarioStep>? steps,
    String? operator,
    bool? autoRun,
    bool? stopOnError,
  }) =>
      Scenario(
        id: id,
        name: name ?? this.name,
        steps: steps ?? this.steps,
        operator: operator ?? this.operator,
        autoRun: autoRun ?? this.autoRun,
        stopOnError: stopOnError ?? this.stopOnError,
      );

  /// Подходит ли сценарий оператору [operatorName].
  bool matchesOperator(String operatorName) {
    final filter = operator.trim().toLowerCase();
    if (filter.isEmpty) return true;
    final name = operatorName.toLowerCase();
    return filter
        .split(RegExp(r'[,;|]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .any(name.contains);
  }

  /// Заголовки столбцов Excel для шагов (null — шаг не создаёт столбец).
  List<String?> columnHeaders() {
    final used = <String, int>{};
    String unique(String base) {
      final count = (used[base] ?? 0) + 1;
      used[base] = count;
      return count == 1 ? base : '$base ($count)';
    }

    var balanceIndex = 0;
    return steps.map<String?>((step) {
      switch (step.type) {
        case StepType.ownNumber:
        case StepType.pause:
          return null;
        case StepType.ussd:
          return unique('USSD ${step.code}');
        case StepType.balance:
          balanceIndex++;
          return unique('Баланс $balanceIndex (${step.code})');
        case StepType.sms:
          return unique('SMS → ${step.recipient}');
        case StepType.call:
          return unique('Звонок → ${step.recipient}');
        case StepType.dtmf:
          return unique('Цифры ${step.digits}');
      }
    }).toList();
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'operator': operator,
        'autoRun': autoRun,
        'stopOnError': stopOnError,
        'steps': steps.map((step) => step.toJson()).toList(),
      };

  factory Scenario.fromJson(Map<String, dynamic> json) => Scenario(
        id: json['id'] as String? ?? newId(),
        name: json['name'] as String? ?? 'Сценарий',
        operator: json['operator'] as String? ?? '',
        autoRun: json['autoRun'] as bool? ?? false,
        stopOnError: json['stopOnError'] as bool? ?? false,
        steps: ((json['steps'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) =>
                ScenarioStep.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
      );
}

/// Сохранённая USSD-команда.
class SavedUssd {
  const SavedUssd({required this.name, required this.code});
  final String name;
  final String code;

  Map<String, Object?> toJson() => {'name': name, 'code': code};

  factory SavedUssd.fromJson(Map<String, dynamic> json) => SavedUssd(
        name: json['name'] as String? ?? '',
        code: json['code'] as String? ?? '',
      );
}

/// Ячейка результата для Excel.
class CellData {
  const CellData(this.text, {this.number});
  final String text;
  final double? number;

  Map<String, Object?> toJson() => {'t': text, if (number != null) 'n': number};

  factory CellData.fromJson(Map<String, dynamic> json) => CellData(
        json['t'] as String? ?? '',
        number: (json['n'] as num?)?.toDouble(),
      );
}

/// Одна строка Excel — результат одного запуска сценария.
class RunRow {
  const RunRow({
    required this.startedAt,
    required this.scenarioName,
    required this.columns,
    required this.cells,
    this.balanceStatus = '',
    this.success = true,
  });

  final DateTime startedAt;
  final String scenarioName;
  final List<String> columns;
  final List<CellData> cells;
  final String balanceStatus;
  final bool success;

  static String encodeColumns(List<String> columns) => jsonEncode(columns);
  static String encodeCells(List<CellData> cells) =>
      jsonEncode(cells.map((cell) => cell.toJson()).toList());

  static List<String> decodeColumns(String raw) =>
      (jsonDecode(raw) as List).map((e) => '$e').toList();

  static List<CellData> decodeCells(String raw) => (jsonDecode(raw) as List)
      .whereType<Map>()
      .map((item) => CellData.fromJson(Map<String, dynamic>.from(item)))
      .toList();
}

enum LiveStatus { pending, running, ok, error, skipped }

/// Состояние шага во время выполнения (для экрана).
class LiveStep {
  LiveStep({required this.title, this.status = LiveStatus.pending});
  final String title;
  LiveStatus status;
  String value = '';
}
