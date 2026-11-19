part of 'pages.dart';

/// Конструктор и запуск сценариев.
class ScenariosPage extends StatefulWidget {
  const ScenariosPage({super.key});

  @override
  State<ScenariosPage> createState() => _ScenariosPageState();
}

class _ScenariosPageState extends State<ScenariosPage> {
  String? _selectedId;
  Scenario? _draft;
  bool _dirty = false;
  late final TextEditingController _name = TextEditingController();
  late final TextEditingController _operator = TextEditingController();

  @override
  void initState() {
    super.initState();
    final scenarios = context.read<AppController>().settings.scenarios;
    if (scenarios.isNotEmpty) _select(scenarios.first);
  }

  @override
  void dispose() {
    _name.dispose();
    _operator.dispose();
    super.dispose();
  }

  void _select(Scenario scenario) {
    _selectedId = scenario.id;
    _draft = scenario;
    _dirty = false;
    _name.text = scenario.name;
    _operator.text = scenario.operator;
  }

  Future<void> _switchTo(AppController c, Scenario target) async {
    if (_draft != null && _dirty) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Сохранить изменения?'),
          content: Text('В сценарии «${_draft!.name}» есть несохранённые изменения.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, 'cancel'), child: const Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(context, 'discard'), child: const Text('Не сохранять')),
            FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('Сохранить')),
          ],
        ),
      );
      if (choice == null || choice == 'cancel') return;
      if (choice == 'save') await c.saveScenario(_draft!);
    }
    if (!mounted) return;
    setState(() => _select(c.scenarioById(target.id) ?? target));
  }

  void _update(Scenario Function(Scenario) change) {
    final draft = _draft;
    if (draft == null) return;
    setState(() {
      _draft = change(draft);
      _dirty = true;
    });
  }

  Future<void> _save(AppController c) async {
    final draft = _draft;
    if (draft == null) return;
    final saved = draft.copyWith(
      name: _name.text.trim().isEmpty ? 'Сценарий' : _name.text.trim(),
      operator: _operator.text.trim(),
    );
    await c.saveScenario(saved);
    if (!mounted) return;
    setState(() {
      _draft = saved;
      _dirty = false;
    });
  }

  Future<void> _create(AppController c) async {
    final scenario = Scenario.empty('Новый сценарий ${c.settings.scenarios.length + 1}');
    await c.saveScenario(scenario);
    if (!mounted) return;
    setState(() => _select(scenario));
  }

  Future<void> _duplicate(AppController c) async {
    final draft = _draft;
    if (draft == null) return;
    final copy = Scenario(
      id: newId(),
      name: '${_name.text.trim().isEmpty ? draft.name : _name.text.trim()} (копия)',
      operator: _operator.text.trim(),
      stopOnError: draft.stopOnError,
      autoRun: false,
      steps: draft.steps
          .map((step) => ScenarioStep(
                id: newId(),
                type: step.type,
                code: step.code,
                recipient: step.recipient,
                text: step.text,
                seconds: step.seconds,
                digits: step.digits,
              ))
          .toList(),
    );
    await c.saveScenario(copy);
    if (!mounted) return;
    setState(() => _select(copy));
  }

  Future<void> _delete(AppController c) async {
    final draft = _draft;
    if (draft == null) return;
    final ok = await _confirm(context, 'Удалить сценарий?', 'Сценарий «${draft.name}» будет удалён.');
    if (!ok) return;
    await c.deleteScenario(draft.id);
    if (!mounted) return;
    setState(() {
      _draft = null;
      _selectedId = null;
      _dirty = false;
      final rest = c.settings.scenarios;
      if (rest.isNotEmpty) _select(rest.first);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final scenarios = c.settings.scenarios;
    final draft = _draft;

    return _pageBody(ListView(children: [
      _PageHeader(
        'Сценарии',
        subtitle: 'Любая последовательность шагов: USSD, баланс, SMS, пауза, звонок, цифры',
        trailing: FilledButton.icon(
          onPressed: c.isConnected && !c.isRunning && draft != null
              ? () => _perform(context, () async {
                    if (_dirty) await _save(c);
                    await c.runScenario(scenarioId: draft.id);
                  })
              : null,
          icon: c.isRunning
              ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.play_arrow_rounded),
          label: Text(c.isRunning ? 'Выполняется…' : 'Запустить сейчас'),
        ),
      ),
      const SizedBox(height: 14),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Сохранённые сценарии', style: TextStyle(fontWeight: FontWeight.w700))),
            OutlinedButton.icon(
              onPressed: () => _perform(context, () => _create(c)),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Новый'),
            ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final scenario in scenarios)
              ChoiceChip(
                selected: scenario.id == _selectedId,
                onSelected: (_) => _switchTo(c, scenario),
                avatar: scenario.autoRun ? const Icon(Icons.bolt, size: 15, color: Color(0xFFB76E12)) : null,
                label: Text(scenario.operator.isEmpty ? scenario.name : '${scenario.name} · ${scenario.operator}'),
              ),
          ]),
          if (scenarios.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Сценариев нет. Нажмите «Новый».', style: TextStyle(color: _muted, fontSize: 12)),
            ),
          if (c.autoModeWaiting)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('Автозапуск включён: ожидается регистрация SIM-карты в сети.',
                  style: TextStyle(fontSize: 11, color: Color(0xFFB76E12))),
            ),
          const SizedBox(height: 4),
          const Text('⚡ — сценарий запускается автоматически после появления сети.',
              style: TextStyle(color: _muted, fontSize: 10)),
        ]),
      ),
      if (draft != null) ...[
        const SizedBox(height: 14),
        _Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _name,
                  onChanged: (_) => setState(() => _dirty = true),
                  decoration: const InputDecoration(labelText: 'Название сценария'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _operator,
                  onChanged: (_) => setState(() => _dirty = true),
                  decoration: const InputDecoration(
                    labelText: 'Оператор (необязательно)',
                    hintText: 'МТС, Beeline…',
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: draft.autoRun,
              onChanged: (value) => _update((s) => s.copyWith(autoRun: value)),
              title: const Text('Выполнять автоматически после появления сети', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              subtitle: const Text(
                'После вставки модема программа дождётся сети и выполнит этот сценарий. Если указан оператор — только для него. Каждый запуск — новая строка в Excel.',
                style: TextStyle(fontSize: 10, color: _muted),
              ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: draft.stopOnError,
              onChanged: (value) => _update((s) => s.copyWith(stopOnError: value)),
              title: const Text('Прерывать сценарий при первой ошибке', style: TextStyle(fontSize: 12)),
              subtitle: const Text('Иначе ошибка записывается в ячейку, а сценарий идёт дальше.',
                  style: TextStyle(fontSize: 10, color: _muted)),
            ),
            const Divider(height: 24),
            Row(children: [
              const Expanded(child: Text('Шаги', style: TextStyle(fontWeight: FontWeight.w700))),
              PopupMenuButton<StepType>(
                tooltip: 'Добавить шаг',
                onSelected: (type) => _update((s) => s.copyWith(steps: [...s.steps, ScenarioStep.create(type)])),
                itemBuilder: (context) => [
                  for (final type in StepType.values)
                    PopupMenuItem(value: type, child: Text(type.title)),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: _line),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add, size: 16, color: _blue),
                    SizedBox(width: 4),
                    Text('Добавить шаг', style: TextStyle(fontSize: 12, color: _blue, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            if (draft.steps.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('Шагов нет. Добавьте первый шаг.', style: TextStyle(color: _muted, fontSize: 12)),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: draft.steps.length,
                onReorder: (oldIndex, newIndex) {
                  _update((s) {
                    final list = [...s.steps];
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = list.removeAt(oldIndex);
                    list.insert(newIndex, item);
                    return s.copyWith(steps: list);
                  });
                },
                itemBuilder: (context, index) {
                  final step = draft.steps[index];
                  return _StepEditor(
                    key: ValueKey(step.id),
                    index: index,
                    step: step,
                    saved: c.settings.savedUssd,
                    phrases: c.phrases,
                    onChanged: (value) => _update((s) {
                      final list = [...s.steps];
                      list[index] = value;
                      return s.copyWith(steps: list);
                    }),
                    onDelete: () => _update((s) {
                      final list = [...s.steps]..removeAt(index);
                      return s.copyWith(steps: list);
                    }),
                    onDuplicate: () => _update((s) {
                      final list = [...s.steps];
                      list.insert(index + 1, step.duplicate());
                      return s.copyWith(steps: list);
                    }),
                  );
                },
              ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              FilledButton.icon(
                onPressed: _dirty ? () => _perform(context, () => _save(c), successMessage: 'Сценарий сохранён') : null,
                icon: const Icon(Icons.save, size: 16),
                label: const Text('Сохранить'),
              ),
              OutlinedButton.icon(
                onPressed: () => _perform(context, () => _duplicate(c)),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Дублировать'),
              ),
              OutlinedButton.icon(
                onPressed: () => _perform(context, () => _delete(c)),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Удалить'),
              ),
              if (_dirty)
                const Text('Есть несохранённые изменения', style: TextStyle(color: Color(0xFFB76E12), fontSize: 11)),
            ]),
          ]),
        ),
      ],
      const SizedBox(height: 14),
      _LiveRunPanel(controller: c),
      const SizedBox(height: 14),
      _ExcelPanel(controller: c),
    ]));
  }
}

Future<bool> _confirm(BuildContext context, String title, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Да')),
      ],
    ),
  );
  return result ?? false;
}

class _StepEditor extends StatefulWidget {
  const _StepEditor({
    super.key,
    required this.index,
    required this.step,
    required this.saved,
    required this.phrases,
    required this.onChanged,
    required this.onDelete,
    required this.onDuplicate,
  });

  final int index;
  final ScenarioStep step;
  final List<SavedUssd> saved;
  final List<String> phrases;
  final ValueChanged<ScenarioStep> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;

  @override
  State<_StepEditor> createState() => _StepEditorState();
}

class _StepEditorState extends State<_StepEditor> {
  late final TextEditingController _code = TextEditingController(text: widget.step.code);
  late final TextEditingController _recipient = TextEditingController(text: widget.step.recipient);
  late final TextEditingController _text = TextEditingController(text: widget.step.text);
  late final TextEditingController _seconds = TextEditingController(text: widget.step.seconds.toString());
  late final TextEditingController _digits = TextEditingController(text: widget.step.digits);
  late final TextEditingController _smsTimeout = TextEditingController(text: widget.step.smsTimeout.toString());
  late final TextEditingController _smsSender = TextEditingController(text: widget.step.smsSender);

  @override
  void dispose() {
    _code.dispose();
    _recipient.dispose();
    _text.dispose();
    _seconds.dispose();
    _digits.dispose();
    _smsTimeout.dispose();
    _smsSender.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(widget.step.copyWith(
      code: _code.text,
      recipient: _recipient.text,
      text: _text.text,
      seconds: int.tryParse(_seconds.text.trim()) ?? 0,
      digits: _digits.text,
      smsTimeout: int.tryParse(_smsTimeout.text.trim()) ?? 60,
      smsSender: _smsSender.text,
    ));
  }

  void _setActions(List<CallAction> actions) =>
      widget.onChanged(widget.step.copyWith(actions: actions));

  Widget _extras() {
    final step = widget.step;
    if (step.type == StepType.balance) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Checkbox(
            value: step.waitSms,
            onChanged: (value) => widget.onChanged(step.copyWith(waitSms: value ?? true)),
          ),
          const Expanded(
            flex: 3,
            child: Text('Если в ответе нет суммы — ждать SMS с балансом',
                style: TextStyle(fontSize: 12)),
          ),
          if (step.waitSms) ...[
            const SizedBox(width: 8),
            SizedBox(width: 110, child: _field(_smsTimeout, 'Ждать, сек', number: true)),
            const SizedBox(width: 8),
            SizedBox(width: 160, child: _field(_smsSender, 'Отправитель (необяз.)')),
          ],
        ]),
      );
    }
    if (step.type == StepType.call) {
      final actions = step.actions;
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Действия после ответа абонента (по секундам):',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          for (var i = 0; i < actions.length; i++)
            _ActionRow(
              key: ValueKey('${step.id}:$i:${actions.length}'),
              action: actions[i],
              phrases: widget.phrases,
              onChanged: (value) {
                final list = [...actions];
                list[i] = value;
                _setActions(list);
              },
              onDelete: () {
                final list = [...actions]..removeAt(i);
                _setActions(list);
              },
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                final last = actions.isEmpty ? 0 : actions.last.at + 3;
                _setActions([...actions, CallAction(at: last, isPhrase: true)]);
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Добавить действие'),
            ),
          ),
          const Text('Фразу нужно записать на странице «Звонки». Для фраз требуется звуковой порт (Настройки → Голос).',
              style: TextStyle(color: _muted, fontSize: 10)),
        ]),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _field(TextEditingController controller, String label,
      {String? hint, bool number = false, int maxLines = 1, Widget? suffix}) {
    return TextField(
      controller: controller,
      onChanged: (_) => _emit(),
      keyboardType: number ? TextInputType.number : null,
      minLines: 1,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label, hintText: hint, suffixIcon: suffix),
    );
  }

  Widget _ussdField() {
    return _field(
      _code,
      'USSD-код',
      hint: '*100#',
      suffix: widget.saved.isEmpty
          ? null
          : PopupMenuButton<String>(
              tooltip: 'Из сохранённых команд',
              icon: const Icon(Icons.bookmarks_outlined, size: 18),
              onSelected: (code) {
                _code.text = code;
                _emit();
              },
              itemBuilder: (context) => [
                for (final item in widget.saved)
                  PopupMenuItem(value: item.code, child: Text('${item.name}  ${item.code}')),
              ],
            ),
    );
  }

  List<Widget> _fields() {
    switch (widget.step.type) {
      case StepType.ownNumber:
      case StepType.ussd:
      case StepType.balance:
        return [Expanded(child: _ussdField())];
      case StepType.sms:
        return [
          Expanded(flex: 2, child: _field(_recipient, 'Номер получателя', hint: '+79000000000')),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: _field(_text, 'Текст SMS', maxLines: 3)),
        ];
      case StepType.pause:
        return [Expanded(child: _field(_seconds, 'Пауза, секунд', number: true))];
      case StepType.call:
        return [
          Expanded(flex: 2, child: _field(_recipient, 'Номер для звонка', hint: '+79000000000')),
          const SizedBox(width: 8),
          Expanded(child: _field(_seconds, 'Разговор, сек', number: true)),
        ];
      case StepType.dtmf:
        return [Expanded(child: _field(_digits, 'Цифры (0-9, *, #)', hint: '1'))];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ReorderableDragStartListener(
          index: widget.index,
          child: const Padding(
            padding: EdgeInsets.fromLTRB(4, 12, 6, 0),
            child: Icon(Icons.drag_indicator, color: _muted, size: 20),
          ),
        ),
        SizedBox(
          width: 26,
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text('${widget.index + 1}', style: const TextStyle(color: _muted, fontWeight: FontWeight.w700)),
          ),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<StepType>(
            initialValue: widget.step.type,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Тип шага'),
            items: [
              for (final type in StepType.values)
                DropdownMenuItem(value: type, child: Text(type.title, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (type) {
              if (type == null) return;
              widget.onChanged(widget.step.copyWith(
                type: type,
                code: _code.text,
                recipient: _recipient.text,
                text: _text.text,
                seconds: int.tryParse(_seconds.text.trim()) ?? 0,
                digits: _digits.text,
              ));
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: _fields()),
            _extras(),
          ]),
        ),
        IconButton(tooltip: 'Дублировать шаг', onPressed: widget.onDuplicate, icon: const Icon(Icons.copy, size: 18)),
        IconButton(tooltip: 'Удалить шаг', onPressed: widget.onDelete, icon: const Icon(Icons.close, size: 18)),
      ]),
    );
  }
}

class _LiveRunPanel extends StatelessWidget {
  const _LiveRunPanel({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final status = c.balanceStatus;
    final same = status == 'СОВПАЛ';
    final changed = status == 'НЕ СОВПАЛ';
    final Color statusColor = same
        ? const Color(0xFFD92D20)
        : changed
            ? const Color(0xFF16845B)
            : _muted;
    final Color statusBackground = same
        ? const Color(0xFFFFECEB)
        : changed
            ? const Color(0xFFE9F7F0)
            : const Color(0xFFF0F3F7);

    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              c.liveScenarioName.isEmpty ? 'Ход выполнения' : 'Ход выполнения · ${c.liveScenarioName}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (c.isRunning)
            TextButton.icon(
              onPressed: c.abortScenario,
              icon: const Icon(Icons.stop_circle_outlined, size: 17),
              label: const Text('Остановить'),
            ),
          _StatusTag(
            c.isRunning ? 'ВЫПОЛНЯЕТСЯ' : c.currentStep.contains('ошиб') ? 'ЕСТЬ ОШИБКИ' : 'ГОТОВ',
            good: !c.isRunning && c.currentStep.contains('успешно'),
            warning: c.currentStep.contains('ошиб'),
          ),
        ]),
        const SizedBox(height: 6),
        Text(c.currentStep, style: const TextStyle(color: _muted, fontSize: 11)),
        const SizedBox(height: 12),
        if (c.liveSteps.isEmpty)
          const Text('Сценарий ещё не запускался.', style: TextStyle(color: _muted, fontSize: 12))
        else
          ...List.generate(c.liveSteps.length, (index) {
            final step = c.liveSteps[index];
            final error = step.status == LiveStatus.error;
            final running = step.status == LiveStatus.running;
            final pending = step.status == LiveStatus.pending;
            final skipped = step.status == LiveStatus.skipped;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: error
                        ? const Color(0xFFFFECEB)
                        : running
                            ? const Color(0xFFEAF2FF)
                            : (pending || skipped)
                                ? const Color(0xFFF0F3F7)
                                : const Color(0xFFE9F7F0),
                  ),
                  child: Icon(
                    error ? Icons.close : running ? Icons.sync : pending ? Icons.schedule : skipped ? Icons.remove : Icons.check,
                    size: 15,
                    color: error ? Colors.red : running ? _blue : (pending || skipped) ? _muted : const Color(0xFF16845B),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${index + 1}. ${step.title}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                    if (step.value.isNotEmpty)
                      SelectableText(step.value,
                          style: TextStyle(fontSize: 11, color: error ? Colors.red.shade700 : _muted)),
                  ]),
                ),
              ]),
            );
          }),
        if (status.isNotEmpty) ...[
          const Divider(height: 22),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: statusBackground, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(Icons.circle, size: 14, color: statusColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  same
                      ? 'Баланс СОВПАЛ (не изменился)'
                      : changed
                          ? 'Баланс НЕ СОВПАЛ (изменился на ${c.balanceDiff?.toStringAsFixed(2) ?? '?'})'
                          : 'Сверка баланса: $status',
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 4),
          const Text('Красный — баланс совпал, зелёный — не совпал. Сравниваются первая и последняя проверки баланса.',
              style: TextStyle(color: _muted, fontSize: 10)),
        ],
      ]),
    );
  }
}

class _ExcelPanel extends StatelessWidget {
  const _ExcelPanel({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Таблица результатов (Excel)', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Файл: ${c.paths.excelFile}', style: const TextStyle(color: _muted, fontSize: 10)),
        Text('Строк в таблице: ${c.runCount}. Каждый запуск сценария добавляет новую строку.',
            style: const TextStyle(color: _muted, fontSize: 11)),
        if (c.excelMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(c.excelMessage, style: const TextStyle(fontSize: 11, color: Color(0xFF16845B))),
          ),
        Text(
          c.settings.excelColumns.isEmpty
              ? 'Столбцы: все (в стандартном порядке).'
              : 'Столбцы: выбрано ${c.settings.excelColumns.length}.',
          style: const TextStyle(color: _muted, fontSize: 11),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _ColumnsDialog(controller: c),
            ),
            icon: const Icon(Icons.view_column, size: 16),
            label: const Text('Столбцы таблицы'),
          ),
          FilledButton.icon(
            onPressed: () => _perform(context, c.openExcelFile),
            icon: const Icon(Icons.table_chart, size: 16),
            label: const Text('Открыть Excel'),
          ),
          OutlinedButton.icon(
            onPressed: () => _perform(context, c.exportExcel, successMessage: 'Файл обновлён'),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Обновить файл'),
          ),
          OutlinedButton.icon(
            onPressed: () => _perform(context, c.openDataFolder),
            icon: const Icon(Icons.folder_open, size: 16),
            label: const Text('Папка данных'),
          ),
          OutlinedButton.icon(
            onPressed: () => _perform(context, () async {
              final ok = await _confirm(context, 'Очистить таблицу?', 'Все строки результатов будут удалены.');
              if (ok) await c.clearRunResults();
            }),
            icon: const Icon(Icons.delete_sweep_outlined, size: 16),
            label: const Text('Очистить таблицу'),
          ),
        ]),
        const SizedBox(height: 6),
        const Text('Если файл открыт в Excel, новая версия сохраняется рядом как резервная копия.',
            style: TextStyle(color: _muted, fontSize: 10)),
      ]),
    );
  }
}


/// Выбор, порядок, заголовки и пресеты столбцов Excel. Лист «Результаты».
class _ColumnsDialog extends StatefulWidget {
  const _ColumnsDialog({required this.controller});
  final AppController controller;

  @override
  State<_ColumnsDialog> createState() => _ColumnsDialogState();
}

class _ColumnsDialogState extends State<_ColumnsDialog> {
  late List<String> _selected;
  late bool _all;
  late Map<String, String> _customTitles;
  late Map<String, List<String>> _presets;
  final _stepController = TextEditingController();
  final _presetNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final saved = widget.controller.settings.excelColumns;
    _all = saved.isEmpty;
    _selected = saved.isEmpty ? List<String>.of(ExcelFields.base) : List<String>.of(saved);
    _customTitles = Map<String, String>.from(widget.controller.settings.excelColumnTitles);
    _presets = {
      for (final entry in widget.controller.settings.excelColumnPresets.entries)
        entry.key: List<String>.of(entry.value),
    };
  }

  @override
  void dispose() {
    _stepController.dispose();
    _presetNameController.dispose();
    super.dispose();
  }

  String _displayTitle(String id) {
    final custom = _customTitles[id]?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return ExcelFields.title(id);
  }

  void _toggle(String id, bool on) {
    setState(() {
      if (on) {
        if (!_selected.contains(id)) _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
  }

  void _addStep() {
    final number = int.tryParse(_stepController.text.trim());
    if (number == null || number < 1) return;
    setState(() {
      final id = ExcelFields.stepId(number);
      if (!_selected.contains(id)) _selected.add(id);
      _stepController.clear();
    });
  }

  Future<void> _editColumnTitle(String id) async {
    final ctrl = TextEditingController(text: _customTitles[id] ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Заголовок: ${ExcelFields.title(id)}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Своё название столбца',
            hintText: ExcelFields.title(id),
          ),
          onSubmitted: (v) => Navigator.pop(dialogContext, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, ''),
            child: const Text('Сбросить'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, null),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, ctrl.text.trim()),
            child: const Text('Применить'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || !mounted) return;
    setState(() {
      if (result.isEmpty) {
        _customTitles.remove(id);
      } else {
        _customTitles[id] = result;
      }
    });
  }

  void _savePreset() {
    final name = _presetNameController.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _presets[name] = _all ? const <String>[] : List<String>.of(_selected);
      _presetNameController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final available = ExcelFields.base.where((id) => !_selected.contains(id)).toList();
    return AlertDialog(
      title: const Text('Столбцы таблицы Excel'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _all,
              onChanged: (value) => setState(() => _all = value),
              title: const Text('Все данные (стандартный порядок)', style: TextStyle(fontSize: 12)),
              subtitle: const Text('Результаты шагов добавляются автоматически.', style: TextStyle(fontSize: 10)),
            ),
            if (!_all) ...[
              Row(children: [
                const Expanded(
                  child: Text('Порядок и заголовки столбцов:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _selected = List<String>.of(ExcelFields.base);
                    _customTitles.clear();
                  }),
                  child: const Text('По умолчанию', style: TextStyle(fontSize: 11)),
                ),
              ]),
              for (var i = 0; i < _selected.length; i++)
                ListTile(
                  key: ValueKey('col_${_selected[i]}_$i'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${i + 1}. ${_displayTitle(_selected[i])}${_customTitles.containsKey(_selected[i]) ? ' (${ExcelFields.title(_selected[i])})' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'Своё название столбца',
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      onPressed: () => _editColumnTitle(_selected[i]),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_upward, size: 16),
                      onPressed: i == 0
                          ? null
                          : () => setState(() {
                                final item = _selected.removeAt(i);
                                _selected.insert(i - 1, item);
                              }),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_downward, size: 16),
                      onPressed: i == _selected.length - 1
                          ? null
                          : () => setState(() {
                                final item = _selected.removeAt(i);
                                _selected.insert(i + 1, item);
                              }),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => _toggle(_selected[i], false),
                    ),
                  ]),
                ),
              const Divider(),
              const Text('Добавить поле:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final id in available)
                  ActionChip(
                    label: Text(ExcelFields.title(id), style: const TextStyle(fontSize: 11)),
                    onPressed: () => _toggle(id, true),
                  ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _stepController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Результат шага №', isDense: true),
                    onSubmitted: (_) => _addStep(),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _addStep, child: const Text('Добавить шаг')),
              ]),
            ],
            const Divider(),
            const Text('Наборы столбцов (пресеты):', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _presetNameController,
                  decoration: const InputDecoration(labelText: 'Имя набора', hintText: 'Например: Баланс и SIM', isDense: true),
                  onSubmitted: (_) => _savePreset(),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: _savePreset, child: const Text('Сохранить набор')),
            ]),
            if (_presets.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final entry in _presets.entries)
                  InputChip(
                    label: Text(entry.key, style: const TextStyle(fontSize: 11)),
                    onPressed: () => setState(() {
                      if (entry.value.isEmpty) {
                        _all = true;
                      } else {
                        _all = false;
                        _selected = List<String>.of(entry.value);
                      }
                    }),
                    onDeleted: () => setState(() => _presets.remove(entry.key)),
                  ),
              ]),
            ],
            const SizedBox(height: 8),
            const Text('Изменение применяется ко всем строкам, в том числе к старым запускам: '
                'исходные результаты хранятся в базе.',
                style: TextStyle(color: _muted, fontSize: 10)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () async {
            final navigator = Navigator.of(context);
            final c = widget.controller;
            await c.updateSettings(c.settings.copyWith(
              excelColumns: _all ? const <String>[] : List<String>.of(_selected),
              excelColumnTitles: Map<String, String>.from(_customTitles),
              excelColumnPresets: {
                for (final entry in _presets.entries)
                  entry.key: List<String>.of(entry.value),
              },
            ));
            await c.exportExcel();
            navigator.pop();
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}


/// Одно действие звонка: секунда, тип (фраза / цифры), значение.
class _ActionRow extends StatefulWidget {
  const _ActionRow({
    super.key,
    required this.action,
    required this.phrases,
    required this.onChanged,
    required this.onDelete,
  });

  final CallAction action;
  final List<String> phrases;
  final ValueChanged<CallAction> onChanged;
  final VoidCallback onDelete;

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  late final TextEditingController _at = TextEditingController(text: widget.action.at.toString());
  late final TextEditingController _value = TextEditingController(text: widget.action.value);

  @override
  void dispose() {
    _at.dispose();
    _value.dispose();
    super.dispose();
  }

  void _emit({bool? isPhrase, String? value}) {
    widget.onChanged(widget.action.copyWith(
      at: int.tryParse(_at.text.trim()) ?? 0,
      isPhrase: isPhrase,
      value: value ?? _value.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final phraseValue = widget.phrases.contains(action.value) ? action.value : null;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        const Text('на', style: TextStyle(fontSize: 12)),
        const SizedBox(width: 6),
        SizedBox(
          width: 70,
          child: TextField(
            controller: _at,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'сек', isDense: true),
            onChanged: (_) => _emit(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 150,
          child: DropdownButtonFormField<bool>(
            initialValue: action.isPhrase,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: const [
              DropdownMenuItem(value: true, child: Text('Сказать фразу')),
              DropdownMenuItem(value: false, child: Text('Нажать цифры')),
            ],
            onChanged: (value) {
              if (value == null) return;
              _value.clear();
              widget.onChanged(action.copyWith(
                at: int.tryParse(_at.text.trim()) ?? 0,
                isPhrase: value,
                value: '',
              ));
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: action.isPhrase
              ? DropdownButtonFormField<String>(
                  initialValue: phraseValue,
                  isExpanded: true,
                  hint: Text(widget.phrases.isEmpty ? 'Нет записанных фраз' : 'Выберите фразу'),
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    for (final name in widget.phrases)
                      DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (value) => _emit(value: value ?? ''),
                )
              : TextField(
                  controller: _value,
                  decoration: const InputDecoration(labelText: 'Цифры (0-9, *, #)', isDense: true),
                  onChanged: (_) => _emit(),
                ),
        ),
        IconButton(
          tooltip: 'Удалить действие',
          onPressed: widget.onDelete,
          icon: const Icon(Icons.close, size: 16),
        ),
      ]),
    );
  }
}
