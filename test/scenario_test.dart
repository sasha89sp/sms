import 'package:flutter_test/flutter_test.dart';
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

    test('ExcelExporter integration check', () {
      final exporter = ExcelExporter();
      expect(exporter, isNotNull);
    });
  });
}
