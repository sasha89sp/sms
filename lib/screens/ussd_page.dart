part of 'pages.dart';

/// USSD: ручная команда, сохранённые команды и серия команд с задержками.
class UssdPage extends StatefulWidget {
  const UssdPage({super.key});

  @override
  State<UssdPage> createState() => _UssdPageState();
}

class _UssdPageState extends State<UssdPage> {
  late final TextEditingController _code = TextEditingController(text: '*100#');
  late final TextEditingController _name = TextEditingController();
  late final TextEditingController _batch = TextEditingController(text: '*100#;5\n*100#');
  late final TextEditingController _repeats = TextEditingController(text: '1');
  late final TextEditingController _repeatPause = TextEditingController(text: '0');

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _batch.dispose();
    _repeats.dispose();
    _repeatPause.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final response = c.lastUssdResponse;
    final saved = c.settings.savedUssd;
    return _pageBody(ListView(children: [
      const _PageHeader('USSD и баланс', subtitle: 'Отправка команд, сохранённые команды и серия с задержками'),
      const SizedBox(height: 14),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('USSD-команда', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 11),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _code,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.dialpad), hintText: '*100#'),
              ),
            ),
            const SizedBox(width: 9),
            FilledButton.icon(
              onPressed: c.isConnected && !c.isRunning && !c.isBatchRunning
                  ? () => _perform(context, () async {
                        await c.runUssdManually(_code.text.trim());
                      })
                  : null,
              icon: const Icon(Icons.send, size: 16),
              label: const Text('Отправить'),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Название для сохранения', hintText: 'Баланс МТС'),
              ),
            ),
            const SizedBox(width: 9),
            OutlinedButton.icon(
              onPressed: () => _perform(context, () async {
                await c.addSavedUssd(_name.text, _code.text);
                _name.clear();
              }, successMessage: 'Команда сохранена'),
              icon: const Icon(Icons.bookmark_add_outlined, size: 16),
              label: const Text('Сохранить команду'),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Ответ оператора', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (response.isEmpty)
            const Text('Ответ ещё не получен.', style: TextStyle(color: _muted, fontSize: 12))
          else
            SelectableText(response, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ]),
      ),
      const SizedBox(height: 12),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Сохранённые команды', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (saved.isEmpty)
            const Text('Пока пусто. Введите команду выше и нажмите «Сохранить команду».',
                style: TextStyle(color: _muted, fontSize: 12))
          else
            ...saved.map((item) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bookmark_outline, size: 18, color: _blue),
                  title: Text(item.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  subtitle: Text(item.code, style: const TextStyle(fontFamily: 'Consolas', fontSize: 11)),
                  trailing: Wrap(spacing: 2, children: [
                    IconButton(
                      tooltip: 'Подставить в поле',
                      onPressed: () => setState(() => _code.text = item.code),
                      icon: const Icon(Icons.edit_note, size: 19),
                    ),
                    IconButton(
                      tooltip: 'Отправить сейчас',
                      onPressed: c.isConnected && !c.isRunning && !c.isBatchRunning
                          ? () => _perform(context, () async {
                                setState(() => _code.text = item.code);
                                await c.runUssdManually(item.code);
                              })
                          : null,
                      icon: const Icon(Icons.send, size: 17),
                    ),
                    IconButton(
                      tooltip: 'Удалить',
                      onPressed: () => _perform(context, () => c.removeSavedUssd(item.code)),
                      icon: const Icon(Icons.delete_outline, size: 18),
                    ),
                  ]),
                )),
        ]),
      ),
      const SizedBox(height: 12),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Серия USSD без сценария', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'Одна команда в строке. После «;» можно указать паузу в секундах перед следующей командой, например: *100#;10',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _batch,
            minLines: 4,
            maxLines: 10,
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
            decoration: const InputDecoration(alignLabelWithHint: true, labelText: 'Команды'),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _repeats,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Повторить кругов'),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: TextField(
                controller: _repeatPause,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Пауза между кругами, сек'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            FilledButton.icon(
              onPressed: c.isConnected && !c.isRunning && !c.isBatchRunning
                  ? () => _perform(context, () async {
                        final items = AppController.parseBatch(_batch.text);
                        final repeats = (int.tryParse(_repeats.text.trim()) ?? 1).clamp(1, 1000).toInt();
                        final pause = (int.tryParse(_repeatPause.text.trim()) ?? 0).clamp(0, 86400).toInt();
                        await c.runUssdBatch(items, repeats: repeats, repeatPauseSeconds: pause);
                      })
                  : null,
              icon: c.isBatchRunning
                  ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.playlist_play, size: 19),
              label: Text(c.isBatchRunning ? 'Выполняется…' : 'Запустить серию'),
            ),
            const SizedBox(width: 8),
            if (c.isBatchRunning)
              OutlinedButton.icon(
                onPressed: c.stopUssdBatch,
                icon: const Icon(Icons.stop, size: 17),
                label: const Text('Остановить'),
              ),
          ]),
          if (c.batchLog.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Результаты', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(height: 6),
            SelectableText(
              c.batchLog.join('\n'),
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 12),
      const _Panel(
        child: Text(
          'USSD-коды различаются у операторов и тарифов. Не отправляйте неизвестные команды: некоторые подключают платные услуги или меняют тариф.',
          style: TextStyle(color: _muted, fontSize: 11),
        ),
      ),
    ]));
  }
}
