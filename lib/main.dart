import 'package:flutter/material.dart';
import 'screens/dispositivo_screen.dart';
import 'screens/inventario_screen.dart';

void main() {
  runApp(const InventarioCENAMApp());
}

class InventarioCENAMApp extends StatefulWidget {
  const InventarioCENAMApp({super.key});

  static _InventarioCENAMAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_InventarioCENAMAppState>();

  @override
  State<InventarioCENAMApp> createState() => _InventarioCENAMAppState();
}

class _InventarioCENAMAppState extends State<InventarioCENAMApp> {
  ThemeMode _themeMode     = ThemeMode.system;
  bool      _dispositivoOk = false;

  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark;
    });
  }

  bool get isDark => _themeMode == ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inventario CENAM',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B4F8A),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1B4F8A),
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1B4F8A),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B9BD5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A1A2E),
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        cardTheme: const CardThemeData(color: Color(0xFF1E1E1E)),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF5B9BD5),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      // Si el dispositivo no está configurado → pantalla de setup
      // Si ya está configurado → pantalla principal
      home: _dispositivoOk
          ? const InventarioScreen()
          : DispositivoScreen(
              onConfirmado: () => setState(() => _dispositivoOk = true),
            ),
    );
  }
}
