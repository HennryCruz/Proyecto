import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';

import '../services/catalogo_service.dart';
import '../services/inventario_service.dart';
import '../services/teorico_service.dart';
import '../widgets/manual_entry_dialog.dart';
import 'verificacion_screen.dart';

class InventarioScreen extends StatefulWidget {
  const InventarioScreen({super.key});
  @override
  State<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends State<InventarioScreen> {
  final _catalogo  = CatalogoService();
  final _inventario = InventarioService();
  final _teorico   = TeoricoService();

  bool _cargando = true;
  List<RegistroInventario> _registros = [];
  final Set<String> _escaneadosEnSesion = {};

  String? _cveLocalizacion;
  String  _descLocalizacion = '';
  final _locCtrl = TextEditingController();
  List<String> _sugerencias       = [];
  bool         _mostrarSugerencias = false;

  MobileScannerController? _scannerCtrl;
  bool _escaneando = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Future.wait([_catalogo.cargar(), _teorico.cargar()]);
    final regs = await _inventario.cargarRegistros();
    if (mounted) {
      setState(() {
        _registros = regs;
        for (final r in regs) {
          _escaneadosEnSesion.add(r.cveActivo.toUpperCase());
        }
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

  // ── Localización ─────────────────────────────────────────────────

  void _onLocTextChanged(String val) {
    setState(() {
      _sugerencias        = _catalogo.buscarLocalizacion(val).take(80).toList();
      _mostrarSugerencias = true;
    });
    final desc = _catalogo.descripcionLocalizacion(val.toUpperCase());
    setState(() {
      if (desc.isNotEmpty) {
        _cveLocalizacion  = val.toUpperCase();
        _descLocalizacion = desc;
      } else {
        _cveLocalizacion  = null;
        _descLocalizacion = '';
      }
    });
  }

  void _seleccionarLocalizacion(String clave) {
    setState(() {
      _cveLocalizacion    = clave;
      _descLocalizacion   = _catalogo.descripcionLocalizacion(clave);
      _locCtrl.text       = clave;
      _mostrarSugerencias = false;
    });
    FocusScope.of(context).unfocus();
  }

  // ── Insertar activo ───────────────────────────────────────────────

  Future<void> _insertarActivo(String codigoEscaneado) async {
    if (_cveLocalizacion == null) {
      _mostrarError('Selecciona una localización primero');
      return;
    }
    final cve  = _catalogo.normalizarCveActivo(codigoEscaneado);
    final desc = _catalogo.descripcionActivo(codigoEscaneado);
    if (desc.isEmpty) {
      _mostrarError('Activo no encontrado: $cve');
      return;
    }
    if (_escaneadosEnSesion.contains(cve.toUpperCase())) {
      final regPrevio = _registros.lastWhere(
        (r) => r.cveActivo.toUpperCase() == cve.toUpperCase(),
        orElse: () => RegistroInventario(
            localizacion: '?', cveActivo: cve, fecha: DateTime.now()),
      );
      final continuar = await _mostrarAlertaDuplicado(
        cve: cve, desc: desc,
        localizacionPrevia: regPrevio.localizacion,
        fechaPrevia: regPrevio.fecha,
      );
      if (!continuar) return;
    }
    final reg = RegistroInventario(
        localizacion: _cveLocalizacion!, cveActivo: cve, fecha: DateTime.now());
    await _inventario.agregarRegistro(reg);
    setState(() {
      _registros.add(reg);
      _escaneadosEnSesion.add(cve.toUpperCase());
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✓ $cve  $desc'),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<bool> _mostrarAlertaDuplicado({
    required String cve, required String desc,
    required String localizacionPrevia, required DateTime fechaPrevia,
  }) async {
    final fechaStr = DateFormat('dd/MM/yyyy HH:mm').format(fechaPrevia);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 48),
        title: const Text('¡Activo duplicado!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.orange)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cve, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 4),
              Text(desc, style: const TextStyle(fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 12),
          Text('Ya fue registrado en:', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const SizedBox(height: 4),
          Text(localizacionPrevia,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B4F8A))),
          Text(fechaStr, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 12),
          const Text('¿Deseas registrarlo de nuevo?',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w500)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Registrar de nuevo'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── Verificar ubicación ───────────────────────────────────────────

  void _verificarUbicacion() {
    if (_cveLocalizacion == null) {
      _mostrarError('Selecciona una localización primero');
      return;
    }
    final teoricos = _teorico.activosDe(_cveLocalizacion!);
    if (teoricos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No hay activos teóricos para $_cveLocalizacion'),
        backgroundColor: Colors.orange.shade700,
      ));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VerificacionScreen(
          localizacion: _cveLocalizacion!,
          registros: _registros,
        ),
      ),
    );
  }

  // ── Escáner ───────────────────────────────────────────────────────

  void _abrirEscaner() {
    if (_cveLocalizacion == null) {
      _mostrarError('Selecciona una localización primero');
      return;
    }
    setState(() {
      _escaneando  = true;
      _scannerCtrl = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
    });
  }

  void _cerrarEscaner() {
    _scannerCtrl?.dispose();
    _scannerCtrl = null;
    setState(() => _escaneando = false);
  }

  void _onDetected(BarcodeCapture capture) {
    final codigo = capture.barcodes.firstOrNull?.rawValue;
    if (codigo != null && codigo.isNotEmpty) _insertarActivo(codigo);
  }

  // ── Registro manual ───────────────────────────────────────────────

  Future<void> _registrarManual() async {
    if (_cveLocalizacion == null) {
      _mostrarError('Selecciona una localización primero');
      return;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (_) => ManualEntryDialog(cveLocalizacion: _cveLocalizacion!),
    );
    if (result != null && result.isNotEmpty) await _insertarActivo(result);
  }

  // ── Borrar / Compartir ────────────────────────────────────────────

  Future<void> _borrarArchivo() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar'),
        content: const Text('¿Borrar todo el archivo de inventario?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
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
      setState(() { _registros.clear(); _escaneadosEnSesion.clear(); });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Archivo de inventario borrado')));
      }
    }
  }

  Future<void> _compartirArchivo() async {
    final ruta = await _inventario.rutaArchivo;
    await Share.shareXFiles([XFile(ruta)], subject: 'ALM_Inventarios.txt');
  }

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700));
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario CENAM'),
        actions: [
          IconButton(icon: const Icon(Icons.share), tooltip: 'Compartir',
              onPressed: _registros.isEmpty ? null : _compartirArchivo),
          IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Borrar',
              onPressed: _registros.isEmpty ? null : _borrarArchivo),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _escaneando ? _buildEscaner() : _buildPrincipal(),
    );
  }

  Widget _buildPrincipal() {
    return Column(children: [
      _buildPanelLocalizacion(),
      Expanded(child: _buildLista()),
      _buildBotones(),
    ]);
  }

  Widget _buildPanelLocalizacion() {
    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Loc.  ', style: TextStyle(fontWeight: FontWeight.w600)),
          Expanded(
            child: TextField(
              controller: _locCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                isDense: true, hintText: 'Clave o nombre...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              onChanged: _onLocTextChanged,
              onTap: () => setState(() {
                _sugerencias = _catalogo.buscarLocalizacion(_locCtrl.text);
                _mostrarSugerencias = true;
              }),
            ),
          ),
          const SizedBox(width: 12),
          Text(DateFormat('dd/MM/yyyy').format(DateTime.now()),
              style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ]),
        if (_descLocalizacion.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 36),
            child: Text(_descLocalizacion,
                style: TextStyle(color: Colors.blue.shade800,
                    fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        if (_mostrarSugerencias && _sugerencias.isNotEmpty)
          _buildDropdownSugerencias(),
      ]),
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
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.08), blurRadius: 6,
            offset: const Offset(0, 2))],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _sugerencias.length,
        itemBuilder: (_, i) {
          final clave = _sugerencias[i];
          final desc  = _catalogo.descripcionLocalizacion(clave);
          return InkWell(
            onTap: () => _seleccionarLocalizacion(clave),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: RichText(text: TextSpan(
                style: const TextStyle(color: Colors.black87, fontSize: 13),
                children: [
                  TextSpan(text: clave,
                      style: const TextStyle(fontWeight: FontWeight.bold,
                          color: Color(0xFF1B4F8A))),
                  TextSpan(text: '  $desc'),
                ],
              )),
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
              style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _registros.length,
      itemBuilder: (_, i) {
        final r    = _registros[_registros.length - 1 - i];
        final desc = _catalogo.descripcionActivo(r.cveActivo);
        final veces = _registros
            .where((x) => x.cveActivo.toUpperCase() == r.cveActivo.toUpperCase())
            .length;
        final esDup = veces > 1;
        return ListTile(
          dense: true,
          tileColor: esDup ? Colors.orange.shade50 : null,
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: esDup ? Colors.orange : const Color(0xFF1B4F8A),
            child: Text('${_registros.length - i}',
                style: const TextStyle(color: Colors.white, fontSize: 11)),
          ),
          title: Row(children: [
            Text(r.cveActivo,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            if (esDup) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.orange, borderRadius: BorderRadius.circular(10)),
                child: Text('×$veces',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ]),
          subtitle: Text(desc.isNotEmpty ? desc : r.localizacion,
              style: const TextStyle(fontSize: 12)),
          trailing: Text(r.localizacion,
              style: TextStyle(color: Colors.blue.shade700,
                  fontSize: 11, fontWeight: FontWeight.w500)),
        );
      },
    );
  }

  Widget _buildBotones() {
    // Calcular progreso si hay teórico para la localización actual
    int? total;
    int? escaneadosEnLoc;
    if (_cveLocalizacion != null) {
      final teo = _teorico.activosDe(_cveLocalizacion!);
      if (teo.isNotEmpty) {
        total = teo.length;
        final escSet = _registros
            .where((r) => r.localizacion.toUpperCase() == _cveLocalizacion)
            .map((r) => r.cveActivo.toUpperCase())
            .toSet();
        escaneadosEnLoc = teo
            .where((a) =>
                escSet.contains(a.codigoNuevo) ||
                escSet.contains(a.codigoAnterior))
            .length;
      }
    }

    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Registros: ${_registros.length}',
              style: TextStyle(color: Colors.blue.shade800,
                  fontWeight: FontWeight.bold)),
          if (total != null)
            Text('$escaneadosEnLoc / $total en ubicación',
                style: TextStyle(
                    color: escaneadosEnLoc == total
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _abrirEscaner,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Escanear'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _registrarManual,
              icon: const Icon(Icons.edit),
              label: const Text('Manual'),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _verificarUbicacion,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Verificar'),
          ),
        ]),
      ]),
    );
  }

  Widget _buildEscaner() {
    return Stack(children: [
      MobileScanner(controller: _scannerCtrl!, onDetect: _onDetected),
      Positioned(
        top: 0, left: 0, right: 0,
        child: Container(
          color: Colors.black.withOpacity(0.6),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Loc: $_cveLocalizacion',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            Text(_descLocalizacion,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text('Registros: ${_registros.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
      ),
      Positioned(
        bottom: 32, left: 0, right: 0,
        child: Center(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14)),
            onPressed: _cerrarEscaner,
            icon: const Icon(Icons.stop),
            label: const Text('Detener escáner'),
          ),
        ),
      ),
    ]);
  }
}
