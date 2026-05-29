// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/flows_api.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_dashboard_table.dart';
import '../../shared/widgets/app_kpi_card.dart';
import 'dashboard_providers.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

/// Key compuesta: slug + rango de fechas + filtro metadata opcional
typedef _DashKey = ({String slug, String? start, String? end, String? filterKey, String? filterValue});

/// Carga la lista de dashboards desde API.
final dashboardsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return FlowsApi.listDashboardConfigurations();
});

/// Rango de fechas seleccionado. null = hoy (sin filtro explícito)
final dashboardDateRangeProvider = StateProvider<DateTimeRange?>((ref) => null);

/// Filtro metadata activo (e.g. CRUM). key = nombre del campo, value = valor buscado.
final dashboardMetaFilterKeyProvider   = StateProvider<String?>((ref) => null);
final dashboardMetaFilterValueProvider = StateProvider<String?>((ref) => null);

final dashboardKpisProvider =
    FutureProvider.family<Map<String, dynamic>, _DashKey>((ref, key) async {
  return FlowsApi.getDashboardKpis(
    key.slug,
    dateRangeStart: key.start,
    dateRangeEnd: key.end,
  );
});

final dashboardChartsProvider =
    FutureProvider.family<Map<String, dynamic>, _DashKey>((ref, key) async {
  return FlowsApi.getDashboardCharts(
    key.slug,
    dateRangeStart: key.start,
    dateRangeEnd: key.end,
  );
});

final dashboardActivityProvider =
    FutureProvider.family<List<Map<String, dynamic>>, _DashKey>((ref, key) async {
  return FlowsApi.getDashboardActivity(
    key.slug,
    dateRangeStart: key.start,
    dateRangeEnd: key.end,
  );
});

// ── Pantalla ──────────────────────────────────────────────────────────────────

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Column(
      children: [
        _ActionBar(),
        Expanded(child: _DashboardBody()),
      ],
    );
  }
}

// ── Action bar ────────────────────────────────────────────────────────────────

class _ActionBar extends ConsumerWidget {
  const _ActionBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(dashboardDateRangeProvider);
    final metaFilterValue = ref.watch(dashboardMetaFilterValueProvider);

    // Resolve metadata_filters from the active dashboard config (cached, no extra call).
    final dashboards = ref.watch(dashboardsProvider).valueOrNull ?? [];
    final activeDash = dashboards.isEmpty
        ? null
        : dashboards.firstWhere(
            (d) => d['is_default'] == true,
            orElse: () => dashboards.first,
          );
    final metaFilters = activeDash == null
        ? <Map<String, dynamic>>[]
        : (activeDash['metadata_filters'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            <Map<String, dynamic>>[];

    return Container(
      height: 48,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.ctSurface,
        border: Border(bottom: BorderSide(color: AppColors.ctBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Dashboard',
                  style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist'),
                ),
                SizedBox(height: 1),
                Text(
                  'Panel operativo · actualiza cada 45s',
                  style: AppTextStyles.pageSubtitle,
                ),
              ],
            ),
          ),
          // ── Metadata filter fields ─────────────────────────────────────────
          for (final filter in metaFilters) ...[
            const SizedBox(width: 8),
            Text(
              filter['label'] as String? ?? filter['key'] as String? ?? '',
              style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
            ),
            const SizedBox(width: 6),
            _MetaFilterField(
              filterKey: filter['key'] as String? ?? '',
              currentValue: metaFilterValue,
            ),
          ],
          // ── Date range ────────────────────────────────────────────────────
          const SizedBox(width: 8),
          _DateRangeButton(
            range: range,
            onTap: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2025),
                lastDate: DateTime.now(),
                initialDateRange: ref.read(dashboardDateRangeProvider),
              );
              if (picked != null) {
                ref.read(dashboardDateRangeProvider.notifier).state = picked;
              }
            },
            onClear: () =>
                ref.read(dashboardDateRangeProvider.notifier).state = null,
          ),
          const SizedBox(width: 8),
          _RefreshButton(
            onTap: () {
              ref.invalidate(dashboardKpisProvider);
              ref.invalidate(dashboardChartsProvider);
              ref.invalidate(dashboardActivityProvider);
              ref.invalidate(dashboardsProvider);
              ref.invalidate(tableDataProvider);
            },
          ),
        ],
      ),
    );
  }
}

// ── Date range button ─────────────────────────────────────────────────────────

class _DateRangeButton extends StatelessWidget {
  const _DateRangeButton({
    required this.range,
    required this.onTap,
    required this.onClear,
  });
  final DateTimeRange? range;
  final VoidCallback onTap;
  final VoidCallback onClear;

  String get _label {
    if (range == null) return 'Hoy';
    String pad(int n) => n.toString().padLeft(2, '0');
    final s = range!.start;
    final e = range!.end;
    return '${pad(s.day)}/${pad(s.month)} – ${pad(e.day)}/${pad(e.month)}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.ctBorder2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today_rounded,
                size: 12, color: AppColors.ctText2),
            const SizedBox(width: 6),
            Text(
              _label,
              style: AppTextStyles.bodySmall.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            if (range != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close_rounded,
                    size: 12, color: AppColors.ctText2),
              ),
            ] else ...[
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 14, color: AppColors.ctText2),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Metadata filter field ─────────────────────────────────────────────────────

class _MetaFilterField extends ConsumerStatefulWidget {
  const _MetaFilterField({required this.filterKey, this.currentValue});
  final String filterKey;
  final String? currentValue;

  @override
  ConsumerState<_MetaFilterField> createState() => _MetaFilterFieldState();
}

class _MetaFilterFieldState extends ConsumerState<_MetaFilterField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentValue ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _apply() {
    final val = _ctrl.text.trim();
    ref.read(dashboardMetaFilterKeyProvider.notifier).state =
        val.isEmpty ? null : widget.filterKey;
    ref.read(dashboardMetaFilterValueProvider.notifier).state =
        val.isEmpty ? null : val;
  }

  void _clear() {
    _ctrl.clear();
    ref.read(dashboardMetaFilterKeyProvider.notifier).state = null;
    ref.read(dashboardMetaFilterValueProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = ref.watch(dashboardMetaFilterValueProvider) != null;
    return SizedBox(
      width: 140,
      height: 32,
      child: TextField(
        controller: _ctrl,
        style: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: AppColors.ctText),
        decoration: InputDecoration(
          hintText: 'Filtrar...',
          hintStyle: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: AppColors.ctText3),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          suffixIcon: hasValue
              ? GestureDetector(
                  onTap: _clear,
                  child: const Icon(Icons.close_rounded,
                      size: 14, color: AppColors.ctText2),
                )
              : null,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.ctBorder2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.ctTeal, width: 1.5),
          ),
        ),
        onEditingComplete: _apply,
        onSubmitted: (_) => _apply(),
      ),
    );
  }
}

// ── Ghost button (reservado para uso futuro) ──────────────────────────────────

// ── Cuerpo principal ──────────────────────────────────────────────────────────

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncDashboards = ref.watch(dashboardsProvider);
    return asyncDashboards.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.ctTeal),
      ),
      error: (e, _) => Center(
        child: Text(
          'Error al cargar dashboard',
          style: AppTextStyles.pageSubtitle,
        ),
      ),
      data: (dashboards) {
        if (dashboards.isEmpty) return const _EmptyView();
        final dashboard = dashboards.firstWhere(
          (d) => d['is_default'] == true,
          orElse: () => dashboards.first,
        );
        return _ConfiguredView(dashboard: dashboard);
      },
    );
  }
}

// ── Estado vacío ──────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.dashboard_outlined, size: 48, color: AppColors.ctText2),
          const SizedBox(height: 16),
          Text(
            'Sin dashboard configurado',
            style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist', fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Contacta a Conectamos para configurar\ntu panel operativo.',
            textAlign: TextAlign.center,
            style: AppTextStyles.pageSubtitle,
          ),
        ],
      ),
    );
  }
}

// ── Vista configurada ─────────────────────────────────────────────────────────

class _ConfiguredView extends ConsumerWidget {
  const _ConfiguredView({required this.dashboard});
  final Map<String, dynamic> dashboard;

  List<Widget> _buildRows(
    List<Map<String, dynamic>> sortedWidgets,
    Map<String, dynamic> kpis,
    Map<String, dynamic> charts,
    List<Map<String, dynamic>> activityData,
    double maxWidth, {
    String slug = '',
    String? start,
    String? end,
    String? filterKey,
    String? filterValue,
  }) {
    final result = <Widget>[];
    final buffer = <Map<String, dynamic>>[];

    Widget rendererFor(Map<String, dynamic> w) {
      final id = w['id'] as String? ?? '';
      final type = w['widget_type'] as String? ?? '';
      final isBroken = w['broken'] as bool? ?? false;
      if (isBroken) {
        final widgetTitle = w['title'] as String? ?? '';
        return _DashCard(
          title: widgetTitle.toUpperCase(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 18, color: AppColors.ctWarn),
              const SizedBox(width: 8),
              Text(
                'Configuración desactualizada',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
              ),
            ],
          ),
        );
      }
      if (type == 'data_table') {
        return _DataTableWidget(
          title: w['title'] as String? ?? '',
          config: (w['config'] as Map<String, dynamic>?) ?? {},
          dashboardSlug: slug,
          widgetId: id,
          dateRangeStart: start,
          dateRangeEnd: end,
          metadataFilterKey: filterKey,
          metadataFilterValue: filterValue,
        );
      }
      return _DashboardWidgetRenderer(
        widgetConfig: w,
        kpiData: kpis[id] as Map<String, dynamic>?,
        chartData: charts[id] as Map<String, dynamic>?,
        activityData: activityData,
      );
    }

    void flushBuffer() {
      if (buffer.isEmpty) return;
      Widget rowWidget;
      if (buffer.length == 1) {
        rowWidget = rendererFor(buffer.first);
      } else if (maxWidth < 600) {
        rowWidget = Column(
          children: buffer
              .map((w) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: rendererFor(w),
                  ))
              .toList(),
        );
      } else {
        final children = <Widget>[];
        for (int i = 0; i < buffer.length; i++) {
          children.add(Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < buffer.length - 1 ? 12 : 0),
              child: rendererFor(buffer[i]),
            ),
          ));
        }
        rowWidget = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        );
      }
      result.add(Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: rowWidget,
      ));
      buffer.clear();
    }

    String? activeHint; // 'kpi_row' | 'chart_row' | null

    for (final w in sortedWidgets) {
      final config = (w['config'] as Map<String, dynamic>?) ?? {};
      final hint = config['layout_hint'] as String?;
      if (hint == 'kpi_row' || hint == 'chart_row') {
        if (hint != activeHint && buffer.isNotEmpty) {
          // Different group type — flush before starting new buffer
          flushBuffer();
        }
        activeHint = hint;
        buffer.add(w);
      } else {
        flushBuffer();
        activeHint = null;
        result.add(Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: rendererFor(w),
        ));
      }
    }
    flushBuffer();

    return result;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slug = dashboard['slug'] as String? ?? '';
    final range = ref.watch(dashboardDateRangeProvider);
    final metaFilterKey   = ref.watch(dashboardMetaFilterKeyProvider);
    final metaFilterValue = ref.watch(dashboardMetaFilterValueProvider);
    String? start;
    String? end;
    if (range != null) {
      start = range.start.toUtc().toIso8601String();
      end = range.end.toUtc()
          .add(const Duration(hours: 23, minutes: 59, seconds: 59))
          .toIso8601String();
    }
    final key = (slug: slug, start: start, end: end,
        filterKey: metaFilterKey, filterValue: metaFilterValue);

    final asyncKpis = ref.watch(dashboardKpisProvider(key));
    final kpis = asyncKpis.valueOrNull ?? <String, dynamic>{};
    final asyncCharts = ref.watch(dashboardChartsProvider(key));
    final charts = asyncCharts.valueOrNull ?? <String, dynamic>{};
    final asyncActivity = ref.watch(dashboardActivityProvider(key));
    final activityData = asyncActivity.valueOrNull ?? <Map<String, dynamic>>[];

    final widgets = (dashboard['widgets'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    widgets.sort((a, b) =>
        ((a['position'] as num?) ?? 0).compareTo((b['position'] as num?) ?? 0));

    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = _buildRows(
            widgets, kpis, charts, activityData, constraints.maxWidth,
            slug: slug, start: start, end: end,
            filterKey: metaFilterKey, filterValue: metaFilterValue);
        final brokenCount = widgets.where((w) => w['broken'] as bool? ?? false).length;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dashboard['name'] as String? ?? 'Dashboard',
                style: AppTextStyles.kpiValue.copyWith(fontFamily: 'Geist', fontSize: 20),
              ),
              if (brokenCount > 0) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.ctWarn.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.ctWarn.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 16, color: AppColors.ctWarn),
                      const SizedBox(width: 8),
                      Text(
                        '$brokenCount widget${brokenCount > 1 ? 's' : ''} con configuración desactualizada',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              ...rows,
            ],
          ),
        );
      },
    );
  }
}

// ── Renderer de widget individual ─────────────────────────────────────────────

class _DashboardWidgetRenderer extends StatelessWidget {
  const _DashboardWidgetRenderer({
    required this.widgetConfig,
    this.kpiData,
    this.chartData,
    this.activityData,
  });
  final Map<String, dynamic> widgetConfig;
  final Map<String, dynamic>? kpiData;
  final Map<String, dynamic>? chartData;
  final List<Map<String, dynamic>>? activityData;

  @override
  Widget build(BuildContext context) {
    final type = widgetConfig['widget_type'] as String? ?? '';
    final title = widgetConfig['title'] as String? ?? '';
    final config = (widgetConfig['config'] as Map<String, dynamic>?) ?? {};

    switch (type) {
      case 'kpi_card':
        return _KpiCardWidget(title: title, config: config, kpiData: kpiData);
      case 'execution_table':
        return _ExecutionTableWidget(title: title, config: config);
      case 'operator_status_grid':
        return _OperatorGridWidget(title: title, config: config);
      case 'flow_action_button':
        return _FlowActionButton(title: title, config: config);
      case 'recent_activity_feed':
        return _RecentActivityWidget(
            title: title, config: config, activityData: activityData);
      case 'bar_chart':
        return _BarChartWidget(title: title, config: config, chartData: chartData);
      case 'operator_ranking':
        return _OperatorRankingWidget(
            title: title, config: config, chartData: chartData);
      default:
        return const SizedBox.shrink();
    }
  }
}

// ── Widget base card ──────────────────────────────────────────────────────────

class _DashCard extends StatelessWidget {
  const _DashCard({required this.title, this.subtitle, required this.child});
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ctBorder),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.bodySmall.copyWith(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: AppTextStyles.pageSubtitle),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ── kpi_card ──────────────────────────────────────────────────────────────────

class _KpiCardWidget extends StatelessWidget {
  const _KpiCardWidget({
    required this.title,
    required this.config,
    this.kpiData,
  });
  final String title;
  final Map<String, dynamic> config;
  final Map<String, dynamic>? kpiData;

  Color _accentColor() {
    final colorKey =
        kpiData?['color'] as String? ?? config['color'] as String? ?? 'default';
    switch (colorKey) {
      case 'green':
        return AppColors.ctOk;
      case 'red':
        return AppColors.ctDanger;
      case 'amber':
        return AppColors.ctWarn;
      default:
        return AppColors.ctTeal;
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = kpiData?['value'];
    final label =
        kpiData?['label'] as String? ?? config['label'] as String? ?? '';
    final displayValue = value != null ? value.toString() : '—';

    return AppKpiCard(
      label: title.toUpperCase(),
      value: displayValue,
      subtitle: label.isNotEmpty ? label : null,
      accentColor: _accentColor(),
    );
  }
}

// ── execution_table ───────────────────────────────────────────────────────────

class _ExecutionTableWidget extends StatelessWidget {
  const _ExecutionTableWidget({required this.title, required this.config});
  final String title;
  final Map<String, dynamic> config;

  @override
  Widget build(BuildContext context) {
    final subtitle = config['subtitle'] as String?;
    return _DashCard(
      title: title.toUpperCase(),
      subtitle: subtitle,
      child: const _ComingSoonChip(),
    );
  }
}

// ── operator_status_grid ──────────────────────────────────────────────────────

class _OperatorGridWidget extends StatelessWidget {
  const _OperatorGridWidget({required this.title, required this.config});
  final String title;
  final Map<String, dynamic> config;

  @override
  Widget build(BuildContext context) {
    final subtitle = config['subtitle'] as String?;
    return _DashCard(
      title: title.toUpperCase(),
      subtitle: subtitle,
      child: const _ComingSoonChip(),
    );
  }
}

// ── flow_action_button ────────────────────────────────────────────────────────

class _FlowActionButton extends StatelessWidget {
  const _FlowActionButton({required this.title, required this.config});
  final String title;
  final Map<String, dynamic> config;

  @override
  Widget build(BuildContext context) {
    final label = config['label'] as String? ?? title;
    // Sprint siguiente: disparar flow
    return AppButton(
      label: label,
      variant: AppButtonVariant.teal,
      expand: true,
      isDisabled: true,
      prefixIcon: const Icon(Icons.play_arrow_rounded, size: 16, color: AppColors.ctNavy),
      onPressed: () {},
    );
  }
}

// ── recent_activity_feed ──────────────────────────────────────────────────────

class _RecentActivityWidget extends StatelessWidget {
  const _RecentActivityWidget({
    required this.title,
    required this.config,
    this.activityData,
  });
  final String title;
  final Map<String, dynamic> config;
  final List<Map<String, dynamic>>? activityData;

  String _formatTime(String? isoString) {
    if (isoString == null) return '—';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = activityData ?? [];

    if (items.isEmpty) {
      return _DashCard(
        title: title.toUpperCase(),
        child: const _ComingSoonChip(),
      );
    }

    return _DashCard(
      title: title.toUpperCase(),
      child: Column(
        children: items.map((item) {
          final isDelivery = item['is_delivery'] as bool? ?? true;
          final operatorName = item['operator_name'] as String? ?? '—';
          final orderNumber = item['order_number'] as String? ?? '—';
          final completedAt = item['completed_at'] as String?;

          return GestureDetector(
            onTap: () {
                final executionId = item['execution_id'] as String?;
                if (executionId != null) {
                  context.go('/executions/$executionId');
                }
              },
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.ctSurface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDelivery
                      ? AppColors.ctOk.withOpacity(0.3)
                      : AppColors.ctDanger.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isDelivery ? AppColors.ctOk : AppColors.ctDanger,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          operatorName,
                          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Orden #$orderNumber',
                          style: AppTextStyles.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        isDelivery ? 'Entregado' : 'Fallido',
                        style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: isDelivery ? AppColors.ctOk : AppColors.ctDanger),
                      ),
                      Text(
                        _formatTime(completedAt),
                        style: AppTextStyles.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: AppColors.ctText2,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── bar_chart (pie chart) ─────────────────────────────────────────────────────

class _BarChartWidget extends StatefulWidget {
  const _BarChartWidget({
    required this.title,
    required this.config,
    this.chartData,
  });
  final String title;
  final Map<String, dynamic> config;
  final Map<String, dynamic>? chartData;

  @override
  State<_BarChartWidget> createState() => _BarChartWidgetState();
}

class _BarChartWidgetState extends State<_BarChartWidget> {
  int _touchedIndex = -1;

  static const _colors = [
    Color(0xFFEF4444),
    Color(0xFFF59E0B),
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
    Color(0xFF10B981),
    Color(0xFFF97316),
    Color(0xFF06B6D4),
    Color(0xFFEC4899),
  ];

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.config['subtitle'] as String?;
    final data = (widget.chartData?['data'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    if (data.isEmpty) {
      return _DashCard(
        title: widget.title.toUpperCase(),
        subtitle: subtitle,
        child: const _ComingSoonChip(),
      );
    }

    final total = data.fold<double>(
        0, (s, e) => s + (e['value'] as num).toDouble());

    final sections = data.asMap().entries.map((entry) {
      final i = entry.key;
      final item = entry.value;
      final value = (item['value'] as num).toDouble();
      final isTouched = i == _touchedIndex;
      return PieChartSectionData(
        value: value,
        color: _colors[i % _colors.length],
        radius: isTouched ? 60 : 50,
        title: '',
        showTitle: false,
      );
    }).toList();

    return _DashCard(
      title: widget.title.toUpperCase(),
      subtitle: subtitle,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: 160,
            width: 160,
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 40,
                sectionsSpace: 2,
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {
                    setState(() {
                      if (!event.isInterestedForInteractions ||
                          response == null ||
                          response.touchedSection == null) {
                        _touchedIndex = -1;
                        return;
                      }
                      _touchedIndex =
                          response.touchedSection!.touchedSectionIndex;
                    });
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: data.asMap().entries.map((entry) {
                final i = entry.key;
                final item = entry.value;
                final label = item['label'] as String? ?? '';
                final value = (item['value'] as num).toDouble();
                final pct = total > 0 ? (value / total * 100).round() : 0;
                final isSelected = i == _touchedIndex;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _colors[i % _colors.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          style: AppTextStyles.bodySmall.copyWith(fontSize: isSelected ? 12 : 11, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400, color: AppColors.ctText),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$pct%',
                        style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: _colors[i % _colors.length]),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── operator_ranking ──────────────────────────────────────────────────────────

class _OperatorRankingWidget extends StatelessWidget {
  const _OperatorRankingWidget({
    required this.title,
    required this.config,
    this.chartData,
  });
  final String title;
  final Map<String, dynamic> config;
  final Map<String, dynamic>? chartData;

  @override
  Widget build(BuildContext context) {
    final subtitle = config['subtitle'] as String?;
    final data = (chartData?['data'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    if (data.isEmpty) {
      return _DashCard(
        title: title.toUpperCase(),
        subtitle: subtitle,
        child: const _ComingSoonChip(),
      );
    }

    return _DashCard(
      title: title.toUpperCase(),
      subtitle: subtitle,
      child: Column(
        children: data.map((item) {
          final rank = item['rank'] as int? ?? 0;
          final name = item['name'] as String? ?? '';
          final rate = (item['value'] as num).toDouble();
          final total = item['total'] as int? ?? 0;
          final numerator = item['numerator'] as int? ?? 0;

          final medal = rank == 1
              ? '🥇'
              : rank == 2
                  ? '🥈'
                  : rank == 3
                      ? '🥉'
                      : '#$rank';
          final color = rate >= 80
              ? AppColors.ctOk
              : rate >= 60
                  ? AppColors.ctWarn
                  : AppColors.ctDanger;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text(medal, style: AppTextStyles.body.copyWith(fontSize: 14)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: rate / 100,
                          minHeight: 5,
                          backgroundColor: AppColors.ctSurface2,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${rate.toInt()}%',
                      style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w700, color: color),
                    ),
                    Text(
                      '$numerator/$total',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── data_table ────────────────────────────────────────────────────────────────

class _DataTableWidget extends ConsumerWidget {
  const _DataTableWidget({
    required this.title,
    required this.config,
    required this.dashboardSlug,
    required this.widgetId,
    this.dateRangeStart,
    this.dateRangeEnd,
    this.metadataFilterKey,
    this.metadataFilterValue,
  });
  final String title;
  final Map<String, dynamic> config;
  final String dashboardSlug;
  final String widgetId;
  final String? dateRangeStart;
  final String? dateRangeEnd;
  final String? metadataFilterKey;
  final String? metadataFilterValue;

  static String _fmtCell(dynamic value) {
    if (value == null) return '';
    final str = value.toString();
    if (str.isEmpty) return '';
    if (!str.contains('T') && !(str.contains('-') && str.length >= 10)) return str;
    try {
      // UTC-6 approximation for America/Mexico_City (no timezone package)
      final dt = DateTime.parse(str).toUtc().subtract(const Duration(hours: 6));
      return DateFormat('dd/MM HH:mm').format(dt);
    } catch (_) {
      return str;
    }
  }

  static void _downloadXlsx(
    List<Map<String, dynamic>> columns,
    List<Map<String, dynamic>> rows,
    String title,
  ) {
    try {
      final headers = columns
          .map((c) => c['label'] as String? ?? c['field'] as String? ?? '')
          .toList();
      final dataRows = rows.map((row) {
        return columns.map((col) {
          final colKey = col['key'] as String? ?? '';
          return _fmtCell(row[colKey]);
        }).toList();
      }).toList();

      final allRows = [headers, ...dataRows];
      final sheetName = title.replaceAll(RegExp(r'[^\w\s]'), '').trim();

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
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>',
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
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>',
        '</Relationships>',
      ].join());

      addFile('xl/workbook.xml', [
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
            ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">',
        '<sheets>',
        '<sheet name="${_dtXmlEscape(sheetName.isEmpty ? 'Datos' : sheetName)}" sheetId="1" r:id="rId1"/>',
        '</sheets>',
        '</workbook>',
      ].join());

      addFile('xl/styles.xml', [
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
        '<fonts count="2">',
        '<font><sz val="11"/><name val="Calibri"/></font>',
        '<font><b/><sz val="11"/><name val="Calibri"/></font>',
        '</fonts>',
        '<fills count="2">',
        '<fill><patternFill patternType="none"/></fill>',
        '<fill><patternFill patternType="gray125"/></fill>',
        '</fills>',
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>',
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>',
        '<cellXfs count="2">',
        '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>',
        '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0"/>',
        '</cellXfs>',
        '</styleSheet>',
      ].join());

      addFile('xl/worksheets/sheet1.xml', _dtSheetXml(allRows));

      final zipBytes = ZipEncoder().encode(archive)!;
      final fileName =
          '${title}_${DateTime.now().millisecondsSinceEpoch}.xlsx'.replaceAll(' ', '_');

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
      debugPrint('[_DataTableWidget._downloadXlsx] error: $e\n$st');
    }
  }

  Color _resolveAccentColor() {
    final t = title.toLowerCase();
    if (t.contains('receta') || t.contains('entrega')) return AppColors.ctTeal;
    if (t.contains('turno')) return const Color(0xFF378ADD);
    return AppColors.ctTeal;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (
      dashboardSlug: dashboardSlug,
      widgetId: widgetId,
      start: dateRangeStart,
      end: dateRangeEnd,
      filterKey: metadataFilterKey,
      filterValue: metadataFilterValue,
    );
    final asyncData = ref.watch(tableDataProvider(key));
    final displayTitle = title.isNotEmpty ? title : (config['title'] as String? ?? widgetId);
    final subtitle = config['subtitle'] as String?;

    return asyncData.when(
      loading: () => const SizedBox(
        height: 80,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.ctTeal, strokeWidth: 2),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            e.toString(),
            style: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: AppColors.ctDanger),
          ),
        ),
      ),
      data: (data) {
        final apiColumns = (data['columns'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        final apiRows = (data['rows'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();

        final tableColumns = apiColumns.map((col) {
          final label = col['label'] as String? ?? col['key'] as String? ?? '';
          final flex = (col['flex'] as num?)?.toInt() ?? 1;
          final alignRaw = col['alignment'] as String?;
          final isStatus = label.toLowerCase() == 'estatus';
          final alignment = (alignRaw == 'right' || isStatus)
              ? TextAlign.right
              : TextAlign.left;
          return AppDashboardColumn(label: label, flex: flex, alignment: alignment);
        }).toList();

        final tableRows = apiRows.map((row) {
          return apiColumns.map((col) {
            final colKey = col['key'] as String? ?? '';
            final colField = col['field'] as String? ?? '';
            final value = row[colKey];
            final formatted = _fmtCell(value);

            // Status column
            if (colField == 'status' || colKey == 'status') {
              return AppDashboardTable.statusCell(value as String?);
            }

            // Null / empty handling
            if (value == null || formatted.isEmpty) {
              if (colField == 'completed_at' || colKey == 'completed_at') {
                return AppDashboardTable.inProgressCell();
              }
              return AppDashboardTable.emptyCell();
            }

            // Date columns
            if (formatted.contains('/') && formatted.contains(':')) {
              return AppDashboardTable.dateCell(formatted);
            }

            // Primary text (name-like fields)
            final isPrimary = colField == 'operator_name' ||
                colField == 'name' ||
                colKey == 'operator_name' ||
                colKey == 'name';
            return AppDashboardTable.textCell(formatted, primary: isPrimary);
          }).toList();
        }).toList();

        return AppDashboardTable(
          title: displayTitle,
          subtitle: subtitle,
          accentColor: _resolveAccentColor(),
          columns: tableColumns,
          rows: tableRows,
          onDownload: (apiColumns.isNotEmpty && apiRows.isNotEmpty)
              ? () => _downloadXlsx(apiColumns, apiRows, displayTitle)
              : null,
        );
      },
    );
  }
}

// ── XLSX helpers (data_table) ─────────────────────────────────────────────────

String _dtColName(int index) {
  var name = '';
  var i = index;
  do {
    name = String.fromCharCode(65 + (i % 26)) + name;
    i = (i ~/ 26) - 1;
  } while (i >= 0);
  return name;
}

String _dtXmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _dtSheetXml(List<List<String>> rows) {
  final sb = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
    ..write('<sheetData>');
  for (var r = 0; r < rows.length; r++) {
    sb.write('<row r="${r + 1}">');
    final bold = r == 0;
    for (var c = 0; c < rows[r].length; c++) {
      final cell = '${_dtColName(c)}${r + 1}';
      final val = _dtXmlEscape(rows[r][c]);
      final sAttr = bold ? ' s="1"' : '';
      sb.write('<c r="$cell" t="inlineStr"$sAttr><is><t>$val</t></is></c>');
    }
    sb.write('</row>');
  }
  sb.write('</sheetData></worksheet>');
  return sb.toString();
}

// ── Placeholder chip ──────────────────────────────────────────────────────────

class _ComingSoonChip extends StatelessWidget {
  const _ComingSoonChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.ctSurface2,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Datos en tiempo real — próximo sprint',
        style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
      ),
    );
  }
}

// ── Refresh button ────────────────────────────────────────────────────────────

class _RefreshButton extends ConsumerStatefulWidget {
  const _RefreshButton({required this.onTap});
  final VoidCallback onTap;

  @override
  ConsumerState<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends ConsumerState<_RefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    _ctrl.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.ctBorder2),
        ),
        child: RotationTransition(
          turns: CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
          child: const Icon(
            Icons.refresh_rounded,
            size: 14,
            color: AppColors.ctText2,
          ),
        ),
      ),
    );
  }
}
