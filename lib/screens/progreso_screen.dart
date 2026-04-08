import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../services/catalogo_service.dart';
import '../services/checkpoint_service.dart';
import '../services/inventario_service.dart';
import '../services/teorico_service.dart';
import '../services/ubicacion_service.dart';

class ProgresoScreen extends StatefulWidget {
  final List<RegistroInventario> registros;

  const ProgresoScreen({super.key, required this.registros});

  @override
  State<ProgresoScreen> createState() => _ProgresoScreenState();
}

class _ProgresoScreenState extends State<ProgresoScreen>
    with SingleTickerProviderStateMixin {
  final _catalogo    = CatalogoService();
  final _teorico     = TeoricoService();
  final _checkpoints = CheckpointService();
  final _ubicaciones = UbicacionService();

  late TabController _tabs;
  List<CheckpointEdificio> _historial = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _cargar();
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _cargar() async {
    final h = await _checkpoints.cargarCheckpoints();
    if (mounted) setState(() { _historial = h; _cargando = false; });
  }

  // ── Progreso actual por edificio (de registros activos) ───────────

  Map<String, _ResumenEdificio> _calcularProgreso() {
    final edificios = <String, _ResumenEdificio>{};

    for (final r in widget.registros) {
      if (r.localizacion.isEmpty) continue;
      final letra = r.localizacion[0].toUpperCase();
      edificios.putIfAbsent(letra, () => _ResumenEdificio(letra));
      edificios[letra]!.registros.add(r);
      edificios[letra]!.ubicaciones.add(r.localizacion.toUpperCase());
    }

    // Calcular ubicaciones totales teóricas por edificio
    for (final entry in edificios.entries) {
      final locs = _catalogo.localizacionesDeEdificio(entry.key);
      entry.value.ubicacionesTotales = locs.length;
    }

    return edificios;
  }

  // ── Guardar checkpoint del edificio ──────────────────────────────

  Future<void> _guardarCheckpoint(
      String letra, _ResumenEdificio resumen) async {
    final nombre = 'Edificio $letra';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.save_outlined,
            color: Colors.blue, size: 36),
        title: const Text('Guardar punto de control'),
        content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nombre,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Text('${resumen.registros.length} activos escaneados'),
          Text('${resumen.ubicaciones.length} / '
              '${resumen.ubicacionesTotales} ubicaciones'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Se generará un TXT exportable para SIGA con '
              'los registros de este edificio.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Detectar y ofrecer guardar cambios de ubicación
    final cambios = _ubicaciones.detectarCambios(resumen.registros);
    if (cambios.isNotEmpty && mounted) {
      await _mostrarCambiosUbicacion(cambios);
    }

    // Crear checkpoint
    final cp = await _checkpoints.crearCheckpoint(
      letra:               letra,
      nombre:              nombre,
      registros:           resumen.registros,
      ubicacionesCubiertas: resumen.ubicaciones.length,
      ubicacionesTotales:  resumen.ubicacionesTotales,
    );

    await _cargar();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✓ Checkpoint guardado: $nombre'),
        backgroundColor: Colors.green.shade700,
        action: SnackBarAction(
          label: 'Compartir TXT',
          textColor: Colors.white,
          onPressed: () => _compartirCheckpoint(cp),
        ),
      ));
    }
  }

  // ── Cerrar edificio (finalizar inventario) ────────────────────────

  Future<void> _cerrarEdificio(
      CheckpointEdificio cp, _ResumenEdificio? resumen) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline,
            color: Colors.green, size: 36),
        title: const Text('Finalizar edificio'),
        content: Text(
          '¿Marcar ${cp.nombre} como completado?\n\n'
          'Esta acción indica que terminaste el inventario '
          'de este edificio. Podrás seguir viendo el reporte '
          'pero no se podrán agregar más registros a este checkpoint.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final regs = resumen?.registros ??
        await _checkpoints.registrosDeCheckpoint(cp.id);
    final cambios = _ubicaciones.detectarCambios(regs);
    if (cambios.isNotEmpty && mounted) {
      await _mostrarCambiosUbicacion(cambios);
    }

    await _checkpoints.cerrarCheckpoint(
      cp.id, regs,
      ubicacionesCubiertas: resumen?.ubicaciones.length ?? cp.ubicacionesCubiertas,
      ubicacionesTotales:   resumen?.ubicacionesTotales ?? cp.ubicacionesTotales,
    );

    await _cargar();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✓ ${cp.nombre} marcado como completado'),
        backgroundColor: Colors.green.shade700,
      ));
    }
  }

  // ── Mostrar y guardar cambios de ubicación ────────────────────────

  Future<void> _mostrarCambiosUbicacion(
      List<CambioUbicacion> cambios) async {
    final guardar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [
          Icon(Icons.swap_horiz, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          const Text('Cambios de ubicación'),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: Column(children: [
            Text(
              '${cambios.length} activo(s) encontrados en una '
              'ubicación diferente a la teórica.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Expanded(child: ListView.builder(
              itemCount: cambios.length,
              itemBuilder: (_, i) {
                final c = cambios[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(c.cveActivo,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                      Text(c.descripcion,
                          style: const TextStyle(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ])),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                      Text(c.ubicacionAnterior,
                          style: TextStyle(
                              color: Colors.red.shade400,
                              fontSize: 11)),
                      const Icon(Icons.arrow_downward,
                          size: 12, color: Colors.grey),
                      Text(c.ubicacionNueva,
                          style: TextStyle(
                              color: Colors.green.shade600,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ]),
                  ]),
                );
              },
            )),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Ignorar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade600),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar cambios'),
          ),
        ],
      ),
    );

    if (guardar == true) {
      await _ubicaciones.guardarCambios(cambios);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '✓ ${cambios.length} cambios de ubicación guardados'),
          backgroundColor: Colors.orange.shade700,
        ));
      }
    }
  }

  // ── Compartir TXT de checkpoint ───────────────────────────────────

  Future<void> _compartirCheckpoint(CheckpointEdificio cp) async {
    final ruta = await _checkpoints.rutaTxtCheckpoint(cp.id);
    await Share.shareXFiles(
      [XFile(ruta)],
      subject: '${cp.nombre} — '
          '${DateFormat("dd/MM/yyyy").format(cp.fechaInicio)}',
    );
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Progreso por edificio'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Sesión actual'),
            Tab(text: 'Checkpoints'),
          ],
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tabs, children: [
              _buildSesionActual(),
              _buildCheckpoints(),
            ]),
    );
  }

  // ── Tab 1: Sesión actual por edificio ─────────────────────────────

  Widget _buildSesionActual() {
    final progreso = _calcularProgreso();

    if (progreso.isEmpty) {
      return const Center(
        child: Text('Sin registros en la sesión actual.',
            style: TextStyle(color: Colors.grey)),
      );
    }

    final edificios = progreso.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: edificios.length,
      itemBuilder: (_, i) {
        final letra   = edificios[i].key;
        final resumen = edificios[i].value;
        final pct     = resumen.ubicacionesTotales > 0
            ? resumen.ubicaciones.length / resumen.ubicacionesTotales
            : 0.0;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primary,
                  child: Text(letra,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Edificio $letra',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  Text('${resumen.registros.length} activos  '
                      '· ${resumen.ubicaciones.length} / '
                      '${resumen.ubicacionesTotales} ubicaciones',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey)),
                ])),
                // Botón guardar checkpoint
                ElevatedButton.icon(
                  onPressed: () =>
                      _guardarCheckpoint(letra, resumen),
                  icon: const Icon(Icons.save_outlined, size: 16),
                  label: const Text('Checkpoint',
                      style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              // Barra de progreso
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct, minHeight: 8,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(
                      pct >= 1.0
                          ? Colors.green.shade500
                          : Colors.blue.shade500),
                ),
              ),
              const SizedBox(height: 4),
              Text('${(pct * 100).toStringAsFixed(1)}% completado',
                  style: TextStyle(
                      fontSize: 11,
                      color: pct >= 1.0
                          ? Colors.green.shade600
                          : Colors.blue.shade600)),
            ]),
          ),
        );
      },
    );
  }

  // ── Tab 2: Checkpoints guardados ──────────────────────────────────

  Widget _buildCheckpoints() {
    if (_historial.isEmpty) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bookmark_border,
              size: 64, color: Colors.black26),
          const SizedBox(height: 12),
          const Text('Sin checkpoints guardados',
              style: TextStyle(
                  fontSize: 16, color: Colors.black45)),
          const SizedBox(height: 6),
          Text(
            'Guarda un punto de control desde\nla pestaña "Sesión actual".',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13, color: Colors.grey.shade500)),
        ],
      ));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: _historial.length,
      itemBuilder: (_, i) => _cardCheckpoint(_historial[i]),
    );
  }

  Widget _cardCheckpoint(CheckpointEdificio cp) {
    final fechaStr = DateFormat('dd/MM/yyyy HH:mm').format(cp.fechaInicio);
    final cierreStr = cp.fechaCierre != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(cp.fechaCierre!)
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: cp.cerrado
            ? BorderSide(color: Colors.green.shade300, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: cp.cerrado
                  ? Colors.green.shade600
                  : Theme.of(context).colorScheme.primary,
              child: Text(cp.letra,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(cp.nombre,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(width: 6),
                if (cp.cerrado)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.shade600,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('COMPLETADO',
                        style: TextStyle(
                            color: Colors.white, fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ),
              ]),
              Text(fechaStr,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.grey)),
              if (cierreStr != null)
                Text('Cerrado: $cierreStr',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.green.shade600)),
            ])),
          ]),
          const SizedBox(height: 10),
          // Progreso
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: cp.porcentaje, minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(
                  cp.cerrado ? Colors.green.shade500 : Colors.blue.shade500),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${cp.totalRegistros} activos  '
            '· ${cp.ubicacionesCubiertas} / ${cp.ubicacionesTotales} ubicaciones'
            '  · ${(cp.porcentaje * 100).toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          // Acciones
          Row(children: [
            // Compartir TXT
            Expanded(child: OutlinedButton.icon(
              onPressed: () => _compartirCheckpoint(cp),
              icon: const Icon(Icons.description_outlined, size: 16),
              label: const Text('TXT (SIGA)',
                  style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue.shade700,
                side: BorderSide(color: Colors.blue.shade300),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            )),
            const SizedBox(width: 8),
            // Finalizar / ya cerrado
            if (!cp.cerrado)
              Expanded(child: OutlinedButton.icon(
                onPressed: () => _cerrarEdificio(cp, null),
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('Finalizar',
                    style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green.shade700,
                  side: BorderSide(color: Colors.green.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ))
            else
              Expanded(child: OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.check_circle, size: 16),
                label: const Text('Completado',
                    style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green.shade400,
                  side: BorderSide(color: Colors.green.shade200),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              )),
            const SizedBox(width: 8),
            // Eliminar
            IconButton(
              icon: Icon(Icons.delete_outline,
                  color: Colors.red.shade400),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('¿Eliminar checkpoint?'),
                    content: Text(
                        '¿Eliminar el checkpoint de ${cp.nombre}?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancelar')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Eliminar'),
                      ),
                    ],
                  ),
                ) ?? false;
                if (ok) {
                  await _checkpoints.eliminarCheckpoint(cp.id);
                  await _cargar();
                }
              },
              tooltip: 'Eliminar checkpoint',
            ),
          ]),
        ]),
      ),
    );
  }
}

// ── Resumen interno ───────────────────────────────────────────────

class _ResumenEdificio {
  final String letra;
  final List<RegistroInventario> registros = [];
  final Set<String>              ubicaciones = {};
  int ubicacionesTotales = 0;

  _ResumenEdificio(this.letra);
}
