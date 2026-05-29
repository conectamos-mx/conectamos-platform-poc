import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:conectamos_platform/shared/widgets/app_dashboard_table.dart';

void main() {
  Widget buildApp(Widget child) {
    return MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));
  }

  group('AppDashboardTable', () {
    testWidgets('renders columns and rows correctly', (tester) async {
      await tester.pumpWidget(buildApp(
        AppDashboardTable(
          title: 'Test Table',
          columns: [
            const AppDashboardColumn(label: 'Fecha', flex: 2),
            const AppDashboardColumn(label: 'Nombre', flex: 3),
            const AppDashboardColumn(label: 'Estatus', flex: 2),
          ],
          rows: [
            [
              AppDashboardTable.dateCell('01/01 10:00'),
              AppDashboardTable.textCell('Juan', primary: true),
              AppDashboardTable.statusCell('completed'),
            ],
          ],
        ),
      ));

      // Header labels rendered uppercase
      expect(find.text('FECHA'), findsOneWidget);
      expect(find.text('NOMBRE'), findsOneWidget);
      expect(find.text('ESTATUS'), findsOneWidget);

      // Data cells
      expect(find.text('01/01 10:00'), findsOneWidget);
      expect(find.text('Juan'), findsOneWidget);
      expect(find.text('Completado'), findsOneWidget);
    });

    testWidgets('hides download button when onDownload is null', (tester) async {
      await tester.pumpWidget(buildApp(
        AppDashboardTable(
          title: 'No Download',
          columns: [const AppDashboardColumn(label: 'Col')],
          rows: [
            [AppDashboardTable.textCell('data')],
          ],
        ),
      ));

      expect(find.text('Descargar'), findsNothing);
    });

    testWidgets('shows download button when onDownload is provided', (tester) async {
      var pressed = false;
      await tester.pumpWidget(buildApp(
        AppDashboardTable(
          title: 'With Download',
          columns: [const AppDashboardColumn(label: 'Col')],
          rows: [
            [AppDashboardTable.textCell('data')],
          ],
          onDownload: () => pressed = true,
        ),
      ));

      expect(find.text('Descargar'), findsOneWidget);
      await tester.tap(find.text('Descargar'));
      expect(pressed, isTrue);
    });

    testWidgets('shows empty message when rows are empty', (tester) async {
      await tester.pumpWidget(buildApp(
        AppDashboardTable(
          title: 'Empty',
          columns: [const AppDashboardColumn(label: 'Col')],
          rows: const [],
          emptyMessage: 'No hay datos',
        ),
      ));

      expect(find.text('No hay datos'), findsOneWidget);
      // No Table header should render
      expect(find.text('COL'), findsNothing);
    });

    testWidgets('statusCell maps variants correctly', (tester) async {
      await tester.pumpWidget(buildApp(
        AppDashboardTable(
          title: 'Status Test',
          columns: [const AppDashboardColumn(label: 'S')],
          rows: [
            [AppDashboardTable.statusCell('completed')],
            [AppDashboardTable.statusCell('pending')],
            [AppDashboardTable.statusCell('failed')],
            [AppDashboardTable.statusCell(null)],
          ],
        ),
      ));

      expect(find.text('Completado'), findsOneWidget);
      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.text('Fallido'), findsOneWidget);
      expect(find.text('\u2014'), findsOneWidget);
    });

    testWidgets('inProgressCell renders italic text', (tester) async {
      await tester.pumpWidget(buildApp(
        AppDashboardTable(
          title: 'In Progress',
          columns: [const AppDashboardColumn(label: 'Turno')],
          rows: [
            [AppDashboardTable.inProgressCell()],
          ],
        ),
      ));

      expect(find.text('En turno'), findsOneWidget);
      final text = tester.widget<Text>(find.text('En turno'));
      expect(text.style?.fontStyle, FontStyle.italic);
    });
  });
}
