import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../models/call_info.dart';
<<<<<<< HEAD
import '../models/excel_fields.dart';
=======
>>>>>>> a25f356dea16092df8cedcd76460a90b086cf782
import '../models/scenario.dart';

part 'calls_page.dart';
part 'scenario_page.dart';
part 'settings_page.dart';
part 'sms_page.dart';
part 'ussd_page.dart';

const _blue = Color(0xFF246BCE);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE7EBF2);

Future<void> _perform<T>(
  BuildContext context,
  Future<T> Function() action, {
  String? successMessage,
}) async {
  try {
    await action();
    if (context.mounted && successMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
          backgroundColor: const Color(0xFFB42318),
        ),
      );
    }
  }
}

Widget _pageBody(Widget child) => Padding(
      padding: const EdgeInsets.all(24),
      child: child,
    );

class _PageHeader extends StatelessWidget {
  const _PageHeader(this.title, {this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700)),
                if (subtitle != null) ...[
                  const SizedBox(height: 5),
                  Text(subtitle!,
                      style: const TextStyle(color: _muted, fontSize: 12)),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: _line),
        ),
        child: child,
      );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.icon, this.note});
  final String label;
  final String value;
  final IconData? icon;
  final String? note;

  @override
  Widget build(BuildContext context) => _Panel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (icon != null) Icon(icon, size: 17, color: _blue),
              if (icon != null) const SizedBox(width: 7),
              Expanded(
                child: Text(label,
                    style: const TextStyle(color: _muted, fontSize: 11)),
              ),
            ]),
            const SizedBox(height: 12),
            Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (note != null) ...[
              const SizedBox(height: 5),
              Text(note!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 10)),
            ],
          ],
        ),
      );
}

class _StatusTag extends StatelessWidget {
  const _StatusTag(this.text, {this.good = false, this.warning = false});
  final String text;
  final bool good;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = good
        ? const Color(0xFF16845B)
        : warning
            ? const Color(0xFFB76E12)
            : _muted;
    final background = good
        ? const Color(0xFFE9F7F0)
        : warning
            ? const Color(0xFFFFF4E5)
            : const Color(0xFFF0F3F7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: background, borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, this.onNavigate});
  final ValueChanged<int>? onNavigate;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String? _selectedPort;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final info = c.modemInfo;
    return _pageBody(
      ListView(
        children: [
          _PageHeader(
            'Подключение',
            subtitle: 'Huawei E173 · управление USB-модемом',
            trailing: OutlinedButton.icon(
              onPressed: () => c.refreshPorts(),
              icon: const Icon(Icons.refresh, size: 17),
              label: const Text('Обновить порты'),
            ),
          ),
          const SizedBox(height: 18),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: c.isConnected
                          ? const Color(0xFFE9F7F0)
                          : const Color(0xFFFFF4E5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      c.isConnected ? Icons.usb_rounded : Icons.usb_off_rounded,
                      color: c.isConnected
                          ? const Color(0xFF16845B)
                          : const Color(0xFFB76E12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.isConnected ? 'Модем подключён' : 'Модем не подключён',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 3),
                        Text(c.connectionMessage,
                            style: const TextStyle(color: _muted, fontSize: 11)),
                      ],
                    ),
                  ),
                  _StatusTag(c.isConnected ? 'НА СВЯЗИ' : 'ОЖИДАНИЕ',
                      good: c.isConnected),
                ]),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: c.availablePorts.any((port) => port.name == _selectedPort) ? _selectedPort : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'COM-порт (необязательно)',
                          prefixIcon: Icon(Icons.settings_input_component),
                        ),
                        hint: const Text('Автоматически найти Huawei'),
                        items: c.availablePorts
                            .map((port) => DropdownMenuItem(
                                  value: port.name,
                                  child: Text(
                                    '${port.name}${port.isPcUiInterface ? ' · PC UI (рекомендуется)' : port.friendlyName.isNotEmpty ? ' · ${port.friendlyName}' : port.looksLikeHuawei ? ' · Huawei' : ''}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: (value) => setState(() => _selectedPort = value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: c.isScanning
                          ? null
                          : () => _perform(context, () async {
                                await c.connect(portName: _selectedPort);
                              }),
                      icon: c.isScanning
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.link, size: 17),
                      label: Text(c.isScanning ? 'Поиск…' : 'Подключить'),
                    ),
                    if (c.isConnected) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: c.isRunning || c.modem.isBusy
                            ? null
                            : () => _perform(context, c.disconnect),
                        icon: const Icon(Icons.link_off, size: 17),
                        label: const Text('Отключить'),
                      ),
                    ],
                  ],
                ),
                if (c.availablePorts.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Найдено COM-портов: ${c.availablePorts.length}. Автопоиск сначала проверяет Huawei PC UI — основной AT-интерфейс.',
                    style: const TextStyle(color: _muted, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth > 900 ? 4 : 2;
            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.8,
              children: [
                _Metric(label: 'Модель', value: info.model, icon: Icons.router),
                _Metric(
                    label: 'Оператор',
                    value: info.operatorName.isEmpty ? 'Не определён' : info.operatorName,
                    icon: Icons.cell_tower),
                _Metric(label: 'SIM-карта', value: info.simStatus, icon: Icons.sim_card),
                _Metric(
                    label: 'Уровень сигнала',
                    value: c.isConnected ? '${info.signalPercent}%' : '—',
                    icon: Icons.signal_cellular_alt,
                    note: info.signalDbm == null ? 'Нет показаний' : '${info.signalDbm} dBm'),
              ],
            );
          }),
          const SizedBox(height: 14),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Сведения об устройстве',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                _detailLine('COM-порт', info.port.isEmpty ? '—' : info.port),
                _detailLine('IMEI', info.imei.isEmpty ? '—' : info.imei),
                _detailLine('Прошивка', info.firmware.isEmpty ? '—' : info.firmware),
                _detailLine('Регистрация', info.registration),
                _detailLine('Тип сети', info.networkType),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Panel(
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Сценарии',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      SizedBox(height: 4),
                      Text('Настраиваемая последовательность: USSD, SMS, звонки, Excel',
                          style: TextStyle(color: _muted, fontSize: 11)),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: c.isConnected && !c.isRunning
                      ? () => widget.onNavigate?.call(1)
                      : null,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Открыть сценарий'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _detailLine(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(color: _muted, fontSize: 11))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
      ]),
    );

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});
  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  List<_ContactRow> _parse(String raw) {
    final result = <_ContactRow>[];
    final regex = RegExp(r'\+CPBR:\s*(\d+)\s*,\s*"([^"]*)"\s*,\s*(\d+)(?:\s*,\s*"([^"]*)")?');
    for (final match in regex.allMatches(raw)) {
      result.add(_ContactRow(int.tryParse(match.group(1) ?? '') ?? 0, match.group(2) ?? '', match.group(4) ?? ''));
    }
    return result;
  }

  Future<void> _editContact(BuildContext context, {int? index, String number = '', String name = ''}) async {
    final c = context.read<AppController>();
    final indexCtrl = TextEditingController(text: (index ?? 1).toString());
    final numberCtrl = TextEditingController(text: number);
    final nameCtrl = TextEditingController(text: name);
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(index == null ? 'Новый контакт' : 'Изменить контакт'),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: indexCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Ячейка SIM')),
        const SizedBox(height: 8), TextField(controller: numberCtrl, decoration: const InputDecoration(labelText: 'Номер')),
        const SizedBox(height: 8), TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Имя')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Сохранить'))],
    ));
    if (ok == true) {
      final slot = int.tryParse(indexCtrl.text) ?? 0;
      await _perform(context, () => c.writeContact(index: slot, number: numberCtrl.text.trim(), name: nameCtrl.text.trim()));
      await _perform(context, c.refreshContacts);
    }
    indexCtrl.dispose(); numberCtrl.dispose(); nameCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final contacts = _parse(c.contactsRaw);
    return _pageBody(ListView(children: [
      _PageHeader('Контакты', subtitle: 'Телефонная книга SIM-карты', trailing: Wrap(spacing: 7, children: [
        OutlinedButton.icon(onPressed: c.isConnected ? () => _perform(context, c.refreshContacts) : null, icon: const Icon(Icons.refresh, size: 16), label: const Text('Читать SIM')),
        FilledButton.icon(onPressed: c.isConnected ? () => _editContact(context) : null, icon: const Icon(Icons.person_add_alt_1, size: 16), label: const Text('Добавить')),
      ])),
      const SizedBox(height: 14),
      _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Найдено записей: ${contacts.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (contacts.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 22), child: Center(child: Text('Нажмите «Читать SIM», чтобы получить список контактов.', style: TextStyle(color: _muted, fontSize: 12))))
        else ...contacts.map((contact) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
          title: Text(contact.name.isEmpty ? contact.number : contact.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          subtitle: Text('${contact.number} · ячейка ${contact.index}', style: const TextStyle(fontSize: 11)),
          trailing: Wrap(children: [
            IconButton(tooltip: 'Изменить', onPressed: () => _editContact(context, index: contact.index, number: contact.number, name: contact.name), icon: const Icon(Icons.edit_outlined, size: 17)),
            IconButton(tooltip: 'Удалить', onPressed: () => _perform(context, () async { await c.deleteContact(contact.index); await c.refreshContacts(); }), icon: const Icon(Icons.delete_outline, size: 17)),
          ]),
        )),
        const SizedBox(height: 8),
        const Text('Изменение телефонной книги выполняется командой AT+CPBW. Если прошивка не поддерживает запись в SIM, модем вернёт ERROR.', style: TextStyle(color: _muted, fontSize: 10)),
      ])),
    ]));
  }
}

class _ContactRow {
  const _ContactRow(this.index, this.number, this.name);
  final int index;
  final String number;
  final String name;
}

class StatisticsPage extends StatelessWidget {
  const StatisticsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final info = c.modemInfo;
    return _pageBody(ListView(children: [
      _PageHeader('Статистика', subtitle: 'Состояние радиосети и параметры модема', trailing: OutlinedButton.icon(onPressed: c.isConnected ? () => _perform(context, c.refreshModemStatus) : null, icon: const Icon(Icons.refresh, size: 16), label: const Text('Обновить'))),
      const SizedBox(height: 14),
      LayoutBuilder(builder: (context, constraints) {
        final cols = constraints.maxWidth > 850 ? 3 : 2;
        return GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: cols, childAspectRatio: 1.65, crossAxisSpacing: 12, mainAxisSpacing: 12, children: [
          _Metric(label: 'Уровень сигнала', value: c.isConnected ? '${info.signalPercent}%' : '—', icon: Icons.signal_cellular_alt, note: info.signalDbm == null ? 'Нет показаний' : '${info.signalDbm} dBm'),
          _Metric(label: 'Регистрация', value: info.registration, icon: Icons.cell_tower),
          _Metric(label: 'Оператор', value: info.operatorName.isEmpty ? '—' : info.operatorName, icon: Icons.network_cell),
          _Metric(label: 'SIM-карта', value: info.simStatus, icon: Icons.sim_card),
          _Metric(label: 'COM-порт', value: info.port.isEmpty ? '—' : info.port, icon: Icons.usb),
          _Metric(label: 'Модель', value: info.model, icon: Icons.router),
        ]);
      }),
      const SizedBox(height: 14),
      _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Информация о сети', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _detailLine('Тип сети', info.networkType),
        _detailLine('Уровень CSQ', info.signalPercent == 0 ? 'Неизвестно / вне диапазона' : '${(info.signalPercent * 31 / 100).round()} из 31'),
        _detailLine('Входящий/исходящий трафик', 'Не реализовано: E173 не предоставляет универсальный счётчик через стандартный AT-набор'),
        _detailLine('Скорость соединения', 'Не измеряется этим AT-драйвером'),
      ])),
    ]));
  }
}

class LogsPage extends StatelessWidget {
  const LogsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    return _pageBody(ListView(children: [
      _PageHeader('Журнал', subtitle: 'История сценариев, ответы модема и системные события', trailing: FilledButton.icon(onPressed: () => _perform(context, c.exportOperationsCsv, successMessage: 'CSV-файл сохранён в документах'), icon: const Icon(Icons.download, size: 16), label: const Text('Экспорт CSV'))),
      const SizedBox(height: 14),
      _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Последние операции', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 9),
        if (c.operations.isEmpty) const Text('Операций пока нет.', style: TextStyle(color: _muted, fontSize: 12))
        else ...c.operations.take(30).map((row) => ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 10),
          leading: Icon(row['success'] == 1 ? Icons.check_circle : Icons.warning_amber_rounded, color: row['success'] == 1 ? const Color(0xFF16845B) : const Color(0xFFB76E12)),
          title: Text(row['started_at']?.toString() ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          subtitle: Text(row['success'] == 1 ? 'Успешно' : 'Завершено с ошибками', style: const TextStyle(fontSize: 10)),
          children: [
            _detailLine('Номер', row['phone_response']?.toString() ?? ''),
            _detailLine('Баланс до', row['balance_before']?.toString() ?? ''),
            _detailLine('SMS', row['sms_status']?.toString() ?? ''),
            _detailLine('Баланс после', row['balance_after']?.toString() ?? ''),
            SelectableText(row['details']?.toString() ?? '', style: const TextStyle(color: _muted, fontSize: 10)),
          ],
        )),
      ])),
      const SizedBox(height: 14),
      _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('События и AT-ответы', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 9),
        if (c.logs.isEmpty) const Text('Журнал пуст.', style: TextStyle(color: _muted, fontSize: 12))
        else ...c.logs.take(120).map((row) => ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          leading: Icon(_levelIcon(row['level']?.toString() ?? ''), size: 18, color: _levelColor(row['level']?.toString() ?? '')),
          title: Text(row['message']?.toString() ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          subtitle: Text('${row['created_at'] ?? ''} · ${row['level'] ?? ''}', style: const TextStyle(fontSize: 9, color: _muted)),
          children: [SelectableText(row['raw']?.toString() ?? '', style: const TextStyle(fontFamily: 'Consolas', fontSize: 10))],
        )),
      ])),
    ]));
  }

  IconData _levelIcon(String level) => level == 'ERROR' ? Icons.error_outline : level == 'SUCCESS' ? Icons.check_circle_outline : Icons.info_outline;
  Color _levelColor(String level) => level == 'ERROR' ? Colors.red : level == 'SUCCESS' ? const Color(0xFF16845B) : _muted;
}

class AtTerminalPage extends StatefulWidget {
  const AtTerminalPage({super.key});
  @override
  State<AtTerminalPage> createState() => _AtTerminalPageState();
}

class _AtTerminalPageState extends State<AtTerminalPage> {
  final _command = TextEditingController(text: 'AT');
  @override
  void dispose() { _command.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    return _pageBody(ListView(children: [
      _PageHeader('AT-терминал', subtitle: 'Ручная отправка AT-команд Huawei E173'),
      const SizedBox(height: 14),
      _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Команда', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: _command, onSubmitted: (_) => _send(context, c), decoration: const InputDecoration(hintText: 'AT+CSQ', prefixIcon: Icon(Icons.terminal)))),
          const SizedBox(width: 9),
          FilledButton.icon(onPressed: c.isConnected ? () => _send(context, c) : null, icon: const Icon(Icons.play_arrow, size: 17), label: const Text('Выполнить')),
        ]),
        const SizedBox(height: 8),
        const Text('Для отправки используется CR в конце команды. Не отправляйте неизвестные команды записи/сброса: они могут изменить настройки или очистить данные модема.', style: TextStyle(color: _muted, fontSize: 10)),
      ])),
      const SizedBox(height: 14),
      _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Expanded(child: Text('Ответы', style: TextStyle(fontWeight: FontWeight.w700))), TextButton(onPressed: c.clearTerminal, child: const Text('Очистить'))]),
        const SizedBox(height: 8),
        Container(width: double.infinity, constraints: const BoxConstraints(minHeight: 230), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF101A29), borderRadius: BorderRadius.circular(10)), child: SelectableText(c.terminalOutput.isEmpty ? 'Ожидание команды…' : c.terminalOutput, style: const TextStyle(color: Color(0xFFB9E4CB), fontFamily: 'Consolas', fontSize: 11, height: 1.5))),
      ])),
    ]));
  }

  Future<void> _send(BuildContext context, AppController c) async {
    await _perform(context, () => c.executeTerminalCommand(_command.text));
    if (mounted) setState(() {});
  }
}

const int UCS2DcsValue = 72;

void _showInfo(BuildContext context, String title, String message) {
  showDialog<void>(context: context, builder: (context) => AlertDialog(title: Text(title), content: Text(message), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть'))]));
}
