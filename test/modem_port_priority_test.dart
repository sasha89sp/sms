import 'package:flutter_test/flutter_test.dart';
import 'package:huawei_modem_manager/models/modem_info.dart';

void main() {
  group('ModemPortInfo automatic selection', () {
    test('PC UI interface has priority over modem and application ports', () {
      const pcUi = ModemPortInfo(
        name: 'COM22',
        friendlyName: 'Huawei Mobile Connect - 3G PC UI Interface',
        manufacturer: 'Huawei',
      );
      const modem = ModemPortInfo(
        name: 'COM21',
        friendlyName: 'Huawei Mobile Connect Modem',
        manufacturer: 'Huawei',
      );
      const application = ModemPortInfo(
        name: 'COM20',
        friendlyName: 'Huawei Mobile Connect - 3G Application Interface',
        manufacturer: 'Huawei',
      );

      expect(pcUi.isPcUiInterface, isTrue);
      expect(pcUi.autoConnectPriority, lessThan(modem.autoConnectPriority));
      expect(pcUi.autoConnectPriority, lessThan(application.autoConnectPriority));
      expect(modem.autoConnectPriority, lessThan(application.autoConnectPriority));
    });
  });
}
