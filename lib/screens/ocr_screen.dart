import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/catalogo_service.dart';
import '../services/ocr_service.dart';

class OcrScreen extends StatefulWidget {
  final String localizacion;
  final Future<void> Function(String codigo) onCodigoConfirmado;

  const OcrScreen({
    super.key,
    required this.localizacion,
    required this.onCodigoConfirmado,
  });

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  final _ocr      = OcrService();
  final _catalogo = CatalogoService();
  final _picker   = ImagePicker();

  // Estados
  _Estado _estado = _Estado.inicial;
  File?   _imagen;
  OcrResultado? _resultado;
  String? _codigoSeleccionado;
  String  _descCodigo = '';

  // Para edición manual
  final _ctrlManual = TextEditingController();

  @override
  void dispose() {
    _ctrlManual.dispose();
    super.dispose();
  }

  // ── Tomar foto ──────────────────────────────────────────────────

  Future<void> _tomarFoto() async {
    setState(() => _estado = _Estado.inicial);

    final xfile = await _picker.pickImage(
      source:         ImageSource.camera,
      imageQuality:   90,
      preferredCameraDevice: CameraDevice.rear,
    );

    if (xfile == null) return;

    setState(() {
      _imagen  = File(xfile.path);
      _estado  = _Estado.procesando;
      _resultado = null;
      _codigoSeleccionado = null;
      _descCodigo = '';
    });

    await _procesarImagen();
  }

  // ── Procesar con OCR ────────────────────────────────────────────

  Future<void> _procesarImagen() async {
    if (_imagen == null) return;

    final resultado = await _ocr.procesarImagen(_imagen!);

    if (!mounted) return;

    if (!resultado.exito || resultado.codigosDetectados.isEmpty) {
      setState(() {
        _resultado = resultado;
        _estado    = _Estado.sinResultado;
      });
      return;
    }

    // Seleccionar automáticamente el primer candidato
    final principal = resultado.codigoPrincipal!;
    final desc      = _catalogo.descripcionActivo(principal);

    setState(() {
      _resultado          = resultado;
      _codigoSeleccionado = principal;
      _descCodigo         = desc;
      _estado             = _Estado.confirmacion;
    });
  }

  // ── Seleccionar candidato alternativo ───────────────────────────

  void _seleccionarCodigo(String codigo) {
    final desc = _catalogo.descripcionActivo(codigo);
    setState(() {
      _codigoSeleccionado = codigo;
      _descCodigo         = desc;
    });
  }

  // ── Confirmar y registrar ───────────────────────────────────────

  Future<void> _confirmar() async {
    if (_codigoSeleccionado == null) return;
    await widget.onCodigoConfirmado(_codigoSeleccionado!);
    if (mounted) Navigator.of(context).pop();
  }

  // ── Editar manualmente ──────────────────────────────────────────

  void _abrirEdicionManual() {
    _ctrlManual.text = _codigoSeleccionado ?? '';
    setState(() => _estado = _Estado.edicionManual);
  }

  void _confirmarManual() {
    final codigo = _ctrlManual.text.trim().toUpperCase();
    if (codigo.isEmpty) return;
    final desc = _catalogo.descripcionActivo(codigo);
    setState(() {
      _codigoSeleccionado = codigo;
      _descCodigo         = desc;
      _estado             = _Estado.confirmacion;
    });
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OCR — Leer etiqueta'),
        actions: [
          if (_estado != _Estado.procesando)
            IconButton(
              icon: const Icon(Icons.camera_alt),
              tooltip: 'Tomar nueva foto',
              onPressed: _tomarFoto,
            ),
        ],
      ),
      body: _buildCuerpo(),
    );
  }

  Widget _buildCuerpo() {
    switch (_estado) {
      case _Estado.inicial:
        return _buildInicial();
      case _Estado.procesando:
        return _buildProcesando();
      case _Estado.confirmacion:
        return _buildConfirmacion();
      case _Estado.sinResultado:
        return _buildSinResultado();
      case _Estado.edicionManual:
        return _buildEdicionManual();
    }
  }

  // ── Pantalla inicial ────────────────────────────────────────────

  Widget _buildInicial() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.document_scanner_outlined,
              size: 80, color: Colors.blue.shade300),
          const SizedBox(height: 20),
          const Text('Leer etiqueta con OCR',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            'Toma una foto de la etiqueta del activo.\n'
            'La app extraerá automáticamente el número de inventario.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(children: [
              _tip(Icons.light_mode_outlined,
                  'Busca buena iluminación — usa la linterna si es necesario'),
              _tip(Icons.center_focus_strong_outlined,
                  'Enfoca en el número impreso bajo el código de barras'),
              _tip(Icons.crop_outlined,
                  'Acerca el celular para que ocupe más espacio'),
            ]),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _tomarFoto,
              icon: const Icon(Icons.camera_alt, size: 24),
              label: const Text('Tomar foto',
                  style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _tip(IconData icon, String texto) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, size: 16, color: Colors.blue.shade700),
        const SizedBox(width: 8),
        Expanded(child: Text(texto,
            style: TextStyle(fontSize: 12, color: Colors.blue.shade800))),
      ]),
    );
  }

  // ── Procesando ─────────────────────────────────────────────────

  Widget _buildProcesando() {
    return Column(children: [
      if (_imagen != null)
        Expanded(
          child: Image.file(_imagen!,
              fit: BoxFit.contain,
              color: Colors.black.withOpacity(0.3),
              colorBlendMode: BlendMode.darken),
        ),
      Container(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          const Text('Analizando etiqueta...',
              style: TextStyle(fontSize: 16)),
          const SizedBox(height: 6),
          Text('Procesando imagen y extrayendo texto',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        ]),
      ),
    ]);
  }

  // ── Confirmación ────────────────────────────────────────────────

  Widget _buildConfirmacion() {
    final enBD      = _descCodigo.isNotEmpty;
    final candidatos = _resultado?.codigosDetectados ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Imagen capturada (miniatura)
        if (_imagen != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: double.infinity,
              height: 180,
              child: Image.file(_imagen!, fit: BoxFit.cover),
            ),
          ),
        const SizedBox(height: 16),

        // Código detectado principal
        Text('Código detectado',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: enBD ? Colors.green.shade50 : Colors.amber.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: enBD ? Colors.green.shade300 : Colors.amber.shade400,
              width: 1.5,
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(children: [
              Icon(
                enBD ? Icons.check_circle : Icons.warning_amber_outlined,
                color: enBD ? Colors.green.shade700 : Colors.amber.shade700,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _codigoSeleccionado ?? '',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: enBD
                      ? Colors.green.shade800
                      : Colors.amber.shade800,
                  letterSpacing: 1.5,
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              enBD ? _descCodigo : 'No encontrado en catálogo — se registrará como NC',
              style: TextStyle(
                fontSize: 13,
                color: enBD ? Colors.green.shade700 : Colors.amber.shade700,
              ),
            ),
          ]),
        ),

        // Candidatos alternativos
        if (candidatos.length > 1) ...[
          const SizedBox(height: 16),
          Text('Otros candidatos detectados',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          const SizedBox(height: 6),
          ...candidatos.skip(1).map((c) {
            final seleccionado = c == _codigoSeleccionado;
            final desc = _catalogo.descripcionActivo(c);
            return GestureDetector(
              onTap: () => _seleccionarCodigo(c),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: seleccionado
                      ? Colors.blue.shade50
                      : Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: seleccionado
                        ? Colors.blue.shade400
                        : Colors.transparent,
                  ),
                ),
                child: Row(children: [
                  Icon(
                    seleccionado
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: Colors.blue.shade600,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(c,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    if (desc.isNotEmpty)
                      Text(desc, style: const TextStyle(fontSize: 12)),
                  ])),
                ]),
              ),
            );
          }),
        ],

        const SizedBox(height: 20),

        // Botones de acción
        Row(children: [
          // Editar manualmente
          Expanded(child: OutlinedButton.icon(
            onPressed: _abrirEdicionManual,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Editar'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          )),
          const SizedBox(width: 12),
          // Confirmar
          Expanded(flex: 2, child: ElevatedButton.icon(
            onPressed: _confirmar,
            icon: const Icon(Icons.check, size: 20),
            label: Text(enBD ? 'Confirmar' : 'Confirmar (NC)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: enBD ? null : Colors.amber.shade600,
              foregroundColor: enBD ? null : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          )),
        ]),

        const SizedBox(height: 8),

        // Tomar otra foto
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: _tomarFoto,
            icon: const Icon(Icons.camera_alt_outlined, size: 16),
            label: const Text('Tomar otra foto'),
          ),
        ),
      ]),
    );
  }

  // ── Sin resultado ────────────────────────────────────────────────

  Widget _buildSinResultado() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        if (_imagen != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: double.infinity,
              height: 200,
              child: Image.file(_imagen!, fit: BoxFit.cover),
            ),
          ),
        const SizedBox(height: 20),
        const Icon(Icons.search_off, size: 56, color: Colors.red),
        const SizedBox(height: 12),
        const Text('No se detectó ningún código',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          _resultado?.mensaje ?? '',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _tomarFoto,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Intentar de nuevo'),
            style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _abrirEdicionManual,
            icon: const Icon(Icons.keyboard),
            label: const Text('Ingresar manualmente'),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ),
      ]),
    );
  }

  // ── Edición manual ───────────────────────────────────────────────

  Widget _buildEdicionManual() {
    final desc = _catalogo.descripcionActivo(
        _ctrlManual.text.trim().toUpperCase());

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        if (_imagen != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: double.infinity,
              height: 160,
              child: Image.file(_imagen!, fit: BoxFit.cover),
            ),
          ),
        const SizedBox(height: 20),
        TextField(
          controller: _ctrlManual,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(fontSize: 18, letterSpacing: 1.5),
          decoration: const InputDecoration(
            labelText: 'Código del activo',
            hintText: 'Ej: I18045 ó 510103039102',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _confirmarManual(),
        ),
        const SizedBox(height: 8),
        if (desc.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade300),
            ),
            child: Text(desc,
                style: TextStyle(color: Colors.green.shade800)),
          ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _ctrlManual.text.trim().isNotEmpty
                ? _confirmarManual
                : null,
            icon: const Icon(Icons.check),
            label: const Text('Confirmar'),
            style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _estado = _Estado.confirmacion),
          child: const Text('Volver'),
        ),
      ]),
    );
  }
}

enum _Estado {
  inicial,
  procesando,
  confirmacion,
  sinResultado,
  edicionManual,
}
