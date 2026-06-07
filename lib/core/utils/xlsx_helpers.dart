// Shared helpers for generating XLSX sheet XML without external packages.
// Used by execution_export.dart and dashboard_screen.dart.

/// Converts a zero-based column index to an Excel column name (A, B, … Z, AA, AB …).
String xlsColName(int index) {
  var name = '';
  var i = index;
  do {
    name = String.fromCharCode(65 + (i % 26)) + name;
    i = (i ~/ 26) - 1;
  } while (i >= 0);
  return name;
}

/// Escapes the five XML special characters for safe inline-string values.
String xlsXmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// Builds a minimal `sheet?.xml` body from a 2-D list of strings.
///
/// When [boldFirstRow] is `true` the first row's cells include `s="1"`,
/// which references a bold cell style defined in the caller's `styles.xml`.
String xlsSheetXml(List<List<String>> rows, {bool boldFirstRow = false}) {
  final sb = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write(
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
    ..write('<sheetData>');
  for (var r = 0; r < rows.length; r++) {
    sb.write('<row r="${r + 1}">');
    final bold = boldFirstRow && r == 0;
    for (var c = 0; c < rows[r].length; c++) {
      final cell = '${xlsColName(c)}${r + 1}';
      final val = xlsXmlEscape(rows[r][c]);
      final sAttr = bold ? ' s="1"' : '';
      sb.write('<c r="$cell" t="inlineStr"$sAttr><is><t>$val</t></is></c>');
    }
    sb.write('</row>');
  }
  sb.write('</sheetData></worksheet>');
  return sb.toString();
}
