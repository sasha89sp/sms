import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import 'pages.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  static const _navigation = <_NavigationItem>[
    _NavigationItem('Обзор', Icons.dashboard_rounded),
    _NavigationItem('Сценарии', Icons.account_tree_rounded),
    _NavigationItem('SMS', Icons.mark_email_unread_rounded),
    _NavigationItem('Вызовы', Icons.call_rounded),
    _NavigationItem('Контакты', Icons.contacts_rounded),
    _NavigationItem('Статистика', Icons.network_check_rounded),
    _NavigationItem('USSD и баланс', Icons.account_balance_wallet_rounded),
    _NavigationItem('Журнал', Icons.receipt_long_rounded),
    _NavigationItem('AT-терминал', Icons.terminal_rounded),
    _NavigationItem('Настройки', Icons.settings_rounded),
  ];

  Widget _pageForIndex(int index) {
    switch (index) {
      case 0:
        return DashboardPage(onNavigate: (value) => setState(() => _selectedIndex = value));
      case 1:
        return ScenariosPage();
      case 2:
        return SmsPage();
      case 3:
        return CallsPage();
      case 4:
        return ContactsPage();
      case 5:
        return StatisticsPage();
      case 6:
        return UssdPage();
      case 7:
        return LogsPage();
      case 8:
        return AtTerminalPage();
      case 9:
        return SettingsPage();
      default:
        return DashboardPage(onNavigate: (value) => setState(() => _selectedIndex = value));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final selected = _navigation[_selectedIndex];
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 238,
            color: const Color(0xFF111C2D),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 19),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Image.asset(
                          'assets/app_icon.ico',
                          width: 38,
                          height: 38,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 38,
                            height: 38,
                            color: const Color(0xFF246BCE),
                            child: const Icon(Icons.router_rounded, color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(width: 11),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('HUAWEI',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                )),
                            Text('MODEM MANAGER · v2.1.15',
                                style: TextStyle(
                                  color: Color(0xFF8EA0B8),
                                  fontSize: 9,
                                  letterSpacing: 1.0,
                                )),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const Padding(
                  padding: EdgeInsets.fromLTRB(19, 0, 12, 9),
                  child: Text('УПРАВЛЕНИЕ',
                      style: TextStyle(
                        color: Color(0xFF6F829C),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      )),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _navigation.length,
                    itemBuilder: (context, index) {
                      final item = _navigation[index];
                      final active = _selectedIndex == index;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(9),
                          onTap: () => setState(() => _selectedIndex = index),
                          child: Container(
                            height: 42,
                            padding: const EdgeInsets.symmetric(horizontal: 11),
                            decoration: BoxDecoration(
                              color: active
                                  ? const Color(0xFF223D61)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Row(
                              children: [
                                Icon(item.icon,
                                    size: 18,
                                    color: active
                                        ? const Color(0xFF78B4FF)
                                        : const Color(0xFF91A1B6)),
                                const SizedBox(width: 12),
                                Text(item.title,
                                    style: TextStyle(
                                      color: active
                                          ? Colors.white
                                          : const Color(0xFFB7C3D2),
                                      fontSize: 13,
                                      fontWeight:
                                          active ? FontWeight.w600 : FontWeight.w400,
                                    )),
                                if (index == 2 && controller.unreadSms > 0) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2E7BE6),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text('${controller.unreadSms}',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B2A40),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2B3C54)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: controller.isConnected
                              ? const Color(0xFF41CF91)
                              : const Color(0xFFF0A44B),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              controller.isConnected ? 'Модем подключён' : 'Нет подключения',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              controller.isConnected
                                  ? controller.modemInfo.port
                                  : 'Ожидание Huawei E173',
                              style: const TextStyle(
                                color: Color(0xFF93A4BA),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 15),
                  child: Text('Версия 2.1.15',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF667990), fontSize: 10)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 66,
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF7F9FC),
                    border: Border(bottom: BorderSide(color: Color(0xFFE7EBF2))),
                  ),
                  child: Row(
                    children: [
                      Text(selected.title,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Icon(
                        controller.isConnected
                            ? Icons.usb_rounded
                            : Icons.usb_off_rounded,
                        size: 17,
                        color: controller.isConnected
                            ? const Color(0xFF23885F)
                            : const Color(0xFF8E9BAC),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        controller.isConnected
                            ? '${controller.modemInfo.operatorName.isEmpty ? 'Сеть подключена' : controller.modemInfo.operatorName} · ${controller.activePort}'
                            : 'Ожидание устройства',
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                      ),
                      const SizedBox(width: 18),
                      IconButton(
                        tooltip: 'Обновить список COM-портов',
                        onPressed: controller.refreshPorts,
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: KeyedSubtree(
                      key: ValueKey(_selectedIndex),
                      child: _pageForIndex(_selectedIndex),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationItem {
  const _NavigationItem(this.title, this.icon);
  final String title;
  final IconData icon;
}
