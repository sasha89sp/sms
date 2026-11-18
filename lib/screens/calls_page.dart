part of 'pages.dart';

/// Голосовые вызовы: набор, разговор со звуком, цифры во время вызова.
class CallsPage extends StatefulWidget {
  const CallsPage({super.key});

  @override
  State<CallsPage> createState() => _CallsPageState();
}

class _CallsPageState extends State<CallsPage> {
  late final TextEditingController _number = TextEditingController();
  late final TextEditingController _wav = TextEditingController();
  late final TextEditingController _phraseName = TextEditingController();
  Timer? _ticker;
  String _sentDigits = '';
  String _voiceInfo = '';

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _number.dispose();
    _wav.dispose();
    _phraseName.dispose();
    super.dispose();
  }

  String _duration(AppController c) {
    final start = c.callStartedAt;
    if (start == null) return '';
    final seconds = DateTime.now().difference(start).inSeconds;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(seconds ~/ 60)}:${two(seconds % 60)}';
  }

  Future<void> _press(AppController c, String key) async {
    if (c.callPhase == CallPhase.active) {
      await c.sendDtmf(key);
      if (mounted) setState(() => _sentDigits += key);
    } else if (c.callPhase == CallPhase.idle) {
      setState(() => _number.text = _number.text + key);
    }
  }

  Widget _key(AppController c, String key) {
    return SizedBox(
      width: 64,
      height: 48,
      child: OutlinedButton(
        onPressed: () => _perform(context, () => _press(c, key)),
        style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
        child: Text(key, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final phase = c.callPhase;
    final idle = phase == CallPhase.idle;
    final active = phase == CallPhase.active;
    final candidates = c.availablePorts.where((port) => port.name != c.modem.connectedPort).toList();
    final audioPort = c.settings.audioPort;
    final voice = c.voice;

    return _pageBody(ListView(children: [
      const _PageHeader('Вызовы', subtitle: 'Голосовой вызов через модем, цифры во время разговора'),
      const SizedBox(height: 14),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? const Color(0xFFE9F7F0)
                    : phase == CallPhase.incoming
                        ? const Color(0xFFFFF4E5)
                        : const Color(0xFFEAF2FF),
              ),
              child: Icon(
                phase == CallPhase.incoming ? Icons.ring_volume : Icons.call,
                color: active ? const Color(0xFF16845B) : _blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(phase.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                if (!idle)
                  Text(
                    '${c.callNumber.isEmpty ? '—' : c.callNumber}${active ? '  ·  ${_duration(c)}' : ''}',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
              ]),
            ),
            if (phase == CallPhase.incoming) ...[
              FilledButton.icon(
                onPressed: () => _perform(context, c.answerIncoming),
                icon: const Icon(Icons.call, size: 17),
                label: const Text('Ответить'),
              ),
              const SizedBox(width: 8),
            ],
            if (!idle)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD92D20)),
                onPressed: () => _perform(context, () async {
                  await c.hangUp();
                  if (mounted) setState(() => _sentDigits = '');
                }),
                icon: const Icon(Icons.call_end, size: 17),
                label: Text(phase == CallPhase.incoming ? 'Отклонить' : 'Завершить'),
              ),
          ]),
          if (c.callStatus.isNotEmpty && !idle) ...[
            const SizedBox(height: 10),
            Text(c.callStatus, style: const TextStyle(color: _muted, fontSize: 11)),
          ],
        ]),
      ),
      const SizedBox(height: 12),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(active ? 'Набор цифр во время разговора' : 'Номер и клавиатура',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (!active)
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _number,
                  enabled: idle,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.dialpad), hintText: '+79000000000'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Стереть',
                onPressed: idle && _number.text.isNotEmpty
                    ? () => setState(() => _number.text = _number.text.substring(0, _number.text.length - 1))
                    : null,
                icon: const Icon(Icons.backspace_outlined, size: 19),
              ),
              const SizedBox(width: 6),
              FilledButton.icon(
                onPressed: c.isConnected && idle && !c.isRunning
                    ? () => _perform(context, () async {
                          _sentDigits = '';
                          await c.startCall(_number.text);
                        })
                    : null,
                icon: const Icon(Icons.call, size: 17),
                label: const Text('Позвонить'),
              ),
            ])
          else
            Text(
              _sentDigits.isEmpty ? 'Нажимайте кнопки — цифры уйдут собеседнику (DTMF).' : 'Отправлено: $_sentDigits',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final key in const ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#']) _key(c, key),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Звук', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'Голос идёт по отдельному COM-порту модема (PCM 8 кГц, 16 бит). Выберите этот порт, чтобы слышать собеседника через динамики и говорить в микрофон.',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: candidates.any((port) => port.name == audioPort) ? audioPort : '',
            decoration: const InputDecoration(labelText: 'Звуковой COM-порт модема', prefixIcon: Icon(Icons.graphic_eq)),
            items: [
              const DropdownMenuItem(value: '', child: Text('Не выбран (без звука)')),
              ...candidates.map((port) => DropdownMenuItem(
                    value: port.name,
                    child: Text('${port.name} · ${port.friendlyName.isEmpty ? 'COM-порт' : port.friendlyName}',
                        overflow: TextOverflow.ellipsis),
                  )),
            ],
            onChanged: (value) => _perform(context, () => c.updateSettings(c.settings.copyWith(audioPort: value ?? ''))),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilterChip(
              selected: voice != null && voice.muted,
              onSelected: voice == null ? null : (value) => c.setMicMuted(value),
              avatar: const Icon(Icons.mic_off, size: 16),
              label: const Text('Микрофон выключен'),
            ),
            FilterChip(
              selected: voice != null && !voice.speakerOn,
              onSelected: voice == null ? null : (value) => c.setSpeakerOn(!value),
              avatar: const Icon(Icons.volume_off, size: 16),
              label: const Text('Динамики выключены'),
            ),
            if (voice != null)
              Text('Принято ${voice.rxBytes ~/ 1024} КБ · передано ${voice.txBytes ~/ 1024} КБ',
                  style: const TextStyle(color: _muted, fontSize: 10)),
          ]),
          if (voice != null && voice.lastError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(voice.lastError, style: TextStyle(color: Colors.red.shade700, fontSize: 10)),
            ),
          const SizedBox(height: 12),
          const Text('Фразы для вызова', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _phraseName,
                decoration: const InputDecoration(labelText: 'Название фразы', hintText: 'да', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            if (!c.isRecordingPhrase)
              FilledButton.icon(
                onPressed: () => _perform(context, c.startPhraseRecording),
                icon: const Icon(Icons.mic, size: 18),
                label: const Text('Записать'),
              )
            else ...[
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD92D20)),
                onPressed: () => _perform(
                  context,
                  () async {
                    await c.stopPhraseRecording(_phraseName.text);
                    _phraseName.clear();
                  },
                  successMessage: 'Фраза сохранена',
                ),
                icon: const Icon(Icons.stop, size: 18),
                label: Text('Стоп и сохранить (${(c.recordedMillis / 1000).toStringAsFixed(1)} с)'),
              ),
              const SizedBox(width: 6),
              TextButton(onPressed: c.cancelPhraseRecording, child: const Text('Отмена')),
            ],
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _wav,
                decoration: const InputDecoration(
                  labelText: 'Импорт: путь к WAV-файлу (будет сохранён под названием выше)',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _perform(
                context,
                () async {
                  await c.importPhrase(_wav.text.trim().replaceAll('"', ''), _phraseName.text);
                  _wav.clear();
                  _phraseName.clear();
                },
                successMessage: 'Фраза импортирована',
              ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('Импорт'),
            ),
          ]),
          const SizedBox(height: 8),
          if (c.phrases.isEmpty)
            const Text('Фраз пока нет. Запишите с микрофона компьютера (8 кГц, 16 бит, моно).',
                style: TextStyle(color: _muted, fontSize: 11))
          else
            for (final name in c.phrases)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.graphic_eq, size: 18),
                title: Text(name, style: const TextStyle(fontSize: 13)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Прослушать на компьютере',
                    icon: const Icon(Icons.volume_up, size: 18),
                    onPressed: () => _perform(context, () => c.previewPhrase(name)),
                  ),
                  IconButton(
                    tooltip: 'Проиграть в вызов',
                    icon: const Icon(Icons.phone_forwarded, size: 18),
                    onPressed: active && voice != null
                        ? () => _perform(context, () => c.playPhraseIntoCall(name),
                            successMessage: 'Фраза отправлена в вызов')
                        : null,
                  ),
                  IconButton(
                    tooltip: 'Удалить',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _perform(context, () async {
                      final ok = await _confirm(context, 'Удалить фразу?', name);
                      if (ok) await c.deletePhrase(name);
                    }),
                  ),
                ]),
              ),
          const SizedBox(height: 4),
          Text('Фразы хранятся в папке: ${c.paths.soundsDir}',
              style: const TextStyle(color: _muted, fontSize: 10)),
        ]),
      ),
      const SizedBox(height: 12),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Диагностика голоса', style: TextStyle(fontWeight: FontWeight.w700))),
            TextButton.icon(
              onPressed: c.isConnected
                  ? () => _perform(context, () async {
                        final result = await c.enableVoice();
                        if (mounted) setState(() => _voiceInfo = result);
                      })
                  : null,
              icon: const Icon(Icons.record_voice_over, size: 16),
              label: const Text('Проверить / включить голос'),
            ),
            TextButton.icon(
              onPressed: c.isConnected ? () => _perform(context, c.refreshCalls) : null,
              icon: const Icon(Icons.refresh, size: 15),
              label: const Text('AT+CLCC'),
            ),
          ]),
          const SizedBox(height: 6),
          SelectableText(
            [
              if (_voiceInfo.isNotEmpty) _voiceInfo,
              if (c.callsRaw.isNotEmpty) c.callsRaw,
            ].join('\n').trim().isEmpty
                ? 'Нет данных. ^CVOICE:0,8000,16,20 означает, что голосовой режим включён.'
                : [
                    if (_voiceInfo.isNotEmpty) _voiceInfo,
                    if (c.callsRaw.isNotEmpty) c.callsRaw,
                  ].join('\n'),
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
          ),
          const SizedBox(height: 8),
          const Text(
            'Если собеседника не слышно: проверьте, что выбран именно звуковой порт (не тот, по которому идут AT-команды), и что ответ AT^CVOICE? начинается с ^CVOICE:0.',
            style: TextStyle(color: _muted, fontSize: 10),
          ),
        ]),
      ),
    ]));
  }
}
