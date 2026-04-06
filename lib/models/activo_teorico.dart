// Modelo de datos del Excel teórico
class ActivoTeorico {
  final String codigoNuevo;
  final String descripcion;
  final String marca;
  final String modelo;
  final String noSerie;
  final String empleado;
  final String nombre;
  final String localizacion;
  final String ubicaDesc;
  final String codigoAnterior;
  final String contrato;
  final String factura;
  final String resguardo;

  const ActivoTeorico({
    required this.codigoNuevo,
    required this.descripcion,
    required this.marca,
    required this.modelo,
    required this.noSerie,
    required this.empleado,
    required this.nombre,
    required this.localizacion,
    required this.ubicaDesc,
    required this.codigoAnterior,
    required this.contrato,
    required this.factura,
    required this.resguardo,
  });

  factory ActivoTeorico.fromCsv(List<String> row) {
    String s(int i) => i < row.length ? row[i].trim() : '';
    return ActivoTeorico(
      codigoNuevo:     s(0).toUpperCase(),
      descripcion:     s(1),
      marca:           s(2),
      modelo:          s(3),
      noSerie:         s(4),
      empleado:        s(5),
      nombre:          s(6),
      localizacion:    s(7).toUpperCase(),
      ubicaDesc:       s(8),
      codigoAnterior:  s(9),
      contrato:        s(10),
      factura:         s(11),
      resguardo:       s(12),
    );
  }
}
