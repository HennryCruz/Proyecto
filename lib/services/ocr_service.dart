import 'dart:io';
import 'dart:typed_data';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

// ── Resultado del OCR ─────────────────────────────────────────────

class OcrResultado {
  final List<String> codigosDetectados; // Ordenados por confianza
  final String? codigoPrincipal;        // El más probable
  final bool exito;
  final String mensaje;

  const OcrResultado({
    required this.codigosDetectados,
    this.codigoPrincipal,
    required this.exito,
    required this.mensaje,
  });

  static const OcrResultado sinResultado = OcrResultado(
    codigosDetectados: [],
    codigoPrincipal:   null,
    exito:             false,
    mensaje:           'No se detectó ningún código válido',
  );
}

// ── Servicio OCR ──────────────────────────────────────────────────

class OcrService {
  static final OcrService _i = OcrService._();
  factory OcrService() => _i;
  OcrService._();

  // Patrones de códigos válidos para CENAM
  // Código nuevo: I + 5 dígitos (I18045)
  //   — OCR frecuentemente lee la I como 1 o l → corrección automática
  // Código antiguo: 12 dígitos numéricos (510103039102)
  static final _patrones = [
    RegExp(r'\b[IiCcPp1l]\d{5}\b'),  // I18045 — incluye 1 y l como I
    RegExp(r'\b\d{12}\b'),            // 510103039102
    RegExp(r'\b\d{10,14}\b'),         // rangos numéricos largos
    RegExp(r'\b[A-Z0-9]{6,}\b'),      // alfanuméricos
  ];

  // Corrección específica para etiquetas nuevas CENAM:
  // El OCR lee "I" como "1" o "l" — normalizamos al formato correcto
  String _corregirCodigo(String codigo) {
    // Si empieza con 1 o l seguido de 5 dígitos → probablemente es I
    if (RegExp(r'^[1l]\d{5}$').hasMatch(codigo)) {
      return 'I${codigo.substring(1)}';
    }
    // Normalizar a mayúsculas
    return codigo.toUpperCase();
  }

  // ── Proceso principal ──────────────────────────────────────────

  Future<OcrResultado> procesarImagen(File imagenOriginal) async {
    try {
      // 1. Preprocesar imagen para mejorar OCR
      final imagenProcesada = await _preprocesar(imagenOriginal);

      // 2. Extraer texto con ML Kit
      final textos = await _extraerTexto(imagenProcesada);

      // 3. Filtrar y rankear códigos válidos
      final codigos = _filtrarCodigos(textos);

      if (codigos.isEmpty) {
        return OcrResultado.sinResultado;
      }

      return OcrResultado(
        codigosDetectados: codigos,
        codigoPrincipal:   codigos.first,
        exito:             true,
        mensaje:           '${codigos.length} código(s) detectado(s)',
      );
    } catch (e) {
      return OcrResultado(
        codigosDetectados: [],
        codigoPrincipal:   null,
        exito:             false,
        mensaje:           'Error al procesar: $e',
      );
    }
  }

  // ── Preprocesamiento de imagen ─────────────────────────────────
  // Escala de grises → contraste → binarización

  Future<File> _preprocesar(File original) async {
    try {
      final bytes   = await original.readAsBytes();
      img.Image? imagen = img.decodeImage(Uint8List.fromList(bytes));
      if (imagen == null) return original;

      // Redimensionar si es muy grande (mejora velocidad sin perder calidad)
      if (imagen.width > 1920 || imagen.height > 1920) {
        imagen = img.copyResize(imagen,
            width:  imagen.width > imagen.height ? 1920 : -1,
            height: imagen.height >= imagen.width ? 1920 : -1);
      }

      // Recortar zona de interés más amplia para cubrir ambos tipos:
      // — Etiqueta nueva: I18045 está en el centro-inferior
      // — Etiqueta vieja: número de 12 dígitos en el tercio inferior
      // Usamos el 40%-95% vertical para capturar ambos casos
      final roiTop    = (imagen.height * 0.35).toInt();
      final roiHeight = (imagen.height * 0.60).toInt();
      final roi = img.copyCrop(imagen,
          x: 0, y: roiTop,
          width: imagen.width, height: roiHeight);

      // Escala de grises
      final gris = img.grayscale(roi);

      // Aumentar contraste
      final contraste = img.adjustColor(gris, contrast: 1.8, brightness: 1.1);

      // Guardar imagen procesada en temporal
      final dir    = Directory.systemTemp;
      final tmpFile = File('${dir.path}/ocr_procesada.jpg');
      await tmpFile.writeAsBytes(img.encodeJpg(contraste, quality: 95));
      return tmpFile;
    } catch (_) {
      return original; // Si falla el preprocesamiento, usar original
    }
  }

  // ── Extracción de texto con ML Kit ─────────────────────────────

  Future<List<String>> _extraerTexto(File imagen) async {
    final inputImage = InputImage.fromFile(imagen);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      final resultado  = await recognizer.processImage(inputImage);
      final textos     = <String>[];

      for (final bloque in resultado.blocks) {
        for (final linea in bloque.lines) {
          final texto = linea.text.trim().replaceAll(' ', '');
          if (texto.isNotEmpty) textos.add(texto);
        }
      }

      return textos;
    } finally {
      await recognizer.close();
    }
  }

  // ── Filtrado y ranking de códigos ──────────────────────────────

  List<String> _filtrarCodigos(List<String> textos) {
    final encontrados = <String>{};

    for (final texto in textos) {
      final limpio = texto.trim().toUpperCase();

      for (final patron in _patrones) {
        final matches = patron.allMatches(limpio);
        for (final m in matches) {
          final raw    = m.group(0)!;
          final codigo = _corregirCodigo(raw);
          if (_esFecha(codigo)) continue;
          encontrados.add(codigo);
        }
      }
    }

    // Ordenar: códigos CENAM nuevos (I/C/P + 5 dígitos) primero
    // luego 12 dígitos, luego el resto
    final lista = encontrados.toList();
    lista.sort((a, b) {
      final esNuevoA = RegExp(r'^[ICP]\d{5}$').hasMatch(a);
      final esNuevoB = RegExp(r'^[ICP]\d{5}$').hasMatch(b);
      final es12A    = RegExp(r'^\d{12}$').hasMatch(a);
      final es12B    = RegExp(r'^\d{12}$').hasMatch(b);

      if (esNuevoA && !esNuevoB) return -1;
      if (!esNuevoA && esNuevoB) return 1;
      if (es12A    && !es12B)   return -1;
      if (!es12A   && es12B)    return 1;
      return b.length.compareTo(a.length);
    });

    return lista.take(5).toList();
  }

  bool _esFecha(String s) {
    // Detectar patrones de fecha: 8 dígitos tipo ddmmaaaa o aaaammdd
    if (!RegExp(r'^\d{8}$').hasMatch(s)) return false;
    final d1 = int.tryParse(s.substring(0, 2)) ?? 0;
    final d2 = int.tryParse(s.substring(2, 4)) ?? 0;
    // Si parece día/mes (1-31 y 1-12) probablemente es fecha
    return (d1 >= 1 && d1 <= 31 && d2 >= 1 && d2 <= 12);
  }
}
