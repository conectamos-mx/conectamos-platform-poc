import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import 'app_badge.dart';

// ── Column definition ────────────────────────────────────────────────────────

class AppDashboardColumn {
  const AppDashboardColumn({
    required this.label,
    this.flex = 1,
    this.alignment = TextAlign.left,
  });

  final String label;
  final int flex;
  final TextAlign alignment;
}

// ── AppDashboardTable ────────────────────────────────────────────────────────

class AppDashboardTable extends StatelessWidget {
  const AppDashboardTable({
    super.key,
    required this.title,
    this.subtitle,
    this.accentColor = AppColors.ctTeal,
    required this.columns,
    required this.rows,
    this.onDownload,
    this.emptyMessage = 'Sin datos en el período',
  });

  final String title;
  final String? subtitle;
  final Color accentColor;
  final List<AppDashboardColumn> columns;
  final List<List<Widget>> rows;
  final VoidCallback? onDownload;
  final String emptyMessage;

  // ── Cell helpers ───────────────────────────────────────────────────────────

  static Widget dateCell(String date) => Text(
        date,
        style: AppTextStyles.bodySmall.copyWith(
          color: AppColors.ctText2,
          fontFamily: 'GeistMono',
        ),
      );

  static Widget textCell(String text, {bool primary = false}) => Text(
        text,
        style: primary
            ? AppTextStyles.body.copyWith(fontWeight: FontWeight.w500)
            : AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2),
      );

  static Widget emptyCell({String label = '\u2014'}) => Text(
        label,
        style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
      );

  static Widget inProgressCell() => Text(
        'En turno',
        style: AppTextStyles.bodySmall.copyWith(
          color: AppColors.ctText3,
          fontStyle: FontStyle.italic,
        ),
      );

  static Widget statusCell(String? status) {
    final AppBadgeVariant variant;
    final String label;
    switch (status) {
      case 'completed':
        variant = AppBadgeVariant.ok;
        label = 'Completado';
      case 'pending':
        variant = AppBadgeVariant.warn;
        label = 'Pendiente';
      case 'failed':
        variant = AppBadgeVariant.danger;
        label = 'Fallido';
      default:
        variant = AppBadgeVariant.neutral;
        label = status ?? '\u2014';
    }
    return AppBadge(label: label, variant: variant);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final columnWidths = <int, TableColumnWidth>{};
    for (var i = 0; i < columns.length; i++) {
      columnWidths[i] = FlexColumnWidth(columns[i].flex.toDouble());
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Accent bar
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(11),
              ),
            ),
          ),

          // Header row: title + download
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.toUpperCase(),
                        style: AppTextStyles.bodySmall.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                          color: AppColors.ctText2,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 12,
                            color: AppColors.ctText3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onDownload != null)
                  TextButton.icon(
                    onPressed: onDownload,
                    icon: Icon(
                      Icons.download_outlined,
                      size: 14,
                      color: AppColors.ctText2,
                    ),
                    label: Text(
                      'Descargar',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.ctText2,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.ctBorder),

          // Table or empty state
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  emptyMessage,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.ctText3,
                  ),
                ),
              ),
            )
          else
            Table(
              border: const TableBorder(
                horizontalInside: BorderSide(
                  color: AppColors.ctBorder,
                  width: 0.5,
                ),
              ),
              columnWidths: columnWidths,
              children: [
                // Header
                TableRow(
                  decoration: const BoxDecoration(color: AppColors.ctSurface2),
                  children: [
                    for (var i = 0; i < columns.length; i++)
                      _HeaderCell(
                        label: columns[i].label,
                        alignment: columns[i].alignment,
                        isFirst: i == 0,
                        isLast: i == columns.length - 1,
                      ),
                  ],
                ),
                // Data rows
                for (final row in rows)
                  TableRow(
                    children: [
                      for (var i = 0; i < columns.length; i++)
                        _DataCell(
                          alignment: columns[i].alignment,
                          isFirst: i == 0,
                          isLast: i == columns.length - 1,
                          child: i < row.length ? row[i] : emptyCell(),
                        ),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Private cell wrappers ────────────────────────────────────────────────────

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    required this.alignment,
    required this.isFirst,
    required this.isLast,
  });

  final String label;
  final TextAlign alignment;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: 9,
        horizontal: (isFirst || isLast) ? 20 : 16,
      ),
      child: Text(
        label.toUpperCase(),
        textAlign: alignment,
        style: AppTextStyles.bodySmall.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.ctText2,
        ),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  const _DataCell({
    required this.alignment,
    required this.isFirst,
    required this.isLast,
    required this.child,
  });

  final TextAlign alignment;
  final bool isFirst;
  final bool isLast;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hPadding = (isFirst || isLast) ? 20.0 : 16.0;
    Alignment align;
    switch (alignment) {
      case TextAlign.right:
      case TextAlign.end:
        align = Alignment.centerRight;
      case TextAlign.center:
        align = Alignment.center;
      default:
        align = Alignment.centerLeft;
    }
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: hPadding),
      child: Align(alignment: align, child: child),
    );
  }
}
