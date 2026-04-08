import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';

import '../services/mapa_service.dart';

class MapaScreen extends StatefulWidget {
  final String? localizacion;

  const MapaScreen({super.key, this.localizacion});

  @override
  State<MapaScreen> createState() => _MapaScreenState();
}

class _MapaScreenState extends State<MapaScreen> {
  final _servicio = MapaService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.localizacion != null) {
        final mapa = _servicio.mapaDeLocalizacion(widget.localizacion);
        if (mapa != null) _abrirEdificio(mapa);
      }
    });
  }

  void _abrirEdificio(MapaEdificio mapa) {
    if (mapa.assets.length == 1) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => _VisorPdf(
          titulo:    mapa.nombre,
          assetPath: mapa.assets.first,
        ),
      ));
    } else {
      _mostrarSelectorPlantas(mapa);
    }
  }

  void _mostrarSelectorPlantas(MapaEdificio mapa) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(mapa.nombre,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 4),
          Text('Selecciona la planta:',
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          ...mapa.assets.map((asset) {
            final nombre = _nombreLegible(mapa.letra, asset);
            return ListTile(
              leading: Icon(Icons.map_outlined,
                  color: Theme.of(context).colorScheme.primary),
              title: Text(nombre),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => _VisorPdf(
                    titulo:    '${mapa.nombre} — $nombre',
                    assetPath: asset,
                  ),
                ));
              },
            );
          }),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  String _nombreLegible(String letra, String assetPath) {
    return assetPath
        .split('/').last
        .replaceAll('.pdf', '')
        .replaceAll('ED_${letra}_', '')
        .replaceAll('_', ' ')
        .toLowerCase()
        .split(' ')
        .map((w) => w.isEmpty
            ? ''
            : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final todos = _servicio.todos;

    return Scaffold(
      appBar: AppBar(title: const Text('Mapas de edificios')),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: todos.length,
        itemBuilder: (_, i) {
          final mapa   = todos[i];
          final esActual = widget.localizacion != null &&
              widget.localizacion![0].toUpperCase() == mapa.letra;

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: esActual
                  ? BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2)
                  : BorderSide.none,
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: esActual
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context)
                        .colorScheme.surfaceContainerHighest,
                child: Text(mapa.letra,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: esActual ? Colors.white : null)),
              ),
              title: Text(mapa.nombre,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text(
                mapa.assets.length > 1
                    ? '${mapa.assets.length} plantas'
                    : '1 plano',
                style: const TextStyle(fontSize: 12)),
              trailing: esActual
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('Actual',
                          style: TextStyle(
                              color: Colors.white, fontSize: 11)),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: () => _abrirEdificio(mapa),
            ),
          );
        },
      ),
    );
  }
}

// ── Visor PDF con pdfx ────────────────────────────────────────────

class _VisorPdf extends StatefulWidget {
  final String titulo;
  final String assetPath;

  const _VisorPdf({required this.titulo, required this.assetPath});

  @override
  State<_VisorPdf> createState() => _VisorPdfState();
}

class _VisorPdfState extends State<_VisorPdf> {
  PdfControllerPinch? _ctrl;
  bool  _cargando = true;
  bool  _error    = false;
  int   _pagActual = 1;
  int   _pagTotal  = 1;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final bytes = await rootBundle.load(widget.assetPath);
      final ctrl  = PdfControllerPinch(
        document: PdfDocument.openData(
            bytes.buffer.asUint8List()),
      );
      ctrl.addListener(() {
        if (mounted) {
          setState(() => _pagActual = ctrl.page);
        }
      });
      final doc = await ctrl.document;
      if (mounted) {
        setState(() {
          _ctrl     = ctrl;
          _pagTotal = doc.pagesCount;
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _cargando = false; _error = true; });
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo,
            style: const TextStyle(fontSize: 14),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (!_cargando && !_error && _pagTotal > 1)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 14),
              child: Text('$_pagActual / $_pagTotal',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13)),
            ),
        ],
      ),
      body: _buildCuerpo(),
    );
  }

  Widget _buildCuerpo() {
    if (_cargando) {
      return const Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Cargando plano...'),
        ],
      ));
    }

    if (_error || _ctrl == null) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 56),
          const SizedBox(height: 12),
          const Text('No se pudo cargar el plano'),
          const SizedBox(height: 4),
          Text(widget.assetPath,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ));
    }

    return Stack(children: [
      // Visor con pinch-to-zoom nativo
      PdfViewPinch(
        controller: _ctrl!,
        scrollDirection: Axis.vertical,
        padding: 8,
        onPageChanged: (page) {
          if (mounted) setState(() => _pagActual = page);
        },
        builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
          options: const DefaultBuilderOptions(),
          documentLoaderBuilder: (_) =>
              const Center(child: CircularProgressIndicator()),
          pageLoaderBuilder: (_) =>
              const Center(child: CircularProgressIndicator()),
          errorBuilder: (_, err) =>
              Center(child: Text('Error: $err')),
        ),
      ),
      // Hint de zoom
      Positioned(
        bottom: 16, right: 16,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.pinch_outlined, color: Colors.white70, size: 14),
            SizedBox(width: 4),
            Text('Pellizca para hacer zoom',
                style: TextStyle(color: Colors.white70, fontSize: 11)),
          ]),
        ),
      ),
    ]);
  }
}
