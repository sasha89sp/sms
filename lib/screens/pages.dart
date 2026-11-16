import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../models/app_settings.dart';
import '../models/sms_item.dart';

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
                      Text('Автоматическая операция',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      SizedBox(height: 4),
                      Text('Номер → баланс → SMS → баланс',
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

class AutomationPage extends StatelessWidget {
  const AutomationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final items = c.scenarioResults.entries.toList();
    return _pageBody(ListView(children: [
      _PageHeader(
        'Автоматизация',
        subtitle: 'Последовательность из четырёх операций',
        trailing: FilledButton.icon(
          onPressed: c.isConnected && !c.isRunning
              ? () => _perform(context, () => c.runScenario())
              : null,
          icon: c.isRunning
              ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.play_arrow_rounded),
          label: Text(c.isRunning ? 'Выполняется…' : 'Запустить вручную'),
        ),
      ),
      const SizedBox(height: 16),
      _Panel(
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: c.settings.autoStart,
          onChanged: (value) => _perform(
            context,
            () => c.updateSettings(c.settings.copyWith(autoStart: value)),
            successMessage: value ? 'Автозапуск включён' : 'Автозапуск выключен',
          ),
          title: const Text('Автоматический запуск после регистрации в сети',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          subtitle: const Text(
            'После подключения модема программа дождётся готовности SIM и регистрации в сети, затем выполнит сценарий один раз для текущего подключения.',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
        ),
      ),
      if (c.autoModeWaiting) ...[
        const SizedBox(height: 10),
        const _Panel(child: Row(children: [
          Icon(Icons.hourglass_top_rounded, color: Color(0xFFB76E12), size: 18),
          SizedBox(width: 9),
          Expanded(child: Text('Автозапуск включён: ожидается регистрация SIM-карты в сети.', style: TextStyle(fontSize: 11))),
        ])),
      ],
      const SizedBox(height: 14),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Ход выполнения', style: TextStyle(fontWeight: FontWeight.w700))),
            _StatusTag(c.isRunning ? 'ВЫПОЛНЯЕТСЯ' : c.currentStep.contains('ошиб') ? 'ЕСТЬ ОШИБКИ' : 'ГОТОВ',
                good: !c.isRunning && c.currentStep.contains('успешно'),
                warning: c.currentStep.contains('ошиб')),
          ]),
          const SizedBox(height: 8),
          Text(c.currentStep, style: const TextStyle(color: _muted, fontSize: 11)),
          const SizedBox(height: 16),
          ...List.generate(items.length, (index) {
            final entry = items[index];
            final running = entry.value == 'Выполняется…';
            final error = entry.value.startsWith('ОШИБКА') || entry.value.startsWith('НЕ ОТПРАВЛЕНО');
            final pending = entry.value == 'Ожидает выполнения';
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 27,
                  height: 27,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: error ? const Color(0xFFFFECEB) : running ? const Color(0xFFEAF2FF) : pending ? const Color(0xFFF0F3F7) : const Color(0xFFE9F7F0),
                  ),
                  child: Icon(error ? Icons.close : running ? Icons.sync : pending ? Icons.schedule : Icons.check,
                      size: 15, color: error ? Colors.red : running ? _blue : pending ? _muted : const Color(0xFF16845B)),
                ),
                const SizedBox(width: 11),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${index + 1}. ${entry.key}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 3),
                  SelectableText(entry.value, style: TextStyle(fontSize: 11, color: error ? Colors.red.shade700 : _muted)),
                ])),
              ]),
            );
          }),
        ]),
      ),
      const SizedBox(height: 14),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Параметры сценария', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 9),
          _detailLine('USSD номера', c.settings.numberUssd.isEmpty ? 'Не задан' : c.settings.numberUssd),
          _detailLine('USSD баланса', c.settings.balanceUssd),
          _detailLine('Получатель SMS', c.settings.smsRecipient.isEmpty ? 'Не задан' : c.settings.smsRecipient),
          _detailLine('Текст SMS', c.settings.smsText.isEmpty ? 'Не задан' : c.settings.smsText),
          const SizedBox(height: 4),
          Align(alignment: Alignment.centerRight, child: TextButton.icon(
            onPressed: () => _showInfo(context, 'Параметры сценария', 'Коды USSD, номер получателя и текст SMS настраиваются в разделе «Настройки». Не используйте неизвестные USSD-команды: некоторые из них могут подключать платные услуги или менять тариф.'),
            icon: const Icon(Icons.info_outline, size: 16), label: const Text('Важно'),
          )),
        ]),
      ),
    ]));
  }
}

class SmsPage extends StatefulWidget {
  const SmsPage({super.key});
  @override
  State<SmsPage> createState() => _SmsPageState();
}

class _SmsPageState extends State<SmsPage> {
  late final TextEditingController _recipient;
  late final TextEditingController _message;
  String _filter = 'Все';

  @override
  void initState() {
    super.initState();
    final settings = context.read<AppController>().settings;
    _recipient = TextEditingController(text: settings.smsRecipient);
    _message = TextEditingController(text: settings.smsText);
  }

  @override
  void dispose() {
    _recipient.dispose();
    _message.dispose();
    super.dispose();
  }

  bool _isIncoming(SmsItem item) => item.status.toUpperCase().contains('REC');

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final visible = c.messages.where((m) => _filter == 'Все' || (_filter == 'Входящие' ? _isIncoming(m) : !_isIncoming(m))).toList();
    return _pageBody(ListView(children: [
      _PageHeader('SMS', subtitle: 'Чтение сообщений SIM-карты и отправка SMS на заданный номер', trailing: OutlinedButton.icon(
        onPressed: c.isConnected && !c.isLoadingMessages ? () => _perform(context, c.refreshMessages) : null,
        icon: c.isLoadingMessages ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh, size: 17),
        label: const Text('Обновить'),
      )),
      const SizedBox(height: 14),
      _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Новое сообщение', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        TextField(controller: _recipient, decoration: const InputDecoration(labelText: 'Номер получателя', hintText: '+7 900 000-00-00', prefixIcon: Icon(Icons.phone_android))),
        const SizedBox(height: 10),
        TextField(controller: _message, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Текст SMS', alignLabelWithHint: true)),
        const SizedBox(height: 10),
        Row(children: [
          const Expanded(child: Text('Русский текст отправляется в UCS-2; длинные SMS разбиваются на части.', style: TextStyle(color: _muted, fontSize: 10))),
          FilledButton.icon(
            onPressed: c.isConnected ? () => _perform(context, () async {
              await c.sendSmsManually(_recipient.text.trim(), _message.text);
            }, successMessage: 'Команда отправки принята модемом') : null,
            icon: const Icon(Icons.send_rounded, size: 16), label: const Text('Отправить'),
          ),
        ]),
      ])),
      const SizedBox(height: 14),
      _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Память сообщений модема', style: TextStyle(fontWeight: FontWeight.w700))),
          Text('${visible.length} шт.', style: const TextStyle(color: _muted, fontSize: 11)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 7, children: ['Все', 'Входящие', 'Исходящие'].map((v) => ChoiceChip(label: Text(v), selected: _filter == v, onSelected: (_) => setState(() => _filter = v))).toList()),
        const SizedBox(height: 9),
        if (visible.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('Сообщения не загружены или список пуст.', style: TextStyle(color: _muted, fontSize: 12))))
        else
          ...visible.map((item) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(backgroundColor: const Color(0xFFEAF2FF), child: Icon(_isIncoming(item) ? Icons.call_received : Icons.call_made, color: _blue, size: 17)),
            title: Text(item.sender.isEmpty ? 'Неизвестный отправитель' : item.sender, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            subtitle: Text('${item.status}${item.timestamp.isEmpty ? '' : ' · ${item.timestamp}'}\n${item.body}', maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
            isThreeLine: true,
            trailing: IconButton(tooltip: 'Удалить из памяти SIM', icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _perform(context, () => c.deleteMessage(item.index))),
          )),
        const SizedBox(height: 4),
        const Text('Примечание: папки «Черновики», «Важные», «Удалённые» и отчёты зависят от функций прошивки. Эта версия читает статусы REC/ STO из хранилища модема.', style: TextStyle(color: _muted, fontSize: 10)),
      ])),
    ]));
  }
}

class CallsPage extends StatefulWidget {
  const CallsPage({super.key});
  @override
  State<CallsPage> createState() => _CallsPageState();
}

class _CallsPageState extends State<CallsPage> {
  final _number = TextEditingController();
  @override
  void dispose() { _number.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    return _pageBody(ListView(children: [
      _PageHeader('Вызовы', subtitle: 'Управление голосовой связью через AT-команды модема'),
      const SizedBox(height: 14),
      _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Набор номера', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 11),
        Row(children: [
          Expanded(child: TextField(controller: _number, keyboardType: TextInputType.phone, decoration: const InputDecoration(prefixIcon: Icon(Icons.phone), hintText: '+7 900 000-00-00'))),
          const SizedBox(width: 9),
          FilledButton.icon(onPressed: c.isConnected ? () => _perform(context, () => c.dial(_number.text.trim())) : null, icon: const Icon(Icons.call, size: 16), label: const Text('Позвонить')),
          const SizedBox(width: 7),
          OutlinedButton.icon(onPressed: c.isConnected ? () => _perform(context, c.hangUp) : null, icon: const Icon(Icons.call_end, size: 16), label: const Text('Отбой')),
        ]),
        const SizedBox(height: 10),
        const Text('Важно: Huawei E173 обычно используется как 3G-модем. Голосовые вызовы могут быть отключены аппаратно, тарифом или прошивкой; наличие ATD-команды не гарантирует поддержку голосового режима.', style: TextStyle(color: _muted, fontSize: 11)),
      ])),
      const SizedBox(height: 14),
      _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Expanded(child: Text('Текущий вызов (AT+CLCC)', style: TextStyle(fontWeight: FontWeight.w700))), TextButton.icon(onPressed: c.isConnected ? () => _perform(context, c.refreshCalls) : null, icon: const Icon(Icons.refresh, size: 15), label: const Text('Проверить'))]),
        SelectableText(c.callsRaw.isEmpty ? 'Нет данных. AT+CLCC показывает активные вызовы, а не историю завершённых звонков.' : c.callsRaw, style: const TextStyle(fontFamily: 'Consolas', fontSize: 12)),
      ])),
    ]));
  }
}

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

class BalancePage extends StatefulWidget {
  const BalancePage({super.key});
  @override
  State<BalancePage> createState() => _BalancePageState();
}

class _BalancePageState extends State<BalancePage> {
  late final TextEditingController _code;
  @override
  void initState() { super.initState(); _code = TextEditingController(text: context.read<AppController>().settings.balanceUssd); }
  @override
  void dispose() { _code.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final response = c.lastUssdResponse;
    return _pageBody(ListView(children: [
      _PageHeader('Баланс', subtitle: 'Ручная проверка счёта через USSD'),
      const SizedBox(height: 14),
      _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('USSD-команда', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 11),
        Row(children: [
          Expanded(child: TextField(controller: _code, decoration: const InputDecoration(prefixIcon: Icon(Icons.dialpad), hintText: '*100#'))),
          const SizedBox(width: 9),
          FilledButton.icon(onPressed: c.isConnected ? () => _perform(context, () async { await c.runUssdManually(_code.text.trim()); }) : null, icon: const Icon(Icons.send, size: 16), label: const Text('Проверить')),
        ]),
      ])),
      const SizedBox(height: 14),
      _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Ответ оператора', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (response.isEmpty) const Text('Ответ ещё не получен.', style: TextStyle(color: _muted, fontSize: 12)) else SelectableText(response, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        if (response.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Последняя проверка: ${DateTime.now().toLocal()}', style: const TextStyle(color: _muted, fontSize: 10)),
        ],
      ])),
      const SizedBox(height: 14),
      _Panel(child: const Text('Важно: USSD-коды различаются у операторов и тарифов. Команда по умолчанию *100# является примером, а не гарантированно правильным кодом вашей SIM-карты.', style: TextStyle(color: _muted, fontSize: 11))),
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

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _numberCode;
  late final TextEditingController _balanceCode;
  late final TextEditingController _recipient;
  late final TextEditingController _smsText;
  late final TextEditingController _networkWait;
  late final TextEditingController _ussdTimeout;
  late final TextEditingController _retries;
  String _port = '';
  int _baud = 115200;
  int _dcs = 15;
  bool _autoStart = false;
  bool _autoConnect = true;
  bool _statusReport = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppController>().settings;
    _numberCode = TextEditingController(text: s.numberUssd);
    _balanceCode = TextEditingController(text: s.balanceUssd);
    _recipient = TextEditingController(text: s.smsRecipient);
    _smsText = TextEditingController(text: s.smsText);
    _networkWait = TextEditingController(text: s.networkWaitSeconds.toString());
    _ussdTimeout = TextEditingController(text: s.ussdTimeoutSeconds.toString());
    _retries = TextEditingController(text: s.retryCount.toString());
    _port = s.preferredPort;
    _baud = s.baudRate;
    _dcs = s.ussdDcs;
    _autoStart = s.autoStart;
    _autoConnect = s.autoConnect;
    _statusReport = s.smsRequireNetworkAck;
  }

  @override
  void dispose() {
    _numberCode.dispose(); _balanceCode.dispose(); _recipient.dispose(); _smsText.dispose();
    _networkWait.dispose(); _ussdTimeout.dispose(); _retries.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    return _pageBody(ListView(children: [
      const _PageHeader('Настройки', subtitle: 'Параметры соединения, USSD, SMS и автоматического сценария'),
      const SizedBox(height: 14),
      _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Подключение к модему', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 11),
        DropdownButtonFormField<String>(value: _port.isEmpty ? null : _port, decoration: const InputDecoration(labelText: 'Предпочтительный COM-порт', prefixIcon: Icon(Icons.usb)), hint: const Text('Автоматический поиск'), items: [
          const DropdownMenuItem(value: '', child: Text('Автоматический поиск')),
          if (_port.isNotEmpty && !c.availablePorts.any((item) => item.name == _port))
            DropdownMenuItem(value: _port, child: Text('$_port · сейчас не найден')),
          ...c.availablePorts.map((p) => DropdownMenuItem(value: p.name, child: Text('${p.name} · ${p.friendlyName.isEmpty ? 'COM-порт' : p.friendlyName}'))),
        ], onChanged: (value) => setState(() => _port = value ?? '')),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(value: _baud, decoration: const InputDecoration(labelText: 'Скорость порта (baud)'), items: const [9600, 19200, 38400, 57600, 115200].map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(), onChanged: (value) => setState(() => _baud = value ?? 115200)),
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: _autoConnect, onChanged: (value) => setState(() => _autoConnect = value), title: const Text('Автоматически подключаться при появлении модема', style: TextStyle(fontSize: 12))),
      ])),
      const SizedBox(height: 12),
      _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('USSD и автоматическая операция', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        TextField(controller: _numberCode, decoration: const InputDecoration(labelText: 'USSD для определения номера', hintText: '*161#')),
        const SizedBox(height: 9),
        TextField(controller: _balanceCode, decoration: const InputDecoration(labelText: 'USSD для проверки баланса', hintText: '*100#')),
        const SizedBox(height: 9),
        DropdownButtonFormField<int>(value: _dcs, decoration: const InputDecoration(labelText: 'DCS для USSD'), items: const [15, 72,  UCS2DcsValue].map((v) => DropdownMenuItem(value: v, child: Text(v == 72 ? '72 — UCS-2 (часто для кириллицы)' : v == 15 ? '15 — стандартная таблица' : '$v'))).toList(), onChanged: (value) => setState(() => _dcs = value ?? 15)),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: _autoStart, onChanged: (value) => setState(() => _autoStart = value), title: const Text('Автозапуск после регистрации в сети', style: TextStyle(fontSize: 12)), subtitle: const Text('Один запуск на каждое подключение модема.', style: TextStyle(fontSize: 10))),
      ])),
      const SizedBox(height: 12),
      _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('SMS', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        TextField(controller: _recipient, decoration: const InputDecoration(labelText: 'Номер получателя', hintText: '+79000000000')),
        const SizedBox(height: 9),
        TextField(controller: _smsText, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Текст сообщения', alignLabelWithHint: true)),
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: _statusReport, onChanged: (value) => setState(() => _statusReport = value), title: const Text('Запрашивать сетевой отчёт о доставке', style: TextStyle(fontSize: 12)), subtitle: const Text('Отчёт может не поддерживаться оператором или прошивкой. Сам ответ +CMGS не подтверждает доставку.', style: TextStyle(fontSize: 10))),
      ])),
      const SizedBox(height: 12),
      _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Таймауты и повторы', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _numberField(_networkWait, 'Ожидание сети, секунд'),
        const SizedBox(height: 9), _numberField(_ussdTimeout, 'Таймаут USSD, секунд'),
        const SizedBox(height: 9), _numberField(_retries, 'Количество повторов USSD (0–5)'),
      ])),
      const SizedBox(height: 14),
      Row(children: [
        const Expanded(child: Text('Настройки сохраняются на этом компьютере.', style: TextStyle(color: _muted, fontSize: 10))),
        FilledButton.icon(onPressed: () => _save(context), icon: const Icon(Icons.save, size: 16), label: const Text('Сохранить настройки')),
      ]),
    ]));
  }

  Widget _numberField(TextEditingController controller, String label) => TextField(controller: controller, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: label));

  Future<void> _save(BuildContext context) async {
    final networkWait = int.tryParse(_networkWait.text) ?? 180;
    final timeout = int.tryParse(_ussdTimeout.text) ?? 45;
    final retries = int.tryParse(_retries.text) ?? 1;
    if (networkWait < 10 || networkWait > 1800 || timeout < 5 || timeout > 180 || retries < 0 || retries > 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Проверьте таймауты и количество повторов.')));
      return;
    }
    final settings = AppSettings(
      preferredPort: _port,
      baudRate: _baud,
      numberUssd: _numberCode.text.trim(),
      balanceUssd: _balanceCode.text.trim(),
      smsRecipient: _recipient.text.trim(),
      smsText: _smsText.text,
      ussdDcs: _dcs,
      autoStart: _autoStart,
      autoConnect: _autoConnect,
      networkWaitSeconds: networkWait,
      ussdTimeoutSeconds: timeout,
      retryCount: retries,
      smsRequireNetworkAck: _statusReport,
    );
    await _perform(context, () => context.read<AppController>().updateSettings(settings), successMessage: 'Настройки сохранены');
  }
}

const int UCS2DcsValue = 72;

void _showInfo(BuildContext context, String title, String message) {
  showDialog<void>(context: context, builder: (context) => AlertDialog(title: Text(title), content: Text(message), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть'))]));
}
