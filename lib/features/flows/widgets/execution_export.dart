// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/utils/date_format.dart';
import '../../../core/utils/execution_labels.dart';
import '../../../core/utils/xlsx_helpers.dart';

// ── Color constants ────────────────────────────────────────────────────────────

const _navy    = PdfColor(0.043, 0.075, 0.169);   // #0B132B
const _teal    = PdfColor(0.349, 0.878, 0.800);   // #59E0CC
const _white   = PdfColors.white;
const _text    = PdfColor(0.067, 0.094, 0.153);   // #111827
const _text2   = PdfColor(0.420, 0.447, 0.502);   // #6B7280
const _border  = PdfColor(0.898, 0.910, 0.922);   // #E5E7EB
const _altRow  = PdfColor(0.945, 0.945, 0.945);   // #F1F1F1
const _ok      = PdfColor(0.063, 0.725, 0.506);   // #10B981
const _warn    = PdfColor(0.965, 0.620, 0.043);   // #F59E0B
const _danger  = PdfColor(0.937, 0.267, 0.267);   // #EF4444
const _info    = PdfColor(0.231, 0.510, 0.965);   // #3B82F6
const _steel   = PdfColor(0.482, 0.573, 0.655);   // #7B92A7

// ── Helpers ───────────────────────────────────────────────────────────────────

const _months = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

PdfColor _eventColor(String type) => switch (type) {
  'flujo_iniciado'       => _teal,
  'flujo_completado'     => _teal,
  'flujo_retomado'       => _teal,
  'campo_capturado'      => _ok,
  'campo_rechazado'      => _warn,
  'worker_escaló'        => _warn,
  'flujo_abandonado'     => _danger,
  'supervisor_intervino' => _info,
  _                      => _steel,
};

// Pure helpers moved to lib/core/utils/execution_labels.dart (PLA-68):
// executionEventLabel, executionStatusLabel, groupExecutionEvents, resolveFieldValue

// ── PDF ────────────────────────────────────────────────────────────────────────

Future<void> exportExecutionPdf(
  Map<String, dynamic> exec,
  Map<String, dynamic> flow,
) async {
  try {
  // Load font with fallback
  pw.Font geistFont;
  pw.Font geistBold;
  try {
    final fontData =
        await rootBundle.load('assets/fonts/Geist-VariableFont_wght.ttf');
    geistFont = pw.Font.ttf(fontData);
    geistBold = pw.Font.ttf(fontData);
  } catch (_) {
    geistFont = pw.Font.helvetica();
    geistBold = pw.Font.helveticaBold();
  }

  final pdf = pw.Document(
    title: 'Reporte de ejecución',
    theme: pw.ThemeData.withFont(base: geistFont, bold: geistBold),
  );

  // ── Data extraction ────────────────────────────────────────────────────────
  final execId     = exec['id'] as String? ?? '';
  final flowName   = flow['name'] as String? ?? '—';
  final status     = exec['status'] as String? ?? 'completed';
  final startedAt  = exec['created_at'] as String?;
  final completedAt = exec['completed_at'] as String?;

  // Operator
  final opRaw = exec['operator'];
  final opName = (opRaw is Map ? opRaw['name'] : null) as String? ?? 'Sin operador';

  // Channel
  final channelRaw = exec['channel'];
  final channelType = (channelRaw is Map ? channelRaw['channel_type'] : null)
      as String?
      ?? switch (exec['actor_type'] as String?) {
        'operator'    => 'whatsapp',
        'tenant_user' => 'dashboard',
        'system'      => 'api',
        _             => null,
      };

  // Trigger / type
  final triggerSources = flow['trigger_sources'] as List?;
  final flowType = triggerSources?.firstOrNull?.toString() ?? 'conversacional';

  // Field values
  final rawFvList = exec['field_values'] as List? ?? [];
  final fvList = rawFvList
      .whereType<Map>()
      .map((e) => e.cast<String, dynamic>())
      .toList();

  // Snapshot fields map by key for type lookup
  final snapshotFields = (flow['fields'] as List? ?? [])
      .whereType<Map>()
      .map((f) => f.cast<String, dynamic>())
      .toList();
  final fieldTypeMap = <String, String>{
    for (final f in snapshotFields)
      if (f['key'] is String) f['key'] as String: (f['type'] as String? ?? 'text'),
  };

  // Progress
  final total = snapshotFields.length;
  final filled = fvList.where((fv) =>
      fv['value_text'] != null ||
      fv['value_numeric'] != null ||
      fv['value_media_url'] != null ||
      fv['value_jsonb'] != null).length;

  // Events
  final rawEvents = exec['events'] as List? ?? [];
  final events = rawEvents
      .whereType<Map>()
      .map((e) => e.cast<String, dynamic>())
      .toList()
    ..sort((a, b) {
      final ta = a['timestamp'] as String? ?? a['created_at'] as String? ?? '';
      final tb = b['timestamp'] as String? ?? b['created_at'] as String? ?? '';
      return ta.compareTo(tb);
    });
  final eventGroups = groupExecutionEvents(events);

  // Messages
  final rawMessages = exec['messages'] as List? ?? [];
  final messages = rawMessages
      .whereType<Map>()
      .map((m) => m.cast<String, dynamic>())
      .toList();

  // Date for report subtitle
  final now = DateTime.now();
  final reportDate =
      '${now.day.toString().padLeft(2, '0')} ${_months[now.month - 1]} ${now.year}';

  // Short exec ID for footer
  final shortId = execId.length > 18 ? execId.substring(0, 18) : execId;

  // ── pw.TextStyle helpers ───────────────────────────────────────────────────
  pw.TextStyle ts({
    double size = 10,
    PdfColor? color,
    pw.FontWeight weight = pw.FontWeight.normal,
  }) =>
      pw.TextStyle(
        font: geistFont,
        fontSize: size,
        color: color ?? _text,
        fontWeight: weight,
      );

  // ── PDF pages ──────────────────────────────────────────────────────────────
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      footer: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 10),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _border)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generado por ConectamOS · conectamos.ai',
              style: ts(size: 8, color: _text2),
            ),
            pw.Text(
              shortId,
              style: ts(size: 8, color: _text2),
            ),
          ],
        ),
      ),
      build: (ctx) => [
        // ── HEADER block ────────────────────────────────────────────────────
        pw.Container(
          color: _navy,
          padding: const pw.EdgeInsets.fromLTRB(28, 22, 28, 22),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Brand + subtitle
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.RichText(
                    text: pw.TextSpan(
                      children: [
                        pw.TextSpan(
                          text: 'Conectam',
                          style: ts(size: 16, color: _white, weight: pw.FontWeight.bold),
                        ),
                        pw.TextSpan(
                          text: 'OS',
                          style: ts(size: 16, color: _teal, weight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  pw.Text(
                    'Reporte de ejecución · $reportDate',
                    style: ts(size: 9, color: PdfColor(1, 1, 1, 0.6)),
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Divider(color: PdfColor(1, 1, 1, 0.12), thickness: 0.5),
              pw.SizedBox(height: 12),
              // Flow name
              pw.Text(
                flowName,
                style: ts(size: 20, color: _white, weight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              // Badges row
              pw.Row(
                children: [
                  _pdfBadge(executionStatusLabel(status), _statusColor(status), geistFont),
                  pw.SizedBox(width: 6),
                  if (channelType != null) ...[
                    _pdfBadge(channelType, _steel, geistFont),
                    pw.SizedBox(width: 6),
                  ],
                  _pdfBadge(flowType, _teal, geistFont),
                ],
              ),
            ],
          ),
        ),

        // ── METADATA row ────────────────────────────────────────────────────
        pw.Container(
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _border)),
          ),
          child: pw.Table(
            columnWidths: {
              0: const pw.FlexColumnWidth(),
              1: const pw.FlexColumnWidth(),
              2: const pw.FlexColumnWidth(),
              3: const pw.FlexColumnWidth(),
            },
            children: [
              pw.TableRow(
                children: [
                  _metaCell('Operador', opName, geistFont, rightBorder: true),
                  _metaCell('Iniciada', fmtDateShort(startedAt), geistFont, rightBorder: true),
                  _metaCell('Finalizada', fmtDateShort(completedAt), geistFont, rightBorder: true),
                  _metaCell('Progreso', '$filled / $total campos', geistFont),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 20),

        // ── CAMPOS section ──────────────────────────────────────────────────
        if (fvList.isNotEmpty) ...[
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 28),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'CAMPOS CAPTURADOS',
                  style: ts(size: 9, color: _text2, weight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 8),
                pw.Table(
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2),
                    1: const pw.FlexColumnWidth(3),
                    2: const pw.FlexColumnWidth(1.2),
                  },
                  border: pw.TableBorder.all(color: _border, width: 0.5),
                  children: [
                    // Header
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: _navy),
                      children: [
                        _tableHeader('Campo', geistFont),
                        _tableHeader('Valor', geistFont),
                        _tableHeader('Tipo', geistFont),
                      ],
                    ),
                    // Data rows
                    for (var i = 0; i < fvList.length; i++)
                      pw.TableRow(
                        decoration: pw.BoxDecoration(
                          color: i.isOdd ? _altRow : PdfColors.white,
                        ),
                        children: [
                          _tableCell(fvList[i]['field_key']?.toString() ?? '—', geistFont),
                          _tableCell(
                            resolveFieldValue(
                              fvList[i],
                              fieldTypeMap[fvList[i]['field_key']] ?? 'text',
                            ),
                            geistFont,
                          ),
                          _tableCell(
                            fieldTypeMap[fvList[i]['field_key']] ?? '—',
                            geistFont,
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 24),
        ],

        // ── CRONOLOGÍA section ───────────────────────────────────────────────
        if (eventGroups.isNotEmpty) ...[
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 28),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'CRONOLOGÍA',
                  style: ts(size: 9, color: _text2, weight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 8),
                pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _border, width: 0.5),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  padding: const pw.EdgeInsets.all(12),
                  child: pw.Column(
                    children: [
                      for (final g in eventGroups) ...[
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Container(
                              width: 7,
                              height: 7,
                              margin: const pw.EdgeInsets.only(top: 2, right: 8),
                              decoration: pw.BoxDecoration(
                                color: _eventColor(g.type),
                                shape: pw.BoxShape.circle,
                              ),
                            ),
                            pw.Expanded(
                              child: pw.Text(
                                g.items.length > 1
                                    ? '${executionEventLabel(g.type)} ×${g.items.length}'
                                    : executionEventLabel(g.type),
                                style: ts(size: 10, weight: pw.FontWeight.bold),
                              ),
                            ),
                            pw.Text(
                              fmtDateShort(
                                g.items.first['timestamp'] as String? ??
                                g.items.first['created_at'] as String?,
                              ),
                              style: ts(size: 9, color: _text2),
                            ),
                          ],
                        ),
                        if (g != eventGroups.last) pw.SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 24),
        ],

        // ── CONVERSACIÓN section ─────────────────────────────────────────────
        if (messages.isNotEmpty) ...[
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 28),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'CONVERSACIÓN',
                  style: ts(size: 9, color: _text2, weight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 8),
                pw.Table(
                  columnWidths: {
                    0: const pw.FixedColumnWidth(70),
                    1: const pw.FlexColumnWidth(),
                    2: const pw.FixedColumnWidth(55),
                  },
                  border: pw.TableBorder.all(color: _border, width: 0.5),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: _navy),
                      children: [
                        _tableHeader('Hora', geistFont),
                        _tableHeader('Mensaje', geistFont),
                        _tableHeader('De', geistFont),
                      ],
                    ),
                    for (var i = 0; i < messages.length; i++)
                      pw.TableRow(
                        decoration: pw.BoxDecoration(
                          color: i.isOdd ? _altRow : PdfColors.white,
                        ),
                        children: [
                          _tableCell(messages[i]['at']?.toString() ?? '—', geistFont),
                          _tableCell(messages[i]['text']?.toString() ?? '—', geistFont),
                          _tableCell(
                            messages[i]['from'] == 'worker' ? 'Worker' : 'Usuario',
                            geistFont,
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 24),
        ],
      ],
    ),
  );

  await Printing.layoutPdf(
    onLayout: (_) => pdf.save(),
    name: '${flowName}_${shortId.replaceAll('-', '')}.pdf',
  );
  } catch (e, st) {
    debugPrint('[exportExecutionPdf] error: $e\n$st');
  }
}

// ── PDF widget helpers ────────────────────────────────────────────────────────

PdfColor _statusColor(String s) => switch (s) {
  'completed'                   => _ok,
  'in_progress' || 'active'    => _info,
  'paused'                      => _warn,
  'failed' || 'escalated'      => _danger,
  _                             => _steel,
};

pw.Widget _pdfBadge(String label, PdfColor color, pw.Font font) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: pw.BoxDecoration(
      color: PdfColor(color.red, color.green, color.blue, 0.2),
      border: pw.Border.all(color: color, width: 0.5),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(99)),
    ),
    child: pw.Text(
      label,
      style: pw.TextStyle(font: font, fontSize: 9, color: color),
    ),
  );
}

pw.Widget _metaCell(
  String label,
  String value,
  pw.Font font, {
  bool rightBorder = false,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(14),
    decoration: pw.BoxDecoration(
      border: rightBorder
          ? const pw.Border(right: pw.BorderSide(color: _border))
          : null,
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label.toUpperCase(),
          style: pw.TextStyle(
            font: font, fontSize: 8, color: _text2,
            fontWeight: pw.FontWeight.bold, letterSpacing: 0.4,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          value,
          style: pw.TextStyle(font: font, fontSize: 11, color: _text, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
  );
}

pw.Widget _tableHeader(String text, pw.Font font) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    child: pw.Text(
      text.toUpperCase(),
      style: pw.TextStyle(
        font: font, fontSize: 8, color: _white, fontWeight: pw.FontWeight.bold,
      ),
    ),
  );
}

pw.Widget _tableCell(String text, pw.Font font) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    child: pw.Text(
      text,
      style: pw.TextStyle(font: font, fontSize: 10, color: _text),
      maxLines: 3,
      overflow: pw.TextOverflow.clip,
    ),
  );
}

// ── XLS ────────────────────────────────────────────────────────────────────────

Future<void> exportExecutionXls(
  Map<String, dynamic> exec,
  Map<String, dynamic> flow,
) async {
  try {
    final execId   = exec['id'] as String? ?? '';
    final flowName = flow['name'] as String? ?? 'flujo';
    final shortId  = execId.length > 8
        ? execId.substring(0, 8).toUpperCase()
        : execId.toUpperCase();

    final opRaw      = exec['operator'];
    final opName     = (opRaw is Map ? opRaw['name'] : null) as String? ?? '—';
    final channelRaw = exec['channel'];
    final channelName =
        (channelRaw is Map ? channelRaw['display_name'] ?? channelRaw['channel_type'] : null)
            as String? ?? '—';

    // ── Campos rows ────────────────────────────────────────────────────────
    final snapshotFields = (flow['fields'] as List? ?? [])
        .whereType<Map>()
        .map((f) => f.cast<String, dynamic>())
        .toList();
    final fieldTypeMap = <String, String>{
      for (final f in snapshotFields)
        if (f['key'] is String)
          f['key'] as String: (f['type'] as String? ?? 'text'),
    };
    final rawFvList = exec['field_values'] as List? ?? [];
    final fvList    = rawFvList
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();

    final camposRows = <List<String>>[
      ['Campo', 'Valor', 'Tipo', 'Source', 'Capturado'],
      for (final fv in fvList)
        [
          fv['field_key']?.toString() ?? '',
          resolveFieldValue(fv, fieldTypeMap[fv['field_key']] ?? 'text'),
          fieldTypeMap[fv['field_key']] ?? '',
          fv['source']?.toString() ?? 'captured',
          fmtDateShort(fv['captured_at'] as String? ?? fv['created_at'] as String?),
        ],
    ];

    // ── Metadatos rows ─────────────────────────────────────────────────────
    final metadatosRows = <List<String>>[
      ['Campo', 'Valor'],
      ['Execution ID', execId],
      ['Flujo', flowName],
      ['Operador', opName],
      ['Canal', channelName],
      ['Status', exec['status']?.toString() ?? '—'],
      ['Iniciada', fmtDateShort(exec['created_at'] as String?)],
      ['Finalizada', fmtDateShort(exec['completed_at'] as String?)],
    ];

    // ── Cronología rows ────────────────────────────────────────────────────
    final rawEvents = exec['events'] as List? ?? [];
    final events    = rawEvents
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList()
      ..sort((a, b) {
        final ta = a['timestamp'] as String? ?? a['created_at'] as String? ?? '';
        final tb = b['timestamp'] as String? ?? b['created_at'] as String? ?? '';
        return ta.compareTo(tb);
      });
    final hasEvents = events.isNotEmpty;

    final cronologiaRows = <List<String>>[
      if (hasEvents) ...[
        ['Tipo', 'Label', 'Timestamp'],
        for (final e in events)
          [
            e['type'] as String? ?? e['event_type'] as String? ?? '',
            executionEventLabel(e['type'] as String? ?? e['event_type'] as String? ?? ''),
            e['timestamp'] as String? ?? e['created_at'] as String? ?? '—',
          ],
      ],
    ];

    // ── Build ZIP ─────────────────────────────────────────────────────────
    final archive = Archive();

    void addFile(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    addFile('[Content_Types].xml', [
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">',
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>',
      '<Default Extension="xml" ContentType="application/xml"/>',
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>',
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
      '<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
      if (hasEvents)
        '<Override PartName="/xl/worksheets/sheet3.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
      '</Types>',
    ].join());

    addFile('_rels/.rels', [
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>',
      '</Relationships>',
    ].join());

    addFile('xl/_rels/workbook.xml.rels', [
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>',
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>',
      if (hasEvents)
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet3.xml"/>',
      '</Relationships>',
    ].join());

    addFile('xl/workbook.xml', [
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">',
      '<sheets>',
      '<sheet name="Campos" sheetId="1" r:id="rId1"/>',
      '<sheet name="Metadatos" sheetId="2" r:id="rId2"/>',
      if (hasEvents) '<sheet name="Cronología" sheetId="3" r:id="rId3"/>',
      '</sheets>',
      '</workbook>',
    ].join());

    addFile('xl/worksheets/sheet1.xml', xlsSheetXml(camposRows));
    addFile('xl/worksheets/sheet2.xml', xlsSheetXml(metadatosRows));
    if (hasEvents) addFile('xl/worksheets/sheet3.xml', xlsSheetXml(cronologiaRows));

    // ── Download ──────────────────────────────────────────────────────────
    final zipBytes = ZipEncoder().encode(archive)!;

    final fileName = '${flowName}_$shortId.xlsx'
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^\w\-_.]'), '');

    final blob = html.Blob(
      [Uint8List.fromList(zipBytes)],
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    final url = html.Url.createObjectUrlFromBlob(blob);
    (html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click())
        .remove();
    html.Url.revokeObjectUrl(url);
  } catch (e, st) {
    debugPrint('[exportExecutionXls] error: $e\n$st');
  }
}
