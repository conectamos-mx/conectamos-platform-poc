import 'dart:async';
import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/ai_workers_api.dart';
import '../../core/api/api_client.dart';
import '../../core/api/escalaciones_api.dart';
import '../../core/api/operators_api.dart';
import '../../core/api/overview_api.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/relative_time.dart';
import '../../shared/widgets/operator_avatar.dart';
import '../../shared/widgets/screen_header.dart';

// ── Pantalla ──────────────────────────────────────────────────────────────────

class OverviewScreen extends ConsumerStatefulWidget {
  const OverviewScreen({super.key});

  @override
  ConsumerState<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends ConsumerState<OverviewScreen> {
  Map<String, dynamic>? _kpis;
  bool _kpisLoading = false;
  String? _kpisErrorMsg;
  bool _initialized = false;
  DateTime? _lastUpdated;
  int _reloadKey = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tenantId = ref.read(activeTenantIdProvider);
      if (tenantId.isNotEmpty) _fetchKpis(tenantId);
    });
  }

  Future<void> _fetchKpis(String tenantId) async {
    if (tenantId.isEmpty) return;
    setState(() { _kpisLoading = true; _kpisErrorMsg = null; });
    try {
      final data = await OverviewApi.getKpis(dio: ref.read(apiClientProvider).dio, tenantId: tenantId);
      setState(() {
        _kpis = data;
        _kpisLoading = false;
        _initialized = true;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      setState(() {
        _kpisLoading = false;
        _kpisErrorMsg = e.toString();
        _initialized = true;
      });
    }
  }

  void _reload() {
    final tenantId = ref.read(activeTenantIdProvider);
    if (tenantId.isEmpty) return;
    setState(() { _reloadKey++; });
    _fetchKpis(tenantId);
  }

  @override
  Widget build(BuildContext context) {
    final tenantId   = ref.watch(activeTenantIdProvider);
    final tenantName = ref.watch(activeTenantDisplayProvider);

    ref.listen<String>(activeTenantIdProvider, (prev, next) {
      if (next.isNotEmpty && !_initialized && !_kpisLoading) {
        _fetchKpis(next);
      }
    });

    if (tenantId.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        ScreenHeader(
          title: 'Vista general',
          subtitle: tenantName.isNotEmpty ? tenantName : 'Sistema operativo',
          actions: [
            _LastUpdatedLabel(lastUpdated: _lastUpdated),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20, color: AppColors.ctText2),
              tooltip: 'Actualizar',
              onPressed: _reload,
            ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeroBand(
                  kpis: _kpis,
                  loading: _kpisLoading,
                  error: _kpisErrorMsg,
                  onRetry: _reload,
                ),
                // const SizedBox(height: 14),
                // _KpiRow(kpis: _kpis, loading: _kpisLoading, error: _kpisError),
                const SizedBox(height: 14),
                _OperatorsSection(key: ValueKey(_reloadKey), tenantId: tenantId),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 13, child: _WorkersFlows(tenantId: tenantId)),
                    const SizedBox(width: 14),
                    Expanded(flex: 10, child: const _DayThread()),
                    const SizedBox(width: 14),
                    Expanded(flex: 10, child: _Attention(tenantId: tenantId)),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── _LastUpdatedLabel ─────────────────────────────────────────────────────────

class _LastUpdatedLabel extends StatefulWidget {
  const _LastUpdatedLabel({required this.lastUpdated});
  final DateTime? lastUpdated;

  @override
  State<_LastUpdatedLabel> createState() => _LastUpdatedLabelState();
}

class _LastUpdatedLabelState extends State<_LastUpdatedLabel> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _label {
    final lu = widget.lastUpdated;
    if (lu == null) return 'Actualizando...';
    return 'Actualizado ${fmtRelative(lu.toUtc().toIso8601String(), compact: true, showSeconds: true)}';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _label,
      style: AppFonts.geist(fontSize: 12, color: AppColors.ctText2),
    );
  }
}

// ── Fila de KPIs ─────────────────────────────────────────────────────────────

// ignore: unused_element
class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.kpis,
    required this.loading,
    required this.error,
  });

  final Map<String, dynamic>? kpis;
  final bool loading;
  final bool error;

  String _val(String key) {
    if (loading) return '...';
    if (error || kpis == null) return '—';
    return kpis![key]?.toString() ?? '—';
  }

  @override
  Widget build(BuildContext context) {
    final activeOps = loading ? null : (kpis?['operators_active'] as num?)?.toInt();
    final totalOps  = loading ? null : (kpis?['operators_total']  as num?)?.toInt();

    final opsValue = loading
        ? '...'
        : (error || kpis == null)
            ? '— / —'
            : '${activeOps ?? '—'} / ${totalOps ?? '—'}';

    final inactivos = (activeOps != null && totalOps != null)
        ? totalOps - activeOps
        : null;
    final opsSub = inactivos != null
        ? '$inactivos sin turno hoy'
        : 'Operadores en turno activo';

    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            Expanded(
              child: KpiCard(
                topBorderColor: AppColors.ctTeal,
                label: 'OPERADORES ACTIVOS',
                value: opsValue,
                subtext: opsSub,
                hasError: error,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: KpiCard(
                topBorderColor: AppColors.ctOk,
                label: 'FLUJOS ACTIVOS',
                value: _val('flows_active'),
                subtext: 'En curso ahora',
                hasError: error,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: KpiCard(
                topBorderColor: AppColors.ctWarn,
                label: 'FLUJOS COMPLETADOS HOY',
                value: _val('flows_completed_today'),
                subtext: 'Desde medianoche',
                hasError: error,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: KpiCard(
                topBorderColor: AppColors.ctDanger,
                label: 'WORKERS CONTRATADOS',
                value: _val('workers_contracted'),
                subtext: 'Activos en tu operación',
                hasError: error,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── KpiCard ───────────────────────────────────────────────────────────────────

class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.topBorderColor,
    required this.label,
    required this.value,
    required this.subtext,
    this.hasError = false,
  });

  final Color  topBorderColor;
  final String label;
  final String value;
  final String subtext;
  final bool   hasError;

  @override
  Widget build(BuildContext context) {
    final valueWidget = hasError
        ? Tooltip(
            message: 'Error al cargar',
            child: Text(
              value,
              style: AppFonts.onest(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.ctText3,
                height: 1,
              ),
            ),
          )
        : Text(
            value,
            style: AppFonts.onest(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.ctText,
              height: 1,
            ),
          );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: topBorderColor,
              borderRadius: const BorderRadius.only(
                topLeft:  Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: AppTextStyles.kpiLabel,
          ),
          const SizedBox(height: 8),
          valueWidget,
          const SizedBox(height: 5),
          Text(
            subtext,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
          ),
        ],
      ),
    );
  }
}

// ── _HeroBand ─────────────────────────────────────────────────────────────────

class _HeroBand extends StatelessWidget {
  const _HeroBand({
    required this.kpis,
    required this.loading,
    this.error,
    this.onRetry,
  });

  final Map<String, dynamic>? kpis;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final operatorsActive = (kpis?['operators_active']       as num?)?.toInt();
    final operatorsTotal  = (kpis?['operators_total']        as num?)?.toInt();
    final flowsRunning    = (kpis?['flows_running_now']      as num?)?.toInt();
    final flowsCompleted  = (kpis?['flows_completed_today']  as num?)?.toInt();
    final eventsProcessed = (kpis?['events_processed_today'] as num?)?.toInt();
    final completionRate  = (kpis?['completion_rate']        as num?)?.toDouble();
    final workersCont     = (kpis?['workers_contracted']     as num?)?.toInt();
    final flowsCatalog    = (kpis?['flows_catalog_count']    as num?)?.toInt();

    final pct = (operatorsActive != null &&
            operatorsTotal != null &&
            operatorsTotal > 0)
        ? (operatorsActive / operatorsTotal * 100).round()
        : null;

    final completionPct = kpis?.containsKey('completion_rate') == true
        ? '${((completionRate ?? 0.0) * 100).round()}%'
        : '—';

    final paragraphText =
        '${flowsRunning ?? '—'} flujos en ejecución · '
        '${flowsCompleted ?? '—'} completados hoy · '
        '${eventsProcessed ?? '—'} eventos procesados.';

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 200),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF0B132B),
        image: const DecorationImage(
          image: AssetImage('assets/images/hero-bg.png'),
          fit: BoxFit.cover,
          alignment: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xB80B132B),
              Color(0x520B132B),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: loading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                )
              : error != null
              ? Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.ctRedBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.ctDanger),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.ctRedText, size: 16),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(error!, style: AppFonts.geist(fontSize: 12, color: AppColors.ctRedText)),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: onRetry,
                          child: Text('Reintentar', style: AppFonts.geist(fontSize: 12, color: AppColors.ctRedText, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width:  220,
                      height: 220,
                      child: _BigDonut(
                        active:  operatorsActive,
                        total:   operatorsTotal,
                        loading: loading,
                      ),
                    ),
                    const SizedBox(width: 32),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Align(
                            alignment: Alignment.topRight,
                            child: Text(
                              fmtDateLongEs(DateTime.now()),
                              style: AppFonts.geist(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.85),
                                letterSpacing: 0.02,
                              ).copyWith(shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ]),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'TU OPERACIÓN · AHORA',
                            style: AppFonts.geist(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ctTeal,
                              letterSpacing: 0.08,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${pct ?? '—'}% de tu equipo está operando.',
                            style: AppFonts.onest(
                              fontSize: 38,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.03,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            paragraphText,
                            style: AppFonts.geist(
                              fontSize: 14,
                              color: const Color(0xB3FFFFFF),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _MiniMetricChip(
                                label: 'Workers',
                                value: workersCont?.toString() ?? '—',
                              ),
                              _MiniMetricChip(
                                label: 'Flujos del catálogo',
                                value: flowsCatalog?.toString() ?? '—',
                              ),
                              _MiniMetricChip(
                                label: 'Completitud',
                                value: completionPct,
                                highlight: true,
                              ),
                              _MiniMetricChip(
                                label: 'Completados hoy',
                                value: flowsCompleted?.toString() ?? '—',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ── _BigDonut ─────────────────────────────────────────────────────────────────

class _BigDonut extends StatelessWidget {
  const _BigDonut({
    required this.active,
    required this.total,
    required this.loading,
  });

  final int?  active;
  final int?  total;
  final bool  loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 14),
      );
    }

    final progress = (active != null && total != null && total! > 0)
        ? (active! / total!).clamp(0.0, 1.0)
        : 0.0;

    return Stack(
      alignment: Alignment.center,
      children: [
        CustomPaint(
          size: const Size(220, 220),
          painter: _DonutPainter(progress: progress),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              active?.toString() ?? '—',
              style: AppFonts.onest(
                fontSize: 42,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'de ${total ?? '—'} operadores',
              style: AppFonts.geist(
                fontSize: 12,
                color: const Color(0xB3FFFFFF),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'EN TURNO HOY',
              style: AppFonts.geist(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.ctTeal,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── _DonutPainter ─────────────────────────────────────────────────────────────

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 14) / 2;
    final rect   = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect, -pi / 2, 2 * pi, false,
      Paint()
        ..color       = const Color(0x1AFFFFFF)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap   = StrokeCap.round,
    );

    if (progress > 0) {
      canvas.drawArc(
        rect, -pi / 2, 2 * pi * progress, false,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF66E2D0), Color(0xFF5BC0BE)],
          ).createShader(rect)
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap   = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.progress != progress;
}

// ── _MiniMetricChip ───────────────────────────────────────────────────────────

class _MiniMetricChip extends StatelessWidget {
  const _MiniMetricChip({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool   highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: highlight ? const Color(0x2E59E0CC) : const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlight ? const Color(0x6659E0CC) : const Color(0x1AFFFFFF),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: AppFonts.geist(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: const Color(0x99FFFFFF),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppFonts.onest(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: highlight ? AppColors.ctTeal : Colors.white,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ── _OperatorsSection ─────────────────────────────────────────────────────────

class _OperatorsSection extends ConsumerStatefulWidget {
  const _OperatorsSection({super.key, required this.tenantId});
  final String tenantId;

  @override
  ConsumerState<_OperatorsSection> createState() => _OperatorsSectionState();
}

class _OperatorsSectionState extends ConsumerState<_OperatorsSection> {
  String _viewMode     = 'chips'; // 'chips' | 'cards'
  String _filterStatus = 'all';

  bool   _loading = false;
  String? _error;
  List<Map<String, dynamic>> _operators = [];

  @override
  void initState() {
    super.initState();
    if (widget.tenantId.isNotEmpty) _load();
  }

  @override
  void didUpdateWidget(_OperatorsSection old) {
    super.didUpdateWidget(old);
    if (old.tenantId.isEmpty && widget.tenantId.isNotEmpty) _load();
  }

  Future<void> _load() async {
    if (widget.tenantId.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final raw = await OperatorsApi.listOperators(dio: ref.read(apiClientProvider).dio);
      setState(() { _operators = raw; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _statusOf(Map<String, dynamic> op) {
    final s = (_safeString(op['computed_status']) ?? _safeString(op['status']) ?? '').toLowerCase();
    return switch (s) {
      'active'   => 'active',
      'incident' => 'incident',
      _          => 'off',
    };
  }

  Color _colorOf(String status) => switch (status) {
    'active'   => const Color(0xFF10B981),
    'incident' => const Color(0xFFE24C4B),
    _          => const Color(0xFF9CA3AF),
  };

  String _labelOf(String status) => switch (status) {
    'active'   => 'Activo',
    'incident' => 'Incidencia',
    _          => 'Sin turno',
  };

  int? _lastEventMin(Map<String, dynamic> op) {
    final raw = op['last_inbound_at'] as String?;
    if (raw == null) return null;
    try {
      return DateTime.now().difference(DateTime.parse(raw)).inMinutes;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filterStatus == 'all'
        ? _operators
        : _operators.where((op) => _statusOf(op) == _filterStatus).toList();

    final activeCount = _operators.where((op) => _statusOf(op) != 'off').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(activeCount),
        const SizedBox(height: 12),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: AppColors.ctTeal),
            ),
          )
        else if (_error != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.ctRedBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.ctDanger),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.ctRedText, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_error!, style: AppFonts.geist(fontSize: 12, color: AppColors.ctRedText)),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _load,
                  child: Text('Reintentar', style: AppFonts.geist(fontSize: 12, color: AppColors.ctRedText, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          )
        else if (_viewMode == 'chips')
          _buildChipsView(filtered)
        else
          _buildCardsView(filtered),
      ],
    );
  }

  Widget _buildHeader(int activeCount) {
    const filterOptions = [
      ('all',      'Todos',      null),
      ('active',   'Activos',    Color(0xFF10B981)),
      ('incident', 'Incidencia', Color(0xFFE24C4B)),
      ('off',      'Sin turno',  Color(0xFF9CA3AF)),
    ];

    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Operadores en turno',
              style: AppFonts.onest(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ctText),
            ),
            Text(
              '$activeCount de ${_operators.length} · agrupados por estado',
              style: AppFonts.geist(fontSize: 12, color: AppColors.ctText2),
            ),
          ],
        ),
        const Spacer(),
        // Filter pills
        Row(
          children: filterOptions.map((opt) {
            final (status, label, dotColor) = opt;
            final isActive = _filterStatus == status;
            return GestureDetector(
              onTap: () => setState(() => _filterStatus = status),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                margin: const EdgeInsets.only(right: 3),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF0B132B) : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (dotColor != null) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      label,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isActive ? Colors.white : AppColors.ctInk700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(width: 10),
        // View toggle
        Row(
          children: [
            _ViewToggleBtn(
              icon: Icons.view_headline,
              active: _viewMode == 'chips',
              onTap: () => setState(() => _viewMode = 'chips'),
            ),
            const SizedBox(width: 4),
            _ViewToggleBtn(
              icon: Icons.grid_view,
              active: _viewMode == 'cards',
              onTap: () => setState(() => _viewMode = 'cards'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChipsView(List<Map<String, dynamic>> ops) {
    if (_filterStatus != 'all') {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: ops.map((op) {
          final status = _statusOf(op);
          return _OpChip(
            op: op,
            statusColor: _colorOf(status),
            lastEventMin: _lastEventMin(op),
          );
        }).toList(),
      );
    }

    const groupOrder = ['active', 'incident', 'off'];
    const groupLabels = {
      'active':   'Activos',
      'incident': 'Incidencia',
      'off':      'Sin turno',
    };

    final groups = <String, List<Map<String, dynamic>>>{};
    for (final status in groupOrder) {
      final group = ops.where((op) => _statusOf(op) == status).toList();
      if (group.isNotEmpty) groups[status] = group;
    }

    if (groups.isEmpty) {
      return Text(
        'Sin operadores',
        style: AppFonts.geist(fontSize: 13, color: AppColors.ctText3),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: groups.entries.map((entry) {
        final status = entry.key;
        final group  = entry.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 7, height: 7,
                    decoration: BoxDecoration(
                      color: _colorOf(status),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    groupLabels[status]!.toUpperCase(),
                    style: AppFonts.geist(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.08,
                      color: AppColors.ctText,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '· ${group.length}',
                    style: AppFonts.geist(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.ctText2),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: group.map((op) => _OpChip(
                  op: op,
                  statusColor: _colorOf(status),
                  lastEventMin: _lastEventMin(op),
                )).toList(),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCardsView(List<Map<String, dynamic>> ops) {
    if (ops.isEmpty) {
      return Text(
        'Sin operadores',
        style: AppFonts.geist(fontSize: 13, color: AppColors.ctText3),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: ops.length,
      itemBuilder: (_, i) {
        final op     = ops[i];
        final status = _statusOf(op);
        return _OpCard(
          op:           op,
          statusColor:  _colorOf(status),
          statusLabel:  _labelOf(status),
          lastEventMin: _lastEventMin(op),
        );
      },
    );
  }
}

// ── _ViewToggleBtn ────────────────────────────────────────────────────────────

class _ViewToggleBtn extends StatelessWidget {
  const _ViewToggleBtn({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final bool     active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF0B132B) : Colors.white,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: AppColors.ctBorder),
        ),
        child: Icon(
          icon,
          size: 16,
          color: active ? Colors.white : const Color(0xFF7B92A7),
        ),
      ),
    );
  }
}

// ── _OpChip ───────────────────────────────────────────────────────────────────

class _OpChip extends StatefulWidget {
  const _OpChip({
    required this.op,
    required this.statusColor,
    this.lastEventMin,
  });

  final Map<String, dynamic> op;
  final Color statusColor;
  final int?  lastEventMin;

  @override
  State<_OpChip> createState() => _OpChipState();
}

class _OpChipState extends State<_OpChip> {
  bool _hovered = false;

  String get _shortName {
    final name  = widget.op['name'] as String? ?? '—';
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return name;
    if (parts.length == 1) return parts[0];
    return '${parts[0]} ${parts[1][0]}.';
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        transform: _hovered
            ? (Matrix4.identity()..translateByDouble(0.0, -1.0, 0.0, 1.0))
            : Matrix4.identity(),
        decoration: BoxDecoration(
          color: AppColors.ctSurface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: _hovered ? AppColors.ctTeal : AppColors.ctBorder,
          ),
          boxShadow: _hovered
              ? [BoxShadow(
                  color: const Color(0xFF5BC0BE).withValues(alpha: 0.18),
                  blurRadius: 6,
                )]
              : null,
        ),
        child: InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.only(left: 4, right: 11, top: 4, bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    OperatorAvatar(
                      name:     widget.op['name'] as String? ?? '',
                      photoUrl: widget.op['profile_picture_url'] as String?,
                      size:     26,
                    ),
                    Positioned(
                      bottom: -1,
                      right:  -1,
                      child: Container(
                        width:  8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: widget.statusColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 7),
                Text(
                  _shortName,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ctNavy,
                  ),
                ),
                if (widget.lastEventMin != null) ...[
                  const SizedBox(width: 7),
                  Container(width: 1, height: 12, color: AppColors.ctBorder),
                  const SizedBox(width: 7),
                  Text(
                    _formatElapsed(widget.lastEventMin),
                    style: AppFonts.geist(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ctText2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── _OpCard ───────────────────────────────────────────────────────────────────

class _OpCard extends StatefulWidget {
  const _OpCard({
    required this.op,
    required this.statusColor,
    required this.statusLabel,
    this.lastEventMin,
  });

  final Map<String, dynamic> op;
  final Color  statusColor;
  final String statusLabel;
  final int?   lastEventMin;

  @override
  State<_OpCard> createState() => _OpCardState();
}

class _OpCardState extends State<_OpCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final flowsRaw = widget.op['flows'];
    final flowCount = flowsRaw is List ? flowsRaw.length : 0;
    final lm        = widget.lastEventMin;
    final lmColor   = lm != null && lm >= 30 ? AppColors.ctDanger : AppColors.ctText;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: AppColors.ctSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _hovered ? AppColors.ctBorder2 : AppColors.ctBorder,
          ),
          boxShadow: _hovered
              ? [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: widget.statusColor, width: 2),
                    ),
                    child: OperatorAvatar(
                      name:     widget.op['name'] as String? ?? '',
                      photoUrl: widget.op['profile_picture_url'] as String?,
                      size:     34,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.op['name'] as String? ?? '—',
                      style: AppFonts.onest(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ctText,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: widget.statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.statusLabel.toUpperCase(),
                      style: AppTextStyles.navSectionLabel.copyWith(
                        letterSpacing: 0.06,
                        color: widget.statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, color: AppColors.ctBorder),
              const SizedBox(height: 8),
              Row(
                children: [
                  _MetaItem(
                    label: 'Flujos',
                    value: flowCount.toString(),
                    valueColor: AppColors.ctText,
                  ),
                  const SizedBox(width: 16),
                  _MetaItem(
                    label: 'Último evento',
                    value: lm != null ? _formatElapsed(lm) : '—',
                    valueColor: lmColor,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({
    required this.label,
    required this.value,
    this.valueColor = AppColors.ctText,
  });

  final String label;
  final String value;
  final Color  valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppFonts.geist(fontSize: 10, color: AppColors.ctText3)),
        Text(value, style: AppFonts.geist(fontSize: 12, fontWeight: FontWeight.w600, color: valueColor)),
      ],
    );
  }
}

// ── _WorkersFlows ─────────────────────────────────────────────────────────────

class _WorkersFlows extends StatefulWidget {
  const _WorkersFlows({required this.tenantId});
  final String tenantId;

  @override
  State<_WorkersFlows> createState() => _WorkersFlowsState();
}

class _WorkersFlowsState extends State<_WorkersFlows> {
  bool   _loading = false;
  String? _error;
  List<Map<String, dynamic>> _workers = [];

  @override
  void initState() {
    super.initState();
    if (widget.tenantId.isNotEmpty) _load();
  }

  @override
  void didUpdateWidget(_WorkersFlows old) {
    super.didUpdateWidget(old);
    if (old.tenantId.isEmpty && widget.tenantId.isNotEmpty) _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final raw = await AiWorkersApi.listWorkers();
      setState(() { _workers = raw; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  int get _totalFlows => _workers.fold(0, (acc, w) {
    final f = w['flows'];
    return acc + (f is List ? f.length : 0);
  });

  int get _totalCompleted => _workers.fold(0, (acc, w) {
    final f = w['flows'];
    if (f is! List) return acc;
    return acc + f.fold<int>(0, (a, flow) {
      return a + ((flow['completed_today'] as num?)?.toInt() ?? 0);
    });
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Workers contratados · ${_workers.length}',
                      style: AppFonts.geist(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ctText,
                      ),
                    ),
                    Text(
                      '$_totalFlows flujos · $_totalCompleted ejecuciones hoy',
                      style: AppFonts.geist(fontSize: 12, color: AppColors.ctText2),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: AppColors.ctTeal),
            ))
          else if (_error != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.ctRedBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.ctDanger),
              ),
              child: Text(_error!, style: AppFonts.geist(fontSize: 12, color: AppColors.ctRedText)),
            )
          else if (_workers.isEmpty)
            Center(
              child: Text(
                'Sin workers contratados.',
                style: AppFonts.geist(fontSize: 13, color: AppColors.ctText3),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _workers
                    .map((w) => SizedBox(
                          width: (constraints.maxWidth - 10) / 2,
                          child: _WorkerCard(worker: w, totalFlows: _totalFlows),
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

// ── helpers ───────────────────────────────────────────────────────────────────

String _formatElapsed(int? minutes) {
  if (minutes == null) return '';
  if (minutes < 60)   return '${minutes}m';
  if (minutes < 1440) return '${(minutes / 60).floor()}h';
  return '${(minutes / 1440).floor()}d';
}

/// Safely extracts a String from API fields that are normally TEXT but may
/// occasionally arrive as a nested Map (e.g. when a join is not fully flattened).
String? _safeString(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is Map) return value['hex'] as String? ?? value['value'] as String?;
  return value.toString();
}

// ── _WorkerCard ───────────────────────────────────────────────────────────────

class _WorkerCard extends StatefulWidget {
  const _WorkerCard({required this.worker, required this.totalFlows});
  final Map<String, dynamic> worker;
  final int totalFlows;

  @override
  State<_WorkerCard> createState() => _WorkerCardState();
}

class _WorkerCardState extends State<_WorkerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late Animation<double>   _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.55, end: 1.0).animate(_pulse);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Color _iconBg(String? colorHex) {
    if (colorHex == null) return AppColors.ctTealLight;
    try {
      final hex = colorHex.replaceAll('#', '');
      return Color(int.parse('0xFF$hex')).withValues(alpha: 0.1);
    } catch (_) {
      return AppColors.ctTealLight;
    }
  }

  IconData _iconFor(String? type) => switch (type) {
    'logistics'      => Icons.local_shipping_outlined,
    'communication'  => Icons.chat_bubble_outline,
    'analytics'      => Icons.bar_chart,
    _                => Icons.smart_toy_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final w             = widget.worker;
    final name          = _safeString(w['catalog_name']) ?? _safeString(w['display_name']) ?? '—';
    final type          = _safeString(w['catalog_worker_type']);
    final colorHex      = _safeString(w['catalog_color']);
    final flowsRaw      = w['flows'];
    final flows         = flowsRaw is List ? flowsRaw : <dynamic>[];
    final runningNow    = (w['running_now'] as num?)?.toInt() ?? 0;
    final completedToday = flows.fold<int>(0, (a, f) =>
        a + ((f['completed_today'] as num?)?.toInt() ?? 0));
    final fraction      = widget.totalFlows > 0 ? flows.length / widget.totalFlows : 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: _iconBg(colorHex),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(_iconFor(type), size: 18, color: AppColors.ctTealDark),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppFonts.geist(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ctText),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${flows.length} flujos del catálogo',
                      style: AppFonts.geist(fontSize: 11, color: AppColors.ctText2),
                    ),
                  ],
                ),
              ),
              if (runningNow > 0)
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (context, child) => Opacity(
                    opacity: _pulseAnim.value,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.ctOkBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 5, height: 5,
                            decoration: const BoxDecoration(
                              color: AppColors.ctOk,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$runningNow',
                            style: AppFonts.geist(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.ctOkText),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hoy', style: AppFonts.geist(fontSize: 10, color: AppColors.ctText3)),
                  Text(
                    '$completedToday',
                    style: AppFonts.onest(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ctText, height: 1),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fraction.clamp(0.0, 1.0),
                    backgroundColor: AppColors.ctBorder,
                    color: AppColors.ctTeal,
                    minHeight: 6,
                  ),
                ),
              ),
            ],
          ),
          if (flows.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...flows.take(3).map((f) {
              final fname = (f['name'] as String? ?? '—');
              final count = (f['completed_today'] as num?)?.toInt() ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        fname,
                        style: AppFonts.geist(fontSize: 11, color: AppColors.ctText2),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.ctSurface2,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$count',
                        style: AppFonts.geist(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.ctText2),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (flows.length > 3)
              Text(
                '+${flows.length - 3} más',
                style: AppFonts.geist(fontSize: 11, color: AppColors.ctTeal),
              ),
          ],
        ],
      ),
    );
  }
}

// ── _Attention ────────────────────────────────────────────────────────────────

class _Attention extends StatefulWidget {
  const _Attention({required this.tenantId});
  final String tenantId;

  @override
  State<_Attention> createState() => _AttentionState();
}

class _AttentionState extends State<_Attention> {
  bool   _loading = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    if (widget.tenantId.isNotEmpty) _load();
  }

  @override
  void didUpdateWidget(_Attention old) {
    super.didUpdateWidget(old);
    if (old.tenantId.isEmpty && widget.tenantId.isNotEmpty) _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final raw = await EscalacionesApi.getEscalaciones();
      final filtered = raw
          .where((e) => (e['status'] as String? ?? '') != 'resolved')
          .take(4)
          .toList();
      setState(() { _items = filtered; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _severityOf(Map<String, dynamic> item) {
    final status = (item['status'] as String? ?? '').toLowerCase();
    return switch (status) {
      'open'     => 'incident',
      'reopened' => 'incident',
      'assigned' => 'warn',
      _          => 'info',
    };
  }

  Color _colorOf(String sev) => switch (sev) {
    'incident' => const Color(0xFFE24C4B),
    'warn'     => const Color(0xFFFFB700),
    _          => AppColors.ctTeal,
  };

  int get _incidentCount =>
      _items.where((e) => _severityOf(e) == 'incident').length;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Atención',
                          style: AppFonts.onest(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ctText,
                          ),
                        ),
                        if (_incidentCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.ctRedBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$_incidentCount',
                              style: AppFonts.geist(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ctRedText,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      'lo que necesita decisión ahora',
                      style: AppFonts.geist(fontSize: 12, color: AppColors.ctText2),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: AppColors.ctTeal),
            ))
          else if (_error != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.ctRedBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.ctDanger),
              ),
              child: Text(_error!, style: AppFonts.geist(fontSize: 12, color: AppColors.ctRedText)),
            )
          else if (_items.isEmpty)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  const Icon(Icons.check_circle_outline, size: 28, color: AppColors.ctTeal),
                  const SizedBox(height: 8),
                  Text(
                    'Sin alertas activas',
                    style: AppFonts.geist(fontSize: 13, color: AppColors.ctText2),
                  ),
                ],
              ),
            )
          else
            Column(
              children: _items.map((item) {
                final sev = _severityOf(item);
                return _AttentionItem(item: item, color: _colorOf(sev));
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// ── _AttentionItem ────────────────────────────────────────────────────────────

class _AttentionItem extends StatelessWidget {
  const _AttentionItem({required this.item, required this.color});

  final Map<String, dynamic> item;
  final Color color;

  String _operatorName() {
    final op = item['operator'];
    if (op is Map) return op['name'] as String? ?? op['email'] as String? ?? 'Operador';
    return item['operator_name'] as String? ?? '—';
  }

  @override
  Widget build(BuildContext context) {
    final reason   = item['reason'] as String? ?? '—';
    final canResume = item['worker_can_resume'] as bool? ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              size: 15,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _operatorName(),
                  style: AppFonts.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ctText,
                  ),
                ),
                Text(
                  reason,
                  style: AppFonts.geist(fontSize: 11, color: AppColors.ctText2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (canResume) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.ctTealLight,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Reanudar',
                style: AppFonts.geist(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ctTealDark,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── _DayThread ────────────────────────────────────────────────────────────────

class _DayThread extends StatelessWidget {
  const _DayThread();

  @override
  Widget build(BuildContext context) {
    // TODO: nutrir con flow_events y sesiones reales
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timeline_outlined, size: 32, color: AppColors.ctText3),
            SizedBox(height: 8),
            Text(
              'Hilo del día',
              style: AppTextStyles.body.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Próximamente',
              style: AppTextStyles.bodySmall.copyWith(
                fontSize: 12,
                color: AppColors.ctText3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
