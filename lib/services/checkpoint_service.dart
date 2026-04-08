import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'inventario_service.dart';

// ── Modelo de ubicación dentro de un checkpoint ───────────────────

class UbicacionProgreso {
  final String clave;
  final String descripcion;
  final int    escaneados;
  final int    esperados;
  final bool   completada;

  const UbicacionProgreso({
    required this.clave,
    required this.descripcion,
    required this.escaneados,
    required this.esperados,
    required this.completada,
  });

  double get porcentaje =>
      esperados > 0 ? (escaneados / esperados).clamp(0.0, 1.0) : 0.0;
}

// ── Modelo de checkpoint de edificio ─────────────────────────────

class CheckpointEdificio {
  final String   id;          // "A_20260408_143022"
  final String   letra;       // "A"
  final String   nombre;      // "Edificio A"
  final DateTime fechaInicio;
  final DateTime? fechaCierre;
  final int      totalRegistros;
  final int      ubicacionesCubiertas;
  final int      ubicacionesTotales;
  final bool     cerrado;

  CheckpointEdificio({
    required this.id,
    required this.letra,
    required this.nombre,
    required this.fechaInicio,
    this.fechaCierre,
    required this.totalRegistros,
    required this.ubicacionesCubiertas,
    required this.ubicacionesTotales,
    required this.cerrado,
  });

  double get porcentaje => ubicacionesTotales > 0
      ? (ubicacionesCubiertas / ubicacionesTotales).clamp(0.0, 1.0)
      : 0.0;

  Map<String, dynamic> toJson() => {
    'id':                    id,
    'letra':                 letra,
    'nombre':                nombre,
    'fechaInicio':           fechaInicio.toIso8601String(),
    'fechaCierre':           fechaCierre?.toIso8601String(),
    'totalRegistros':        totalRegistros,
    'ubicacionesCubiertas':  ubicacionesCubiertas,
    'ubicacionesTotales':    ubicacionesTotales,
    'cerrado':               cerrado,
  };

  factory CheckpointEdificio.fromJson(Map<String, dynamic> j) =>
      CheckpointEdificio(
        id:                   j['id'],
        letra:                j['letra'],
        nombre:               j['nombre'],
        fechaInicio:          DateTime.parse(j['fechaInicio']),
        fechaCierre:          j['fechaCierre'] != null
            ? DateTime.parse(j['fechaCierre'])
            : null,
        totalRegistros:       j['totalRegistros'],
        ubicacionesCubiertas: j['ubicacionesCubiertas'],
        ubicacionesTotales:   j['ubicacionesTotales'],
        cerrado:              j['cerrado'] ?? false,
      );
}

// ── Servicio de checkpoints ───────────────────────────────────────

class CheckpointService {
  static final CheckpointService _i = CheckpointService._();
  factory CheckpointService() => _i;
  CheckpointService._();

  static const _carpeta  = 'ALM_Inventario';
  static const _indice   = 'checkpoints_index.json';

  Future<Directory> get _dir async {
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/$_carpeta');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  // ── Leer índice ───────────────────────────────────────────────────

  Future<List<CheckpointEdificio>> cargarCheckpoints() async {
    try {
      final d    = await _dir;
      final file = File('${d.path}/$_indice');
      if (!await file.exists()) return [];
      final json = jsonDecode(await file.readAsString()) as List;
      return json
          .map((e) => CheckpointEdificio.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.fechaInicio.compareTo(a.fechaInicio));
    } catch (_) {
      return [];
    }
  }

  Future<void> _guardarIndice(List<CheckpointEdificio> lista) async {
    final d    = await _dir;
    final file = File('${d.path}/$_indice');
    await file.writeAsString(
        jsonEncode(lista.map((c) => c.toJson()).toList()));
  }

  // ── Crear checkpoint ──────────────────────────────────────────────

  Future<CheckpointEdificio> crearCheckpoint({
    required String letra,
    required String nombre,
    required List<RegistroInventario> registros,
    required int ubicacionesCubiertas,
    required int ubicacionesTotales,
  }) async {
    final ahora = DateTime.now();
    final id    = '${letra}_${DateFormat("yyyyMMdd_HHmmss").format(ahora)}';

    final cp = CheckpointEdificio(
      id:                   id,
      letra:                letra,
      nombre:               nombre,
      fechaInicio:          ahora,
      totalRegistros:       registros.length,
      ubicacionesCubiertas: ubicacionesCubiertas,
      ubicacionesTotales:   ubicacionesTotales,
      cerrado:              false,
    );

    // Guardar TXT del checkpoint (formato SIGA — sin notas)
    await _guardarTxtCheckpoint(id, registros);

    // Actualizar índice
    final lista = await cargarCheckpoints();
    lista.insert(0, cp);
    await _guardarIndice(lista);

    return cp;
  }

  // ── Cerrar checkpoint (marcar como terminado) ─────────────────────

  Future<CheckpointEdificio> cerrarCheckpoint(
      String id,
      List<RegistroInventario> registros,
      {required int ubicacionesCubiertas,
       required int ubicacionesTotales}) async {
    final lista = await cargarCheckpoints();
    final idx   = lista.indexWhere((c) => c.id == id);
    if (idx < 0) throw Exception('Checkpoint no encontrado');

    final cp = lista[idx];
    final cerrado = CheckpointEdificio(
      id:                   cp.id,
      letra:                cp.letra,
      nombre:               cp.nombre,
      fechaInicio:          cp.fechaInicio,
      fechaCierre:          DateTime.now(),
      totalRegistros:       registros.length,
      ubicacionesCubiertas: ubicacionesCubiertas,
      ubicacionesTotales:   ubicacionesTotales,
      cerrado:              true,
    );

    // Actualizar TXT con registros finales
    await _guardarTxtCheckpoint(id, registros);

    lista[idx] = cerrado;
    await _guardarIndice(lista);
    return cerrado;
  }

  // ── TXT por checkpoint (para SIGA) ────────────────────────────────

  Future<void> _guardarTxtCheckpoint(
      String id, List<RegistroInventario> registros) async {
    final d    = await _dir;
    final file = File('${d.path}/Checkpoint_$id.txt');
    final buf  = StringBuffer();
    for (final r in registros) {
      buf.writeln(r.toLineTxt()); // limpio sin notas
    }
    await file.writeAsString(buf.toString());
  }

  Future<String> rutaTxtCheckpoint(String id) async {
    final d = await _dir;
    return '${d.path}/Checkpoint_$id.txt';
  }

  // ── Eliminar checkpoint ───────────────────────────────────────────

  Future<void> eliminarCheckpoint(String id) async {
    final lista = await cargarCheckpoints();
    lista.removeWhere((c) => c.id == id);
    await _guardarIndice(lista);

    final d    = await _dir;
    final file = File('${d.path}/Checkpoint_$id.txt');
    if (await file.exists()) await file.delete();
  }

  // ── Registros de un checkpoint ────────────────────────────────────

  Future<List<RegistroInventario>> registrosDeCheckpoint(String id) async {
    try {
      final d    = await _dir;
      final file = File('${d.path}/Checkpoint_$id.txt');
      if (!await file.exists()) return [];
      final lines = await file.readAsLines();
      return lines
          .map(RegistroInventario.fromLine)
          .whereType<RegistroInventario>()
          .toList();
    } catch (_) {
      return [];
    }
  }
}
