import 'package:flutter/material.dart';
import '../services/sync_service.dart';

// ── Widget de estado de sincronización ───────────────────────
// Pequeño indicador que aparece en el AppBar

class SyncStatusWidget extends StatelessWidget {
  const SyncStatusWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = SyncService();
    return StreamBuilder<SyncStatus>(
      stream: sync.statusStream,
      initialData: sync.status,
      builder: (_, snap) {
        final s = snap.data ?? sync.status;
        return GestureDetector(
          onTap: () => _mostrarDetalle(context, s),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _icono(s),
              const SizedBox(width: 4),
              _etiqueta(s),
            ]),
          ),
        );
      },
    );
  }

  Widget _icono(SyncStatus s) {
    switch (s.estado) {
      case EstadoSync.ok:
        return const Icon(Icons.cloud_done_outlined,
            color: Colors.greenAccent, size: 18);
      case EstadoSync.sincronizando:
        return const SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white70));
      case EstadoSync.sinConexion:
        return Badge(
          label: Text('${s.pendientes}',
              style: const TextStyle(fontSize: 9)),
          child: const Icon(Icons.cloud_off_outlined,
              color: Colors.orangeAccent, size: 18),
        );
      case EstadoSync.error:
        return const Icon(Icons.cloud_off,
            color: Colors.redAccent, size: 18);
      case EstadoSync.inactivo:
        return const Icon(Icons.cloud_outlined,
            color: Colors.white38, size: 18);
    }
  }

  Widget _etiqueta(SyncStatus s) {
    String txt;
    Color  color;
    switch (s.estado) {
      case EstadoSync.ok:
        txt   = 'Sync';        color = Colors.greenAccent;  break;
      case EstadoSync.sincronizando:
        txt   = 'Sync...';     color = Colors.white70;      break;
      case EstadoSync.sinConexion:
        txt   = 'Offline';     color = Colors.orangeAccent; break;
      case EstadoSync.error:
        txt   = 'Error';       color = Colors.redAccent;    break;
      case EstadoSync.inactivo:
        txt   = 'Sin sync';    color = Colors.white38;      break;
    }
    return Text(txt,
        style: TextStyle(color: color, fontSize: 11,
            fontWeight: FontWeight.w500));
  }

  void _mostrarDetalle(BuildContext context, SyncStatus s) {
    final sync = SyncService();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sincronización'),
        content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          _fila('Estado', _textoEstado(s.estado)),
          if (s.pendientes > 0)
            _fila('Pendientes', '${s.pendientes} registros sin enviar'),
          if (s.ultimaSync != null)
            _fila('Última sync',
                _formatFecha(s.ultimaSync!)),
          if (s.error != null)
            _fila('Error', s.error!),
          const SizedBox(height: 8),
          Text(
            'Los registros se sincronizan cada '
            '${SupabaseConfig.syncIntervalSeg}s. '
            'Si no hay WiFi, se guardan localmente y se envían '
            'al recuperar la conexión.',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ]),
        actions: [
          if (s.pendientes > 0)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                sync.sincronizarPendientes();
              },
              child: const Text('Sincronizar ahora'),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _fila(String label, String valor) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 100,
          child: Text('$label:',
              style: const TextStyle(fontWeight: FontWeight.bold,
                  fontSize: 13))),
      Expanded(child: Text(valor,
          style: const TextStyle(fontSize: 13))),
    ]),
  );

  String _textoEstado(EstadoSync e) {
    switch (e) {
      case EstadoSync.ok:          return '✓ Sincronizado';
      case EstadoSync.sincronizando: return '⟳ Sincronizando...';
      case EstadoSync.sinConexion: return '⚠ Sin conexión — modo offline';
      case EstadoSync.error:       return '✗ Error de conexión';
      case EstadoSync.inactivo:    return '○ No iniciado';
    }
  }

  String _formatFecha(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60)  return 'Hace ${diff.inSeconds}s';
    if (diff.inMinutes < 60)  return 'Hace ${diff.inMinutes}min';
    return 'Hace ${diff.inHours}h';
  }
}
