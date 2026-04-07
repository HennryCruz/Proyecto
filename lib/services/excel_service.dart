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

  static final _azulOscuro = ExcelColor.fromHexString('FF1B4F8A');
  static final _azulClaro  = ExcelColor.fromHexString('FFD6E4F0');
  static final _verde      = ExcelColor.fromHexString('FFE2EFDA');
  static final _verdeOsc   = ExcelColor.fromHexString('FF375623');
  static final _rojo       = ExcelColor.fromHexString('FFFCE4D6');
  static final _rojoOsc    = ExcelColor.fromHexString('FF9C0006');
  static final _naranja    = ExcelColor.fromHexString('FFFCE5CD');
  static final _naranjaOsc = ExcelColor.fromHexString('FF833C00');
  static final _amarillo   = ExcelColor.fromHexString('FFFFF2CC');
  static final _amarilloOsc= ExcelColor.fromHexString('FF7D6608');
  static final _grisClaro  = ExcelColor.fromHexString('FFF2F2F2');
  static final _blanco     = ExcelColor.fromHexString('FFFFFFFF');

  // ── Exportar sesión completa ──────────────────────────────────────

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

  // ── Exportar diferencias de verificación ─────────────────────────

  Future<String> exportarDiferencias({
    required String localizacion,
    required List<ActivoTeorico> faltantes,
    required List<ActivoTeorico> escaneados,
    required List<RegistroInventario> sobrantes,
    required List<RegistroInventario> registros,
  }) async {
    final excel = Excel.createExcel();
    final fecha = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    // ── Hoja resumen ────────────────────────────────────────────────
    final resumen = excel['Resumen'];
    _mergeTitulo(resumen,
        'Reporte de diferencias — $localizacion', 0, 5);
    _mergeTituloSub(resumen, 'Generado: $fecha', 1, 5);

    int row = 3;
    _filaEncabezado(resumen, row, ['Categoría', 'Cantidad', '', '', '']);
    row++;
    _filaData(resumen, row++,
        ['Total esperados', '${faltantes.length + escaneados.length}',
         '', '', ''], _blanco, _azulOscuro);
    _filaData(resumen, row++,
        ['Escaneados correctamente', '${escaneados.length}',
         '', '', ''], _verde, _verdeOsc);
    _filaData(resumen, row++,
        ['Faltantes', '${faltantes.length}', '', '', ''],
        _rojo, _rojoOsc);
    _filaData(resumen, row++,
        ['Sobrantes (no esperados)', '${sobrantes.length}',
         '', '', ''],
        _naranja, _naranjaOsc);

    resumen.setColumnWidth(0, 32);
    resumen.setColumnWidth(1, 14);

    // ── Hoja faltantes ──────────────────────────────────────────────
    if (faltantes.isNotEmpty) {
      final hoja = excel['Faltantes'];
      _mergeTitulo(hoja, 'Activos faltantes — $localizacion', 0, 8);
      _mergeTituloSub(hoja,
          '${faltantes.length} activos no escaneados | $fecha', 1, 8);
      _filaEncabezado(hoja, 2, [
        'Cód. anterior', 'Cód. nuevo', 'Descripción',
        'Marca', 'Modelo', 'No. Serie',
        'Responsable', 'Resguardo',
      ]);
      _anchosFaltantes(hoja);

      int r = 3;
      for (int i = 0; i < faltantes.length; i++) {
        final a   = faltantes[i];
        final par = i % 2 == 0;
        _filaData(hoja, r++, [
          a.codigoAnterior, a.codigoNuevo, a.descripcion,
          a.marca, a.modelo, a.noSerie,
          a.nombre, a.resguardo,
        ], par ? _rojo : _blanco, _rojoOsc);
      }
    }

    // ── Hoja sobrantes ──────────────────────────────────────────────
    if (sobrantes.isNotEmpty) {
      final hoja = excel['Sobrantes'];
      _mergeTitulo(hoja,
          'Activos sobrantes (no esperados) — $localizacion', 0, 6);
      _mergeTituloSub(hoja,
          '${sobrantes.length} activos fuera del teórico | $fecha', 1, 6);
      _filaEncabezado(hoja, 2, [
        'Código escaneado', 'Descripción', 'Marca',
        'Modelo', 'No. Serie', 'Fecha escaneo',
      ]);
      hoja.setColumnWidth(0, 16);
      hoja.setColumnWidth(1, 38);
      hoja.setColumnWidth(2, 16);
      hoja.setColumnWidth(3, 16);
      hoja.setColumnWidth(4, 16);
      hoja.setColumnWidth(5, 18);

      int r = 3;
      for (int i = 0; i < sobrantes.length; i++) {
        final reg    = sobrantes[i];
        final activo = _teorico.buscarPorCodigo(reg.cveActivo);
        final par    = i % 2 == 0;
        _filaData(hoja, r++, [
          reg.cveActivo,
          activo?.descripcion ?? 'Desconocido',
          activo?.marca ?? '',
          activo?.modelo ?? '',
          activo?.noSerie ?? '',
          DateFormat('dd/MM/yyyy HH:mm').format(reg.fecha),
        ], par ? _naranja : _blanco, _naranjaOsc);
      }
    }

    // ── Hoja no catalogados ─────────────────────────────────────────
    final noCatalogados = registros
        .where((r) =>
            r.localizacion.toUpperCase() == localizacion &&
            r.tipo == TipoActivo.noCatalogado)
        .toList();

    if (noCatalogados.isNotEmpty) {
      final hoja = excel['No Catalogados'];
      _mergeTitulo(hoja,
          'Activos no catalogados — $localizacion', 0, 4);
      _mergeTituloSub(hoja,
          '${noCatalogados.length} activos sin registro | $fecha', 1, 4);
      _filaEncabezado(hoja, 2, [
        'Código escaneado', 'Fecha escaneo', 'Localización', 'Nota',
      ]);
      hoja.setColumnWidth(0, 20);
      hoja.setColumnWidth(1, 20);
      hoja.setColumnWidth(2, 16);
      hoja.setColumnWidth(3, 30);

      int r = 3;
      for (int i = 0; i < noCatalogados.length; i++) {
        final reg = noCatalogados[i];
        final par = i % 2 == 0;
        _filaData(hoja, r++, [
          reg.cveActivo,
          DateFormat('dd/MM/yyyy HH:mm').format(reg.fecha),
          reg.localizacion,
          reg.nota,
        ], par ? _amarillo : _blanco, _amarilloOsc);
      }
    }

    excel.delete('Sheet1');

    final bytes = excel.save()!;
    final dir   = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final carpeta = Directory('${dir.path}/ALM_Inventario');
    if (!await carpeta.exists()) await carpeta.create(recursive: true);

    final fechaStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file     = File(
        '${carpeta.path}/Diferencias_${localizacion}_$fechaStr.xlsx');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  // ── Hoja detalle completo ─────────────────────────────────────────

  void _hojaDetalle(Excel excel,
      List<RegistroInventario> registros, String titulo) {
    final sheet = excel['Registros'];

    _mergeTitulo(sheet, titulo, 0, 14);
    _mergeTituloSub(sheet,
        'Generado: ${DateFormat("dd/MM/yyyy HH:mm").format(DateTime.now())}'
        '  |  Total: ${registros.length}'
        '  |  No catalogados: ${registros.where((r) => r.tipo == TipoActivo.noCatalogado).length}',
        1, 14);

    _filaEncabezado(sheet, 2, [
      '#', 'Código nuevo', 'Código anterior', 'Descripción',
      'Marca', 'Modelo', 'No. Serie', 'Responsable',
      'No. Empleado', 'Localización', 'Desc. ubicación',
      'Fecha escaneo', 'Nota', 'Estado',
    ]);

    final anchos = [5.0, 14.0, 16.0, 40.0, 16.0, 16.0, 16.0,
                    28.0, 12.0, 14.0, 35.0, 18.0, 20.0, 14.0];
    for (int c = 0; c < anchos.length; c++) {
      sheet.setColumnWidth(c, anchos[c]);
    }

    int row = 3;
    for (int i = 0; i < registros.length; i++) {
      final r      = registros[i];
      final activo = _teorico.buscarPorCodigo(r.cveActivo);
      final esNC   = r.tipo == TipoActivo.noCatalogado;
      final par    = i % 2 == 0;

      // Color especial para no catalogados
      final bg = esNC
          ? _amarillo
          : par ? _grisClaro : _blanco;
      final fc = esNC ? _amarilloOsc : _azulOscuro;

      final valores = [
        i + 1,
        r.cveActivo,
        activo?.codigoAnterior ?? '',
        activo?.descripcion    ?? (esNC ? '⚠ No catalogado' : ''),
        activo?.marca          ?? '',
        activo?.modelo         ?? '',
        activo?.noSerie        ?? '',
        activo?.nombre         ?? '',
        activo?.empleado       ?? '',
        r.localizacion,
        activo?.ubicaDesc      ?? '',
        DateFormat('dd/MM/yyyy HH:mm').format(r.fecha),
        r.nota,
        esNC ? 'No catalogado' : 'Catalogado',
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
          fontColorHex: fc,
          fontSize: 10,
          verticalAlign: VerticalAlign.Center,
        );
      }
      row++;
    }
  }

  void _hojaResumenLocalizacion(Excel excel,
      List<RegistroInventario> registros) {
    final sheet = excel['Por Ubicacion'];

    _mergeTitulo(sheet, 'Resumen por ubicación', 0, 5);
    _filaEncabezado(sheet, 1,
        ['Localización', 'Descripción', 'Escaneados',
         'Esperados', '% Avance']);

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
      final bg        =
          completo ? _verde : (i % 2 == 0 ? _grisClaro : _blanco);
      final fc        = completo ? _verdeOsc : _azulOscuro;

      final desc = _teorico.activosDe(loc).isNotEmpty
          ? _teorico.activosDe(loc).first.ubicaDesc
          : '';

      _filaData(sheet, row++,
          [loc, desc, esc, esperados, '${pct.toStringAsFixed(1)}%'],
          bg, fc);
    }

    _filaEncabezado(sheet, row,
        ['TOTAL', '', registros.length, '', '']);
  }

  void _hojaResumenEmpleado(Excel excel,
      List<RegistroInventario> registros) {
    final sheet = excel['Por Empleado'];

    _mergeTitulo(sheet, 'Resumen por empleado', 0, 5);
    _filaEncabezado(sheet, 1,
        ['No. Empleado', 'Nombre', 'Escaneados',
         'Asignados', '% Avance']);

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
      final bg       =
          completo ? _verde : (i % 2 == 0 ? _grisClaro : _blanco);
      final fc       = completo ? _verdeOsc : _azulOscuro;

      _filaData(sheet, row++,
          [emp, data['nombre'], esc, asig,
           '${pct.toStringAsFixed(1)}%'],
          bg, fc);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  void _anchosFaltantes(Sheet sheet) {
    final anchos = [16.0, 14.0, 38.0, 16.0, 16.0, 16.0, 28.0, 20.0];
    for (int c = 0; c < anchos.length; c++) {
      sheet.setColumnWidth(c, anchos[c]);
    }
  }

  void _mergeTitulo(Sheet sheet, String texto, int row, int cols) {
    final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
    cell.value = TextCellValue(texto);
    cell.cellStyle = CellStyle(
      backgroundColorHex: _azulOscuro,
      fontColorHex:       _blanco,
      bold: true, fontSize: 13,
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign:   VerticalAlign.Center,
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
      bold: false, fontSize: 10,
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign:   VerticalAlign.Center,
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: cols - 1, rowIndex: row),
    );
  }

  void _filaEncabezado(Sheet sheet, int row, List<dynamic> vals) {
    for (int c = 0; c < vals.length; c++) {
      final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row));
      final v = vals[c];
      cell.value =
          v is int ? IntCellValue(v) : TextCellValue(v.toString());
      cell.cellStyle = CellStyle(
        backgroundColorHex: _azulOscuro,
        fontColorHex:       _blanco,
        bold: true, fontSize: 10,
        horizontalAlign: HorizontalAlign.Center,
      );
    }
  }

  void _filaData(Sheet sheet, int row, List<dynamic> vals,
      ExcelColor bg, ExcelColor fc) {
    for (int c = 0; c < vals.length; c++) {
      final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row));
      final v = vals[c];
      cell.value =
          v is int ? IntCellValue(v) : TextCellValue(v.toString());
      cell.cellStyle = CellStyle(
        backgroundColorHex: bg,
        fontColorHex:       fc,
        fontSize: 10,
      );
    }
  }
}
