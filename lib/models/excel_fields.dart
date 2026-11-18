/// Поля, которые можно выводить в Excel, и их порядок.
class ExcelFields {
  static const date = 'date';
  static const sim = 'sim';
  static const iccid = 'iccid';
  static const operator = 'operator';
  static const scenario = 'scenario';
  static const balanceFirst = 'balance_first';
  static const balanceLast = 'balance_last';
  static const balanceStatus = 'balance_status';
  static const balanceDiff = 'balance_diff';
  static const smsStatus = 'sms_status';
  static const callStatus = 'call_status';
  static const success = 'success';
  static const errors = 'errors';

  /// Основной порядок «по умолчанию» (без шагов).
  static const base = <String>[
    date,
    sim,
    iccid,
    operator,
    scenario,
    balanceFirst,
    balanceLast,
    balanceStatus,
    balanceDiff,
    smsStatus,
    callStatus,
    success,
    errors,
  ];

  static const _titles = <String, String>{
    date: 'Дата и время',
    sim: 'SIM (номер)',
    iccid: 'ICCID',
    operator: 'Оператор',
    scenario: 'Сценарий',
    balanceFirst: 'Первый баланс',
    balanceLast: 'Последний баланс',
    balanceStatus: 'Сверка баланса',
    balanceDiff: 'Изменение баланса',
    smsStatus: 'Статус SMS',
    callStatus: 'Статус звонка',
    success: 'Успешно',
    errors: 'Ошибки',
  };

  static bool isStep(String id) => id.startsWith('step:');

  static int stepNumber(String id) =>
      int.tryParse(id.substring(id.indexOf(':') + 1)) ?? 0;

  static String stepId(int number) => 'step:$number';

  /// Служебное поле с названием шага (для заголовка столбца).
  static String stepNameId(int number) => 'stepname:$number';

  static String title(String id) {
    if (isStep(id)) return 'Результат шага ${stepNumber(id)}';
    return _titles[id] ?? id;
  }

  /// Выбранные поля; пустой список — все поля, включая шаги до [maxStep].
  static List<String> resolve(List<String> selected, int maxStep) {
    if (selected.isNotEmpty) return selected;
    return [
      ...base,
      for (var i = 1; i <= maxStep; i++) stepId(i),
    ];
  }
}
