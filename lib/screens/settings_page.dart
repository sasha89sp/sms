part of 'pages.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _networkWait;
  late final TextEditingController _ussdTimeout;
  late final TextEditingController _retries;
  late final TextEditingController _smsPoll;
  late final TextEditingController _smsMin;
  String _port = '';
  int _baud = 115200;
  int _dcs = 15;
  bool _autoConnect = true;
  bool _statusReport = false;
  bool _smsAuto = true;
  bool _deleteFromModem = false;
  bool _excelDate = true;
  bool _closeToTray = true;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppController>().settings;
    _networkWait = TextEditingController(text: s.networkWaitSeconds.toString());
    _ussdTimeout = TextEditingController(text: s.ussdTimeoutSeconds.toString());
    _retries = TextEditingController(text: s.retryCount.toString());
    _smsPoll = TextEditingController(text: s.smsPollSeconds.toString());
    _smsMin = TextEditingController(text: s.smsMinBalance.toString());
    _port = s.preferredPort;
    _baud = s.baudRate;
    _dcs = s.ussdDcs;
    _autoConnect = s.autoConnect;
    _statusReport = s.smsRequireNetworkAck;
    _smsAuto = s.smsAutoReceive;
    _deleteFromModem = s.deleteSmsFromModem;
    _excelDate = s.excelIncludeDate;
    _closeToTray = s.closeToTray;
  }

  @override
  void dispose() {
    _networkWait.dispose();
    _ussdTimeout.dispose();
    _retries.dispose();
    _smsPoll.dispose();
    _smsMin.dispose();
    super.dispose();
  }

  Widget _numberField(TextEditingController controller, String label) =>
      TextField(controller: controller, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: label));

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    return _pageBody(ListView(children: [
      const _PageHeader('Настройки', subtitle: 'Соединение, USSD, SMS, Excel и поведение программы'),
      const SizedBox(height: 14),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Подключение к модему', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 11),
          DropdownButtonFormField<String>(
            value: _port.isEmpty ? '' : _port,
            decoration: const InputDecoration(labelText: 'Предпочтительный COM-порт', prefixIcon: Icon(Icons.usb)),
            items: [
              const DropdownMenuItem(value: '', child: Text('Автоматический поиск')),
              if (_port.isNotEmpty && !c.availablePorts.any((item) => item.name == _port))
                DropdownMenuItem(value: _port, child: Text('$_port · сейчас не найден')),
              ...c.availablePorts.map((p) => DropdownMenuItem(
                    value: p.name,
                    child: Text('${p.name} · ${p.friendlyName.isEmpty ? 'COM-порт' : p.friendlyName}', overflow: TextOverflow.ellipsis),
                  )),
            ],
            onChanged: (value) => setState(() => _port = value ?? ''),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: _baud,
            decoration: const InputDecoration(labelText: 'Скорость порта (baud)'),
            items: const [9600, 19200, 38400, 57600, 115200].map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
            onChanged: (value) => setState(() => _baud = value ?? 115200),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _autoConnect,
            onChanged: (value) => setState(() => _autoConnect = value),
            title: const Text('Автоматически подключаться при появлении модема', style: TextStyle(fontSize: 12)),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('USSD, сеть и повторы', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: _dcs,
            decoration: const InputDecoration(labelText: 'DCS для USSD'),
            items: const [15, 72]
                .map((v) => DropdownMenuItem(value: v, child: Text(v == 72 ? '72 — UCS-2 (часто для кириллицы)' : '15 — стандартная таблица')))
                .toList(),
            onChanged: (value) => setState(() => _dcs = value ?? 15),
          ),
          const SizedBox(height: 9),
          _numberField(_networkWait, 'Ожидание сети, секунд'),
          const SizedBox(height: 9),
          _numberField(_ussdTimeout, 'Таймаут USSD, секунд'),
          const SizedBox(height: 9),
          _numberField(_retries, 'Количество повторов USSD (0–5)'),
        ]),
      ),
      const SizedBox(height: 12),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('SMS', style: TextStyle(fontWeight: FontWeight.w700)),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _smsAuto,
            onChanged: (value) => setState(() => _smsAuto = value),
            title: const Text('Автоматически получать входящие SMS', style: TextStyle(fontSize: 12)),
            subtitle: const Text('Новые сообщения выгружаются из памяти модема в локальную базу.', style: TextStyle(fontSize: 10)),
          ),
          _numberField(_smsPoll, 'Проверять память модема каждые, секунд (0 — только по уведомлению)'),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _deleteFromModem,
            onChanged: (value) => setState(() => _deleteFromModem = value),
            title: const Text('Удалять SMS из памяти модема после сохранения', style: TextStyle(fontSize: 12)),
            subtitle: const Text('Освобождает память SIM. Сообщения остаются в программе.', style: TextStyle(fontSize: 10)),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _statusReport,
            onChanged: (value) => setState(() => _statusReport = value),
            title: const Text('Запрашивать сетевой отчёт о доставке', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _smsMin,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Минимальный баланс для отправки SMS в сценарии',
              helperText: '0 — не проверять. Ниже этой суммы SMS не отправляется, шаг помечается «НЕДОСТАТОЧНО СРЕДСТВ».',
            ),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Excel и приложение', style: TextStyle(fontWeight: FontWeight.w700)),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _excelDate,
            onChanged: (value) => setState(() => _excelDate = value),
            title: const Text('Добавлять дату и время в таблицу Excel', style: TextStyle(fontSize: 12)),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _closeToTray,
            onChanged: (value) => setState(() => _closeToTray = value),
            title: const Text('При закрытии окна сворачивать в трей', style: TextStyle(fontSize: 12)),
            subtitle: const Text('Выход — через значок в системном трее → «Выход».', style: TextStyle(fontSize: 10)),
          ),
          Text('Данные программы: ${c.paths.dataDir}', style: const TextStyle(color: _muted, fontSize: 10)),
        ]),
      ),
      const SizedBox(height: 14),
      Row(children: [
        const Expanded(
          child: Text('Настройки хранятся в папке программы (портативно).', style: TextStyle(color: _muted, fontSize: 10)),
        ),
        FilledButton.icon(
          onPressed: () => _save(context),
          icon: const Icon(Icons.save, size: 16),
          label: const Text('Сохранить настройки'),
        ),
      ]),
    ]));
  }

  Future<void> _save(BuildContext context) async {
    final c = context.read<AppController>();
    final networkWait = int.tryParse(_networkWait.text.trim()) ?? 180;
    final timeout = int.tryParse(_ussdTimeout.text.trim()) ?? 45;
    final retries = int.tryParse(_retries.text.trim()) ?? 1;
    final poll = int.tryParse(_smsPoll.text.trim()) ?? 15;
    final minBalance = double.tryParse(_smsMin.text.trim().replaceAll(',', '.')) ?? 0;
    if (networkWait < 10 || networkWait > 1800 || timeout < 5 || timeout > 180 || retries < 0 || retries > 5 || poll < 0 || poll > 3600 || minBalance < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Проверьте числовые значения.')));
      return;
    }
    final settings = c.settings.copyWith(
      preferredPort: _port,
      baudRate: _baud,
      ussdDcs: _dcs,
      autoConnect: _autoConnect,
      networkWaitSeconds: networkWait,
      ussdTimeoutSeconds: timeout,
      retryCount: retries,
      smsRequireNetworkAck: _statusReport,
      smsAutoReceive: _smsAuto,
      smsPollSeconds: poll,
      deleteSmsFromModem: _deleteFromModem,
      smsMinBalance: minBalance,
      excelIncludeDate: _excelDate,
      closeToTray: _closeToTray,
    );
    await _perform(context, () => c.updateSettings(settings), successMessage: 'Настройки сохранены');
  }
}
