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

      // 140 UCS-2 code units require three concatenated messages:
      // 67 + 67 + 6 code units. The 6-byte concatenation UDH is part
      // of TP-UD, whose maximum size is 140 octets. The complete PDU is
      // longer than 140 bytes because it also contains the SMSC/TPDU
      // addressing and control fields.
      expect(parts, hasLength(3));
      expect(parts.first.pdu.contains('0500035A0301'), isTrue);
      expect(parts[1].pdu.contains('0500035A0302'), isTrue);
      expect(parts[2].pdu.contains('0500035A0303'), isTrue);
      for (final part in parts) {
        final bytes = part.pdu.length ~/ 2;
        final userDataLength = int.parse(part.pdu.substring(26, 28), radix: 16);
        expect(userDataLength, lessThanOrEqualTo(140));
        expect(part.tpduLength, bytes - 1);
      }
      expect(int.parse(parts.first.pdu.substring(26, 28), radix: 16), 140);
      expect(int.parse(parts[1].pdu.substring(26, 28), radix: 16), 140);
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

    test('encodes USSD request to packed 7-bit hex', () {
      expect(UssdCodec.encodeGsm7PackedHex('*100#'), 'AA180C3602');
      expect(UssdCodec.decodeGsm7PackedHex('AA180C3602'), '*100#');
    });

    test('decodes packed 7-bit hex reply (not mistaken for UCS-2)', () {
      final hex = UssdCodec.encodeGsm7PackedHex('Balance 123.45 rub');
      expect(hex.length % 4, 0);
      expect(UssdCodec.decodeHuaweiResponse('+CUSD: 0,"$hex",15'),
          'Balance 123.45 rub');
    });

    test('plain text reply is returned as is', () {
      expect(UssdCodec.decodeHuaweiResponse('+CUSD: 0,"Balance: 50.2 rub",15'),
          'Balance: 50.2 rub');
    });
  });
}
