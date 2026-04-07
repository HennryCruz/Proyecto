import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

// ── Modelo de registro ────────────────────────────────────────────

class RegistroInventario {
  final String localizacion;
  final String cveActivo;
  final DateTime fecha;
  final String nota;

  RegistroInventario({
    required this.localizacion,
    required this.cveActivo,
    required this.fecha,
    this.nota = '',
  });

  // Formato SIGA: siempre LOCALIZACION_CVEACTIVO_FECHA (sin nota)
  String toLineTxt() {
    final fechaStr = DateFormat('dd/MM/yyyy').format(fecha);
    return '${localizacion}_${cveActivo}_$fechaStr';
  }

  // Formato completo con nota — solo para archivos internos y Excel
  String toLineCompleto() {
    final fechaStr = DateFormat('dd/MM/yyyy').format(fecha);
    final base = '${localizacion}_${cveActivo}_$fechaStr';
    return nota.isNotEmpty ? '${base}_$nota' : base;
  }

  static RegistroInventario? fromLine(String line) {
    final parts = line.trim().replaceAll('\r', '').split('_');
    if (parts.length < 3) return null;
    try {
      final fecha = DateFormat('dd/MM/yyyy').parse(parts[2]);
      final nota  = parts.length >= 4 ? parts.sublist(3).join('_') : '';
      return RegistroInventario(
        localizacion: parts[0],
        cveActivo:    parts[1],
        fecha:        fecha,
        nota:         nota,
      );
    } catch (_) {
      return null;
    }
  }
}

// ── Modelo de sesión ──────────────────────────────────────────────

class SesionInventario {
  final String id;          // yyyyMMdd — una sesión por día
  final DateTime inicio;
  final List<RegistroInventario> registros;

  SesionInventario({
    required this.id,
    required this.inicio,
    required this.registros,
  });

  String get nombreArchivo  => 'Inventario_$id.txt';
  String get fechaLegible   =>
      DateFormat('dd/MM/yyyy').format(inicio);
  int    get total          => registros.length;
}

// ── Servicio principal ────────────────────────────────────────────

class InventarioService {
  static final InventarioService _i = InventarioService._();
  factory InventarioService() => _i;
  InventarioService._();

  static const String _carpeta       = 'ALM_Inventario';
  static const String _archivoActual = 'ALM_Inventarios.txt';

  // ── Directorio base ───────────────────────────────────────────────

  Future<Directory> get _dir async {
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final folder = Directory('${base.path}/$_carpeta');
    if (!await folder.exists()) await folder.create(recursive: true);
    return folder;
  }

  Future<File> get _archivoActualFile async {
    final d = await _dir;
    return File('${d.path}/$_archivoActual');
  }

  Future<String> get rutaArchivo async =>
      (await _archivoActualFile).path;

  // ── Sesión activa ─────────────────────────────────────────────────

  Future<List<RegistroInventario>> cargarRegistros() async {
    try {
      final file = await _archivoActualFile;
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

  /// Agrega el registro al archivo activo Y al archivo de sesión del día.
  /// Archivo activo usa toLineCompleto (preserva nota para leer de vuelta).
  /// El TXT que se comparte con SIGA usa toLineTxt() (sin nota).
  Future<void> agregarRegistro(RegistroInventario r) async {
    // 1 — Archivo activo con nota (para leer de vuelta correctamente)
    final activo = await _archivoActualFile;
    await activo.writeAsString('${r.toLineCompleto()}\n',
        mode: FileMode.append);

    // 2 — Archivo de sesión del día (también con nota)
    await _agregarASesionDelDia(r);
  }

  Future<void> _agregarASesionDelDia(RegistroInventario r) async {
    try {
      final d    = await _dir;
      final hoy  = DateFormat('yyyyMMdd').format(DateTime.now());
      final file = File('${d.path}/Inventario_$hoy.txt');
      await file.writeAsString('${r.toLineCompleto()}\n',
          mode: FileMode.append);
    } catch (_) {
      // Si falla el guardado secundario, no interrumpir el flujo
    }
  }

  Future<void> borrarArchivo() async {
    final file = await _archivoActualFile;
    if (await file.exists()) await file.delete();
  }

  // ── Historial de sesiones ─────────────────────────────────────────
  // Lee todos los archivos Inventario_yyyyMMdd.txt del directorio

  Future<List<SesionInventario>> cargarHistorial() async {
    try {
      final d = await _dir;
      final archivos = d
          .listSync()
          .whereType<File>()
          .where((f) {
            final nombre = f.uri.pathSegments.last;
            return nombre.startsWith('Inventario_') &&
                nombre.endsWith('.txt') &&
                nombre != _archivoActual;
          })
          .toList();

      // Más reciente primero
      archivos.sort((a, b) => b.path.compareTo(a.path));

      final sesiones = <SesionInventario>[];
      for (final file in archivos) {
        final nombre = file.uri.pathSegments.last;
        final id     = nombre
            .replaceFirst('Inventario_', '')
            .replaceAll('.txt', '');

        DateTime inicio;
        try {
          inicio = DateFormat('yyyyMMdd').parse(id);
        } catch (_) {
          inicio = await file.lastModified();
        }

        final lines = await file.readAsLines();
        final regs  = lines
            .map(RegistroInventario.fromLine)
            .whereType<RegistroInventario>()
            .toList();

        if (regs.isNotEmpty) {
          sesiones.add(SesionInventario(
            id:        id,
            inicio:    inicio,
            registros: regs,
          ));
        }
      }
      return sesiones;
    } catch (_) {
      return [];
    }
  }

  Future<void> eliminarSesion(String id) async {
    final d    = await _dir;
    final file = File('${d.path}/Inventario_$id.txt');
    if (await file.exists()) await file.delete();
  }

  Future<String> rutaSesion(String id) async {
    final d = await _dir;
    return '${d.path}/Inventario_$id.txt';
  }

  /// Genera un TXT limpio SIN notas para subir al SIGA.
  /// Formato: LOCALIZACION_CVEACTIVO_FECHA (una línea por registro)
  Future<String> exportarTxtSiga(List<RegistroInventario> registros) async {
    final d        = await _dir;
    final fechaStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file     = File('${d.path}/SIGA_$fechaStr.txt');
    final buf      = StringBuffer();
    for (final r in registros) {
      buf.writeln(r.toLineTxt()); // sin nota
    }
    await file.writeAsString(buf.toString());
    return file.path;
  }
}
