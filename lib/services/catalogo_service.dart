import 'package:flutter/services.dart';

class CatalogoService {
  static final CatalogoService _instance = CatalogoService._internal();
  factory CatalogoService() => _instance;
  CatalogoService._internal();

  // Ambos mapas apuntan a la misma estructura: clave interna -> descripcion
  // _activos   : clave interna  (I00311)       -> descripcion
  // _barcode   : codigo antiguo (510105006293) -> clave interna (I00311)
  Map<String, String> _activos = {};
  Map<String, String> _barcode = {};
  Map<String, String> _localizaciones = {};
  List<String> _clavesLocalizacion = [];
  bool _loaded = false;

  Future<void> cargar() async {
    if (_loaded) return;

    // ── Localizaciones: CLAVE_DESCRIPCION ──────────────────────────
    final locStr = await rootBundle.loadString('assets/localizaciones.txt');
    for (final line in locStr.split('\n')) {
      final l = line.trim().replaceAll('\r', '');
      if (l.isEmpty) continue;
      final idx = l.indexOf('_');
      if (idx < 0) continue;
      final clave = l.substring(0, idx).trim().toUpperCase();
      final desc  = l.substring(idx + 1).trim();
      if (clave.isNotEmpty) _localizaciones[clave] = desc;
    }
    _clavesLocalizacion = _localizaciones.keys.toList()..sort();

    // ── Activos: CLAVE_DESCRIPCION_CODIGOBARRAS ────────────────────
    // Clave interna = primer campo  (I00311, C00001, P00001)
    // Descripcion   = entre primer y ultimo _
    // Codigo antiguo= ultimo campo  (510105006293)  — solo en claves I, 12 dígitos
    final actStr = await rootBundle.loadString('assets/activos.txt');
    for (final line in actStr.split('\n')) {
      final l = line.trim().replaceAll('\r', '');
      if (l.isEmpty) continue;

      final firstIdx = l.indexOf('_');
      if (firstIdx < 0) continue;
      final lastIdx = l.lastIndexOf('_');

      final clave = l.substring(0, firstIdx).trim().toUpperCase();
      final desc  = lastIdx > firstIdx
          ? l.substring(firstIdx + 1, lastIdx).trim()
          : l.substring(firstIdx + 1).trim();
      final sufijo = lastIdx > firstIdx
          ? l.substring(lastIdx + 1).trim()
          : '';

      if (clave.isEmpty || desc.isEmpty) continue;

      // Indexar por clave interna
      _activos[clave] = desc;

      // Indexar también por código de barras antiguo (12 dígitos, empieza con 5)
      if (sufijo.length == 12 && sufijo.startsWith('5')) {
        _barcode[sufijo] = clave;
      }
    }

    _loaded = true;
  }

  // ── Lookup principal ───────────────────────────────────────────────
  // Recibe CUALQUIER código (interno o barcode antiguo) y devuelve descripcion
  String descripcionActivo(String rawCodigo) {
    final codigo = rawCodigo.trim().toUpperCase();

    // 1. Buscar directo por clave interna (I00311, C00001...)
    final descDirecta = _activos[codigo];
    if (descDirecta != null && descDirecta.isNotEmpty) return descDirecta;

    // 2. Buscar por codigo de barras antiguo (510105006293...)
    final claveInterna = _barcode[codigo];  // barcode no tiene prefijo de mayusculas
    if (claveInterna != null) {
      return _activos[claveInterna] ?? '';
    }

    // 3. Buscar barcode en minusculas/mixto por si acaso
    final barcodeKey = rawCodigo.trim();
    final claveInterna2 = _barcode[barcodeKey];
    if (claveInterna2 != null) {
      return _activos[claveInterna2] ?? '';
    }

    return '';
  }

  // Devuelve la clave interna normalizada a partir de cualquier código
  String normalizarCveActivo(String rawCodigo) {
    final codigo = rawCodigo.trim().toUpperCase();

    // Si es barcode antiguo (12 dígitos), devolver la clave interna
    final claveInterna = _barcode[codigo] ?? _barcode[rawCodigo.trim()];
    if (claveInterna != null) return claveInterna;

    // Si tiene 5 dígitos numéricos, agregar prefijo I
    if (codigo.length == 5 && RegExp(r'^\d{5}$').hasMatch(codigo)) {
      return 'I$codigo';
    }

    return codigo;
  }

  String descripcionLocalizacion(String clave) {
    return _localizaciones[clave.toUpperCase()] ?? '';
  }

  List<String> get clavesLocalizacion => _clavesLocalizacion;

  List<String> buscarLocalizacion(String query) {
    if (query.isEmpty) return _clavesLocalizacion;
    final q = query.toUpperCase();
    return _clavesLocalizacion
        .where((k) =>
            k.contains(q) ||
            (_localizaciones[k] ?? '').toUpperCase().contains(q))
        .toList();
  }

  int get totalActivos       => _activos.length;
  int get totalBarcodes      => _barcode.length;
  int get totalLocalizaciones => _localizaciones.length;
}
