part of 'pages.dart';

/// SMS: локальное хранилище со всех SIM, автополучение и корзина.
class SmsPage extends StatefulWidget {
  const SmsPage({super.key});

  @override
  State<SmsPage> createState() => _SmsPageState();
}

class _SmsPageState extends State<SmsPage> {
  late final TextEditingController _recipient = TextEditingController();
  late final TextEditingController _text = TextEditingController();
  String _folder = 'inbox';
  final Set<int> _selectedIds = <int>{};

  @override
  void dispose() {
    _recipient.dispose();
    _text.dispose();
    super.dispose();
  }

  String _simLabel(AppController c, Object? simId) {
    final id = '${simId ?? ''}';
    final phone = c.simPhones[id] ?? '';
    if (phone.isNotEmpty) return phone;
    if (id.length > 6) return 'SIM …${id.substring(id.length - 6)}';
    return id.isEmpty ? 'SIM ?' : 'SIM $id';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final allRows = _folder == 'inbox'
        ? c.smsInbox
        : _folder == 'sent'
            ? c.smsSent
            : c.smsTrash;
    final rows = allRows.take(300).toList();
    final visibleIds = rows.map((r) => (r['id'] as num).toInt()).toSet();
    final selectedVisibleIds = _selectedIds.intersection(visibleIds);
    final allVisibleSelected =
        visibleIds.isNotEmpty && selectedVisibleIds.length == visibleIds.length;
    final inboxCount = c.smsCounts['inbox'] ?? 0;
    final sentCount = c.smsCounts['sent'] ?? 0;
    final trashCount = c.smsCounts['trash'] ?? 0;

    return _pageBody(ListView(children: [
      _PageHeader(
        'SMS',
        subtitle: 'Все сообщения хранятся локально, со всех вставленных SIM-карт',
        trailing: OutlinedButton.icon(
          onPressed: c.isConnected && !c.isSyncingSms
              ? () => _perform(context, () async {
                    final added = await c.syncSms();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(added > 0 ? 'Новых сообщений: $added' : 'Новых сообщений нет')),
                      );
                    }
                  })
              : null,
          icon: c.isSyncingSms
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download, size: 17),
          label: const Text('Получить с модема'),
        ),
      ),
      const SizedBox(height: 14),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Новое сообщение', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          TextField(
            controller: _recipient,
            decoration: const InputDecoration(labelText: 'Номер получателя', prefixIcon: Icon(Icons.smartphone), hintText: '+79000000000'),
          ),
          const SizedBox(height: 9),
          TextField(
            controller: _text,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Текст SMS', alignLabelWithHint: true),
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Expanded(
              child: Text('Русский текст отправляется в UCS-2; длинные SMS разбиваются на части.',
                  style: TextStyle(color: _muted, fontSize: 10)),
            ),
            FilledButton.icon(
              onPressed: c.isConnected && !c.isRunning
                  ? () => _perform(context, () async {
                        await c.sendSmsManually(_recipient.text.trim(), _text.text);
                        _text.clear();
                      }, successMessage: 'SMS передана модему')
                  : null,
              icon: const Icon(Icons.send, size: 16),
              label: const Text('Отправить'),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      _Panel(
        child: Row(children: [
          const Expanded(
            child: Text('Приходят ли новые SMS: проверка настроек модема (AT+CNMI, память, счётчик уведомлений).',
                style: TextStyle(color: _muted, fontSize: 11)),
          ),
          OutlinedButton.icon(
            onPressed: c.isConnected && !c.isRunning
                ? () => _perform(context, () async {
                      final report = await c.smsDiagnostics();
                      if (!context.mounted) return;
                      await showDialog<void>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Диагностика SMS'),
                          content: SizedBox(
                            width: 520,
                            child: SingleChildScrollView(
                              child: SelectableText(report,
                                  style: const TextStyle(fontFamily: 'Consolas', fontSize: 12)),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text('Закрыть'),
                            ),
                          ],
                        ),
                      );
                    })
                : null,
            icon: const Icon(Icons.health_and_safety_outlined, size: 16),
            label: const Text('Диагностика SMS'),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Wrap(spacing: 8, runSpacing: 6, children: [
                ChoiceChip(
                  selected: _folder == 'inbox',
                  onSelected: (_) => setState(() {
                    _folder = 'inbox';
                    _selectedIds.clear();
                  }),
                  label: Text('Входящие ($inboxCount)${c.unreadSms > 0 ? ' · новых ${c.unreadSms}' : ''}'),
                ),
                ChoiceChip(
                  selected: _folder == 'sent',
                  onSelected: (_) => setState(() {
                    _folder = 'sent';
                    _selectedIds.clear();
                  }),
                  label: Text('Отправленные ($sentCount)'),
                ),
                ChoiceChip(
                  selected: _folder == 'trash',
                  onSelected: (_) => setState(() {
                    _folder = 'trash';
                    _selectedIds.clear();
                  }),
                  avatar: const Icon(Icons.delete_outline, size: 15),
                  label: Text('Корзина ($trashCount)'),
                ),
              ]),
            ),
            if (_folder == 'inbox' && c.unreadSms > 0)
              TextButton(
                onPressed: () => _perform(context, c.markAllSmsRead),
                child: const Text('Отметить все прочитанными'),
              ),
            if (_folder == 'trash' && trashCount > 0)
              TextButton.icon(
                onPressed: () => _perform(context, () async {
                  final ok = await _confirm(context, 'Очистить корзину?', 'Сообщения будут удалены окончательно.');
                  if (ok) {
                    await c.emptySmsTrash();
                    setState(() => _selectedIds.clear());
                  }
                }),
                icon: const Icon(Icons.delete_forever, size: 17),
                label: const Text('Очистить корзину'),
              ),
          ]),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F6FA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _line),
              ),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  InkWell(
                    onTap: () => setState(() {
                      if (allVisibleSelected) {
                        _selectedIds.removeAll(visibleIds);
                      } else {
                        _selectedIds.addAll(visibleIds);
                      }
                    }),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Checkbox(
                        value: allVisibleSelected,
                        onChanged: (checked) => setState(() {
                          if (checked == true) {
                            _selectedIds.addAll(visibleIds);
                          } else {
                            _selectedIds.removeAll(visibleIds);
                          }
                        }),
                        visualDensity: VisualDensity.compact,
                      ),
                      Text(
                        selectedVisibleIds.isEmpty
                            ? 'Выделить все (${visibleIds.length})'
                            : 'Выбрано: ${selectedVisibleIds.length}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                  if (selectedVisibleIds.isNotEmpty) ...[
                    TextButton.icon(
                      onPressed: () {
                        final joined = rows
                            .where((r) => selectedVisibleIds.contains((r['id'] as num).toInt()))
                            .map((r) => '[${r['sms_time']}] ${r['sender']}: ${r['body']}')
                            .join('\n---\n');
                        Clipboard.setData(ClipboardData(text: joined));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Скопировано сообщений: ${selectedVisibleIds.length}')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Копировать'),
                    ),
                    if (_folder != 'trash') ...[
                      if (_folder == 'inbox')
                        TextButton.icon(
                          onPressed: () => _perform(context, () async {
                            final ids = selectedVisibleIds.toList();
                            await c.markSmsReadBatch(ids);
                            setState(() => _selectedIds.removeAll(ids));
                          }),
                          icon: const Icon(Icons.done_all, size: 16),
                          label: const Text('Прочитано'),
                        ),
                      TextButton.icon(
                        onPressed: () => _perform(context, () async {
                          final ids = selectedVisibleIds.toList();
                          await c.trashSmsBatch(ids);
                          setState(() => _selectedIds.removeAll(ids));
                        }),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('В корзину'),
                      ),
                    ] else ...[
                      TextButton.icon(
                        onPressed: () => _perform(context, () async {
                          final ids = selectedVisibleIds.toList();
                          await c.restoreSmsBatch(ids);
                          setState(() => _selectedIds.removeAll(ids));
                        }),
                        icon: const Icon(Icons.restore, size: 16),
                        label: const Text('Восстановить'),
                      ),
                      TextButton.icon(
                        onPressed: () => _perform(context, () async {
                          final ok = await _confirm(
                            context,
                            'Удалить выбранные (${selectedVisibleIds.length})?',
                            'Сообщения нельзя будет восстановить.',
                          );
                          if (ok) {
                            final ids = selectedVisibleIds.toList();
                            await c.purgeSmsBatch(ids);
                            setState(() => _selectedIds.removeAll(ids));
                          }
                        }),
                        icon: const Icon(Icons.delete_forever, size: 16),
                        label: const Text('Удалить навсегда'),
                      ),
                    ],
                    TextButton(
                      onPressed: () => setState(() => _selectedIds.removeAll(visibleIds)),
                      child: const Text('Снять выделение'),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Сообщений нет.', style: TextStyle(color: _muted, fontSize: 12)),
            )
          else
            ...rows.map((row) {
              final id = (row['id'] as num).toInt();
              final isNew = row['is_new'] == 1 && _folder == 'inbox';
              final isSelected = _selectedIds.contains(id);
              return Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFE7F0FF)
                      : (isNew ? const Color(0xFFF2F7FF) : const Color(0xFFF8FAFD)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? _blue
                        : (isNew ? const Color(0xFFBBD3F5) : _line),
                  ),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Checkbox(
                    value: isSelected,
                    onChanged: (checked) => setState(() {
                      if (checked == true) {
                        _selectedIds.add(id);
                      } else {
                        _selectedIds.remove(id);
                      }
                    }),
                    visualDensity: VisualDensity.compact,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 10),
                    child: Icon(
                      _folder == 'sent' ? Icons.call_made : Icons.call_received,
                      size: 17,
                      color: _blue,
                    ),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('${row['sender']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                        const SizedBox(width: 8),
                        if (isNew) const _StatusTag('НОВОЕ', good: true),
                      ]),
                      const SizedBox(height: 2),
                      Text('${row['sms_time']} · ${_simLabel(c, row['sim_id'])}',
                          style: const TextStyle(color: _muted, fontSize: 10)),
                      const SizedBox(height: 6),
                      SelectableText('${row['body']}', style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
                  if (_folder == 'trash') ...[
                    IconButton(
                      tooltip: 'Восстановить',
                      onPressed: () => _perform(context, () => c.restoreSms(id)),
                      icon: const Icon(Icons.restore, size: 18),
                    ),
                    IconButton(
                      tooltip: 'Удалить окончательно',
                      onPressed: () => _perform(context, () async {
                        final ok = await _confirm(context, 'Удалить окончательно?', 'Сообщение нельзя будет восстановить.');
                        if (ok) await c.purgeSms(id);
                      }),
                      icon: const Icon(Icons.delete_forever, size: 18),
                    ),
                  ] else ...[
                    if (isNew)
                      IconButton(
                        tooltip: 'Отметить прочитанным',
                        onPressed: () => _perform(context, () => c.markSmsRead(id)),
                        icon: const Icon(Icons.done, size: 18),
                      ),
                    IconButton(
                      tooltip: 'В корзину',
                      onPressed: () => _perform(context, () => c.trashSms(id)),
                      icon: const Icon(Icons.delete_outline, size: 18),
                    ),
                  ],
                ]),
              );
            }),
          const SizedBox(height: 10),
          Text(
            c.settings.smsAutoReceive
                ? 'Автополучение включено: новые SMS выгружаются из модема каждые ${c.settings.smsPollSeconds} с и сразу при уведомлении модема.'
                : 'Автополучение выключено (Настройки → SMS).',
            style: const TextStyle(color: _muted, fontSize: 10),
          ),
        ]),
      ),
    ]));
  }
}
