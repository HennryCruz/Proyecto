import 'package:flutter/services.dart';

class MapaEdificio {
  final String letra;
  final String nombre;
  final List<String> assets;

  const MapaEdificio({
    required this.letra,
    required this.nombre,
    required this.assets,
  });
}

class MapaService {
  static final MapaService _i = MapaService._();
  factory MapaService() => _i;
  MapaService._();

  static const _catalogo = <String, MapaEdificio>{
    'A': MapaEdificio(
      letra:  'A',
      nombre: 'Edificio A',
      assets: ['assets/mapas/ED_A.pdf'],
    ),
    'B': MapaEdificio(
      letra:  'B',
      nombre: 'Edificio B',
      assets: ['assets/mapas/ED_B.pdf'],
    ),
    'C': MapaEdificio(
      letra:  'C',
      nombre: 'Edificio C',
      assets: ['assets/mapas/ED_C.pdf'],
    ),
    'D': MapaEdificio(
      letra:  'D',
      nombre: 'Edificio D',
      assets: ['assets/mapas/ED_D.pdf'],
    ),
    'E': MapaEdificio(
      letra:  'E',
      nombre: 'Edificio E',
      assets: ['assets/mapas/ED_E.pdf'],
    ),
    'F': MapaEdificio(
      letra:  'F',
      nombre: 'Edificio F',
      assets: ['assets/mapas/ED_F.pdf'],
    ),
    'G': MapaEdificio(
      letra:  'G',
      nombre: 'Edificio G',
      assets: ['assets/mapas/ED_G.pdf'],
    ),
    'H': MapaEdificio(
      letra:  'H',
      nombre: 'Edificio H',
      assets: [
        'assets/mapas/ED_H_PLANTA_BAJA.pdf',
        'assets/mapas/ED_H_PLANTA_ALTA.pdf',
      ],
    ),
    'I': MapaEdificio(
      letra:  'I',
      nombre: 'Edificio I',
      assets: ['assets/mapas/ED_I.pdf'],
    ),
    'L': MapaEdificio(
      letra:  'L',
      nombre: 'Edificio L',
      assets: [
        'assets/mapas/ED_L.pdf',
        'assets/mapas/ED_L_SOTANO.pdf',
      ],
    ),
    'M': MapaEdificio(
      letra:  'M',
      nombre: 'Edificio M',
      assets: [
        'assets/mapas/ED_M.pdf',
        'assets/mapas/ED_M_PLANTA_BAJA_Y_ASOTEA.pdf',
      ],
    ),
    'O': MapaEdificio(
      letra:  'O',
      nombre: 'Edificio O',
      assets: ['assets/mapas/ED_O.pdf'],
    ),
    'P': MapaEdificio(
      letra:  'P',
      nombre: 'Edificio P',
      assets: ['assets/mapas/ED_P.pdf'],
    ),
    'Q': MapaEdificio(
      letra:  'Q',
      nombre: 'Edificio Q',
      assets: [
        'assets/mapas/ED_Q.pdf',
        'assets/mapas/ED_Q_SOTANO.pdf',
      ],
    ),
    'T': MapaEdificio(
      letra:  'T',
      nombre: 'Edificio T',
      assets: [
        'assets/mapas/ED_T_PLANTA_BAJA.pdf',
        'assets/mapas/ED_T_PLANTA_ALTA.pdf',
        'assets/mapas/ED_T_SOTANO.pdf',
      ],
    ),
    'U': MapaEdificio(
      letra:  'U',
      nombre: 'Edificio U',
      assets: ['assets/mapas/ED_U.pdf'],
    ),
  };

  List<MapaEdificio> get todos =>
      _catalogo.values.toList()
        ..sort((a, b) => a.letra.compareTo(b.letra));

  MapaEdificio? mapaDeLocalizacion(String? cveLocalizacion) {
    if (cveLocalizacion == null || cveLocalizacion.isEmpty) return null;
    final letra = cveLocalizacion[0].toUpperCase();
    return _catalogo[letra];
  }

  Future<bool> existeAsset(String assetPath) async {
    try {
      await rootBundle.load(assetPath);
      return true;
    } catch (_) {
      return false;
    }
  }
}
