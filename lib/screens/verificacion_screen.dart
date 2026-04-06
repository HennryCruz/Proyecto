import 'package:flutter/material.dart';

import '../models/activo_teorico.dart';
import '../services/inventario_service.dart';
import '../services/teorico_service.dart';

class VerificacionScreen extends StatefulWidget {
  final String localizacion;
  final List<RegistroInventario> registros;

  const VerificacionScreen({
    super.key,
    required this.localizacion,
    required this.registros,
  });

  @override
  State<VerificacionScreen> createState() => _VerificacionScreenState();
}

class _VerificacionScreenState extends State<VerificacionScreen>
    with SingleTickerProviderStateMixin {
  final _teorico = TeoricoService();
  late TabController _tabCtrl;

  List<ActivoTeorico> _esperados  = [];
  List<ActivoTeorico> _faltantes  = [];
  List<RegistroInventario> _sobrantes = [];
  List<ActivoTeorico> _escaneados = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _calcular();
  }

  void _calcular() {
    _esperados = _teorico.activosDe(widget.localizacion);

    // Códigos escaneados en esta localización
    final escaneadosEnLoc = widget.registros
        .where((r) => r.localizacion.toUpperCase() == widget.localizacion)
        .map((r) => r.cveActivo.toUpperCase())
        .toSet();

    // Escaneados con info completa
    _escaneados = escaneadosEnLoc
        .map((c) => _teorico.buscarPorCodigo(c))
        .whereType<ActivoTeorico>()
        .toList();

    // Códigos teóricos de la ubicación
    final codigosTeoricoNuevo    = _esperados.map((a) => a.codigoNuevo).toSet();
    final codigosTeoricoAnterior = _esperados
        .where((a) => a.codigoAnterior.isNotEmpty)
        .map((a) => a.codigoAnterior)
        .toSet();

    // Faltantes: esperados pero NO escaneados
    _faltantes = _esperados.where((a) {
      return !escaneadosEnLoc.contains(a.codigoNuevo) &&
             !escaneadosEnLoc.contains(a.codigoAnterior);
    }).toList();

    // Sobrantes: escaneados en esta loc pero NO en el teórico
    _sobrantes = widget.registros.where((r) {
      if (r.localizacion.toUpperCase() != widget.localizacion) return false;
      final c = r.cveActivo.toUpperCase();
      final activo = _teorico.buscarPorCodigo(c);
      if (activo == null) return true; // No existe en el catálogo teórico
      return !codigosTeoricoNuevo.contains(activo.codigoNuevo) &&
             !codigosTeoricoAnterior.contains(activo.codigoAnterior);
    }).toList();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total     = _esperados.length;
    final escaneados = total - _faltantes.length;
    final pct = total > 0 ? escaneados / total : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text('Verificación ${widget.localizacion}'),
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
      body: Column(
        children: [
          // Resumen
          _buildResumen(total, escaneados, pct),
          // Pestañas
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildListaFaltantes(),
                _buildListaEscaneados(),
                _buildListaSobrantes(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumen(int total, int escaneados, double pct) {
    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat('Esperados', '$total', Colors.blue.shade700),
              _stat('Escaneados', '$escaneados', Colors.green.shade700),
              _stat('Faltantes', '${_faltantes.length}',
                  _faltantes.isEmpty ? Colors.green.shade700 : Colors.red.shade700),
              _stat('Sobrantes', '${_sobrantes.length}',
                  _sobrantes.isEmpty ? Colors.green.shade700 : Colors.orange.shade700),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 10,
              backgroundColor: Colors.red.shade100,
              valueColor: AlwaysStoppedAnimation(
                pct >= 1.0 ? Colors.green.shade600 : Colors.blue.shade600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(pct * 100).toStringAsFixed(1)}% completado',
            style: TextStyle(
              fontSize: 12,
              color: pct >= 1.0 ? Colors.green.shade700 : Colors.blue.shade700,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    );
  }

  // ── Pestaña Faltantes ──────────────────────────────────────────

  Widget _buildListaFaltantes() {
    if (_faltantes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 64),
            SizedBox(height: 8),
            Text('¡Todo escaneado!',
                style: TextStyle(
                    fontSize: 18,
                    color: Colors.green,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: _faltantes.length,
      itemBuilder: (_, i) => _cardActivo(_faltantes[i], Colors.red.shade50,
          Colors.red.shade700, Icons.error_outline),
    );
  }

  // ── Pestaña Escaneados ─────────────────────────────────────────

  Widget _buildListaEscaneados() {
    if (_escaneados.isEmpty) {
      return const Center(
          child: Text('Sin activos escaneados en esta ubicación',
              style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      itemCount: _escaneados.length,
      itemBuilder: (_, i) => _cardActivo(_escaneados[i], Colors.green.shade50,
          Colors.green.shade700, Icons.check_circle_outline),
    );
  }

  // ── Pestaña Sobrantes ──────────────────────────────────────────

  Widget _buildListaSobrantes() {
    if (_sobrantes.isEmpty) {
      return const Center(
          child: Text('Sin activos sobrantes',
              style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      itemCount: _sobrantes.length,
      itemBuilder: (_, i) {
        final r = _sobrantes[i];
        final activo = _teorico.buscarPorCodigo(r.cveActivo);
        if (activo != null) {
          return _cardActivo(activo, Colors.orange.shade50,
              Colors.orange.shade700, Icons.warning_amber_outlined);
        }
        return ListTile(
          leading: Icon(Icons.help_outline, color: Colors.orange.shade700),
          title: Text(r.cveActivo,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('No encontrado en catálogo teórico'),
          tileColor: Colors.orange.shade50,
        );
      },
    );
  }

  // ── Card con toda la info del activo ───────────────────────────

  Widget _cardActivo(ActivoTeorico a, Color bg, Color accent, IconData icon) {
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado: icono + código + descripción
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.codigoNuevo,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: accent)),
                      Text(a.descripcion,
                          style: const TextStyle(
                              fontWeight: FontWeight.w500, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            // Detalle en grid 2 columnas
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (a.marca.isNotEmpty)     _chip('Marca', a.marca),
                if (a.modelo.isNotEmpty)    _chip('Modelo', a.modelo),
                if (a.noSerie.isNotEmpty)   _chip('No. Serie', a.noSerie),
                if (a.nombre.isNotEmpty)    _chip('Responsable', a.nombre),
                if (a.empleado.isNotEmpty)  _chip('No. Empleado', a.empleado),
                if (a.codigoAnterior.isNotEmpty)
                  _chip('Cód. anterior', a.codigoAnterior),
                if (a.resguardo.isNotEmpty) _chip('Resguardo', a.resguardo),
                if (a.contrato.isNotEmpty)  _chip('Contrato', a.contrato),
              ],
            ),
          ],
        ),
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
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 11, color: Colors.black87),
          children: [
            TextSpan(
                text: '$label: ',
                style: const TextStyle(color: Colors.black54)),
            TextSpan(
                text: value,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
