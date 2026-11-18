import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'app_controller.dart';
import 'screens/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await windowManager.ensureInitialized();
    // Закрытие окна перехватывается: окно сворачивается в трей.
    await windowManager.setPreventClose(true);
  } catch (_) {
    // Без оконного плагина программа работает как обычно.
  }
  runApp(const HuaweiModemManagerApp());
}

class HuaweiModemManagerApp extends StatefulWidget {
  const HuaweiModemManagerApp({super.key});

  @override
  State<HuaweiModemManagerApp> createState() => _HuaweiModemManagerAppState();
}

class _HuaweiModemManagerAppState extends State<HuaweiModemManagerApp>
    with TrayListener, WindowListener {
  late final Future<AppController> _controllerFuture = AppController.create();

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    windowManager.addListener(this);
    _initTray();
  }

  Future<void> _initTray() async {
    try {
      await trayManager.setIcon('assets/app_icon.ico');
      await trayManager.setToolTip('Huawei Modem Manager');
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show_window', label: 'Показать окно'),
        MenuItem.separator(),
        MenuItem(key: 'exit_app', label: 'Выход'),
      ]));
    } catch (_) {
      // Трей недоступен — закрытие окна тогда завершает программу.
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _exitApp() async {
    try {
      final controller = await _controllerFuture;
      await controller.modem.disconnect();
    } catch (_) {}
    try {
      await trayManager.destroy();
    } catch (_) {}
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onWindowClose() async {
    var toTray = true;
    try {
      final controller = await _controllerFuture;
      toTray = controller.settings.closeToTray;
    } catch (_) {
      toTray = false;
    }
    if (toTray) {
      await windowManager.hide();
    } else {
      await _exitApp();
    }
  }

  @override
  void onTrayIconMouseDown() {
    _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') {
      _showWindow();
    } else if (menuItem.key == 'exit_app') {
      _exitApp();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppController>(
      future: _controllerFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('Не удалось запустить приложение:\n${snapshot.error}'),
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(colorSchemeSeed: const Color(0xFF246BCE)),
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        return ChangeNotifierProvider.value(
          value: snapshot.data!,
          child: MaterialApp(
            title: 'Huawei Modem Manager',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF2167C5),
                brightness: Brightness.light,
                surface: const Color(0xFFF7F9FC),
              ),
              scaffoldBackgroundColor: const Color(0xFFF7F9FC),
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: const Color(0xFFF8FAFD),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE1E6EF)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE1E6EF)),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              dividerColor: const Color(0xFFE8ECF2),
              appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFFF7F9FC),
                surfaceTintColor: Colors.transparent,
              ),
            ),
            home: const HomeShell(),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _controllerFuture.then((controller) => controller.dispose());
    super.dispose();
  }
}
