import 'package:flutter/services.dart';

class CatalogoService {
  static final CatalogoService _instance = CatalogoService._internal();
  factory CatalogoService() => _instance;
  CatalogoService._internal();

  // Clave -> Descripcion
  Map<String, String> _localizaciones = {};
  Map<String, String> _activos = {};
  List<String> _clavesLocalizacion = [];
  bool _loaded = false;

  Future<void> cargar() async {
    if (_loaded) return;

    // Cargar localizaciones: formato  CLAVE_DESCRIPCION
    final locStr = await rootBundle.loadString('assets/localizaciones.txt');
    for (final line in locStr.split('\n')) {
      final l = line.trim().replaceAll('\r', '');
      if (l.isEmpty) continue;
      final idx = l.indexOf('_');
      if (idx < 0) continue;
      final clave = l.substring(0, idx).trim();
      final desc = l.substring(idx + 1).trim();
      if (clave.isNotEmpty) {
        _localizaciones[clave.toUpperCase()] = desc;
      }
    }
    _clavesLocalizacion = _localizaciones.keys.toList()..sort();

    // Cargar activos: formato  CLAVE_DESCRIPCION_CLAVE
    final actStr = await rootBundle.loadString('assets/activos.txt');
    for (final line in actStr.split('\n')) {
      final l = line.trim().replaceAll('\r', '');
      if (l.isEmpty) continue;
      final parts = l.split('_');
      if (parts.length < 2) continue;
      final clave = parts[0].trim().toUpperCase();
      final desc = parts.length >= 3
          ? parts.sublist(1, parts.length - 1).join('_').trim()
          : parts[1].trim();
      if (clave.isNotEmpty && desc.isNotEmpty) {
        _activos[clave] = desc;
      }
    }

    _loaded = true;
  }

  String descripcionLocalizacion(String clave) {
    return _localizaciones[clave.toUpperCase()] ?? '';
  }

  String descripcionActivo(String clave) {
    final c = clave.toUpperCase();
    return _activos[c] ?? '';
  }

  List<String> get clavesLocalizacion => _clavesLocalizacion;

  // Filtra localizaciones para autocomplete
  List<String> buscarLocalizacion(String query) {
    if (query.isEmpty) return _clavesLocalizacion;
    final q = query.toUpperCase();
    return _clavesLocalizacion
        .where((k) =>
            k.contains(q) ||
            (_localizaciones[k] ?? '').toUpperCase().contains(q))
        .toList();
  }

  // Normaliza clave de activo: si tiene 5 dígitos y es numérico, agrega prefijo "I"
  String normalizarCveActivo(String raw) {
    final trimmed = raw.trim().toUpperCase();
    if (trimmed.length == 5 && RegExp(r'^\d{5}$').hasMatch(trimmed)) {
      return 'I$trimmed';
    }
    return trimmed;
  }
}
