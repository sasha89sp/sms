import 'package:flutter_test/flutter_test.dart';
import 'package:huawei_modem_manager/models/app_settings.dart';
import 'package:huawei_modem_manager/models/excel_fields.dart';
import 'package:huawei_modem_manager/models/scenario.dart';
import 'package:huawei_modem_manager/services/excel_exporter.dart';
import 'package:huawei_modem_manager/services/sms_pdu.dart';
import 'package:huawei_modem_manager/services/ussd_codec.dart';

void main() {
  group('SmsPduDecoder', () {
    test('decodes classic GSM 7-bit SMS-DELIVER', () {
      final sms = SmsPduDecoder.decode(
          '07917283010010F5040BC87238880900F10000993092516195800AE8329BFD4697D9EC37');
      expect(sms, isNotNull);
      expect(sms!.text, 'hellohello');
      expect(sms.sender, '27838890001');
      expect(sms.outgoing, isFalse);
    });

    test('decodes UCS-2 SMS-DELIVER with international sender', () {
      final sms = SmsPduDecoder.decode(
          '00040B919700214365F70008621161818544210C041F04400438043204350442');
      expect(sms, isNotNull);
      expect(sms!.text, 'Привет');
      expect(sms.sender, '+79001234567');
      expect(sms.time, '2026-11-16 18:58:44');
    });

    test('merges concatenated parts into one message', () {
      final merged = SmsPduDecoder.decodeAndMerge(const [
        RawSms(
          storage: 'SM',
          index: 1,
          stat: 0,
          pdu: '00440B919700214365F70008621161818544210C050003AB0201041F04400438',
        ),
        RawSms(
          storage: 'SM',
          index: 2,
          stat: 0,
          pdu: '00440B919700214365F70008621161818544210C050003AB0202043204350442',
        ),
      ]);
      expect(merged, hasLength(1));
      expect(merged.first.text, 'Привет');
      expect(merged.first.refs, ['SM:1', 'SM:2']);
    });

    test('holds incomplete concatenated groups', () {
      final merged = SmsPduDecoder.decodeAndMerge(const [
        RawSms(
          storage: 'SM',
          index: 1,
          stat: 1,
          pdu: '00440B919700214365F70008621161818544210C050003AB0201041F04400438',
        ),
      ]);
      expect(merged, isEmpty);
    });
  });

  group('Balance and phone extraction from combined USSD', () {
    test('finds balance next to a label or currency', () {
      expect(UssdCodec.extractBalance('Баланс:2663,62р'), '2663.62');
      expect(UssdCodec.extractBalance('Ваш баланс 50.5 руб.'), '50.5');
      expect(UssdCodec.extractBalance('12,00 р.'), '12.00');
      expect(UssdCodec.extractBalance('Остаток: -3.4р'), '-3.4');
    });

    test('separates balance and phone number from a single combined response', () {
      const combined = 'Ваш номер +79991234567. Баланс: 150,50 руб.';
      expect(UssdCodec.extractBalance(combined), '150.50');
      expect(UssdCodec.extractPhoneNumber(combined), '+79991234567');

      const phoneOnly = 'Номер: 8 (916) 555-44-33';
      expect(UssdCodec.extractBalance(phoneOnly), '');
      expect(UssdCodec.extractPhoneNumber(phoneOnly), '+79165554433');
    });
  });

  group('Scenario', () {
    test('builds unique Excel column headers in step order', () {
      final scenario = Scenario(
        id: '1',
        name: 'Тест',
        steps: const [
          ScenarioStep(id: 'a', type: StepType.ownNumber, code: '*161#'),
          ScenarioStep(id: 'b', type: StepType.ussd, code: '*100#'),
          ScenarioStep(id: 'c', type: StepType.balance, code: '*100#'),
          ScenarioStep(id: 'd', type: StepType.sms, recipient: '+7900'),
          ScenarioStep(id: 'e', type: StepType.pause, seconds: 5),
          ScenarioStep(id: 'f', type: StepType.balance, code: '*100#'),
          ScenarioStep(id: 'g', type: StepType.ussd, code: '*100#'),
        ],
      );
      expect(scenario.columnHeaders(), [
        'Номер SIM',
        'USSD *100#',
        'Баланс 1 (*100#)',
        'SMS → +7900',
        null,
        'Баланс 2 (*100#)',
        'USSD *100# (2)',
      ]);
    });

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
    });

    test('AppSettings preserves SMS notification sound and volume', () {
      const defaults = AppSettings();
      expect(defaults.smsSoundEnabled, isTrue);
      expect(defaults.smsSoundVolume, closeTo(0.7, 0.001));

      final updated = defaults.copyWith(smsSoundEnabled: false, smsSoundVolume: 0.35);
      final restored = AppSettings.fromJson(updated.toJson());
      expect(restored.smsSoundEnabled, isFalse);
      expect(restored.smsSoundVolume, closeTo(0.35, 0.001));

      final clamped = AppSettings.fromJson({'smsSoundVolume': 1.5});
      expect(clamped.smsSoundVolume, 1.0);

      final withCols = defaults.copyWith(
        excelColumns: const ['sim', 'balance_first', 'step:1'],
        excelColumnTitles: const {'sim': 'Телефон', 'step:1': 'Баланс USSD'},
        excelColumnPresets: const {
          'Кратко': ['sim', 'balance_first'],
        },
      );
      final restoredCols = AppSettings.fromJson(withCols.toJson());
      expect(restoredCols.excelColumns, ['sim', 'balance_first', 'step:1']);
      expect(restoredCols.excelColumnTitles['sim'], 'Телефон');
      expect(restoredCols.excelColumnPresets['Кратко'], ['sim', 'balance_first']);

      final withAudio = defaults.copyWith(audioPort: 'COM21');
      final restoredAudio = AppSettings.fromJson(withAudio.toJson());
      expect(restoredAudio.audioPort, 'COM21');
    });
  });
}
