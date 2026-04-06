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

  String _busqueda = '';
  final _busCtrl   = TextEditingController();

  int _totalTeorico    = 0;
  int _totalEscaneados = 0;

  Map<String, _Dato> _porLoc      = {};
  Map<String, _Dato> _porEmpleado = {};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _calcular();
  }

  // ── Edificio de una clave ─────────────────────────────────────────

  static String _edificioDe(String clave) {
    final c = clave.toUpperCase().trim();
    if (c.startsWith('EXT.') && c.length > 4) return c[4];
    if (c.startsWith('QS'))   return 'Q';
    if (c.startsWith('GP'))   return 'G';
    if (RegExp(r'^L[ABOPZ]\d').hasMatch(c)) return 'L';
    if (['LTRAN','LUPS','LIDF','LCOM'].contains(c)) return 'L';
    if (c.startsWith('MENA')) return 'M';
    if (['PLAZA','VARI','VARIA','VARIO','VEST','VESTI',
         'S000','PD','BORRA','FUERA'].contains(c)) return 'VARIOS';
    final m = RegExp(r'^([A-Z])').firstMatch(c);
    return m != null ? m.group(1)! : 'OTROS';
  }

  static String _nombreEdificio(String letra) {
    const nombres = {
      'A':'Edificio A','B':'Edificio B','C':'Edificio C',
      'D':'Edificio D','E':'Edificio E','F':'Edificio F',
      'G':'Edificio G','H':'Edificio H','I':'Edificio I',
      'J':'Edificio J','K':'Edificio K','L':'Edificio L',
      'M':'Edificio M','N':'Edificio N','O':'Edificio O',
      'P':'Edificio P','Q':'Edificio Q','R':'Edificio R',
      'T':'Edificio T','U':'Edificio U','Z':'Áreas Exteriores',
      'VARIOS':'Varios / Generales',
    };
    return nombres[letra] ?? 'Edificio $letra';
  }

  // ── Cálculo ───────────────────────────────────────────────────────

  void _calcular() {
    final escSet = widget.registros
        .map((r) => r.cveActivo.toUpperCase())
        .toSet();

    int escaneados = 0;
    final porLoc = <String, _Dato>{};
    final porEmp = <String, _Dato>{};

    for (final loc in _teorico.localizaciones) {
      final activos = _teorico.activosDe(loc);
      if (activos.isEmpty) continue;

      porLoc[loc] = _Dato(loc, activos.first.ubicaDesc, activos.length, 0);

      for (final a in activos) {
        final esc = escSet.contains(a.codigoNuevo.toUpperCase()) ||
            (a.codigoAnterior.isNotEmpty &&
                escSet.contains(a.codigoAnterior));
        if (esc) {
          escaneados++;
          porLoc[loc]!.escaneados++;
        }

        final emp = a.nombre.trim();
        if (emp.isNotEmpty && emp != 'Almacen') {
          porEmp.putIfAbsent(emp, () => _Dato(emp, '', 0, 0));
          porEmp[emp]!.total++;
          if (esc) porEmp[emp]!.escaneados++;
        }
      }
    }

    _totalTeorico    = _teorico.total;
    _totalEscaneados = escaneados;
    _porLoc          = porLoc;
    _porEmpleado     = porEmp;
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
    final pct = _totalTeorico > 0 ? _totalEscaneados / _totalTeorico : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard de progreso'),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          onTap: (_) => setState(() {
            _busqueda = '';
            _busCtrl.clear();
          }),
          tabs: const [
            Tab(icon: Icon(Icons.location_on_outlined), text: 'Ubicaciones'),
            Tab(icon: Icon(Icons.person_outline),       text: 'Empleados'),
          ],
        ),
      ),
      body: Column(children: [
        _buildResumenGlobal(pct),
        _buildBuscador(),
        Expanded(child: TabBarView(
          controller: _tabCtrl,
          children: [
            _buildTabUbicaciones(),
            _buildTabEmpleados(),
          ],
        )),
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
        Row(children: [
          _statCard('Total\nactivos',  '$_totalTeorico',    Colors.white,
              Colors.white.withOpacity(0.15)),
          const SizedBox(width: 8),
          _statCard('Escaneados', '$_totalEscaneados', Colors.green.shade300,
              Colors.green.withOpacity(0.15)),
          const SizedBox(width: 8),
          _statCard('Pendientes', '$faltan',
              faltan == 0 ? Colors.green.shade300 : Colors.orange.shade300,
              Colors.orange.withOpacity(0.12)),
          const SizedBox(width: 8),
          _statCard('Progreso',
              '${(pct * 100).toStringAsFixed(1)}%',
              Colors.white, Colors.white.withOpacity(0.12)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct, minHeight: 12,
            backgroundColor: Colors.white.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation(
                pct >= 1.0 ? Colors.green.shade400 : Colors.white),
          ),
        ),
      ]),
    );
  }

  Widget _statCard(String label, String value, Color vc, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(8)),
        child: Column(children: [
          Text(value, style: TextStyle(
              color: vc, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ]),
      ),
    );
  }

  // ── Buscador ──────────────────────────────────────────────────────

  Widget _buildBuscador() {
    final hint = _tabCtrl.index == 0
        ? 'Buscar por clave, nombre o edificio...'
        : 'Buscar empleado...';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: TextField(
        controller: _busCtrl,
        decoration: InputDecoration(
          hintText: hint,
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

  // ── Tab Ubicaciones ───────────────────────────────────────────────

  Widget _buildTabUbicaciones() {
    var items = _porLoc.values.toList();

    if (_busqueda.isNotEmpty) {
      final q = _busqueda.toUpperCase();
      items = items.where((d) =>
          d.clave.contains(q) ||
          d.desc.toUpperCase().contains(q) ||
          // Buscar también por nombre o letra de edificio
          _edificioDe(d.clave).contains(q) ||
          _nombreEdificio(_edificioDe(d.clave)).toUpperCase().contains(q),
      ).toList();
    }

    items.sort((a, b) {
      if (a.pct == 1.0 && b.pct < 1.0) return 1;
      if (b.pct == 1.0 && a.pct < 1.0) return -1;
      return a.pct.compareTo(b.pct);
    });

    if (items.isEmpty) {
      return const Center(child: Text('Sin resultados',
          style: TextStyle(color: Colors.grey)));
    }

    // Cabecera con total filtrado
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${items.length} ubicaciones',
              style: const TextStyle(color: Colors.black45, fontSize: 12)),
          Text(
            '${items.where((d) => d.pct >= 1.0).length} completas',
            style: TextStyle(color: Colors.green.shade600, fontSize: 12,
                fontWeight: FontWeight.w500),
          ),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: items.length,
          itemBuilder: (_, i) => _filaDato(items[i], mostrarEdificio: true),
        ),
      ),
    ]);
  }

  // ── Tab Empleados ─────────────────────────────────────────────────

  Widget _buildTabEmpleados() {
    var items = _porEmpleado.values.toList();

    if (_busqueda.isNotEmpty) {
      final q = _busqueda.toUpperCase();
      items = items.where((d) => d.clave.toUpperCase().contains(q)).toList();
    }

    items.sort((a, b) {
      if (a.pct == 1.0 && b.pct < 1.0) return 1;
      if (b.pct == 1.0 && a.pct < 1.0) return -1;
      return a.pct.compareTo(b.pct);
    });

    if (items.isEmpty) {
      return const Center(child: Text('Sin resultados',
          style: TextStyle(color: Colors.grey)));
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${items.length} empleados',
              style: const TextStyle(color: Colors.black45, fontSize: 12)),
          Text(
            '${items.where((d) => d.pct >= 1.0).length} completos',
            style: TextStyle(color: Colors.green.shade600, fontSize: 12,
                fontWeight: FontWeight.w500),
          ),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: items.length,
          itemBuilder: (_, i) => _filaDato(items[i], esEmpleado: true),
        ),
      ),
    ]);
  }

  // ── Fila genérica ─────────────────────────────────────────────────

  Widget _filaDato(_Dato d,
      {bool esEmpleado = false, bool mostrarEdificio = false}) {
    final completo = d.pct >= 1.0;
    final color    = completo ? Colors.green.shade600
        : d.pct > 0.5 ? Colors.orange.shade600
        : Colors.red.shade600;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: completo ? Colors.green.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: completo ? Colors.green.shade200 : Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            esEmpleado
                ? (completo ? Icons.person : Icons.person_outline)
                : (completo ? Icons.location_on : Icons.location_on_outlined),
            color: color, size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(d.clave, style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13, color: color)),
              // Etiqueta de edificio en ubicaciones
              if (mostrarEdificio) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _nombreEdificio(_edificioDe(d.clave)),
                    style: TextStyle(fontSize: 10, color: color),
                  ),
                ),
              ],
            ]),
            if (d.desc.isNotEmpty)
              Text(d.desc,
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${d.escaneados}/${d.total}',
                style: TextStyle(fontWeight: FontWeight.bold,
                    fontSize: 13, color: color)),
            Text('${(d.pct * 100).toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 11, color: color)),
          ]),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: d.pct, minHeight: 6,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        if (!completo && d.total - d.escaneados <= 5) ...[
          const SizedBox(height: 3),
          Text(
            'Faltan ${d.total - d.escaneados} '
            'activo${d.total - d.escaneados == 1 ? "" : "s"}',
            style: TextStyle(fontSize: 10,
                color: Colors.orange.shade700,
                fontWeight: FontWeight.w500),
          ),
        ],
      ]),
    );
  }
}

// ── Modelo interno ────────────────────────────────────────────────

class _Dato {
  final String clave;
  final String desc;
  int total;
  int escaneados;

  _Dato(this.clave, this.desc, this.total, this.escaneados);

  double get pct => total > 0 ? escaneados / total : 0.0;
}
