import 'package:flutter/services.dart';

import '../models/activo_teorico.dart';

class TeoricoService {
  static final TeoricoService _instance = TeoricoService._internal();
  factory TeoricoService() => _instance;
  TeoricoService._internal();

  List<ActivoTeorico> _todos = [];

  // Índices para búsqueda rápida
  Map<String, ActivoTeorico> _porCodigoNuevo   = {};
  Map<String, ActivoTeorico> _porCodigoAnterior = {};
  Map<String, List<ActivoTeorico>> _porLocalizacion = {};
  Map<String, List<ActivoTeorico>> _porNombre = {};

  bool _loaded = false;

  Future<void> cargar() async {
    if (_loaded) return;

    final raw = await rootBundle.loadString('assets/activos_teorico.csv');
    final lines = raw.split('\n');

    // Saltar header
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim().replaceAll('\r', '');
      if (line.isEmpty) continue;

      final cols = _parseCsvLine(line);
      if (cols.isEmpty || cols[0].isEmpty) continue;

      final activo = ActivoTeorico.fromCsv(cols);
      _todos.add(activo);

      _porCodigoNuevo[activo.codigoNuevo] = activo;

      if (activo.codigoAnterior.isNotEmpty) {
        _porCodigoAnterior[activo.codigoAnterior] = activo;
      }

      if (activo.localizacion.isNotEmpty) {
        _porLocalizacion
            .putIfAbsent(activo.localizacion, () => [])
            .add(activo);
      }

      final nombreKey = activo.nombre.toUpperCase();
      if (nombreKey.isNotEmpty) {
        _porNombre.putIfAbsent(nombreKey, () => []).add(activo);
      }
    }

    _loaded = true;
  }

  // ── Consultas ────────────────────────────────────────────────────

  /// Activos teóricos asignados a una localización
  List<ActivoTeorico> activosDe(String localizacion) {
    return _porLocalizacion[localizacion.toUpperCase()] ?? [];
  }

  /// Buscar activo por cualquier código (nuevo o anterior)
  ActivoTeorico? buscarPorCodigo(String codigo) {
    final c = codigo.trim().toUpperCase();
    return _porCodigoNuevo[c] ?? _porCodigoAnterior[c];
  }

  /// Empleados únicos ordenados por nombre
  List<String> get nombresEmpleados {
    final nombres = _todos
        .map((a) => a.nombre.trim())
        .where((n) => n.isNotEmpty && n != 'Almacen')
        .toSet()
        .toList();
    nombres.sort();
    return nombres;
  }

  /// Activos de un empleado por nombre
  List<ActivoTeorico> activosDeEmpleado(String nombre) {
    return _porNombre[nombre.toUpperCase()] ?? [];
  }

  /// Localizaciones únicas
  List<String> get localizaciones => _porLocalizacion.keys.toList()..sort();

  int get total => _todos.length;

  // ── CSV parser simple ────────────────────────────────────────────
  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    final buf = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (ch == ',' && !inQuotes) {
        result.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    result.add(buf.toString());
    return result;
  }
}
