import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';

import '../services/catalogo_service.dart';
import '../services/inventario_service.dart';
import '../services/teorico_service.dart';
import '../widgets/manual_entry_dialog.dart';
import 'verificacion_screen.dart';
import 'checklist_screen.dart';
import 'dashboard_screen.dart';

class InventarioScreen extends StatefulWidget {
  const InventarioScreen({super.key});
  @override
  State<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends State<InventarioScreen> {
  final _catalogo   = CatalogoService();
  final _inventario = InventarioService();
  final _teorico    = TeoricoService();

  bool _cargando = true;
  List<RegistroInventario> _registros = [];
  final Set<String> _escaneadosEnSesion = {};

  String? _cveLocalizacion;
  String  _descLocalizacion = '';
  final _locCtrl = TextEditingController();
  List<String> _sugerencias        = [];
  bool         _mostrarSugerencias = false;

  MobileScannerController? _scannerCtrl;
  bool   _escaneando        = false;
  String _codigoMostrado    = '';
  String _descMostrada      = '';
  bool   _esDuplicadoVisor  = false;
  bool   _noEncontrado      = false;

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
        for (final r in regs) _escaneadosEnSesion.add(r.cveActivo.toUpperCase());
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

  Future<void> _insertarActivo(String codigoEscaneado,
      {String? localizacionForzada}) async {
    final loc = localizacionForzada ?? _cveLocalizacion;
    if (loc == null) {
      _mostrarError('Selecciona una localización primero');
      return;
    }
    final cveInterno = _catalogo.normalizarCveActivo(codigoEscaneado);
    final desc       = _catalogo.descripcionActivo(codigoEscaneado);
    final display    = codigoEscaneado.trim();

    if (desc.isEmpty) {
      setState(() {
        _codigoMostrado   = display;
        _descMostrada     = 'No encontrado en catálogo';
        _esDuplicadoVisor = false;
        _noEncontrado     = true;
      });
      return;
    }

    final duplicado = _esDuplicado(cveInterno);
    setState(() {
      _codigoMostrado   = display;
      _descMostrada     = desc;
      _esDuplicadoVisor = duplicado;
      _noEncontrado     = false;
    });
    if (duplicado) return;

    final reg = RegistroInventario(
        localizacion: loc, cveActivo: cveInterno, fecha: DateTime.now());
    await _inventario.agregarRegistro(reg);
    setState(() {
      _registros.add(reg);
      _escaneadosEnSesion.add(cveInterno.toUpperCase());
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✓ $display  $desc'),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  bool _esDuplicado(String cveInterno) {
    if (_escaneadosEnSesion.contains(cveInterno.toUpperCase())) return true;
    final activo = _teorico.buscarPorCodigo(cveInterno);
    if (activo == null) return false;
    return _escaneadosEnSesion.contains(activo.codigoNuevo.toUpperCase()) ||
        (activo.codigoAnterior.isNotEmpty &&
            _escaneadosEnSesion.contains(activo.codigoAnterior));
  }

  bool _mismoActivo(String a, String b) {
    if (a.toUpperCase() == b.toUpperCase()) return true;
    final aa = _teorico.buscarPorCodigo(a);
    final bb = _teorico.buscarPorCodigo(b);
    if (aa == null || bb == null) return false;
    return aa.codigoNuevo == bb.codigoNuevo;
  }

  // ── Eliminar registro ─────────────────────────────────────────────

  Future<void> _eliminarRegistro(int index) async {
    setState(() => _registros.removeAt(index));
    await _inventario.borrarArchivo();
    for (final r in _registros) await _inventario.agregarRegistro(r);
    _escaneadosEnSesion.clear();
    for (final r in _registros) _escaneadosEnSesion.add(r.cveActivo.toUpperCase());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Registro eliminado'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 2),
      ));
    }
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
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => VerificacionScreen(
        localizacion: _cveLocalizacion!,
        registros:    _registros,
        onActivoEscaneado: (codigo) =>
            _insertarActivo(codigo, localizacionForzada: _cveLocalizacion),
      ),
    )).then((_) => setState(() {}));
  }

  // ── Ir a checklist ────────────────────────────────────────────────

  void _abrirChecklist() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ChecklistScreen(
        registros: _registros,
        onActivoEscaneado: (codigo, loc) =>
            _insertarActivo(codigo, localizacionForzada: loc),
      ),
    )).then((_) => setState(() {}));
  }

  // ── Escáner mejorado ──────────────────────────────────────────────

  void _abrirEscaner() {
    if (_cveLocalizacion == null) {
      _mostrarError('Selecciona una localización primero');
      return;
    }
    setState(() {
      _escaneando       = true;
      _codigoMostrado   = '';
      _descMostrada     = '';
      _esDuplicadoVisor = false;
      _noEncontrado     = false;
      _scannerCtrl      = _crearControladorEscaner();
    });
  }

  /// Controlador con configuración optimizada para Code 128B deteriorado
  MobileScannerController _crearControladorEscaner() {
    return MobileScannerController(
      // noDuplicates pero con ventana de tiempo mayor para etiquetas difíciles
      detectionSpeed: DetectionSpeed.normal,
      // Habilitar explícitamente los formatos relevantes
      formats: const [
        BarcodeFormat.code128,  // Código principal (Ixxxxx y Cxxxxx)
        BarcodeFormat.code39,
        BarcodeFormat.ean13,    // Código anterior (5xxxxxxxxxxx)
        BarcodeFormat.ean8,
        BarcodeFormat.itf,
        BarcodeFormat.codabar,
        BarcodeFormat.dataMatrix,
        BarcodeFormat.qrCode,
      ],
      // Torch automático para etiquetas en lugares oscuros
      torchEnabled: false,
      // Auto enfoque continuo — clave para etiquetas deterioradas
      autoStart: true,
    );
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

  void _toggleLinterna() {
    _scannerCtrl?.toggleTorch();
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

  Future<void> _borrarArchivo() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar'),
        content: const Text('¿Borrar todo el archivo de inventario?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
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
      setState(() { _registros.clear(); _escaneadosEnSesion.clear(); });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Archivo de inventario borrado')));
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
          // Dashboard de progreso
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Dashboard de progreso',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => DashboardScreen(registros: _registros),
            )).then((_) => setState(() {})),
          ),
          // Botón checklist por empleado
          IconButton(
            icon: const Icon(Icons.person_search),
            tooltip: 'Checklist por empleado',
            onPressed: _abrirChecklist,
          ),
          IconButton(icon: const Icon(Icons.share), tooltip: 'Compartir',
              onPressed: _registros.isEmpty ? null : _compartirArchivo),
          IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Borrar todo',
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08),
            blurRadius: 6, offset: const Offset(0, 2))],
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
                  TextSpan(text: clave, style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Color(0xFF1B4F8A))),
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
        final realIdx = _registros.length - 1 - i;
        final r    = _registros[realIdx];
        final desc = _catalogo.descripcionActivo(r.cveActivo);
        final veces = _registros
            .where((x) => _mismoActivo(x.cveActivo, r.cveActivo)).length;
        final esDup = veces > 1;

        return Dismissible(
          key: Key('${r.cveActivo}_${r.fecha.millisecondsSinceEpoch}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            color: Colors.red.shade700,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          confirmDismiss: (_) async {
            return await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Eliminar registro'),
                content: Text('¿Eliminar ${r.cveActivo}?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar')),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Eliminar'),
                  ),
                ],
              ),
            ) ?? false;
          },
          onDismissed: (_) => _eliminarRegistro(realIdx),
          child: ListTile(
            dense: true,
            tileColor: esDup ? Colors.orange.shade50 : null,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: esDup ? Colors.orange : const Color(0xFF1B4F8A),
              child: Text('${_registros.length - i}',
                  style: const TextStyle(color: Colors.white, fontSize: 11)),
            ),
            title: Row(children: [
              Text(r.cveActivo, style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
              if (esDup) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.orange,
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('×$veces', style: const TextStyle(
                      color: Colors.white, fontSize: 10,
                      fontWeight: FontWeight.bold)),
                ),
              ],
            ]),
            subtitle: Text(desc.isNotEmpty ? desc : r.localizacion,
                style: const TextStyle(fontSize: 12)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(r.localizacion,
                  style: TextStyle(color: Colors.blue.shade700,
                      fontSize: 11, fontWeight: FontWeight.w500)),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _eliminarRegistro(realIdx),
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(Icons.remove_circle_outline,
                      color: Colors.red.shade300, size: 20),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildBotones() {
    int? total;
    int? escaneadosEnLoc;
    if (_cveLocalizacion != null) {
      final teo = _teorico.activosDe(_cveLocalizacion!);
      if (teo.isNotEmpty) {
        total = teo.length;
        final escSet = _registros
            .where((r) => r.localizacion.toUpperCase() == _cveLocalizacion)
            .map((r) => r.cveActivo.toUpperCase()).toSet();
        escaneadosEnLoc = teo.where((a) =>
            escSet.contains(a.codigoNuevo) ||
            escSet.contains(a.codigoAnterior)).length;
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
                        ? Colors.green.shade700 : Colors.orange.shade700,
                    fontWeight: FontWeight.bold, fontSize: 13)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: ElevatedButton.icon(
            onPressed: _abrirEscaner,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Escanear'),
          )),
          const SizedBox(width: 8),
          Expanded(child: ElevatedButton.icon(
            onPressed: _registrarManual,
            icon: const Icon(Icons.edit),
            label: const Text('Manual'),
          )),
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

  // ── Vista escáner mejorada ────────────────────────────────────────

  Widget _buildEscaner() {
    return Stack(children: [
      MobileScanner(controller: _scannerCtrl!, onDetect: _onDetected),
      _buildOverlayConRecuadro(),
      // Info superior
      Positioned(
        top: 0, left: 0, right: 0,
        child: Container(
          color: Colors.black.withOpacity(0.65),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Loc: $_cveLocalizacion',
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.bold)),
            Text(_descLocalizacion,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text('Registros: ${_registros.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
      ),
      // Panel inferior
      Positioned(
        bottom: 0, left: 0, right: 0,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_codigoMostrado.isNotEmpty) _buildPanelUltimoEscaneo(),
          Container(
            color: Colors.black.withOpacity(0.65),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              // Linterna
              GestureDetector(
                onTap: _toggleLinterna,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.flashlight_on,
                      color: Colors.white, size: 26),
                ),
              ),
              // Detener
              Expanded(child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                onPressed: _cerrarEscaner,
                icon: const Icon(Icons.stop),
                label: const Text('Detener escáner'),
              )),
            ]),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildOverlayConRecuadro() {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      // Recuadro más ancho para facilitar lectura de Code 128 (barras largas)
      const rW = 300.0, rH = 140.0;
      final left = (w - rW) / 2;
      final top  = (h - rH) / 2 - 30;

      final borderColor = _codigoMostrado.isEmpty
          ? Colors.white
          : _noEncontrado ? Colors.red
          : _esDuplicadoVisor ? Colors.orange
          : Colors.green;

      return Stack(children: [
        Positioned.fill(child: Container(color: Colors.black.withOpacity(0.45))),
        Positioned(
          left: left, top: top, width: rW, height: rH,
          child: Container(decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(color: borderColor, width: 2.5),
            borderRadius: BorderRadius.circular(8),
          )),
        ),
        ..._buildEsquinas(left, top, rW, rH, borderColor),
        // Línea guía central horizontal (ayuda a centrar el código)
        Positioned(
          left: left + 10, top: top + rH / 2 - 0.5, width: rW - 20,
          height: 1,
          child: Container(color: borderColor.withOpacity(0.5)),
        ),
        Positioned(
          left: left, top: top + rH + 8, width: rW,
          child: Text(
            _codigoMostrado.isEmpty ? 'Centra el código en el recuadro' : '',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ]);
    });
  }

  List<Widget> _buildEsquinas(double l, double t, double w, double h, Color c) {
    const len = 22.0, thick = 3.5;
    Widget corner(double x, double y, bool izq, bool arr) => Positioned(
      left: x, top: y,
      child: SizedBox(width: len, height: len,
          child: CustomPaint(painter: _CornerPainter(
              color: c, thickness: thick, izquierda: izq, arriba: arr))),
    );
    return [
      corner(l,         t,           true,  true),
      corner(l + w - len, t,         false, true),
      corner(l,         t + h - len, true,  false),
      corner(l + w - len, t + h - len, false, false),
    ];
  }

  Widget _buildPanelUltimoEscaneo() {
    final bgColor = _noEncontrado ? Colors.red.shade900
        : _esDuplicadoVisor ? Colors.orange.shade900
        : Colors.green.shade900;
    final icono = _noEncontrado ? Icons.error_outline
        : _esDuplicadoVisor ? Icons.warning_amber_outlined
        : Icons.check_circle_outline;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: bgColor.withOpacity(0.92),
          borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(icono, color: Colors.white70, size: 22),
        const SizedBox(width: 10),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_codigoMostrado, style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 2),
          Text(_descMostrada, style: const TextStyle(
              color: Colors.white70, fontSize: 12),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          if (_esDuplicadoVisor)
            const Text('⚠ Activo ya registrado', style: TextStyle(
                color: Colors.orangeAccent, fontSize: 11,
                fontWeight: FontWeight.w500)),
        ])),
      ]),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final bool izquierda, arriba;
  const _CornerPainter({required this.color, required this.thickness,
      required this.izquierda, required this.arriba});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color ..strokeWidth = thickness
        ..strokeCap = StrokeCap.square ..style = PaintingStyle.stroke;
    final x  = izquierda ? 0.0 : size.width;
    final y  = arriba    ? 0.0 : size.height;
    canvas.drawLine(Offset(x, y), Offset(x + (izquierda ? size.width : -size.width), y), p);
    canvas.drawLine(Offset(x, y), Offset(x, y + (arriba ? size.height : -size.height)), p);
  }
  @override
  bool shouldRepaint(_CornerPainter o) =>
      o.color != color || o.izquierda != izquierda || o.arriba != arriba;
}
