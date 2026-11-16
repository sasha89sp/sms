import 'package:flutter_test/flutter_test.dart';
import 'package:huawei_modem_manager/services/sms_pdu.dart';
import 'package:huawei_modem_manager/services/ussd_codec.dart';

void main() {
  group('SmsPduEncoder', () {
    test('creates one UCS-2 SMS segment for short text', () {
      final parts = SmsPduEncoder.encodeUcs2(
        recipient: '+79001234567',
        message: 'Тест',
        requestStatusReport: false,
      );

      expect(parts, hasLength(1));
      expect(parts.first.pdu.startsWith('0001000B91'), isTrue);
      expect(parts.first.pdu.contains('08'), isTrue);
      expect(parts.first.tpduLength, parts.first.pdu.length ~/ 2 - 1);
    });

    test('splits long text into concatenated segments', () {
      final parts = SmsPduEncoder.encodeUcs2(
        recipient: '89001234567',
        message: List.filled(140, 'Я').join(),
        reference: 0x5A,
      );

      expect(parts.length, greaterThan(1));
      expect(parts.first.pdu.contains('0500035A'), isTrue);
      for (final part in parts) {
        expect(part.pdu.length ~/ 2, lessThanOrEqualTo(141));
        expect(part.tpduLength, part.pdu.length ~/ 2 - 1);
      }
    });

    test('rejects invalid recipient', () {
      expect(
        () => SmsPduEncoder.encodeUcs2(recipient: '123', message: 'Hi'),
        throwsArgumentError,
      );
    });
  });

  group('UssdCodec', () {
    test('decodes UCS-2 response from Huawei modem', () {
      // "Баланс 50"
      const response = '+CUSD: 0,"04110430043B0430043D0441002000350030",72';
      expect(UssdCodec.decodeHuaweiResponse(response), 'Баланс 50');
    });

    test('extracts Russian phone number', () {
      expect(
        UssdCodec.extractPhoneNumber('Ваш номер: 8 (900) 123-45-67'),
        '+79001234567',
      );
    });

    test('recognizes network-side USSD error status', () {
      expect(
        UssdCodec.decodeHuaweiResponse('+CUSD: 2'),
        startsWith('Ошибка USSD'),
      );
    });
  });
}
