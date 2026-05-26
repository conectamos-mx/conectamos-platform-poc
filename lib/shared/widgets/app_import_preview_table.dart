import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

// ── Data classes ────────────────────────────────────────────────────────────

class ImportColumn {
  const ImportColumn({required this.header, required this.key});
  final String header;
  final String key;
}

class ImportRowError {
  const ImportRowError({required this.field, required this.message});
  final String field;
  final String message;
}

class ImportRow {
  const ImportRow({
    required this.row,
    required this.data,
    this.errors = const [],
  });
  final int row;
  final Map<String, dynamic> data;
  final List<ImportRowError> errors;

  bool get isValid => errors.isEmpty;
}

// ── Widget ──────────────────────────────────────────────────────────────────

class AppImportPreviewTable extends StatelessWidget {
  const AppImportPreviewTable({
    super.key,
    required this.columns,
    required this.rows,
    this.maxHeight = 400,
  });

  final List<ImportColumn> columns;
  final List<ImportRow> rows;
  final double? maxHeight;

  int get _validCount => rows.where((r) => r.isValid).length;
  int get _errorCount => rows.where((r) => !r.isValid).length;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: BoxConstraints(
            maxHeight: maxHeight ?? 400,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.ctBorder),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SingleChildScrollView(
              child: _buildTable(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _SummaryRow(validCount: _validCount, errorCount: _errorCount),
      ],
    );
  }

  Widget _buildTable() {
    return Table(
      columnWidths: {
        0: const FixedColumnWidth(42),
        for (int i = 0; i < columns.length; i++)
          i + 1: const FlexColumnWidth(),
        columns.length + 1: const FixedColumnWidth(42),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        _buildHeaderRow(),
        ...rows.map(_buildDataRow),
      ],
    );
  }

  TableRow _buildHeaderRow() {
    return TableRow(
      decoration: const BoxDecoration(color: AppColors.ctSurface2),
      children: [
        _HeaderCell(label: '#'),
        ...columns.map((c) => _HeaderCell(label: c.header)),
        const _HeaderCell(label: ''),
      ],
    );
  }

  TableRow _buildDataRow(ImportRow row) {
    final hasError = !row.isValid;
    final bgColor = hasError
        ? AppColors.ctDanger.withValues(alpha: 0.04)
        : AppColors.ctSurface;

    String? errorText;
    if (hasError) {
      final first = row.errors.first;
      errorText = '${first.field}: ${first.message}';
      if (row.errors.length > 1) {
        errorText = '$errorText +${row.errors.length - 1} mas';
      }
    }

    return TableRow(
      decoration: BoxDecoration(
        color: bgColor,
        border: const Border(
          bottom: BorderSide(color: AppColors.ctBorder, width: 0.5),
        ),
      ),
      children: [
        _DataCell(value: '${row.row}'),
        ...columns.map((c) {
          final val = row.data[c.key];
          return _DataCell(value: val?.toString() ?? '');
        }),
        _StatusCell(isValid: row.isValid, errorText: errorText),
      ],
    );
  }
}

// ── Header cell ─────────────────────────────────────────────────────────────

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text(
        label.toUpperCase(),
        style: AppTextStyles.formLabel.copyWith(
          fontSize: 10,
          color: AppColors.ctText2,
        ),
      ),
    );
  }
}

// ── Data cell ───────────────────────────────────────────────────────────────

class _DataCell extends StatelessWidget {
  const _DataCell({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text(
        value,
        style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ── Status cell ─────────────────────────────────────────────────────────────

class _StatusCell extends StatelessWidget {
  const _StatusCell({required this.isValid, this.errorText});
  final bool isValid;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final icon = isValid
        ? const Icon(Icons.check_circle, size: 16, color: AppColors.ctTeal)
        : const Icon(Icons.cancel, size: 16, color: AppColors.ctDanger);

    if (errorText == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: icon,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Tooltip(
        message: errorText!,
        child: icon,
      ),
    );
  }
}

// ── Summary row ─────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.validCount, required this.errorCount});
  final int validCount;
  final int errorCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$validCount validas',
          style: AppTextStyles.caption.copyWith(color: AppColors.ctOkText),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '\u00b7',
            style: AppTextStyles.caption.copyWith(color: AppColors.ctText3),
          ),
        ),
        Text(
          '$errorCount con errores',
          style: AppTextStyles.caption.copyWith(color: AppColors.ctRedText),
        ),
      ],
    );
  }
}
