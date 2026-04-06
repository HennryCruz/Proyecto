import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';

import '../services/catalogo_service.dart';
import '../services/inventario_service.dart';
import '../widgets/manual_entry_dialog.dart';

class InventarioScreen extends StatefulWidget {
  const InventarioScreen({super.key});

  @override
  State<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends State<InventarioScreen> {
  final _catalogo = CatalogoService();
  final _inventario = InventarioService();

  bool _cargando = true;
  List<RegistroInventario> _registros = [];

  // Localización seleccionada
  String? _cveLocalizacion;
  String _descLocalizacion = '';

  // Controlador de autocomplete
  final _locCtrl = TextEditingController();
  List<String> _sugerencias = [];
  bool _mostrarSugerencias = false;

  // Scanner
  MobileScannerController? _scannerCtrl;
  bool _escaneando = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _catalogo.cargar();
    final regs = await _inventario.cargarRegistros();
    if (mounted) {
      setState(() {
        _registros = regs;
        _cargando = false;
      });
    }
  }

  @override
  void dispose() {
    _scannerCtrl?.dispose();
    _locCtrl.dispose();
    super.dispose();
  }

  // ── Localización ────────────────────────────────────────────────

  void _onLocTextChanged(String val) {
    final sugs = _catalogo.buscarLocalizacion(val);
    setState(() {
      _sugerencias = sugs.take(80).toList();
      _mostrarSugerencias = true;
    });
    // Si la clave exacta existe, actualizar descripción
    final desc = _catalogo.descripcionLocalizacion(val.toUpperCase());
    if (desc.isNotEmpty) {
      setState(() {
        _cveLocalizacion = val.toUpperCase();
        _descLocalizacion = desc;
      });
    } else {
      setState(() {
        _cveLocalizacion = null;
        _descLocalizacion = '';
      });
    }
  }

  void _seleccionarLocalizacion(String clave) {
    setState(() {
      _cveLocalizacion = clave;
      _descLocalizacion = _catalogo.descripcionLocalizacion(clave);
      _locCtrl.text = clave;
      _mostrarSugerencias = false;
    });
    FocusScope.of(context).unfocus();
  }

  // ── Insertar activo ──────────────────────────────────────────────

  Future<void> _insertarActivo(String cveActivo) async {
    if (_cveLocalizacion == null || _cveLocalizacion!.isEmpty) {
      _mostrarError('Selecciona una localización primero');
      return;
    }

    final cve = _catalogo.normalizarCveActivo(cveActivo);
    final desc = _catalogo.descripcionActivo(cve);
    if (desc.isEmpty) {
      _mostrarError('Activo no encontrado: $cve');
      return;
    }

    final reg = RegistroInventario(
      localizacion: _cveLocalizacion!,
      cveActivo: cve,
      fecha: DateTime.now(),
    );
    await _inventario.agregarRegistro(reg);
    setState(() => _registros.add(reg));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ $cve  $desc'),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ── Escáner ──────────────────────────────────────────────────────

  void _abrirEscaner() {
    if (_cveLocalizacion == null) {
      _mostrarError('Selecciona una localización primero');
      return;
    }
    setState(() {
      _escaneando = true;
      _scannerCtrl = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
    });
  }

  void _cerrarEscaner() {
    _scannerCtrl?.dispose();
    _scannerCtrl = null;
    setState(() => _escaneando = false);
  }

  void _onDetected(BarcodeCapture capture) {
    final codigo = capture.barcodes.firstOrNull?.rawValue;
    if (codigo != null && codigo.isNotEmpty) {
      _insertarActivo(codigo);
    }
  }

  // ── Registro manual ──────────────────────────────────────────────

  Future<void> _registrarManual() async {
    if (_cveLocalizacion == null) {
      _mostrarError('Selecciona una localización primero');
      return;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (_) =>
          ManualEntryDialog(cveLocalizacion: _cveLocalizacion!),
    );
    if (result != null && result.isNotEmpty) {
      await _insertarActivo(result);
    }
  }

  // ── Borrar archivo ───────────────────────────────────────────────

  Future<void> _borrarArchivo() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar'),
        content: const Text('¿Borrar todo el archivo de inventario?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _inventario.borrarArchivo();
      setState(() => _registros.clear());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Archivo de inventario borrado')),
        );
      }
    }
  }

  // ── Compartir archivo ────────────────────────────────────────────

  Future<void> _compartirArchivo() async {
    final ruta = await _inventario.rutaArchivo;
    await Share.shareXFiles(
      [XFile(ruta)],
      subject: 'ALM_Inventarios.txt',
    );
  }

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario CENAM'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Compartir archivo',
            onPressed: _registros.isEmpty ? null : _compartirArchivo,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Borrar archivo',
            onPressed: _registros.isEmpty ? null : _borrarArchivo,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _escaneando
              ? _buildEscaner()
              : _buildPrincipal(),
    );
  }

  Widget _buildPrincipal() {
    return Column(
      children: [
        // Panel superior: localización + fecha
        _buildPanelLocalizacion(),
        // Lista de registros
        Expanded(child: _buildLista()),
        // Botones inferiores
        _buildBotones(),
      ],
    );
  }

  Widget _buildPanelLocalizacion() {
    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Loc.  ',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              Expanded(
                child: TextField(
                  controller: _locCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Clave o nombre...',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                  onChanged: _onLocTextChanged,
                  onTap: () {
                    setState(() {
                      _sugerencias =
                          _catalogo.buscarLocalizacion(_locCtrl.text);
                      _mostrarSugerencias = true;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Text(
                DateFormat('dd/MM/yyyy').format(DateTime.now()),
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
          ),
          if (_descLocalizacion.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 36),
              child: Text(
                _descLocalizacion,
                style: TextStyle(
                    color: Colors.blue.shade800,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
              ),
            ),
          if (_mostrarSugerencias && _sugerencias.isNotEmpty)
            _buildDropdownSugerencias(),
        ],
      ),
    );
  }

  Widget _buildDropdownSugerencias() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _sugerencias.length,
        itemBuilder: (_, i) {
          final clave = _sugerencias[i];
          final desc = _catalogo.descripcionLocalizacion(clave);
          return InkWell(
            onTap: () => _seleccionarLocalizacion(clave),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(color: Colors.black87, fontSize: 13),
                  children: [
                    TextSpan(
                        text: clave,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1B4F8A))),
                    TextSpan(text: '  $desc'),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLista() {
    if (_registros.isEmpty) {
      return const Center(
        child: Text('Sin registros aún.\nEscanea o captura un activo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _registros.length,
      itemBuilder: (_, i) {
        final r = _registros[_registros.length - 1 - i];
        final desc = _catalogo.descripcionActivo(r.cveActivo);
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFF1B4F8A),
            child: Text(
              '${_registros.length - i}',
              style:
                  const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
          title: Text(r.cveActivo,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: Text(desc.isNotEmpty ? desc : r.localizacion,
              style: const TextStyle(fontSize: 12)),
          trailing: Text(
            r.localizacion,
            style: TextStyle(
                color: Colors.blue.shade700,
                fontSize: 11,
                fontWeight: FontWeight.w500),
          ),
        );
      },
    );
  }

  Widget _buildBotones() {
    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Column(
        children: [
          Text(
            'Registros: ${_registros.length}',
            style: TextStyle(
                color: Colors.blue.shade800, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _abrirEscaner,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Escanear'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _registrarManual,
                  icon: const Icon(Icons.edit),
                  label: const Text('Captura manual'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEscaner() {
    return Stack(
      children: [
        MobileScanner(
          controller: _scannerCtrl!,
          onDetect: _onDetected,
        ),
        // Overlay con información
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            color: Colors.black.withOpacity(0.6),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Loc: $_cveLocalizacion',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
                Text(
                  _descLocalizacion,
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  'Registros: ${_registros.length}',
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        // Botón cerrar
        Positioned(
          bottom: 32,
          left: 0,
          right: 0,
          child: Center(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 14),
              ),
              onPressed: _cerrarEscaner,
              icon: const Icon(Icons.stop),
              label: const Text('Detener escáner'),
            ),
          ),
        ),
      ],
    );
  }
}
