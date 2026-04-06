import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

class RegistroInventario {
  final String localizacion;
  final String cveActivo;
  final DateTime fecha;

  RegistroInventario({
    required this.localizacion,
    required this.cveActivo,
    required this.fecha,
  });

  String toLine() {
    final fechaStr = DateFormat('dd/MM/yyyy').format(fecha);
    return '${localizacion}_${cveActivo}_$fechaStr';
  }

  static RegistroInventario? fromLine(String line) {
    final parts = line.trim().split('_');
    if (parts.length < 3) return null;
    try {
      final fecha = DateFormat('dd/MM/yyyy').parse(parts[2]);
      return RegistroInventario(
        localizacion: parts[0],
        cveActivo: parts[1],
        fecha: fecha,
      );
    } catch (_) {
      return null;
    }
  }
}

class InventarioService {
  static final InventarioService _instance = InventarioService._internal();
  factory InventarioService() => _instance;
  InventarioService._internal();

  static const String _fileName = 'ALM_Inventarios.txt';

  Future<File> get _archivo async {
    final dir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/ALM_Inventario');
    if (!await folder.exists()) await folder.create(recursive: true);
    return File('${folder.path}/$_fileName');
  }

  Future<String> get rutaArchivo async {
    final f = await _archivo;
    return f.path;
  }

  Future<List<RegistroInventario>> cargarRegistros() async {
    try {
      final file = await _archivo;
      if (!await file.exists()) return [];
      final lines = await file.readAsLines();
      return lines
          .map((l) => RegistroInventario.fromLine(l))
          .whereType<RegistroInventario>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> agregarRegistro(RegistroInventario r) async {
    final file = await _archivo;
    await file.writeAsString('${r.toLine()}\n', mode: FileMode.append);
  }

  Future<void> borrarArchivo() async {
    final file = await _archivo;
    if (await file.exists()) {
      await file.delete();
    }
  }
}
