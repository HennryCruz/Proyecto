import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vibration/vibration.dart';

import '../services/catalogo_service.dart';
import '../services/excel_service.dart';
import '../services/inventario_service.dart';
import '../services/teorico_service.dart';
import '../widgets/manual_entry_dialog.dart';
import 'checklist_screen.dart';
import 'dashboard_screen.dart';
import 'historial_screen.dart';
import 'verificacion_screen.dart';

class InventarioScreen extends StatefulWidget {
  const InventarioScreen({super.key});
  @override
  State<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends State<InventarioScreen> {
  final _catalogo   = CatalogoService();
  final _inventario = InventarioService();
  final _teorico    = TeoricoService();
  final _excel      = ExcelService();

  bool _cargando = true;
  // Estado de carga detallado para pantalla de inicio
  String _estadoCarga = 'Iniciando...';
  bool   _errorCarga  = false;

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

  // Vibración disponible
  bool _vibracionDisponible = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      setState(() => _estadoCarga = 'Cargando catálogo de localizaciones...');
      await _catalogo.cargar();

      setState(() => _estadoCarga = 'Cargando catálogo de activos...');
      await _teorico.cargar();

      setState(() => _estadoCarga = 'Leyendo registros anteriores...');
      final regs = await _inventario.cargarRegistros();

      // Verificar vibración
      _vibracionDisponible = await Vibration.hasVibrator() ?? false;

      if (mounted) {
        setState(() {
          _registros = regs;
          for (final r in regs) {
            _escaneadosEnSesion.add(r.cveActivo.toUpperCase());
          }
          _estadoCarga = 'Listo: ${_catalogo.totalLocalizaciones} locs · '
              '${_catalogo.totalActivos} activos';
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorCarga  = true;
          _estadoCarga = 'Error al cargar: $e';
          _cargando    = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _scannerCtrl?.dispose();
    _locCtrl.dispose();
    super.dispose();
  }

  // ── Vibrar ────────────────────────────────────────────────────────

  void _vibrar({bool error = false, bool duplicado = false}) {
    if (!_vibracionDisponible) return;
    if (error) {
      Vibration.vibrate(pattern: [0, 100, 80, 100]); // doble pulso = error
    } else if (duplicado) {
      Vibration.vibrate(pattern: [0, 200, 100, 200]); // triple largo = dup
    } else {
      Vibration.vibrate(duration: 80); // pulso corto = OK
    }
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
      {String? localizacionForzada, String nota = ''}) async {
    final loc = localizacionForzada ?? _cveLocalizacion;
    if (loc == null) {
      _mostrarError('Selecciona una localización primero');
      return;
    }
    final cveInterno = _catalogo.normalizarCveActivo(codigoEscaneado);
    final desc       = _catalogo.descripcionActivo(codigoEscaneado);
    final display    = codigoEscaneado.trim();

    if (desc.isEmpty) {
      _vibrar(error: true);
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

    if (duplicado) {
      _vibrar(duplicado: true);
      return;
    }

    _vibrar(); // Pulso corto = registro exitoso

    final reg = RegistroInventario(
      localizacion: loc,
      cveActivo:    cveInterno,
      fecha:        DateTime.now(),
      nota:         nota,
    );
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

  // ── Nota al escanear ──────────────────────────────────────────────

  Future<String?> _pedirNota() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Agregar nota (opcional)'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(
            hintText: 'Ej: dañado, sin etiqueta, ubicación incorrecta...',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Sin nota')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Guardar')),
        ],
      ),
    );
  }

  // ── Eliminar registro ─────────────────────────────────────────────

  Future<void> _eliminarRegistro(int index) async {
    setState(() => _registros.removeAt(index));
    await _inventario.borrarArchivo();
    for (final r in _registros) await _inventario.agregarRegistro(r);
    _escaneadosEnSesion.clear();
    for (final r in _registros) {
      _escaneadosEnSesion.add(r.cveActivo.toUpperCase());
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Registro eliminado'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 2),
      ));
    }
  }

  // ── Exportar Excel sesión activa ──────────────────────────────────

  Future<void> _exportarExcel() async {
    if (_registros.isEmpty) {
      _mostrarError('No hay registros para exportar');
      return;
    }
    _mostrarSnack('Generando Excel...', color: Colors.blue.shade700);
    try {
      await _excel.exportarYCompartir(
        registros: _registros,
        titulo: 'Inventario CENAM — '
            '${DateFormat("dd/MM/yyyy HH:mm").format(DateTime.now())} '
            '(${_registros.length} registros)',
      );
    } catch (e) {
      if (mounted) _mostrarError('Error al generar Excel: $e');
    }
  }

  // ── Verificar ubicación ───────────────────────────────────────────

  void _verificarUbicacion() {
    if (_cveLocalizacion == null) {
      _mostrarError('Selecciona una localización primero');
      return;
    }
    if (_teorico.activosDe(_cveLocalizacion!).isEmpty) {
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

  // ── Escáner ───────────────────────────────────────────────────────

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
      _scannerCtrl      = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        formats: const [
          BarcodeFormat.code128, BarcodeFormat.code39,
          BarcodeFormat.ean13,   BarcodeFormat.ean8,
          BarcodeFormat.itf,     BarcodeFormat.codabar,
          BarcodeFormat.dataMatrix, BarcodeFormat.qrCode,
        ],
        autoStart: true,
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
    if (codigo != null && codigo.isNotEmpty) _insertarActivo(codigo);
  }

  // ── Registro manual con nota ──────────────────────────────────────

  Future<void> _registrarManual() async {
    if (_cveLocalizacion == null) {
      _mostrarError('Selecciona una localización primero');
      return;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (_) => ManualEntryDialog(cveLocalizacion: _cveLocalizacion!),
    );
    if (result == null || result.isEmpty) return;

    // Preguntar nota
    final nota = await _pedirNota() ?? '';
    await _insertarActivo(result, nota: nota);
  }

  // ── Borrar todo ───────────────────────────────────────────────────

  Future<void> _borrarArchivo() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar'),
        content: const Text('¿Borrar el archivo activo de inventario?\n\n'
            'Los datos del día ya están guardados automáticamente en el historial.'),
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

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700));
  }

  void _mostrarSnack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: color,
            duration: const Duration(seconds: 2)));
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario CENAM'),
        actions: [
          IconButton(icon: const Icon(Icons.bar_chart),
              tooltip: 'Dashboard',
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => DashboardScreen(registros: _registros),
              )).then((_) => setState(() {}))),
          IconButton(icon: const Icon(Icons.person_search),
              tooltip: 'Checklist empleado',
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => ChecklistScreen(
                  registros: _registros,
                  onActivoEscaneado: (c, l) =>
                      _insertarActivo(c, localizacionForzada: l),
                ),
              )).then((_) => setState(() {}))),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              switch (v) {
                case 'historial':
                  Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const HistorialScreen()));
                  break;
                case 'excel':     _exportarExcel(); break;
                case 'compartir':
                  if (_registros.isNotEmpty) {
                    _inventario.rutaArchivo.then((ruta) =>
                        Share.shareXFiles([XFile(ruta)],
                            subject: 'ALM_Inventarios.txt'));
                  }
                  break;
                case 'borrar':    _borrarArchivo(); break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'historial',
                  child: ListTile(dense: true,
                      leading: Icon(Icons.history),
                      title: Text('Historial de sesiones'))),
              const PopupMenuItem(value: 'excel',
                  child: ListTile(dense: true,
                      leading: Icon(Icons.table_chart_outlined),
                      title: Text('Exportar Excel'))),
              const PopupMenuItem(value: 'compartir',
                  child: ListTile(dense: true,
                      leading: Icon(Icons.share),
                      title: Text('Compartir TXT (SIGA)'))),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'borrar',
                  child: ListTile(dense: true,
                      leading: Icon(Icons.delete_outline, color: Colors.red),
                      title: Text('Borrar todo',
                          style: TextStyle(color: Colors.red)))),
            ],
          ),
        ],
      ),
      body: _cargando
          ? _buildCargando()
          : _errorCarga
              ? _buildError()
              : _escaneando
                  ? _buildEscaner()
                  : _buildPrincipal(),
    );
  }

  // ── Pantalla de carga detallada ───────────────────────────────────

  Widget _buildCargando() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(_estadoCarga,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.black54)),
        ]),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 56),
          const SizedBox(height: 12),
          const Text('Error al cargar los catálogos',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Text(_estadoCarga,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, fontSize: 13)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () {
              setState(() { _cargando = true; _errorCarga = false; });
              _init();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ]),
      ),
    );
  }

  Widget _buildPrincipal() {
    return Column(children: [
      // Banner de estado de carga
      if (!_cargando && !_errorCarga)
        Container(
          color: Colors.green.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(children: [
            Icon(Icons.check_circle, color: Colors.green.shade600, size: 14),
            const SizedBox(width: 6),
            Text(_estadoCarga,
                style: TextStyle(fontSize: 11, color: Colors.green.shade700)),
          ]),
        ),
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
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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

  // ── Lista con nota visible ────────────────────────────────────────

  Widget _buildLista() {
    if (_registros.isEmpty) {
      return const Center(child: Text(
          'Sin registros aún.\nEscanea o captura un activo.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _registros.length,
      itemBuilder: (_, i) {
        final realIdx = _registros.length - 1 - i;
        final r       = _registros[realIdx];
        final desc    = _catalogo.descripcionActivo(r.cveActivo);
        final veces   = _registros
            .where((x) => _mismoActivo(x.cveActivo, r.cveActivo)).length;
        final esDup      = veces > 1;
        final tieneNota  = r.nota.isNotEmpty;

        // Color del tile: nota tiene prioridad visual sobre duplicado
        Color? tileColor;
        if (tieneNota && esDup) {
          tileColor = Colors.purple.shade50;
        } else if (tieneNota) {
          tileColor = Colors.purple.shade50;
        } else if (esDup) {
          tileColor = Colors.orange.shade50;
        }

        return Dismissible(
          key: Key('${r.cveActivo}_${r.fecha.millisecondsSinceEpoch}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            color: Colors.red.shade700,
            padding: const EdgeInsets.only(right: 20),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.delete, color: Colors.white),
                SizedBox(height: 2),
                Text('Eliminar', style: TextStyle(
                    color: Colors.white, fontSize: 10)),
              ],
            ),
          ),
          // Confirmar al deslizar
          confirmDismiss: (_) => _confirmarEliminar(r.cveActivo),
          onDismissed: (_) => _eliminarRegistro(realIdx),
          child: ListTile(
            dense: true,
            tileColor: tileColor,
            // Borde izquierdo morado si tiene nota
            contentPadding: EdgeInsets.only(
              left: tieneNota ? 0 : 16,
              right: 8,
            ),
            leading: Row(mainAxisSize: MainAxisSize.min, children: [
              // Barra lateral morada si hay nota
              if (tieneNota)
                Container(
                  width: 4,
                  height: 56,
                  color: Colors.purple.shade400,
                ),
              if (tieneNota) const SizedBox(width: 8),
              CircleAvatar(
                radius: 16,
                backgroundColor: tieneNota
                    ? Colors.purple.shade400
                    : esDup
                        ? Colors.orange
                        : const Color(0xFF1B4F8A),
                child: Text('${_registros.length - i}',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11)),
              ),
            ]),
            title: Row(children: [
              Text(r.cveActivo, style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
              if (esDup) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.orange,
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('×$veces', style: const TextStyle(
                      color: Colors.white, fontSize: 10,
                      fontWeight: FontWeight.bold)),
                ),
              ],
              // Badge "NOTA" resaltado
              if (tieneNota) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade400,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('NOTA', style: TextStyle(
                      color: Colors.white, fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5)),
                ),
              ],
            ]),
            subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(desc.isNotEmpty ? desc : r.localizacion,
                  style: const TextStyle(fontSize: 12)),
              if (tieneNota)
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.edit_note,
                        size: 13, color: Colors.purple.shade700),
                    const SizedBox(width: 4),
                    Flexible(child: Text(r.nota,
                        style: TextStyle(fontSize: 11,
                            color: Colors.purple.shade800,
                            fontWeight: FontWeight.w500))),
                  ]),
                ),
            ]),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(r.localizacion,
                    style: TextStyle(color: Colors.blue.shade700,
                        fontSize: 10, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  // Botón nota
                  GestureDetector(
                    onTap: () => _editarNota(realIdx),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Icon(
                        tieneNota
                            ? Icons.edit_note
                            : Icons.note_add_outlined,
                        color: tieneNota
                            ? Colors.purple.shade400
                            : Colors.grey.shade400,
                        size: 20,
                      ),
                    ),
                  ),
                  // Botón eliminar con confirmación
                  GestureDetector(
                    onTap: () async {
                      final ok = await _confirmarEliminar(r.cveActivo);
                      if (ok == true) _eliminarRegistro(realIdx);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Icon(Icons.remove_circle_outline,
                          color: Colors.red.shade300, size: 20),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Confirmar eliminación ─────────────────────────────────────────

  Future<bool> _confirmarEliminar(String cveActivo) async {
    final desc = _catalogo.descripcionActivo(cveActivo);
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            icon: const Icon(Icons.warning_amber_rounded,
                color: Colors.red, size: 36),
            title: const Text('¿Eliminar registro?'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(cveActivo,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(desc,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.black54)),
              ],
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Sí, eliminar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ── Editar nota de un registro existente ──────────────────────────

  Future<void> _editarNota(int index) async {
    final r    = _registros[index];
    final ctrl = TextEditingController(text: r.nota);

    final nuevaNota = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [
          Icon(Icons.edit_note, color: Colors.purple.shade400),
          const SizedBox(width: 8),
          Expanded(child: Text(r.cveActivo,
              style: const TextStyle(fontSize: 15))),
        ]),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 80,
          decoration: InputDecoration(
            hintText: 'Ej: dañado, sin etiqueta, ubicación incorrecta...',
            border: const OutlineInputBorder(),
            // Botón para limpiar nota
            suffixIcon: ctrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => ctrl.clear(),
                  )
                : null,
          ),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          if (r.nota.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: Text('Quitar nota',
                  style: TextStyle(color: Colors.red.shade400)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (nuevaNota == null) return; // Canceló

    // Reconstruir el registro con la nueva nota
    final actualizado = RegistroInventario(
      localizacion: r.localizacion,
      cveActivo:    r.cveActivo,
      fecha:        r.fecha,
      nota:         nuevaNota,
    );

    setState(() => _registros[index] = actualizado);

    // Reescribir el archivo completo
    await _inventario.borrarArchivo();
    for (final reg in _registros) await _inventario.agregarRegistro(reg);
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
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 14),
            ),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Verificar'),
          ),
        ]),
      ]),
    );
  }

  // ── Vista escáner ─────────────────────────────────────────────────

  Widget _buildEscaner() {
    return Stack(children: [
      MobileScanner(controller: _scannerCtrl!, onDetect: _onDetected),
      _buildOverlayConRecuadro(),
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
      Positioned(
        bottom: 0, left: 0, right: 0,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_codigoMostrado.isNotEmpty) _buildPanelUltimoEscaneo(),
          Container(
            color: Colors.black.withOpacity(0.65),
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            child: Row(children: [
              GestureDetector(
                onTap: () => _scannerCtrl?.toggleTorch(),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(color: Colors.white24,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.flashlight_on,
                      color: Colors.white, size: 26),
                ),
              ),
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
      const rW = 300.0, rH = 140.0;
      final left = (w - rW) / 2;
      final top  = (h - rH) / 2 - 30;

      final borderColor = _codigoMostrado.isEmpty ? Colors.white
          : _noEncontrado ? Colors.red
          : _esDuplicadoVisor ? Colors.orange
          : Colors.green;

      return Stack(children: [
        Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.45))),
        Positioned(
          left: left, top: top, width: rW, height: rH,
          child: Container(decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(color: borderColor, width: 2.5),
            borderRadius: BorderRadius.circular(8),
          )),
        ),
        ..._buildEsquinas(left, top, rW, rH, borderColor),
        Positioned(
          left: left, top: top + rH / 2 - 0.5, width: rW,
          height: 1,
          child: Container(color: borderColor.withOpacity(0.4)),
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

  List<Widget> _buildEsquinas(
      double l, double t, double w, double h, Color c) {
    const len = 22.0, thick = 3.5;
    Widget corner(double x, double y, bool izq, bool arr) => Positioned(
      left: x, top: y,
      child: SizedBox(width: len, height: len,
          child: CustomPaint(painter: _CornerPainter(
              color: c, thickness: thick,
              izquierda: izq, arriba: arr))),
    );
    return [
      corner(l,           t,           true,  true),
      corner(l + w - len, t,           false, true),
      corner(l,           t + h - len, true,  false),
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
    canvas.drawLine(Offset(x, y),
        Offset(x + (izquierda ? size.width : -size.width), y), p);
    canvas.drawLine(Offset(x, y),
        Offset(x, y + (arriba ? size.height : -size.height)), p);
  }
  @override
  bool shouldRepaint(_CornerPainter o) =>
      o.color != color || o.izquierda != izquierda || o.arriba != arriba;
}
