import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/sync_service.dart';

class DispositivoScreen extends StatefulWidget {
  final VoidCallback onConfirmado;
  const DispositivoScreen({super.key, required this.onConfirmado});

  @override
  State<DispositivoScreen> createState() => _DispositivoScreenState();
}

class _DispositivoScreenState extends State<DispositivoScreen> {
  static const _prefUsuarioId     = 'usuario_id';
  static const _prefUsuarioNombre = 'usuario_nombre';
  static const _prefDeviceHash    = 'device_hash';
  static const _prefVinculado     = 'vinculado';

  bool    _cargando = true;
  bool    _vinculado = false;
  String  _usuarioVinculado = '';
  String? _error;

  // Lista de usuarios desde Supabase
  List<Map<String, String>> _usuarios = [];
  String? _usuarioSeleccionadoId;
  String? _usuarioSeleccionadoNombre;

  @override
  void initState() {
    super.initState();
    _verificarVinculo();
  }

  // ── Verificar si este dispositivo ya está vinculado ───────────

  Future<void> _verificarVinculo() async {
    final prefs = await SharedPreferences.getInstance();
    final yaVinculado = prefs.getBool(_prefVinculado) ?? false;

    if (yaVinculado) {
      final nombre = prefs.getString(_prefUsuarioNombre) ?? '';
      final usuId  = prefs.getString(_prefUsuarioId) ?? '';
      final hash   = prefs.getString(_prefDeviceHash) ?? '';

      // Verificar contra Supabase que el vínculo sigue válido
      final valido = await SyncService().verificarVinculo(
          deviceHash: hash, usuarioId: usuId);

      if (valido) {
        // Ya vinculado y verificado — inicializar y continuar
        await SyncService().inicializar(
          usuarioId:     usuId,
          usuarioNombre: nombre,
          deviceHash:    hash,
        );
        if (mounted) widget.onConfirmado();
        return;
      } else {
        // Vínculo inválido (fue revocado por admin) — limpiar y pedir de nuevo
        await prefs.clear();
      }
    }

    // No vinculado — cargar usuarios y mostrar selección
    await _cargarUsuarios();
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _cargarUsuarios() async {
    final lista = await SyncService().obtenerUsuarios();
    if (mounted) setState(() => _usuarios = lista);
  }

  // ── Generar hash único del dispositivo ───────────────────────

  Future<String> _generarDeviceHash() async {
    try {
      final info = DeviceInfoPlugin();
      String raw = '';
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        raw = '${android.id}_${android.model}_${android.brand}';
      } else {
        raw = DateTime.now().millisecondsSinceEpoch.toString();
      }
      return sha256.convert(utf8.encode(raw)).toString().substring(0, 16);
    } catch (_) {
      return DateTime.now().millisecondsSinceEpoch.toString().substring(0, 16);
    }
  }

  // ── Vincular dispositivo con usuario seleccionado ─────────────

  Future<void> _vincular() async {
    if (_usuarioSeleccionadoId == null) {
      setState(() => _error = 'Selecciona tu nombre');
      return;
    }

    setState(() { _cargando = true; _error = null; });

    final hash = await _generarDeviceHash();

    // Intentar vincular en Supabase
    final resultado = await SyncService().vincularDispositivo(
      usuarioId:     _usuarioSeleccionadoId!,
      usuarioNombre: _usuarioSeleccionadoNombre!,
      deviceHash:    hash,
    );

    if (!resultado.exito) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error    = resultado.mensaje;
        });
      }
      return;
    }

    // Guardar localmente
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefUsuarioId,     _usuarioSeleccionadoId!);
    await prefs.setString(_prefUsuarioNombre, _usuarioSeleccionadoNombre!);
    await prefs.setString(_prefDeviceHash,    hash);
    await prefs.setBool  (_prefVinculado,     true);

    // Inicializar sync con el usuario vinculado
    await SyncService().inicializar(
      usuarioId:     _usuarioSeleccionadoId!,
      usuarioNombre: _usuarioSeleccionadoNombre!,
      deviceHash:    hash,
    );

    if (mounted) widget.onConfirmado();
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(body: Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Conectando...'),
        ],
      )));
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo / ícono
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B4F8A).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.inventory_2_outlined,
                    size: 64, color: Color(0xFF1B4F8A)),
              ),
              const SizedBox(height: 24),
              const Text('Inventario CENAM',
                  style: TextStyle(fontSize: 24,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('¿Quién eres?',
                  style: TextStyle(fontSize: 16,
                      color: Colors.grey.shade600)),
              const SizedBox(height: 6),
              Text(
                'Selecciona tu nombre. Este dispositivo quedará\n'
                'registrado a tu nombre permanentemente.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13,
                    color: Colors.grey.shade500),
              ),
              const SizedBox(height: 32),

              // Lista de usuarios
              if (_usuarios.isEmpty)
                const CircularProgressIndicator()
              else
                ..._usuarios.map((u) {
                  final seleccionado = u['id'] == _usuarioSeleccionadoId;
                  return GestureDetector(
                    onTap: () => setState(() {
                      _usuarioSeleccionadoId     = u['id'];
                      _usuarioSeleccionadoNombre = u['nombre'];
                      _error = null;
                    }),
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: seleccionado
                            ? const Color(0xFF1B4F8A)
                            : Theme.of(context)
                                .colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: seleccionado
                              ? const Color(0xFF1B4F8A)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Row(children: [
                        CircleAvatar(
                          backgroundColor: seleccionado
                              ? Colors.white.withOpacity(0.3)
                              : const Color(0xFF1B4F8A).withOpacity(0.1),
                          child: Text(
                            u['nombre']![0].toUpperCase(),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: seleccionado
                                  ? Colors.white
                                  : const Color(0xFF1B4F8A),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          u['nombre']!,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: seleccionado
                                ? Colors.white
                                : null,
                          ),
                        ),
                        const Spacer(),
                        if (seleccionado)
                          const Icon(Icons.check_circle,
                              color: Colors.white),
                      ]),
                    ),
                  );
                }),

              // Error
              if (_error != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(children: [
                    Icon(Icons.error_outline,
                        color: Colors.red.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!,
                        style: TextStyle(color: Colors.red.shade700,
                            fontSize: 13))),
                  ]),
                ),
              ],

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _usuarioSeleccionadoId != null
                      ? _vincular : null,
                  icon: const Icon(Icons.lock_outline),
                  label: Text(
                    _usuarioSeleccionadoNombre != null
                        ? 'Confirmar — Soy $_usuarioSeleccionadoNombre'
                        : 'Selecciona tu nombre',
                    style: const TextStyle(fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '🔒 Una vez confirmado, este dispositivo queda\n'
                'registrado permanentemente a tu nombre.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11,
                    color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Resultado de vinculación ──────────────────────────────────

class ResultadoVinculo {
  final bool   exito;
  final String mensaje;
  const ResultadoVinculo({required this.exito, required this.mensaje});
}
