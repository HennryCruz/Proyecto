import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';

import '../models/activo_teorico.dart';
import '../services/excel_service.dart';
import '../services/inventario_service.dart';
import '../services/teorico_service.dart';

class VerificacionScreen extends StatefulWidget {
  final String localizacion;
  final List<RegistroInventario> registros;
  final Future<void> Function(String codigo) onActivoEscaneado;

  const VerificacionScreen({
    super.key,
    required this.localizacion,
    required this.registros,
    required this.onActivoEscaneado,
  });

  @override
  State<VerificacionScreen> createState() => _VerificacionScreenState();
}

class _VerificacionScreenState extends State<VerificacionScreen>
    with SingleTickerProviderStateMixin {
  final _teorico = TeoricoService();
  final _excel   = ExcelService();
  late TabController _tabCtrl;

  List<ActivoTeorico>      _esperados  = [];
  List<ActivoTeorico>      _faltantes  = [];
  List<ActivoTeorico>      _escaneados = [];
  List<RegistroInventario> _sobrantes  = [];

  MobileScannerController? _scannerCtrl;
  ActivoTeorico? _activoEnEscaneo;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _calcular();
  }

  void _calcular() {
    _esperados = _teorico.activosDe(widget.localizacion);

    final escSet = widget.registros
        .where((r) => r.localizacion.toUpperCase() == widget.localizacion)
        .map((r) => r.cveActivo.toUpperCase())
        .toSet();

    _escaneados = _esperados.where((a) =>
        escSet.contains(a.codigoNuevo.toUpperCase()) ||
        (a.codigoAnterior.isNotEmpty &&
            escSet.contains(a.codigoAnterior))).toList();

    _faltantes = _esperados.where((a) =>
        !escSet.contains(a.codigoNuevo.toUpperCase()) &&
        !(a.codigoAnterior.isNotEmpty &&
            escSet.contains(a.codigoAnterior))).toList();

    final codigosNuevo    = _esperados.map((a) => a.codigoNuevo).toSet();
    final codigosAnterior = _esperados
        .where((a) => a.codigoAnterior.isNotEmpty)
        .map((a) => a.codigoAnterior).toSet();

    _sobrantes = widget.registros.where((r) {
      if (r.localizacion.toUpperCase() != widget.localizacion) return false;
      final c = r.cveActivo.toUpperCase();
      final activo = _teorico.buscarPorCodigo(c);
      if (activo == null) return true;
      return !codigosNuevo.contains(activo.codigoNuevo) &&
             !codigosAnterior.contains(activo.codigoAnterior);
    }).toList();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _scannerCtrl?.dispose();
    super.dispose();
  }

  // ── Escanear faltante individual ──────────────────────────────────

  void _escanearFaltante(ActivoTeorico activo) {
    setState(() {
      _activoEnEscaneo = activo;
      _scannerCtrl = MobileScannerController(
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

  void _cerrarEscanerFaltante() {
    _scannerCtrl?.dispose();
    _scannerCtrl = null;
    setState(() => _activoEnEscaneo = null);
  }

  Future<void> _onFaltanteDetectado(BarcodeCapture capture) async {
    final codigo = capture.barcodes.firstOrNull?.rawValue;
    if (codigo == null || codigo.isEmpty) return;

    final activo         = _activoEnEscaneo!;
    final activoEscaneado = _teorico.buscarPorCodigo(codigo);
    final corresponde    = activoEscaneado != null &&
        activoEscaneado.codigoNuevo == activo.codigoNuevo;

    if (!corresponde) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '⚠ Código no corresponde a ${_codigoPrincipal(activo)}'),
          backgroundColor: Colors.orange.shade700,
          duration: const Duration(seconds: 2),
        ));
      }
      return;
    }

    _cerrarEscanerFaltante();
    await widget.onActivoEscaneado(codigo);
    setState(() => _calcular());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✓ ${_codigoPrincipal(activo)} registrado'),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  // ── Exportar diferencias a Excel ──────────────────────────────────

  Future<void> _exportarDiferenciasExcel() async {
    if (_faltantes.isEmpty && _sobrantes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('¡Todo correcto! No hay diferencias que exportar.'),
        backgroundColor: Colors.green,
      ));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Generando reporte de diferencias...'),
      backgroundColor: Colors.blue.shade700,
      duration: const Duration(seconds: 2),
    ));

    try {
      final ruta = await _excel.exportarDiferencias(
        localizacion: widget.localizacion,
        faltantes:    _faltantes,
        sobrantes:    _sobrantes,
        escaneados:   _escaneados,
        registros:    widget.registros,
      );
      await Share.shareXFiles(
        [XFile(ruta,
            mimeType: 'application/vnd.openxmlformats-officedocument'
                '.spreadsheetml.sheet')],
        subject: 'Diferencias ${widget.localizacion}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red.shade700,
        ));
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  String _codigoPrincipal(ActivoTeorico a) =>
      a.codigoAnterior.isNotEmpty ? a.codigoAnterior : a.codigoNuevo;

  String _codigoSecundario(ActivoTeorico a) =>
      a.codigoAnterior.isNotEmpty ? a.codigoNuevo : '';

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_activoEnEscaneo != null) return _buildEscanerFaltante();

    final total      = _esperados.length;
    final escaneados = _escaneados.length;
    final pct        = total > 0 ? escaneados / total : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text('Verificación ${widget.localizacion}'),
        actions: [
          // Botón exportar diferencias Excel
          IconButton(
            icon: const Icon(Icons.difference_outlined),
            tooltip: 'Exportar diferencias Excel',
            onPressed: _exportarDiferenciasExcel,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: 'Faltantes (${_faltantes.length})'),
            Tab(text: 'Escaneados ($escaneados)'),
            Tab(text: 'Sobrantes (${_sobrantes.length})'),
          ],
        ),
      ),
      body: Column(children: [
        _buildResumen(total, escaneados, pct),
        Expanded(child: TabBarView(
          controller: _tabCtrl,
          children: [
            _buildListaFaltantes(),
            _buildListaEscaneados(),
            _buildListaSobrantes(),
          ],
        )),
      ]),
    );
  }

  // ── Escáner de faltante ───────────────────────────────────────────

  Widget _buildEscanerFaltante() {
    final activo = _activoEnEscaneo!;
    return Scaffold(
      body: Stack(children: [
        MobileScanner(
            controller: _scannerCtrl!,
            onDetect: _onFaltanteDetectado),
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            color: Colors.black.withOpacity(0.78),
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Text('Buscando activo faltante:',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 4),
              Text(_codigoPrincipal(activo),
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.bold, fontSize: 18)),
              if (_codigoSecundario(activo).isNotEmpty)
                Text(_codigoSecundario(activo),
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 13)),
              Text(activo.descripcion,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
        // Línea de escaneo animada — sin recuadro restrictivo
        const Positioned.fill(child: _ScanLine()),
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            color: Colors.black.withOpacity(0.7),
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    padding:
                        const EdgeInsets.symmetric(vertical: 12)),
                onPressed: _cerrarEscanerFaltante,
                icon: const Icon(Icons.close),
                label: const Text('Cancelar'),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Resumen ───────────────────────────────────────────────────────

  Widget _buildResumen(int total, int escaneados, double pct) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest
          .withOpacity(0.5),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _stat('Esperados',  '$total',             Colors.blue),
          _stat('Escaneados', '$escaneados',         Colors.green),
          _stat('Faltantes',  '${_faltantes.length}',
              _faltantes.isEmpty ? Colors.green : Colors.red),
          _stat('Sobrantes',  '${_sobrantes.length}',
              _sobrantes.isEmpty ? Colors.green : Colors.orange),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct, minHeight: 10,
            backgroundColor: Colors.red.shade100,
            valueColor: AlwaysStoppedAnimation(
                pct >= 1.0 ? Colors.green.shade600
                           : Colors.blue.shade600),
          ),
        ),
        const SizedBox(height: 4),
        Text('${(pct * 100).toStringAsFixed(1)}% completado',
            style: TextStyle(
                fontSize: 12,
                color: pct >= 1.0
                    ? Colors.green.shade700
                    : Colors.blue.shade700,
                fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _stat(String label, String value, Color color) =>
      Column(children: [
        Text(value, style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(
            fontSize: 11, color: Colors.grey)),
      ]);

  // ── Pestaña Faltantes ─────────────────────────────────────────────

  Widget _buildListaFaltantes() {
    if (_faltantes.isEmpty) {
      return const Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 64),
          SizedBox(height: 8),
          Text('¡Todo escaneado!', style: TextStyle(
              fontSize: 18, color: Colors.green,
              fontWeight: FontWeight.bold)),
        ],
      ));
    }
    return ListView.builder(
      itemCount: _faltantes.length,
      itemBuilder: (_, i) => _cardFaltante(_faltantes[i]),
    );
  }

  Widget _cardFaltante(ActivoTeorico a) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.red.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(children: [
              Icon(Icons.error_outline,
                  color: Colors.red.shade700, size: 18),
              const SizedBox(width: 6),
              Text(_codigoPrincipal(a),
                  style: TextStyle(fontWeight: FontWeight.bold,
                      fontSize: 15, color: Colors.red.shade800)),
              if (_codigoSecundario(a).isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(_codigoSecundario(a),
                      style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 11)),
                ),
              ],
            ]),
            const SizedBox(height: 4),
            Text(a.descripcion, style: const TextStyle(
                fontWeight: FontWeight.w500, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (a.marca.isNotEmpty)     _chip('Marca',    a.marca),
              if (a.modelo.isNotEmpty)    _chip('Modelo',   a.modelo),
              if (a.noSerie.isNotEmpty)   _chip('Serie',    a.noSerie),
              if (a.nombre.isNotEmpty)    _chip('Resp.',    a.nombre),
              if (a.resguardo.isNotEmpty) _chip('Resguardo', a.resguardo),
            ]),
          ])),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _escanearFaltante(a),
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
        ]),
      ),
    );
  }

  // ── Pestaña Escaneados ────────────────────────────────────────────

  Widget _buildListaEscaneados() {
    if (_escaneados.isEmpty) {
      return const Center(child: Text('Sin activos escaneados.',
          style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      itemCount: _escaneados.length,
      itemBuilder: (_, i) => _cardActivo(
          _escaneados[i], Colors.green.shade50,
          Colors.green.shade700, Icons.check_circle_outline),
    );
  }

  // ── Pestaña Sobrantes ─────────────────────────────────────────────

  Widget _buildListaSobrantes() {
    if (_sobrantes.isEmpty) {
      return const Center(child: Text('Sin activos sobrantes.',
          style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      itemCount: _sobrantes.length,
      itemBuilder: (_, i) {
        final r      = _sobrantes[i];
        final activo = _teorico.buscarPorCodigo(r.cveActivo);
        if (activo != null) {
          return _cardActivo(activo, Colors.orange.shade50,
              Colors.orange.shade700, Icons.warning_amber_outlined);
        }
        return ListTile(
          leading: Icon(Icons.help_outline,
              color: Colors.orange.shade700),
          title: Text(r.cveActivo,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('No encontrado en catálogo'),
          tileColor: Colors.orange.shade50,
        );
      },
    );
  }

  // ── Card genérico ─────────────────────────────────────────────────

  Widget _cardActivo(ActivoTeorico a, Color bg, Color accent,
      IconData icon) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: accent.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Icon(icon, color: accent, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(_codigoPrincipal(a), style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14, color: accent)),
              if (_codigoSecundario(a).isNotEmpty)
                Text(_codigoSecundario(a), style: TextStyle(
                    fontSize: 12,
                    color: accent.withOpacity(0.7))),
              Text(a.descripcion, style: const TextStyle(
                  fontWeight: FontWeight.w500, fontSize: 13)),
            ])),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            if (a.marca.isNotEmpty)     _chip('Marca',    a.marca),
            if (a.modelo.isNotEmpty)    _chip('Modelo',   a.modelo),
            if (a.noSerie.isNotEmpty)   _chip('Serie',    a.noSerie),
            if (a.nombre.isNotEmpty)    _chip('Resp.',    a.nombre),
            if (a.resguardo.isNotEmpty) _chip('Resguardo', a.resguardo),
          ]),
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
}

// ── Línea de escaneo animada (reutilizada de inventario_screen) ────

class _ScanLine extends StatefulWidget {
  const _ScanLine();
  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => CustomPaint(painter: _ScanLinePainter(_anim.value)),
  );
}

class _ScanLinePainter extends CustomPainter {
  final double progress;
  _ScanLinePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final top    = size.height * 0.18;
    final bottom = size.height * 0.78;
    final y      = top + (bottom - top) * progress;

    final paint = Paint()
      ..shader = LinearGradient(colors: [
        Colors.transparent, Colors.green.withOpacity(0.9),
        Colors.greenAccent, Colors.green.withOpacity(0.9),
        Colors.transparent,
      ], stops: const [0.0, 0.2, 0.5, 0.8, 1.0])
          .createShader(Rect.fromLTWH(0, y - 1, size.width, 2))
      ..strokeWidth = 2.5 ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);

    final glow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Colors.green.withOpacity(0.15), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, y, size.width, 18))
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, y, size.width, 18), glow);
  }

  @override
  bool shouldRepaint(_ScanLinePainter o) => o.progress != progress;
}
