import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_controller.dart';
import 'screens/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HuaweiModemManagerApp());
}

class HuaweiModemManagerApp extends StatefulWidget {
  const HuaweiModemManagerApp({super.key});

  @override
  State<HuaweiModemManagerApp> createState() => _HuaweiModemManagerAppState();
}

class _HuaweiModemManagerAppState extends State<HuaweiModemManagerApp> {
  late final Future<AppController> _controllerFuture = AppController.create();

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
    _controllerFuture.then((controller) => controller.dispose());
    super.dispose();
  }
}
