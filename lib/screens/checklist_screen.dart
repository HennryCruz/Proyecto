import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/activo_teorico.dart';
import '../services/inventario_service.dart';
import '../services/teorico_service.dart';

class ChecklistScreen extends StatefulWidget {
  final List<RegistroInventario> registros;
  final Future<void> Function(String codigo, String localizacion) onActivoEscaneado;

  const ChecklistScreen({
    super.key,
    required this.registros,
    required this.onActivoEscaneado,
  });

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  final _teorico = TeoricoService();

  // Paso 1: selección de empleado
  String? _empleadoSeleccionado;
  String  _busquedaEmpleado = '';
  final _empCtrl = TextEditingController();

  // Paso 2: checklist activo
  List<ActivoTeorico> _activosEmpleado = [];
  Set<String>         _marcados        = {}; // códigos internos ya escaneados

  // Escáner individual
  MobileScannerController? _scannerCtrl;
  ActivoTeorico? _activoEnEscaneo;

  @override
  void initState() {
    super.initState();
    _reconstruirMarcados();
  }

  void _reconstruirMarcados() {
    _marcados = widget.registros
        .map((r) => r.cveActivo.toUpperCase())
        .toSet();
  }

  @override
  void dispose() {
    _scannerCtrl?.dispose();
    _empCtrl.dispose();
    super.dispose();
  }

  // ── Empleado seleccionado ─────────────────────────────────────────

  void _seleccionarEmpleado(String nombre) {
    final activos = _teorico.activosDeEmpleado(nombre);
    setState(() {
      _empleadoSeleccionado = nombre;
      _activosEmpleado      = activos;
      _reconstruirMarcados();
    });
  }

  void _limpiarEmpleado() {
    setState(() {
      _empleadoSeleccionado = null;
      _activosEmpleado      = [];
      _empCtrl.clear();
      _busquedaEmpleado     = '';
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────

  bool _estaMarcado(ActivoTeorico a) =>
      _marcados.contains(a.codigoNuevo.toUpperCase()) ||
      (a.codigoAnterior.isNotEmpty &&
          _marcados.contains(a.codigoAnterior));

  String _codigoPrincipal(ActivoTeorico a) =>
      a.codigoAnterior.isNotEmpty ? a.codigoAnterior : a.codigoNuevo;

  String _codigoSecundario(ActivoTeorico a) =>
      a.codigoAnterior.isNotEmpty ? a.codigoNuevo : '';

  // ── Escanear activo individual ────────────────────────────────────

  void _escanearActivo(ActivoTeorico activo) {
    setState(() {
      _activoEnEscaneo = activo;
      _scannerCtrl = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        formats: const [
          BarcodeFormat.code128,
          BarcodeFormat.code39,
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.itf,
          BarcodeFormat.codabar,
          BarcodeFormat.dataMatrix,
          BarcodeFormat.qrCode,
        ],
        autoStart: true,
      );
    });
  }

  void _cerrarEscaner() {
    _scannerCtrl?.dispose();
    _scannerCtrl = null;
    setState(() => _activoEnEscaneo = null);
  }

  Future<void> _onDetectado(BarcodeCapture capture) async {
    final codigo = capture.barcodes.firstOrNull?.rawValue;
    if (codigo == null || codigo.isEmpty) return;

    final activo = _activoEnEscaneo!;

    // Verificar que corresponde al activo esperado
    final activoEscaneado = _teorico.buscarPorCodigo(codigo);
    final corresponde = activoEscaneado != null &&
        activoEscaneado.codigoNuevo == activo.codigoNuevo;

    if (!corresponde) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('⚠ Código no corresponde a ${_codigoPrincipal(activo)}'),
          backgroundColor: Colors.orange.shade700,
          duration: const Duration(seconds: 2),
        ));
      }
      return;
    }

    _cerrarEscaner();

    // Registrar usando la localización del activo en el teórico
    await widget.onActivoEscaneado(codigo, activo.localizacion);

    setState(() {
      _marcados.add(activo.codigoNuevo.toUpperCase());
      if (activo.codigoAnterior.isNotEmpty) {
        _marcados.add(activo.codigoAnterior);
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✓ ${_codigoPrincipal(activo)} registrado'),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_activoEnEscaneo != null) return _buildEscanerIndividual();
    if (_empleadoSeleccionado == null) return _buildSeleccionEmpleado();
    return _buildChecklist();
  }

  // ── Pantalla 1: Selección de empleado ────────────────────────────

  Widget _buildSeleccionEmpleado() {
    final todos    = _teorico.nombresEmpleados;
    final filtrados = _busquedaEmpleado.isEmpty
        ? todos
        : todos.where((n) =>
            n.toUpperCase().contains(_busquedaEmpleado.toUpperCase())).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Checklist por empleado')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _empCtrl,
            decoration: const InputDecoration(
              hintText: 'Buscar empleado por nombre...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _busquedaEmpleado = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${filtrados.length} empleados',
                  style: const TextStyle(color: Colors.black54, fontSize: 13)),
              Text('${_teorico.total} activos totales',
                  style: const TextStyle(color: Colors.black54, fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: ListView.builder(
            itemCount: filtrados.length,
            itemBuilder: (_, i) {
              final nombre  = filtrados[i];
              final activos = _teorico.activosDeEmpleado(nombre);
              final marcados = activos.where((a) => _estaMarcado(a)).length;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: marcados == activos.length
                      ? Colors.green.shade600
                      : const Color(0xFF1B4F8A),
                  child: Text(
                    nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(nombre,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                subtitle: Text('${activos.length} activos asignados',
                    style: const TextStyle(fontSize: 12)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  // Mini barra de progreso
                  if (activos.isNotEmpty) ...[
                    Text('$marcados/${activos.length}',
                        style: TextStyle(
                            color: marcados == activos.length
                                ? Colors.green.shade700
                                : Colors.orange.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                    const SizedBox(width: 8),
                  ],
                  const Icon(Icons.chevron_right),
                ]),
                onTap: () => _seleccionarEmpleado(nombre),
              );
            },
          ),
        ),
      ]),
    );
  }

  // ── Pantalla 2: Checklist del empleado ───────────────────────────

  Widget _buildChecklist() {
    final total     = _activosEmpleado.length;
    final marcados  = _activosEmpleado.where((a) => _estaMarcado(a)).length;
    final pct       = total > 0 ? marcados / total : 0.0;

    final pendientes = _activosEmpleado.where((a) => !_estaMarcado(a)).toList();
    final completados = _activosEmpleado.where((a) => _estaMarcado(a)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_empleadoSeleccionado!,
            style: const TextStyle(fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _limpiarEmpleado,
        ),
      ),
      body: Column(children: [
        // Resumen progreso
        _buildResumen(total, marcados, pct),
        // Lista unificada: primero pendientes, luego completados
        Expanded(
          child: ListView(children: [
            if (pendientes.isNotEmpty) ...[
              _seccion('Por escanear', pendientes.length, Colors.red.shade700),
              ...pendientes.map((a) => _cardActivo(a, false)),
            ],
            if (completados.isNotEmpty) ...[
              _seccion('Escaneados', completados.length, Colors.green.shade700),
              ...completados.map((a) => _cardActivo(a, true)),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _buildResumen(int total, int marcados, double pct) {
    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _stat('Total',      '$total',   Colors.blue.shade700),
          _stat('Escaneados', '$marcados', Colors.green.shade700),
          _stat('Pendientes', '${total - marcados}',
              total - marcados == 0 ? Colors.green.shade700 : Colors.red.shade700),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct, minHeight: 10,
            backgroundColor: Colors.red.shade100,
            valueColor: AlwaysStoppedAnimation(
                pct >= 1.0 ? Colors.green.shade600 : Colors.blue.shade600),
          ),
        ),
        const SizedBox(height: 4),
        Text('${(pct * 100).toStringAsFixed(1)}% completado',
            style: TextStyle(
                fontSize: 12,
                color: pct >= 1.0 ? Colors.green.shade700 : Colors.blue.shade700,
                fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _seccion(String titulo, int cantidad, Color color) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text('$titulo ($cantidad)',
          style: TextStyle(fontWeight: FontWeight.bold,
              color: color, fontSize: 13)),
    );
  }

  Widget _stat(String label, String value, Color color) => Column(children: [
    Text(value, style: TextStyle(
        fontSize: 22, fontWeight: FontWeight.bold, color: color)),
    Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
  ]);

  // ── Tarjeta de activo con botón escanear ──────────────────────────

  Widget _cardActivo(ActivoTeorico a, bool escaneado) {
    final bg     = escaneado ? Colors.green.shade50 : Colors.red.shade50;
    final accent = escaneado ? Colors.green.shade700 : Colors.red.shade700;
    final border = escaneado ? Colors.green.shade200 : Colors.red.shade200;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Info
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(escaneado ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: accent, size: 18),
              const SizedBox(width: 6),
              Text(_codigoPrincipal(a),
                  style: TextStyle(fontWeight: FontWeight.bold,
                      fontSize: 15, color: accent)),
              if (_codigoSecundario(a).isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: border),
                  ),
                  child: Text(_codigoSecundario(a),
                      style: TextStyle(color: accent, fontSize: 11)),
                ),
              ],
            ]),
            const SizedBox(height: 4),
            Text(a.descripcion,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (a.localizacion.isNotEmpty)
                _chip('Ubicación', '${a.localizacion} — ${a.ubicaDesc}'),
              if (a.marca.isNotEmpty)     _chip('Marca',   a.marca),
              if (a.modelo.isNotEmpty)    _chip('Modelo',  a.modelo),
              if (a.noSerie.isNotEmpty)   _chip('Serie',   a.noSerie),
              if (a.resguardo.isNotEmpty) _chip('Resguardo', a.resguardo),
            ]),
          ])),
          // Botón escanear (solo para pendientes)
          if (!escaneado) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _escanearActivo(a),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade700,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.qr_code_scanner,
                    color: Colors.white, size: 28),
              ),
            ),
          ] else ...[
            const SizedBox(width: 8),
            Icon(Icons.check_circle, color: Colors.green.shade600, size: 32),
          ],
        ]),
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black12),
      ),
      child: RichText(text: TextSpan(
        style: const TextStyle(fontSize: 11, color: Colors.black87),
        children: [
          TextSpan(text: '$label: ',
              style: const TextStyle(color: Colors.black54)),
          TextSpan(text: value,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      )),
    );
  }

  // ── Escáner individual ────────────────────────────────────────────

  Widget _buildEscanerIndividual() {
    final activo = _activoEnEscaneo!;
    return Scaffold(
      body: Stack(children: [
        MobileScanner(controller: _scannerCtrl!, onDetect: _onDetectado),
        // Info del activo buscado
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            color: Colors.black.withOpacity(0.78),
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Escaneando activo:',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 4),
              Text(_codigoPrincipal(activo),
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.bold, fontSize: 18)),
              if (_codigoSecundario(activo).isNotEmpty)
                Text(_codigoSecundario(activo),
                    style: const TextStyle(color: Colors.white60, fontSize: 13)),
              Text(activo.descripcion,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              if (activo.marca.isNotEmpty || activo.modelo.isNotEmpty)
                Text('${activo.marca}  ${activo.modelo}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              if (activo.localizacion.isNotEmpty)
                Text('Ubicación: ${activo.localizacion}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          ),
        ),
        // Recuadro centrado
        Center(child: Container(
          width: 300, height: 140,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 2.5),
            borderRadius: BorderRadius.circular(8),
          ),
        )),
        // Instrucción
        Positioned(
          bottom: 100, left: 0, right: 0,
          child: const Text('Centra el código en el recuadro',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13)),
        ),
        // Botón cancelar
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            color: Colors.black.withOpacity(0.7),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                onPressed: _cerrarEscaner,
                icon: const Icon(Icons.close),
                label: const Text('Cancelar'),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
