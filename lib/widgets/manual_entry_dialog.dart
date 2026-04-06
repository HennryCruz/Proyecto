import 'package:flutter/material.dart';
import '../services/catalogo_service.dart';

class ManualEntryDialog extends StatefulWidget {
  final String cveLocalizacion;

  const ManualEntryDialog({super.key, required this.cveLocalizacion});

  @override
  State<ManualEntryDialog> createState() => _ManualEntryDialogState();
}

class _ManualEntryDialogState extends State<ManualEntryDialog> {
  final _ctrl = TextEditingController();
  final _catalogo = CatalogoService();
  String _descripcion = '';
  bool _valido = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final cve = _catalogo.normalizarCveActivo(value);
    final desc = _catalogo.descripcionActivo(cve);
    setState(() {
      _descripcion = desc;
      _valido = desc.isNotEmpty;
    });
  }

  void _guardar() {
    if (!_valido) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Se requiere un activo válido'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final cve = _catalogo.normalizarCveActivo(_ctrl.text);
    Navigator.of(context).pop(cve);
  }

  @override
  Widget build(BuildContext context) {
    final descLoc =
        _catalogo.descripcionLocalizacion(widget.cveLocalizacion);

    return AlertDialog(
      title: const Text('Registrar activo manualmente'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Localización: ${widget.cveLocalizacion}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (descLoc.isNotEmpty)
            Text(
              descLoc,
              style: TextStyle(
                  color: Colors.blue.shade800, fontSize: 13),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Clave del activo',
              hintText: 'Ej: I14905 o C00123',
              border: OutlineInputBorder(),
            ),
            onChanged: _onChanged,
            onSubmitted: (_) => _guardar(),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _valido
                  ? Colors.green.shade50
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _valido
                    ? Colors.green.shade300
                    : Colors.grey.shade300,
              ),
            ),
            child: Text(
              _descripcion.isNotEmpty
                  ? _descripcion
                  : 'Ingresa una clave válida',
              style: TextStyle(
                color: _valido
                    ? Colors.green.shade800
                    : Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _valido ? _guardar : null,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
