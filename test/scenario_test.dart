import 'package:flutter_test/flutter_test.dart';
<<<<<<< HEAD
import 'package:huawei_modem_manager/models/excel_fields.dart';
=======
>>>>>>> f098d7b0a7509c8378736718f56bf7eacebf9ad0
import 'package:huawei_modem_manager/models/scenario.dart';
import 'package:huawei_modem_manager/services/excel_exporter.dart';

void main() {
  group('Scenario Model & Exporter Tests', () {
    test('ScenarioItem serialization roundtrip', () {
      final jsonMap = {
        'id': 'test_id_1',
        'name': 'Auto USSD Check',
        'description': 'Periodically checks balance via USSD',
        'enabled': true,
        'steps': [
          {
            'id': 'step_1',
            'type': 'ussd',
            'value': '*100#',
            'waitMs': 2000,
          }
        ]
      };

      final scenario = ScenarioItem.fromJson(jsonMap);
      expect(scenario.id, equals('test_id_1'));
      expect(scenario.name, equals('Auto USSD Check'));
      expect(scenario.enabled, isTrue);
      expect(scenario.steps.length, equals(1));
      expect(scenario.steps[0].value, equals('*100#'));
      expect(scenario.steps[0].waitMs, equals(2000));

      final exportedJson = scenario.toJson();
      expect(exportedJson['id'], equals(jsonMap['id']));
      expect(exportedJson['name'], equals(jsonMap['name']));
      expect(exportedJson['enabled'], equals(jsonMap['enabled']));
      expect((exportedJson['steps'] as List).length, equals(1));
    });

    test('ScenarioStep default waitMs value', () {
      final step = ScenarioStep(
        id: 's2',
        type: 'sms',
        value: 'Hello',
      );
      expect(step.waitMs, equals(1000));
    });

<<<<<<< HEAD
    test('matches operator by substring, empty filter matches any', () {
      const any = Scenario(id: '1', name: 'a');
      const mts = Scenario(id: '2', name: 'b', operator: 'mts, beeline');
      expect(any.matchesOperator('Whatever'), isTrue);
      expect(mts.matchesOperator('MTS RUS'), isTrue);
      expect(mts.matchesOperator('Beeline'), isTrue);
      expect(mts.matchesOperator('MegaFon'), isFalse);
    });

    test('survives JSON round trip', () {
      final scenario = Scenario(
        id: 'x',
        name: 'Сценарий',
        autoRun: true,
        operator: 'МТС',
        steps: [ScenarioStep.create(StepType.call).copyWith(recipient: '+7900')],
      );
      final copy = Scenario.fromJson(scenario.toJson());
      expect(copy.name, 'Сценарий');
      expect(copy.autoRun, isTrue);
      expect(copy.steps.single.type, StepType.call);
      expect(copy.steps.single.recipient, '+7900');
    });
  });

  group('Excel layout', () {
    test('resolves all columns including steps when selection is empty', () {
      final ids = ExcelFields.resolve(const [], 2);
      expect(ids.first, ExcelFields.date);
      expect(ids.contains('step:1'), isTrue);
      expect(ids.last, 'step:2');
    });

    test('keeps the chosen order', () {
      expect(ExcelFields.resolve(const ['step:3', 'sim'], 5), ['step:3', 'sim']);
    });

    test('reads values by field id from raw results', () {
      final row = RunRow(
        startedAt: DateTime(2026, 11, 18, 10, 5, 7),
        scenarioName: 'Тест',
        fields: {'sim': const CellData('+7900'), 'step:2': const CellData('12.5', number: 12.5)},
        success: true,
      );
      expect(ExcelExporter.maxStep([row]), 2);
      expect(ExcelExporter.columns(const [], [row]).contains('step:2'), isTrue);
      expect(ExcelExporter.header('date', [row]), 'Дата и время');
    });

    test('fields survive JSON round trip and legacy conversion', () {
      final encoded = RunRow.encodeFields({'sim': const CellData('1', number: 1)});
      expect(RunRow.decodeFields(encoded)['sim']!.number, 1);
      final legacy = RunRow.fromLegacy(
        '["SIM","USSD *100#","Сверка баланса"]',
        '[{"t":"+7"},{"t":"ok"},{"t":"СОВПАЛ"}]',
      );
      expect(legacy['sim']!.text, '+7');
      expect(legacy['step:1']!.text, 'ok');
      expect(legacy['balance_status']!.text, 'СОВПАЛ');
    });

    test('call actions and balance-SMS options survive JSON', () {
      final step = ScenarioStep.create(StepType.call).copyWith(
        actions: const [CallAction(at: 3, isPhrase: true, value: 'да')],
      );
      final copy = ScenarioStep.fromJson(step.toJson());
      expect(copy.actions.single.at, 3);
      expect(copy.actions.single.value, 'да');
      final balance = ScenarioStep.create(StepType.balance).copyWith(smsTimeout: 90, smsSender: 'MTS');
      final back = ScenarioStep.fromJson(balance.toJson());
      expect(back.waitSms, isTrue);
      expect(back.smsTimeout, 90);
      expect(back.smsSender, 'MTS');
=======
    test('ExcelExporter integration check', () {
      final exporter = ExcelExporter();
      expect(exporter, isNotNull);
>>>>>>> f098d7b0a7509c8378736718f56bf7eacebf9ad0
    });
  });
}
