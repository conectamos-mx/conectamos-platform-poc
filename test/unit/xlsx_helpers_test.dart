import 'package:flutter_test/flutter_test.dart';
import 'package:conectamos_platform/core/utils/xlsx_helpers.dart';

void main() {
  group('xlsColName', () {
    test('0 → A', () => expect(xlsColName(0), 'A'));
    test('25 → Z', () => expect(xlsColName(25), 'Z'));
    test('26 → AA', () => expect(xlsColName(26), 'AA'));
    test('27 → AB', () => expect(xlsColName(27), 'AB'));
    test('701 → ZZ', () => expect(xlsColName(701), 'ZZ'));
    test('702 → AAA', () => expect(xlsColName(702), 'AAA'));
  });

  group('xlsXmlEscape', () {
    test('ampersand', () => expect(xlsXmlEscape('&'), '&amp;'));
    test('less-than', () => expect(xlsXmlEscape('<'), '&lt;'));
    test('greater-than', () => expect(xlsXmlEscape('>'), '&gt;'));
    test('double-quote', () => expect(xlsXmlEscape('"'), '&quot;'));
    test('single-quote', () => expect(xlsXmlEscape("'"), '&apos;'));
    test('mixed', () {
      expect(
        xlsXmlEscape('A & B < C > D "E" \'F\''),
        'A &amp; B &lt; C &gt; D &quot;E&quot; &apos;F&apos;',
      );
    });
    test('no-op for safe string', () => expect(xlsXmlEscape('hello'), 'hello'));
  });

  group('xlsSheetXml', () {
    test('boldFirstRow false — no s attribute', () {
      final xml = xlsSheetXml([
        ['H1', 'H2'],
        ['a', 'b'],
      ]);
      expect(xml, contains('<c r="A1" t="inlineStr"><is><t>H1</t></is></c>'));
      expect(xml, isNot(contains('s="1"')));
    });

    test('boldFirstRow true — first row has s="1"', () {
      final xml = xlsSheetXml(
        [
          ['H1', 'H2'],
          ['a', 'b'],
        ],
        boldFirstRow: true,
      );
      expect(xml, contains('<c r="A1" t="inlineStr" s="1"><is><t>H1</t></is></c>'));
      expect(xml, contains('<c r="B1" t="inlineStr" s="1"><is><t>H2</t></is></c>'));
      // second row should NOT be bold
      expect(xml, contains('<c r="A2" t="inlineStr"><is><t>a</t></is></c>'));
    });

    test('escapes cell values', () {
      final xml = xlsSheetXml([
        ['A&B'],
      ]);
      expect(xml, contains('<t>A&amp;B</t>'));
    });
  });
}
