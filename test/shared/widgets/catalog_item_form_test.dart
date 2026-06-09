import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:conectamos_platform/shared/widgets/catalog_item_form.dart';

void main() {
  Widget buildApp(Widget child) {
    return MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

  final schema = [
    {'key': 'sku', 'label': 'SKU', 'type': 'text'},
    {'key': 'price', 'label': 'Precio', 'type': 'number'},
    {'key': 'active', 'label': 'Activo', 'type': 'boolean'},
    {
      'key': 'color',
      'label': 'Color',
      'type': 'text',
      'options': ['rojo', 'azul', 'verde'],
    },
  ];

  group('CatalogItemForm', () {
    testWidgets('getValue emits native types', (tester) async {
      final formKey = GlobalKey<CatalogItemFormState>();

      await tester.pumpWidget(buildApp(
        CatalogItemForm(
          key: formKey,
          fieldsSchema: schema,
          primaryKeyField: 'sku',
        ),
      ));

      // Fill text field (SKU)
      await tester.enterText(find.byType(TextField).first, 'ABC-123');
      // Fill number field (price)
      await tester.enterText(find.byType(TextField).at(1), '99.5');
      await tester.pump();

      final value = formKey.currentState!.getValue();

      expect(value['sku'], isA<String>());
      expect(value['sku'], 'ABC-123');
      expect(value['price'], isA<num>());
      expect(value['price'], 99.5);
      expect(value['active'], isA<bool>());
      expect(value['active'], false);
    });

    testWidgets('empty number field is omitted from getValue', (tester) async {
      final formKey = GlobalKey<CatalogItemFormState>();

      await tester.pumpWidget(buildApp(
        CatalogItemForm(
          key: formKey,
          fieldsSchema: schema,
          primaryKeyField: 'sku',
        ),
      ));

      // Fill only SKU, leave price empty
      await tester.enterText(find.byType(TextField).first, 'X-1');
      await tester.pump();

      final value = formKey.currentState!.getValue();
      expect(value.containsKey('price'), false);
    });

    testWidgets('validate fails when PK is empty', (tester) async {
      final formKey = GlobalKey<CatalogItemFormState>();

      await tester.pumpWidget(buildApp(
        CatalogItemForm(
          key: formKey,
          fieldsSchema: schema,
          primaryKeyField: 'sku',
        ),
      ));

      // Leave SKU empty
      final valid = formKey.currentState!.validate();
      expect(valid, false);
    });

    testWidgets('number field input formatter blocks non-numeric text',
        (tester) async {
      final formKey = GlobalKey<CatalogItemFormState>();

      await tester.pumpWidget(buildApp(
        CatalogItemForm(
          key: formKey,
          fieldsSchema: schema,
          primaryKeyField: 'sku',
        ),
      ));

      await tester.enterText(find.byType(TextField).first, 'SKU-1');
      // The FilteringTextInputFormatter blocks "abc" — field stays empty
      await tester.enterText(find.byType(TextField).at(1), 'abc');
      await tester.pump();

      final value = formKey.currentState!.getValue();
      // "abc" was filtered out, so price is omitted
      expect(value.containsKey('price'), false);
    });

    testWidgets('PK is disabled in edit mode', (tester) async {
      final formKey = GlobalKey<CatalogItemFormState>();

      await tester.pumpWidget(buildApp(
        CatalogItemForm(
          key: formKey,
          fieldsSchema: schema,
          primaryKeyField: 'sku',
          initialData: {
            'sku': 'EXISTING',
            'price': 10,
            'active': true,
          },
        ),
      ));

      // The first TextField (SKU) should be disabled
      final textFields = tester.widgetList<TextField>(find.byType(TextField));
      final skuField = textFields.first;
      expect(skuField.enabled, false);

      // Other text fields should be enabled
      final priceField = textFields.elementAt(1);
      expect(priceField.enabled, true);
    });

    testWidgets('edit mode pre-fills initialData', (tester) async {
      final formKey = GlobalKey<CatalogItemFormState>();

      await tester.pumpWidget(buildApp(
        CatalogItemForm(
          key: formKey,
          fieldsSchema: schema,
          primaryKeyField: 'sku',
          initialData: {
            'sku': 'EXISTING',
            'price': 42,
            'active': true,
          },
        ),
      ));

      final value = formKey.currentState!.getValue();
      expect(value['sku'], 'EXISTING');
      expect(value['price'], 42);
      expect(value['active'], true);
    });
  });
}
