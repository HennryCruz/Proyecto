import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

// ── Tipos de registro ─────────────────────────────────────────────

enum TipoActivo {
  catalogado,      // encontrado en el catálogo (normal)
  noCatalogado,    // escaneado pero no está en el catálogo
}

// ── Modelo de registro ────────────────────────────────────────────

class RegistroInventario {
  final String localizacion;
  final String cveActivo;      // Clave interna normalizada (para BD y SIGA)
  final String codigoDisplay;  // Código exacto escaneado (para mostrar en UI)
  final DateTime fecha;
  final String nota;
  final TipoActivo tipo;

  RegistroInventario({
    required this.localizacion,
    required this.cveActivo,
    String? codigoDisplay,
    required this.fecha,
    this.nota = '',
    this.tipo = TipoActivo.catalogado,
  }) : codigoDisplay = codigoDisplay ?? cveActivo;
  // Si no se provee codigoDisplay, usa cveActivo como fallback

  // Formato SIGA limpio (sin nota, sin tipo)
  String toLineTxt() {
    final fechaStr = DateFormat('dd/MM/yyyy').format(fecha);
    return '${localizacion}_${cveActivo}_$fechaStr';
  }

  // Formato completo interno (con nota y tipo)
  String toLineCompleto() {
    final fechaStr = DateFormat('dd/MM/yyyy').format(fecha);
    final tipoStr  = tipo == TipoActivo.noCatalogado ? 'NC' : 'OK';
    final base     = '${localizacion}_${cveActivo}_$fechaStr';
    final conTipo  = '${base}_T:$tipoStr';
    return nota.isNotEmpty ? '${conTipo}_N:$nota' : conTipo;
  }

  static RegistroInventario? fromLine(String line) {
    final l = line.trim().replaceAll('\r', '');
    if (l.isEmpty) return null;

    final parts = l.split('_');
    if (parts.length < 3) return null;

    try {
      final localizacion = parts[0];
      final cveActivo    = parts[1];
      final fecha        = DateFormat('dd/MM/yyyy').parse(parts[2]);

      // Parsear campos extra (T:OK/NC, N:nota)
      String nota = '';
      TipoActivo tipo = TipoActivo.catalogado;

      for (int i = 3; i < parts.length; i++) {
        if (parts[i].startsWith('T:')) {
          tipo = parts[i] == 'T:NC'
              ? TipoActivo.noCatalogado
              : TipoActivo.catalogado;
        } else if (parts[i].startsWith('N:')) {
          nota = parts[i].substring(2);
        } else {
          // Compatibilidad con formato anterior (nota sin prefijo N:)
          nota = parts.sublist(i).join('_');
          break;
        }
      }

      return RegistroInventario(
        localizacion: localizacion,
        cveActivo:    cveActivo,
        fecha:        fecha,
        nota:         nota,
        tipo:         tipo,
      );
    } catch (_) {
      return null;
    }
  }
}

// ── Modelo de sesión ──────────────────────────────────────────────

class SesionInventario {
  final String id;
  final DateTime inicio;
  final List<RegistroInventario> registros;
  final bool esActual;

  SesionInventario({
    required this.id,
    required this.inicio,
    required this.registros,
    this.esActual = false,
  });

  String get nombreArchivo => esActual
      ? 'ALM_Inventarios.txt'
      : 'Inventario_$id.txt';
  String get fechaLegible  => esActual
      ? 'Hoy ${DateFormat("dd/MM/yyyy").format(inicio)}'
      : DateFormat('dd/MM/yyyy').format(inicio);
  int    get total         => registros.length;
  int    get noCatalogados =>
      registros.where((r) => r.tipo == TipoActivo.noCatalogado).length;
}

// ── Servicio principal ────────────────────────────────────────────

class InventarioService {
  static final InventarioService _i = InventarioService._();
  factory InventarioService() => _i;
  InventarioService._();

  static const String _carpeta       = 'ALM_Inventario';
  static const String _archivoActual = 'ALM_Inventarios.txt';
  static const String _idActual      = 'ACTUAL';

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

  Future<void> agregarRegistro(RegistroInventario r) async {
    final activo = await _archivoActualFile;
    await activo.writeAsString('${r.toLineCompleto()}\n',
        mode: FileMode.append);
    await _agregarASesionDelDia(r);
  }

  Future<void> _agregarASesionDelDia(RegistroInventario r) async {
    try {
      final d    = await _dir;
      final hoy  = DateFormat('yyyyMMdd').format(DateTime.now());
      final file = File('${d.path}/Inventario_$hoy.txt');
      await file.writeAsString('${r.toLineCompleto()}\n',
          mode: FileMode.append);
    } catch (_) {}
  }

  Future<void> borrarArchivo() async {
    final file = await _archivoActualFile;
    if (await file.exists()) await file.delete();
  }

  // ── Historial ─────────────────────────────────────────────────────

  Future<List<SesionInventario>> cargarHistorial() async {
    try {
      final d       = await _dir;
      final sesiones = <SesionInventario>[];

      // 1. Sesión activa siempre primero
      final archivoActivo = File('${d.path}/$_archivoActual');
      if (await archivoActivo.exists()) {
        final lines = await archivoActivo.readAsLines();
        final regs  = lines
            .map(RegistroInventario.fromLine)
            .whereType<RegistroInventario>()
            .toList();
        if (regs.isNotEmpty) {
          sesiones.add(SesionInventario(
            id:        _idActual,
            inicio:    DateTime.now(),
            registros: regs,
            esActual:  true,
          ));
        }
      }

      // 2. Sesiones anteriores por día
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

      archivos.sort((a, b) => b.path.compareTo(a.path));
      final hoy = DateFormat('yyyyMMdd').format(DateTime.now());

      for (final file in archivos) {
        final nombre = file.uri.pathSegments.last;
        final id     = nombre
            .replaceFirst('Inventario_', '')
            .replaceAll('.txt', '');
        if (id == hoy) continue;

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
            id: id, inicio: inicio, registros: regs,
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

  // ── TXT limpio para SIGA (sin notas, sin tipo) ────────────────────

  Future<String> exportarTxtSiga(
      List<RegistroInventario> registros) async {
    final d        = await _dir;
    final fechaStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file     = File('${d.path}/SIGA_$fechaStr.txt');
    final buf      = StringBuffer();
    for (final r in registros) {
      buf.writeln(r.toLineTxt());
    }
    await file.writeAsString(buf.toString());
    return file.path;
  }
}
