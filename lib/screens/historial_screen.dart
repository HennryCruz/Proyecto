import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../services/excel_service.dart';
import '../services/inventario_service.dart';

class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  final _inventario = InventarioService();
  final _excel      = ExcelService();

  bool _cargando = true;
  List<SesionInventario> _sesiones = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final s = await _inventario.cargarHistorial();
    if (mounted) setState(() { _sesiones = s; _cargando = false; });
  }

  // ── Compartir TXT ─────────────────────────────────────────────────

  Future<void> _compartirTxt(SesionInventario s) async {
    // Genera TXT sin notas (formato SIGA limpio)
    final ruta = await _inventario.exportarTxtSiga(s.registros);
    await Share.shareXFiles(
      [XFile(ruta)],
      subject: 'Inventario CENAM ${_fechaLegible(s.inicio)}',
    );
  }

  // ── Exportar Excel ────────────────────────────────────────────────

  Future<void> _exportarExcel(SesionInventario s) async {
    _mostrarSnack('Generando Excel...', color: Colors.blue.shade700);
    try {
      await _excel.exportarYCompartir(
        registros: s.registros,
        titulo:
            'Inventario CENAM — ${_fechaLegible(s.inicio)} (${s.total} registros)',
      );
    } catch (e) {
      if (mounted) _mostrarSnack('Error al generar Excel: $e',
          color: Colors.red.shade700);
    }
  }

  // ── Eliminar sesión ───────────────────────────────────────────────

  Future<void> _eliminar(SesionInventario s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar sesión'),
        content: Text(
            '¿Eliminar el inventario del ${_fechaLegible(s.inicio)} '
            '(${s.total} registros)?'),
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
    );
    if (ok == true) {
      await _inventario.eliminarSesion(s.id);
      await _cargar();
      if (mounted) _mostrarSnack('Sesión eliminada');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  String _fechaLegible(DateTime d) =>
      DateFormat('dd/MM/yyyy HH:mm').format(d);

  String _fechaCorta(DateTime d) => DateFormat('dd MMM yyyy').format(d);
  String _hora(DateTime d)       => DateFormat('HH:mm').format(d);

  void _mostrarSnack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de sesiones'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _sesiones.isEmpty
              ? _buildVacio()
              : _buildLista(),
    );
  }

  Widget _buildVacio() {
    return const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.history, size: 64, color: Colors.black26),
        SizedBox(height: 12),
        Text('Sin sesiones guardadas',
            style: TextStyle(fontSize: 16, color: Colors.black45)),
        SizedBox(height: 6),
        Text('Cada día que escanees activos\nse crea una sesión automáticamente.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black38, fontSize: 13)),
      ]),
    );
  }

  Widget _buildLista() {
    return Column(children: [
      // Cabecera resumen
      Container(
        color: Colors.grey.shade100,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${_sesiones.length} sesiones guardadas',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(
              'Total: ${_sesiones.fold(0, (s, e) => s + e.total)} registros',
              style: TextStyle(color: Colors.blue.shade800,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: _sesiones.length,
          itemBuilder: (_, i) => _cardSesion(_sesiones[i]),
        ),
      ),
    ]);
  }

  Widget _cardSesion(SesionInventario s) {
    // Desglose rápido: cuántas localizaciones distintas
    final locs = s.registros.map((r) => r.localizacion).toSet();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Encabezado: fecha + hora
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1B4F8A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(children: [
        // Banner guardado automático
        Container(
          color: Colors.blue.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Las sesiones se guardan automáticamente cada día.',
                style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
              ),
            ),
          ]),
        ),
                Text(_fechaCorta(s.inicio),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold,
                        fontSize: 13)),
                Text(_hora(s.inicio),
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 11)),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s.total} activos escaneados',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              Text(
                '${locs.length} ubicación${locs.length == 1 ? "" : "es"}: '
                '${locs.take(3).join(", ")}${locs.length > 3 ? "..." : ""}',
                style: const TextStyle(
                    color: Colors.black54, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ])),
          ]),

          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // Botones de acción
          Row(children: [
            // TXT
            Expanded(child: OutlinedButton.icon(
              onPressed: () => _compartirTxt(s),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: const Text('TXT', style: TextStyle(fontSize: 13)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue.shade700,
                side: BorderSide(color: Colors.blue.shade300),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            )),
            const SizedBox(width: 8),
            // Excel
            Expanded(child: OutlinedButton.icon(
              onPressed: () => _exportarExcel(s),
              icon: const Icon(Icons.table_chart_outlined, size: 18),
              label: const Text('Excel', style: TextStyle(fontSize: 13)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.green.shade700,
                side: BorderSide(color: Colors.green.shade300),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            )),
            const SizedBox(width: 8),
            // Eliminar
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
              onPressed: () => _eliminar(s),
              tooltip: 'Eliminar sesión',
            ),
          ]),
        ]),
      ),
    );
  }
}
