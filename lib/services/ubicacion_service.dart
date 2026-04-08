import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'inventario_service.dart';
import 'teorico_service.dart';

// ── Modelo de cambio de ubicación ────────────────────────────────

class CambioUbicacion {
  final String cveActivo;
  final String descripcion;
  final String ubicacionAnterior;
  final String ubicacionNueva;
  final DateTime fecha;

  CambioUbicacion({
    required this.cveActivo,
    required this.descripcion,
    required this.ubicacionAnterior,
    required this.ubicacionNueva,
    required this.fecha,
  });

  String toLinea() {
    final f = DateFormat('dd/MM/yyyy').format(fecha);
    return '$cveActivo|$ubicacionAnterior|$ubicacionNueva|$f';
  }

  static CambioUbicacion? fromLinea(String linea, TeoricoService teorico) {
    final parts = linea.trim().split('|');
    if (parts.length < 4) return null;
    try {
      final activo = teorico.buscarPorCodigo(parts[0]);
      return CambioUbicacion(
        cveActivo:          parts[0],
        descripcion:        activo?.descripcion ?? '',
        ubicacionAnterior:  parts[1],
        ubicacionNueva:     parts[2],
        fecha:              DateFormat('dd/MM/yyyy').parse(parts[3]),
      );
    } catch (_) {
      return null;
    }
  }
}

// ── Servicio de actualización de ubicaciones ─────────────────────

class UbicacionService {
  static final UbicacionService _i = UbicacionService._();
  factory UbicacionService() => _i;
  UbicacionService._();

  final _teorico = TeoricoService();

  static const _carpeta = 'ALM_Inventario';
  static const _archivo = 'cambios_ubicacion.txt';

  Future<Directory> get _dir async {
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/$_carpeta');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  // ── Detectar activos en ubicación diferente al teórico ───────────

  List<CambioUbicacion> detectarCambios(
      List<RegistroInventario> registros) {
    final cambios = <CambioUbicacion>[];

    for (final r in registros) {
      final activo = _teorico.buscarPorCodigo(r.cveActivo);
      if (activo == null) continue;

      // Ubicación teórica vs donde fue escaneado
      final ubTeorica  = activo.localizacion.toUpperCase().trim();
      final ubReal     = r.localizacion.toUpperCase().trim();

      if (ubTeorica.isNotEmpty && ubTeorica != ubReal) {
        cambios.add(CambioUbicacion(
          cveActivo:         r.cveActivo,
          descripcion:       activo.descripcion,
          ubicacionAnterior: ubTeorica,
          ubicacionNueva:    ubReal,
          fecha:             r.fecha,
        ));
      }
    }

    return cambios;
  }

  // ── Guardar cambios de ubicación ─────────────────────────────────

  Future<void> guardarCambios(List<CambioUbicacion> cambios) async {
    if (cambios.isEmpty) return;
    final d    = await _dir;
    final file = File('${d.path}/$_archivo');
    final buf  = StringBuffer();

    // Encabezado con fecha
    buf.writeln('# Cambios registrados: '
        '${DateFormat("dd/MM/yyyy HH:mm").format(DateTime.now())}');
    for (final c in cambios) {
      buf.writeln(c.toLinea());
    }
    buf.writeln();

    await file.writeAsString(buf.toString(), mode: FileMode.append);
  }

  // ── Leer historial de cambios ────────────────────────────────────

  Future<List<CambioUbicacion>> cargarHistorialCambios() async {
    try {
      final d    = await _dir;
      final file = File('${d.path}/$_archivo');
      if (!await file.exists()) return [];

      final lines = await file.readAsLines();
      return lines
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .map((l) => CambioUbicacion.fromLinea(l, _teorico))
          .whereType<CambioUbicacion>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<String> rutaArchivoCambios() async {
    final d = await _dir;
    return '${d.path}/$_archivo';
  }
}
