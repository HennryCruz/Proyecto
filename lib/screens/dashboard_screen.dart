import 'package:flutter/material.dart';

import '../models/activo_teorico.dart';
import '../services/inventario_service.dart';
import '../services/teorico_service.dart';

class DashboardScreen extends StatefulWidget {
  final List<RegistroInventario> registros;

  const DashboardScreen({super.key, required this.registros});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  final _teorico = TeoricoService();
  late TabController _tabCtrl;

  // Vista activa del desglose
  _Vista _vistaActual = _Vista.localizacion;
  String _busqueda = '';
  final _busCtrl = TextEditingController();

  // Datos calculados
  int _totalTeorico    = 0;
  int _totalEscaneados = 0;
  Map<String, _ProgresoDato> _porLocalizacion = {};
  Map<String, _ProgresoDato> _porEmpleado     = {};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _calcular();
  }

  void _calcular() {
    final todos = _teorico.total;
    _totalTeorico = todos;

    // Set de códigos escaneados
    final escSet = widget.registros
        .map((r) => r.cveActivo.toUpperCase())
        .toSet();

    // Contar escaneados únicos que están en el teórico
    int escaneados = 0;

    // Por localización
    final porLoc = <String, _ProgresoDato>{};
    // Por empleado
    final porEmp = <String, _ProgresoDato>{};

    for (final activo in _iterar()) {
      final loc  = activo.localizacion;
      final emp  = activo.nombre.trim();

      final escaneado =
          escSet.contains(activo.codigoNuevo.toUpperCase()) ||
          (activo.codigoAnterior.isNotEmpty &&
              escSet.contains(activo.codigoAnterior));

      if (escaneado) escaneados++;

      // Localización
      porLoc.putIfAbsent(loc, () => _ProgresoDato(loc,
          _teorico.activosDe(loc).length > 0
              ? _teorico.activosDe(loc).first.ubicaDesc
              : ''));
      if (escaneado) porLoc[loc]!.escaneados++;

      // Empleado
      if (emp.isNotEmpty && emp != 'Almacen') {
        porEmp.putIfAbsent(emp, () => _ProgresoDato(emp, ''));
        porEmp[emp]!.total++;
        if (escaneado) porEmp[emp]!.escaneados++;
      }
    }

    // Fijar totales de localización desde el teórico
    for (final key in porLoc.keys) {
      porLoc[key]!.total = _teorico.activosDe(key).length;
    }

    _totalEscaneados  = escaneados;
    _porLocalizacion  = porLoc;
    _porEmpleado      = porEmp;
  }

  Iterable<ActivoTeorico> _iterar() sync* {
    for (final loc in _teorico.localizaciones) {
      for (final a in _teorico.activosDe(loc)) {
        yield a;
      }
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _busCtrl.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pct = _totalTeorico > 0
        ? _totalEscaneados / _totalTeorico
        : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard de progreso'),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          onTap: (i) => setState(() =>
              _vistaActual = i == 0 ? _Vista.localizacion : _Vista.empleado),
          tabs: const [
            Tab(icon: Icon(Icons.location_on_outlined), text: 'Por ubicación'),
            Tab(icon: Icon(Icons.person_outline),       text: 'Por empleado'),
          ],
        ),
      ),
      body: Column(children: [
        // ── Resumen global ──────────────────────────────────────────
        _buildResumenGlobal(pct),
        // ── Buscador ───────────────────────────────────────────────
        _buildBuscador(),
        // ── Lista ──────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildListaLocalizaciones(),
              _buildListaEmpleados(),
            ],
          ),
        ),
      ]),
    );
  }

  // ── Resumen global ────────────────────────────────────────────────

  Widget _buildResumenGlobal(double pct) {
    final faltan = _totalTeorico - _totalEscaneados;

    return Container(
      color: const Color(0xFF1B4F8A),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(children: [
        // Tarjetas de stats
        Row(children: [
          _statCard('Total\nactivos',    '$_totalTeorico',    Colors.white,
              Colors.white.withOpacity(0.15)),
          const SizedBox(width: 8),
          _statCard('Escaneados',        '$_totalEscaneados', Colors.green.shade300,
              Colors.green.withOpacity(0.15)),
          const SizedBox(width: 8),
          _statCard('Pendientes',        '$faltan',
              faltan == 0 ? Colors.green.shade300 : Colors.orange.shade300,
              Colors.orange.withOpacity(0.12)),
          const SizedBox(width: 8),
          _statCard('Progreso',
              '${(pct * 100).toStringAsFixed(1)}%',
              Colors.white,
              Colors.white.withOpacity(0.12)),
        ]),
        const SizedBox(height: 10),
        // Barra global
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 12,
            backgroundColor: Colors.white.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation(
                pct >= 1.0 ? Colors.green.shade400 : Colors.white),
          ),
        ),
      ]),
    );
  }

  Widget _statCard(String label, String value, Color valueColor, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(children: [
          Text(value, style: TextStyle(
              color: valueColor, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ]),
      ),
    );
  }

  // ── Buscador ──────────────────────────────────────────────────────

  Widget _buildBuscador() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: TextField(
        controller: _busCtrl,
        decoration: InputDecoration(
          hintText: _vistaActual == _Vista.localizacion
              ? 'Buscar ubicación...' : 'Buscar empleado...',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          suffixIcon: _busqueda.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _busCtrl.clear();
                    setState(() => _busqueda = '');
                  })
              : null,
        ),
        onChanged: (v) => setState(() => _busqueda = v),
      ),
    );
  }

  // ── Lista por localización ────────────────────────────────────────

  Widget _buildListaLocalizaciones() {
    var items = _porLocalizacion.values.toList();

    // Filtrar
    if (_busqueda.isNotEmpty) {
      final q = _busqueda.toUpperCase();
      items = items.where((d) =>
          d.clave.contains(q) || d.desc.toUpperCase().contains(q)).toList();
    }

    // Ordenar: primero las incompletas, luego por porcentaje asc
    items.sort((a, b) {
      final pA = a.total > 0 ? a.escaneados / a.total : 0.0;
      final pB = b.total > 0 ? b.escaneados / b.total : 0.0;
      if (pA == 1.0 && pB < 1.0) return 1;
      if (pB == 1.0 && pA < 1.0) return -1;
      return pA.compareTo(pB);
    });

    if (items.isEmpty) {
      return const Center(child: Text('Sin resultados',
          style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (_, i) => _filaDato(items[i]),
    );
  }

  // ── Lista por empleado ────────────────────────────────────────────

  Widget _buildListaEmpleados() {
    var items = _porEmpleado.values.toList();

    if (_busqueda.isNotEmpty) {
      final q = _busqueda.toUpperCase();
      items = items.where((d) => d.clave.toUpperCase().contains(q)).toList();
    }

    items.sort((a, b) {
      final pA = a.total > 0 ? a.escaneados / a.total : 0.0;
      final pB = b.total > 0 ? b.escaneados / b.total : 0.0;
      if (pA == 1.0 && pB < 1.0) return 1;
      if (pB == 1.0 && pA < 1.0) return -1;
      return pA.compareTo(pB);
    });

    if (items.isEmpty) {
      return const Center(child: Text('Sin resultados',
          style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (_, i) => _filaDato(items[i], esEmpleado: true),
    );
  }

  // ── Fila de progreso individual ───────────────────────────────────

  Widget _filaDato(_ProgresoDato d, {bool esEmpleado = false}) {
    final pct     = d.total > 0 ? d.escaneados / d.total : 0.0;
    final completo = pct >= 1.0;
    final color    = completo
        ? Colors.green.shade600
        : pct > 0.5
            ? Colors.orange.shade600
            : Colors.red.shade600;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: completo ? Colors.green.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: completo
                ? Colors.green.shade200
                : Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Icono
          Icon(
            esEmpleado
                ? (completo ? Icons.person : Icons.person_outline)
                : (completo ? Icons.location_on : Icons.location_on_outlined),
            color: color, size: 18,
          ),
          const SizedBox(width: 8),
          // Clave / nombre
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.clave,
                  style: TextStyle(fontWeight: FontWeight.bold,
                      fontSize: 13, color: color)),
              if (d.desc.isNotEmpty)
                Text(d.desc,
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          // Contador
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${d.escaneados}/${d.total}',
                style: TextStyle(fontWeight: FontWeight.bold,
                    fontSize: 13, color: color)),
            Text('${(pct * 100).toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 11, color: color)),
          ]),
        ]),
        const SizedBox(height: 6),
        // Barra de progreso individual
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        // Indicador visual de faltantes
        if (!completo && d.total - d.escaneados <= 5) ...[
          const SizedBox(height: 4),
          Text(
            'Faltan ${d.total - d.escaneados} activo${d.total - d.escaneados == 1 ? "" : "s"}',
            style: TextStyle(
                fontSize: 11,
                color: Colors.orange.shade700,
                fontWeight: FontWeight.w500),
          ),
        ],
      ]),
    );
  }
}

// ── Modelos internos ──────────────────────────────────────────────

enum _Vista { localizacion, empleado }

class _ProgresoDato {
  final String clave;
  final String desc;
  int total     = 0;
  int escaneados = 0;

  _ProgresoDato(this.clave, this.desc);
}
