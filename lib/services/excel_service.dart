import 'dart:io';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/activo_teorico.dart';
import '../services/inventario_service.dart';
import '../services/teorico_service.dart';

class ExcelService {
  static final ExcelService _i = ExcelService._();
  factory ExcelService() => _i;
  ExcelService._();

  final _teorico = TeoricoService();

  // Colores
  static final _azulOscuro = ExcelColor.fromHexString('FF1B4F8A');
  static final _azulClaro  = ExcelColor.fromHexString('FFD6E4F0');
  static final _verde      = ExcelColor.fromHexString('FFE2EFDA');
  static final _verdeOsc   = ExcelColor.fromHexString('FF375623');
  static final _grisClaro  = ExcelColor.fromHexString('FFF2F2F2');
  static final _blanco     = ExcelColor.fromHexString('FFFFFFFF');

  // ── Exportar ──────────────────────────────────────────────────────

  Future<String> exportar({
    required List<RegistroInventario> registros,
    required String titulo,
  }) async {
    final excel = Excel.createExcel();

    _hojaDetalle(excel, registros, titulo);
    _hojaResumenLocalizacion(excel, registros);
    _hojaResumenEmpleado(excel, registros);

    excel.delete('Sheet1');

    final bytes = excel.save()!;
    final dir   = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final carpeta = Directory('${dir.path}/ALM_Inventario');
    if (!await carpeta.exists()) await carpeta.create(recursive: true);

    final fechaStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file     = File('${carpeta.path}/Reporte_$fechaStr.xlsx');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  // ── Hoja 1: Detalle ───────────────────────────────────────────────

  void _hojaDetalle(Excel excel,
      List<RegistroInventario> registros, String titulo) {
    final sheet = excel['Registros'];

    _mergeTitulo(sheet, titulo, 0, 13);

    final sub =
        'Generado: ${DateFormat("dd/MM/yyyy HH:mm").format(DateTime.now())}'
        '  |  Total registros: ${registros.length}';
    _mergeTituloSub(sheet, sub, 1, 13);

    final headers = [
      '#', 'Código nuevo', 'Código anterior', 'Descripción',
      'Marca', 'Modelo', 'No. Serie', 'Responsable',
      'No. Empleado', 'Localización', 'Descripción ubicación',
      'Fecha escaneo', 'Nota',
    ];
    _filaEncabezado(sheet, 2, headers);

    final anchos = [5.0, 14.0, 16.0, 40.0, 16.0, 16.0, 16.0,
                    28.0, 12.0, 14.0, 35.0, 18.0, 20.0];
    for (int c = 0; c < anchos.length; c++) {
      sheet.setColumnWidth(c, anchos[c]);
    }

    int row = 3;
    for (int i = 0; i < registros.length; i++) {
      final r      = registros[i];
      final activo = _teorico.buscarPorCodigo(r.cveActivo);
      final par    = i % 2 == 0;
      final bg     = par ? _grisClaro : _blanco;

      final valores = [
        i + 1,
        r.cveActivo,
        activo?.codigoAnterior ?? '',
        activo?.descripcion    ?? '',
        activo?.marca          ?? '',
        activo?.modelo         ?? '',
        activo?.noSerie        ?? '',
        activo?.nombre         ?? '',
        activo?.empleado       ?? '',
        r.localizacion,
        activo?.ubicaDesc      ?? '',
        DateFormat('dd/MM/yyyy HH:mm').format(r.fecha),
        r.nota,
      ];

      for (int c = 0; c < valores.length; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(
            columnIndex: c, rowIndex: row));
        final v = valores[c];
        cell.value = v is int
            ? IntCellValue(v)
            : TextCellValue(v.toString());
        cell.cellStyle = CellStyle(
          backgroundColorHex: bg,
          fontSize: 10,
          verticalAlign: VerticalAlign.Center,
        );
      }
      row++;
    }
  }

  // ── Hoja 2: Resumen por localización ─────────────────────────────

  void _hojaResumenLocalizacion(Excel excel,
      List<RegistroInventario> registros) {
    final sheet = excel['Por Ubicacion'];

    _mergeTitulo(sheet, 'Resumen por ubicación', 0, 5);
    _filaEncabezado(sheet, 1,
        ['Localización', 'Descripción', 'Escaneados', 'Esperados', '% Avance']);

    sheet.setColumnWidth(0, 14);
    sheet.setColumnWidth(1, 38);
    sheet.setColumnWidth(2, 12);
    sheet.setColumnWidth(3, 12);
    sheet.setColumnWidth(4, 12);

    final porLoc = <String, int>{};
    for (final r in registros) {
      porLoc[r.localizacion] = (porLoc[r.localizacion] ?? 0) + 1;
    }

    final locs = porLoc.keys.toList()..sort();
    int row = 2;
    for (int i = 0; i < locs.length; i++) {
      final loc       = locs[i];
      final esc       = porLoc[loc]!;
      final esperados = _teorico.activosDe(loc).length;
      final pct       = esperados > 0 ? (esc / esperados * 100) : 0.0;
      final completo  = esc >= esperados && esperados > 0;
      final bg        = completo ? _verde : (i % 2 == 0 ? _grisClaro : _blanco);
      final fontColor = completo ? _verdeOsc : _azulOscuro;

      final desc = _teorico.activosDe(loc).isNotEmpty
          ? _teorico.activosDe(loc).first.ubicaDesc
          : '';

      final vals = [loc, desc, esc, esperados, '${pct.toStringAsFixed(1)}%'];
      for (int c = 0; c < vals.length; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(
            columnIndex: c, rowIndex: row));
        final v = vals[c];
        cell.value =
            v is int ? IntCellValue(v) : TextCellValue(v.toString());
        cell.cellStyle = CellStyle(
          backgroundColorHex: bg,
          fontColorHex: fontColor,
          fontSize: 10,
        );
      }
      row++;
    }

    _filaEncabezado(sheet, row, ['TOTAL', '', registros.length, '', '']);
  }

  // ── Hoja 3: Resumen por empleado ─────────────────────────────────

  void _hojaResumenEmpleado(Excel excel,
      List<RegistroInventario> registros) {
    final sheet = excel['Por Empleado'];

    _mergeTitulo(sheet, 'Resumen por empleado / responsable', 0, 5);
    _filaEncabezado(sheet, 1,
        ['No. Empleado', 'Nombre', 'Escaneados', 'Asignados', '% Avance']);

    sheet.setColumnWidth(0, 14);
    sheet.setColumnWidth(1, 32);
    sheet.setColumnWidth(2, 12);
    sheet.setColumnWidth(3, 12);
    sheet.setColumnWidth(4, 12);

    final porEmp = <String, Map<String, dynamic>>{};
    for (final r in registros) {
      final activo = _teorico.buscarPorCodigo(r.cveActivo);
      if (activo == null) continue;
      final emp = activo.empleado.isNotEmpty ? activo.empleado : 'N/A';
      porEmp.putIfAbsent(emp, () => {
        'nombre':    activo.nombre,
        'escaneados': 0,
        'asignados': _teorico.activosDeEmpleado(activo.nombre).length,
      });
      porEmp[emp]!['escaneados'] =
          (porEmp[emp]!['escaneados'] as int) + 1;
    }

    final emps = porEmp.keys.toList()..sort();
    int row = 2;
    for (int i = 0; i < emps.length; i++) {
      final emp      = emps[i];
      final data     = porEmp[emp]!;
      final esc      = data['escaneados'] as int;
      final asig     = data['asignados']  as int;
      final pct      = asig > 0 ? (esc / asig * 100) : 0.0;
      final completo = esc >= asig && asig > 0;
      final bg       = completo ? _verde : (i % 2 == 0 ? _grisClaro : _blanco);
      final fontColor = completo ? _verdeOsc : _azulOscuro;

      final vals = [emp, data['nombre'], esc, asig,
          '${pct.toStringAsFixed(1)}%'];
      for (int c = 0; c < vals.length; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(
            columnIndex: c, rowIndex: row));
        final v = vals[c];
        cell.value =
            v is int ? IntCellValue(v) : TextCellValue(v.toString());
        cell.cellStyle = CellStyle(
          backgroundColorHex: bg,
          fontColorHex: fontColor,
          fontSize: 10,
        );
      }
      row++;
    }
  }

  // ── Compartir ─────────────────────────────────────────────────────

  Future<void> exportarYCompartir({
    required List<RegistroInventario> registros,
    required String titulo,
  }) async {
    final ruta = await exportar(registros: registros, titulo: titulo);
    await Share.shareXFiles(
      [XFile(ruta,
          mimeType: 'application/vnd.openxmlformats-officedocument'
              '.spreadsheetml.sheet')],
      subject: titulo,
    );
  }

  // ── Helpers de formato ────────────────────────────────────────────

  void _mergeTitulo(Sheet sheet, String texto, int row, int cols) {
    final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
    cell.value = TextCellValue(texto);
    cell.cellStyle = CellStyle(
      backgroundColorHex: _azulOscuro,
      fontColorHex:       _blanco,
      bold:               true,
      fontSize:           13,
      horizontalAlign:    HorizontalAlign.Left,
      verticalAlign:      VerticalAlign.Center,
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: cols - 1, rowIndex: row),
    );
  }

  void _mergeTituloSub(Sheet sheet, String texto, int row, int cols) {
    final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
    cell.value = TextCellValue(texto);
    cell.cellStyle = CellStyle(
      backgroundColorHex: _azulClaro,
      fontColorHex:       _azulOscuro,
      bold:               false,
      fontSize:           10,
      horizontalAlign:    HorizontalAlign.Left,
      verticalAlign:      VerticalAlign.Center,
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: cols - 1, rowIndex: row),
    );
  }

  void _filaEncabezado(Sheet sheet, int row, List<dynamic> valores) {
    for (int c = 0; c < valores.length; c++) {
      final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row));
      final v = valores[c];
      cell.value = v is int ? IntCellValue(v) : TextCellValue(v.toString());
      cell.cellStyle = CellStyle(
        backgroundColorHex: _azulOscuro,
        fontColorHex:       _blanco,
        bold:               true,
        fontSize:           10,
        horizontalAlign:    HorizontalAlign.Center,
      );
    }
  }
}
