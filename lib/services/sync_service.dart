import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config/supabase_config.dart';
import '../screens/dispositivo_screen.dart';
import 'inventario_service.dart';

// ── Estado de sincronización ──────────────────────────────────

enum EstadoSync { inactivo, sincronizando, ok, error, sinConexion }

class SyncStatus {
  final EstadoSync estado;
  final int        pendientes;
  final DateTime?  ultimaSync;
  final String?    error;

  const SyncStatus({
    required this.estado,
    this.pendientes = 0,
    this.ultimaSync,
    this.error,
  });
}

// ── Servicio de sincronización ────────────────────────────────

class SyncService {
  static final SyncService _i = SyncService._();
  factory SyncService() => _i;
  SyncService._();

  static const _colaPendiente = 'sync_cola_pendiente.json';

  String? _sesionId;
  String? _dispositivoId;
  String? _usuarioId;
  String? _usuarioNombre;
  String? _deviceHash;

  Timer?  _timer;
  bool    _sincronizando = false;

  final _statusCtrl = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusCtrl.stream;
  SyncStatus _status = const SyncStatus(estado: EstadoSync.inactivo);
  SyncStatus get status => _status;

  // ── Getters ───────────────────────────────────────────────────

  bool    get inicializado  => _sesionId != null && _dispositivoId != null;
  String? get usuarioNombre => _usuarioNombre;

  // ── Inicializar tras vincular usuario ─────────────────────────

  Future<void> inicializar({
    required String usuarioId,
    required String usuarioNombre,
    required String deviceHash,
  }) async {
    _usuarioId     = usuarioId;
    _usuarioNombre = usuarioNombre;
    _deviceHash    = deviceHash;

    await _obtenerOCrearDispositivo();
    await _obtenerSesionActiva();

    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: SupabaseConfig.syncIntervalSeg),
      (_) => sincronizarPendientes(),
    );
    _emitir(const SyncStatus(estado: EstadoSync.ok));
  }

  void detener() { _timer?.cancel(); _timer = null; }

  // ── Verificar vínculo existente ───────────────────────────────

  Future<bool> verificarVinculo({
    required String deviceHash,
    required String usuarioId,
  }) async {
    try {
      final resp = await http.get(
        Uri.parse(
          '${SupabaseConfig.url}/rest/v1/vinculos_dispositivo'
          '?device_hash=eq.$deviceHash'
          '&usuario_id=eq.$usuarioId'
          '&select=id',
        ),
        headers: _headers,
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final lista = List.from(jsonDecode(resp.body));
        return lista.isNotEmpty;
      }
    } catch (_) {}
    // Sin conexión — asumir válido para no bloquear offline
    return true;
  }

  // ── Obtener lista de usuarios ─────────────────────────────────

  Future<List<Map<String, String>>> obtenerUsuarios() async {
    try {
      final resp = await http.get(
        Uri.parse(
          '${SupabaseConfig.url}/rest/v1/usuarios'
          '?activo=eq.true'
          '&select=id,nombre'
          '&order=nombre.asc',
        ),
        headers: _headers,
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final lista = List<Map<String, dynamic>>.from(jsonDecode(resp.body));
        return lista.map((u) => {
          'id':     u['id'].toString(),
          'nombre': u['nombre'].toString(),
        }).toList();
      }
    } catch (_) {}
    // Fallback offline si no hay conexión
    return [
      {'id': '', 'nombre': 'Hennry'},
      {'id': '', 'nombre': 'Yaneth'},
      {'id': '', 'nombre': 'Margarita'},
      {'id': '', 'nombre': 'Elizabeth'},
      {'id': '', 'nombre': 'Samuel'},
    ];
  }

  // ── Vincular dispositivo con usuario ─────────────────────────

  Future<ResultadoVinculo> vincularDispositivo({
    required String usuarioId,
    required String usuarioNombre,
    required String deviceHash,
  }) async {
    try {
      // 1. Verificar que el hash no esté ya vinculado a OTRO usuario
      final existeResp = await http.get(
        Uri.parse(
          '${SupabaseConfig.url}/rest/v1/vinculos_dispositivo'
          '?device_hash=eq.$deviceHash'
          '&select=usuario_id,dispositivo_id',
        ),
        headers: _headers,
      ).timeout(const Duration(seconds: 8));

      if (existeResp.statusCode == 200) {
        final lista = List.from(jsonDecode(existeResp.body));
        if (lista.isNotEmpty) {
          final uId = lista.first['usuario_id'];
          if (uId != usuarioId) {
            return const ResultadoVinculo(
              exito:   false,
              mensaje: 'Este dispositivo ya está registrado a otro usuario. '
                       'Contacta al administrador para cambiar el vínculo.',
            );
          }
          // Ya vinculado al mismo usuario — ok
          return const ResultadoVinculo(exito: true, mensaje: 'OK');
        }
      }

      // 2. Crear o reutilizar dispositivo
      await _obtenerOCrearDispositivoConHash(deviceHash, usuarioNombre);

      if (_dispositivoId == null) {
        return const ResultadoVinculo(
          exito:   false,
          mensaje: 'Error al registrar dispositivo. Verifica la conexión.',
        );
      }

      // 3. Crear vínculo
      final vinculo = await http.post(
        Uri.parse('${SupabaseConfig.url}/rest/v1/vinculos_dispositivo'),
        headers: {..._headers, 'Prefer': 'return=minimal'},
        body: jsonEncode({
          'dispositivo_id': _dispositivoId,
          'usuario_id':     usuarioId,
          'device_hash':    deviceHash,
        }),
      ).timeout(const Duration(seconds: 8));

      if (vinculo.statusCode == 201 || vinculo.statusCode == 200) {
        return const ResultadoVinculo(exito: true, mensaje: 'OK');
      }

      return ResultadoVinculo(
        exito:   false,
        mensaje: 'Error al crear vínculo (${vinculo.statusCode})',
      );
    } catch (e) {
      return ResultadoVinculo(
        exito:   false,
        mensaje: 'Sin conexión — intenta de nuevo',
      );
    }
  }

  // ── Enviar registro ───────────────────────────────────────────

  Future<void> enviarRegistro(RegistroInventario r) async {
    if (!inicializado) return;

    final payload = {
      'sesion_id':      _sesionId,
      'dispositivo_id': _dispositivoId,
      'usuario_id':     _usuarioId,
      'usuario_nombre': _usuarioNombre ?? '',
      'cve_activo':     r.cveActivo,
      'codigo_display': r.codigoDisplay,
      'localizacion':   r.localizacion,
      'tipo':           r.tipo == TipoActivo.noCatalogado
                        ? 'no_catalogado' : 'catalogado',
      'nota':           r.nota,
      'escaneado_en':   r.fecha.toUtc().toIso8601String(),
    };

    final enviado = await _postRegistro(payload);
    if (!enviado) {
      await _encolarPendiente(payload);
      _emitir(SyncStatus(
        estado:     EstadoSync.sinConexion,
        pendientes: await _contarPendientes(),
        ultimaSync: _status.ultimaSync,
      ));
    } else {
      _emitir(SyncStatus(
        estado:     EstadoSync.ok,
        pendientes: await _contarPendientes(),
        ultimaSync: DateTime.now(),
      ));
    }
  }

  // ── Sincronizar pendientes ────────────────────────────────────

  Future<void> sincronizarPendientes() async {
    if (_sincronizando || !inicializado) return;
    _sincronizando = true;

    final pendientes = await _leerCola();
    if (pendientes.isEmpty) { _sincronizando = false; return; }

    _emitir(SyncStatus(
      estado:     EstadoSync.sincronizando,
      pendientes: pendientes.length,
      ultimaSync: _status.ultimaSync,
    ));

    final enviados = <int>[];
    for (int i = 0; i < pendientes.length; i++) {
      if (await _postRegistro(pendientes[i])) enviados.add(i);
    }

    final restantes = pendientes.asMap().entries
        .where((e) => !enviados.contains(e.key))
        .map((e) => e.value).toList();
    await _guardarCola(restantes);

    _sincronizando = false;
    _emitir(SyncStatus(
      estado:     restantes.isEmpty ? EstadoSync.ok : EstadoSync.sinConexion,
      pendientes: restantes.length,
      ultimaSync: enviados.isNotEmpty ? DateTime.now() : _status.ultimaSync,
    ));
  }

  // ── Obtener registros de la sesión activa ─────────────────────

  Future<List<Map<String, dynamic>>> obtenerRegistrosSesion() async {
    if (!inicializado) return [];
    try {
      final resp = await http.get(
        Uri.parse(
          '${SupabaseConfig.url}/rest/v1/registros_inventario'
          '?sesion_id=eq.$_sesionId'
          '&select=cve_activo,codigo_display,localizacion,tipo,'
                 'usuario_nombre,escaneado_en'
          '&order=escaneado_en.desc',
        ),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(resp.body));
      }
    } catch (_) {}
    return [];
  }

  // ── Helpers API ───────────────────────────────────────────────

  Map<String, String> get _headers => {
    'apikey':        SupabaseConfig.anonKey,
    'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
    'Content-Type':  'application/json',
    'Prefer':        'return=minimal,resolution=ignore-duplicates',
  };

  Future<bool> _postRegistro(Map<String, dynamic> payload) async {
    try {
      final resp = await http.post(
        Uri.parse('${SupabaseConfig.url}/rest/v1/registros_inventario'),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 8));
      return resp.statusCode == 201 ||
             resp.statusCode == 200 ||
             resp.statusCode == 409;
    } catch (_) { return false; }
  }

  Future<void> _obtenerOCrearDispositivo() async {
    await _obtenerOCrearDispositivoConHash(_deviceHash!, _usuarioNombre!);
  }

  Future<void> _obtenerOCrearDispositivoConHash(
      String hash, String nombre) async {
    try {
      // Buscar por hash
      final resp = await http.get(
        Uri.parse(
          '${SupabaseConfig.url}/rest/v1/vinculos_dispositivo'
          '?device_hash=eq.$hash'
          '&select=dispositivo_id',
        ),
        headers: _headers,
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final lista = List.from(jsonDecode(resp.body));
        if (lista.isNotEmpty) {
          _dispositivoId = lista.first['dispositivo_id'];
          return;
        }
      }

      // Crear nuevo dispositivo
      final create = await http.post(
        Uri.parse('${SupabaseConfig.url}/rest/v1/dispositivos'),
        headers: {..._headers, 'Prefer': 'return=representation'},
        body: jsonEncode({'nombre': 'Dispositivo — $nombre', 'activo': true}),
      ).timeout(const Duration(seconds: 8));

      if (create.statusCode == 201) {
        final data = List.from(jsonDecode(create.body));
        if (data.isNotEmpty) _dispositivoId = data.first['id'];
      }
    } catch (_) {}
  }

  Future<void> _obtenerSesionActiva() async {
    try {
      final resp = await http.get(
        Uri.parse(
          '${SupabaseConfig.url}/rest/v1/sesiones_inventario'
          '?activa=eq.true&select=id&order=creado_en.desc&limit=1',
        ),
        headers: _headers,
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final lista = List.from(jsonDecode(resp.body));
        if (lista.isNotEmpty) _sesionId = lista.first['id'];
      }
    } catch (_) {}
  }

  // ── Cola offline ──────────────────────────────────────────────

  Future<File> get _archivoCola async {
    final d = await getApplicationDocumentsDirectory();
    return File('${d.path}/$_colaPendiente');
  }

  Future<List<Map<String, dynamic>>> _leerCola() async {
    try {
      final f = await _archivoCola;
      if (!await f.exists()) return [];
      return List<Map<String, dynamic>>.from(jsonDecode(await f.readAsString()));
    } catch (_) { return []; }
  }

  Future<void> _guardarCola(List<Map<String, dynamic>> lista) async {
    final f = await _archivoCola;
    await f.writeAsString(jsonEncode(lista));
  }

  Future<void> _encolarPendiente(Map<String, dynamic> payload) async {
    final cola = await _leerCola();
    cola.add(payload);
    await _guardarCola(cola);
  }

  Future<int> _contarPendientes() async => (await _leerCola()).length;

  void _emitir(SyncStatus s) { _status = s; _statusCtrl.add(s); }
}
