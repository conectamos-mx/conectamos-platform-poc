import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:omni_datetime_picker/omni_datetime_picker.dart';

import '../../core/api/assignments_api.dart';
import '../../core/api/catalogs_api.dart';
import '../../core/api/flows_api.dart';
import '../../core/api/operators_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_detail_row.dart';
import '../../shared/widgets/screen_header.dart';

// ── Date helpers ──────────────────────────────────────────────────────────────

const _kWeekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const _kMonths = [
  'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
  'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
];

DateTime _mondayOf(DateTime d) {
  final diff = d.weekday - 1;
  return DateTime(d.year, d.month, d.day - diff);
}

String _isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _weekRangeLabel(DateTime monday) {
  final sunday = monday.add(const Duration(days: 6));
  if (monday.month == sunday.month) {
    return '${monday.day}–${sunday.day} ${_kMonths[monday.month - 1]} ${monday.year}';
  }
  return '${monday.day} ${_kMonths[monday.month - 1]} – '
      '${sunday.day} ${_kMonths[sunday.month - 1]} ${monday.year}';
}

// ── Scope helpers ─────────────────────────────────────────────────────────────

(DateTime?, DateTime?) _parseScope(String? raw) {
  if (raw == null || raw.isEmpty) return (null, null);
  try {
    // Eliminar delimitadores de rango y comillas
    final clean = raw
        .replaceAll('"', '')
        .replaceAll('[', '')
        .replaceAll('(', '')
        .replaceAll(']', '')
        .replaceAll(')', '');
    final parts = clean.split(',');
    if (parts.length < 2) return (null, null);
    final lower = parts[0].trim();
    final upper = parts[1].trim();
    if (lower.isEmpty || upper.isEmpty) return (null, null);
    return (DateTime.parse(lower), DateTime.parse(upper));
  } catch (_) {
    return (null, null);
  }
}

final _dateFmt = DateFormat('d MMM', 'es_MX');
final _timeFmt = DateFormat('HH:mm');
String _formatDt(DateTime dt) {
  final local = dt.toLocal();
  return '${_dateFmt.format(local)} ${local.year} · ${_timeFmt.format(local)}';
}

String _formatWindow(String? raw) {
  final (lo, hi) = _parseScope(raw);
  if (lo == null || hi == null) return '—';
  final loL = lo.toLocal();
  final hiL = hi.toLocal();
  final sameDay = loL.year == hiL.year &&
      loL.month == hiL.month &&
      loL.day == hiL.day;
  if (sameDay) {
    return '${_dateFmt.format(loL)} · ${_timeFmt.format(loL)} – ${_timeFmt.format(hiL)}';
  }
  return '${_dateFmt.format(loL)} ${_timeFmt.format(loL)} – '
      '${_dateFmt.format(hiL)} ${_timeFmt.format(hiL)}';
}

// ── Domain helpers ────────────────────────────────────────────────────────────

Color _behaviorColor(List<dynamic> flows) {
  if (flows.isEmpty) return AppColors.ctText2;
  final behavior = (flows.first as Map<dynamic, dynamic>?)
      ?['behavior'] as String?;
  return switch (behavior) {
    'scheduled'  => AppColors.ctTeal,
    'permissive' => AppColors.ctNavy,
    _            => AppColors.ctText2,
  };
}

String _resourceLabel(Map<String, dynamic> r) {
  final type =
      r['resource_type'] as String? ?? r['catalog_slug'] as String? ?? '';
  String value = r['item_name'] as String? ??
      r['asset_item_id'] as String? ??
      '—';
  return type.isNotEmpty ? '$type: $value' : value;
}

String _flowLabel(Map<String, dynamic> f) {
  final rawId = f['flow_definition_id'] as String? ?? '';
  final name = f['flow_name'] as String? ??
      (rawId.length > 8 ? '${rawId.substring(0, 8)}…' : rawId.isNotEmpty ? rawId : '—');
  final behavior = f['behavior'] as String? ?? '';
  return behavior.isNotEmpty ? '$name ($behavior)' : name;
}

({Color bg, Color fg, String label}) _sourceBadge(String? source) =>
    switch (source) {
      'csv'  => (bg: AppColors.ctInfoBg,   fg: AppColors.ctInfoText,   label: 'CSV'),
      'sync' => (bg: AppColors.ctOkBg,     fg: AppColors.ctOkText,     label: 'sync'),
      'api'  => (bg: AppColors.ctOrangeBg, fg: AppColors.ctOrangeText, label: 'api'),
      _      => (bg: AppColors.ctSurface2, fg: AppColors.ctText2,      label: source ?? 'manual'),
    };

// ── Screen ────────────────────────────────────────────────────────────────────

class AssignmentsScreen extends ConsumerStatefulWidget {
  const AssignmentsScreen({super.key});

  @override
  ConsumerState<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends ConsumerState<AssignmentsScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  String _view = 'calendar'; // 'calendar' | 'table' | 'scheduler'
  int _weekOffset = 0;
  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _operators = [];
  bool _loading = true;
  String? _error;
  DateTime? _drawerDay;
  bool _showNewModal = false;

  DateTime get _today => DateTime.now();
  DateTime get _currentMonday =>
      _mondayOf(_today).add(Duration(days: _weekOffset * 7));

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('es', null).then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadAssignments());
    });
  }

  Future<void> _loadAssignments() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final tenantId = ref.read(activeTenantIdProvider);
      final monday = _currentMonday;
      final dayFutures = List.generate(7, (i) {
        final day = monday.add(Duration(days: i));
        return AssignmentsApi.listAssignments(
          tenantId: tenantId,
          scopeDate: _isoDate(day),
        );
      });
      final operatorsFuture = OperatorsApi.listOperators();
      final dayResults = await Future.wait(dayFutures);
      final operators = await operatorsFuture;
      final data = dayResults.expand((list) => list).toList();
      final seen = <String>{};
      final deduped = data.where((a) {
        final id = a['id'] as String? ?? '';
        return seen.add(id);
      }).toList();
      if (!mounted) return;
      setState(() {
        _assignments = List<Map<String, dynamic>>.from(deduped);
        _operators = operators;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<Map<String, dynamic>> _assignmentsForDay(DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return _assignments.where((a) {
      final (lower, upper) = _parseScope(a['scope'] as String?);
      if (lower == null || upper == null) return false;
      return lower.isBefore(dayEnd) && upper.isAfter(dayStart);
    }).toList();
  }

  void _openDrawerForDay(DateTime day) {
    setState(() => _drawerDay = day);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scaffoldKey.currentState?.openEndDrawer();
    });
  }

  Future<void> _confirmDelete(String assignmentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.ctSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.ctBorder),
        ),
        title: Text('¿Eliminar asignación?',
            style: AppFonts.onest(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.ctText)),
        content: Text('Esta acción no se puede deshacer.',
            style: AppFonts.geist(fontSize: 13, color: AppColors.ctText2)),
        actions: [
          AppButton(
            label: 'Cancelar',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          AppButton(
            label: 'Eliminar',
            variant: AppButtonVariant.danger,
            size: AppButtonSize.sm,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final tenantId = ref.read(activeTenantIdProvider);
      await AssignmentsApi.deleteAssignment(
          tenantId: tenantId, assignmentId: assignmentId);
      if (mounted) _loadAssignments();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString()),
        backgroundColor: AppColors.ctDanger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(activeTenantIdProvider, (prev, next) {
      if (next.isNotEmpty && prev != next) _loadAssignments();
    });

    final canManage = hasPermission(ref, 'assignments', 'manage');

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.ctBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenHeader(
            title: 'Asignaciones',
            subtitle: 'Asigna recursos a operadores con horario.',
            actions: [
              if (canManage) ...[
                AppButton(
                  label: 'Importar CSV',
                  variant: AppButtonVariant.outline,
                  size: AppButtonSize.sm,
                  prefixIcon: const Icon(Icons.upload_file_outlined, size: 14, color: AppColors.ctText2),
                  onPressed: () {},
                ),
                AppButton(
                  label: '+ Nueva asignación',
                  variant: AppButtonVariant.teal,
                  size: AppButtonSize.sm,
                  onPressed: () => setState(() => _showNewModal = true),
                ),
              ],
            ],
          ),
          _Toolbar(
            view: _view,
            weekOffset: _weekOffset,
            currentMonday: _currentMonday,
            onViewChanged: (v) => setState(() => _view = v),
            onWeekBack: () {
              setState(() => _weekOffset--);
              _loadAssignments();
            },
            onWeekForward: () {
              setState(() => _weekOffset++);
              _loadAssignments();
            },
            onToday: () {
              setState(() => _weekOffset = 0);
              _loadAssignments();
            },
          ),
          Expanded(
            child: _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            style: AppFonts.geist(
                                fontSize: 13, color: AppColors.ctDanger)),
                        const SizedBox(height: 12),
                        AppButton(
                          label: 'Reintentar',
                          variant: AppButtonVariant.ghost,
                          size: AppButtonSize.sm,
                          onPressed: _loadAssignments,
                        ),
                      ],
                    ),
                  )
                : _view == 'table'
                    ? (_loading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.ctTeal))
                        : _assignments.isEmpty
                            ? _EmptyState(
                                canManage: canManage,
                                onNew: () =>
                                    setState(() => _showNewModal = true),
                              )
                            : _AssignmentsTable(
                                assignments: _assignments,
                                loading: _loading,
                                canManage: canManage,
                                onDelete: _confirmDelete,
                              ))
                    : _view == 'scheduler'
                        ? _AssignmentsScheduler(
                            operators: _operators,
                            assignments: _assignments,
                            currentMonday: _currentMonday,
                            onAssignmentTap: (a) {
                              final (lo, _) =
                                  _parseScope(a['scope'] as String?);
                              if (lo != null) _openDrawerForDay(lo.toLocal());
                            },
                          )
                        : _AssignmentsCalendar(
                            currentMonday: _currentMonday,
                            today: _today,
                            loading: _loading,
                            assignmentsForDay: _assignmentsForDay,
                            onDayTap: _openDrawerForDay,
                          ),
          ),
        ],
      ),
      endDrawer: _drawerDay == null
          ? null
          : _DayDrawer(
              day: _drawerDay!,
              assignments: _assignmentsForDay(_drawerDay!),
              onClose: () => setState(() => _drawerDay = null),
            ),
      floatingActionButton: null,
    )..also(() {
        if (_showNewModal) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_showNewModal) return;
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => _NewAssignmentDialog(
                tenantId: ref.read(activeTenantIdProvider),
                operators: _operators,
                onSaved: () {
                  setState(() => _showNewModal = false);
                  _loadAssignments();
                },
                onCancel: () => setState(() => _showNewModal = false),
              ),
            ).then((_) {
              if (mounted) setState(() => _showNewModal = false);
            });
            setState(() => _showNewModal = false);
          });
        }
      });
  }
}

extension _ScaffoldAlso on Scaffold {
  Scaffold also(void Function() fn) {
    fn();
    return this;
  }
}

// ── Toolbar ───────────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.view,
    required this.weekOffset,
    required this.currentMonday,
    required this.onViewChanged,
    required this.onWeekBack,
    required this.onWeekForward,
    required this.onToday,
  });

  final String view;
  final int weekOffset;
  final DateTime currentMonday;
  final ValueChanged<String> onViewChanged;
  final VoidCallback onWeekBack;
  final VoidCallback onWeekForward;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final showWeekNav = view == 'calendar' || view == 'scheduler';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          // View toggle
          Container(
            decoration: BoxDecoration(
              color: AppColors.ctSurface2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.ctBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ViewPill(
                  icon: Icons.calendar_month_outlined,
                  label: 'Calendario',
                  active: view == 'calendar',
                  onTap: () => onViewChanged('calendar'),
                ),
                _ViewPill(
                  icon: Icons.table_rows_outlined,
                  label: 'Tabla',
                  active: view == 'table',
                  onTap: () => onViewChanged('table'),
                ),
                _ViewPill(
                  icon: Icons.view_timeline_outlined,
                  label: 'Scheduler',
                  active: view == 'scheduler',
                  onTap: () => onViewChanged('scheduler'),
                ),
              ],
            ),
          ),
          if (showWeekNav) ...[
            const SizedBox(width: 16),
            _IconBtn(icon: Icons.chevron_left, onTap: onWeekBack),
            const SizedBox(width: 8),
            Text(
              _weekRangeLabel(currentMonday),
              style: AppFonts.geist(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ctText),
            ),
            const SizedBox(width: 8),
            _IconBtn(icon: Icons.chevron_right, onTap: onWeekForward),
            const SizedBox(width: 8),
            if (weekOffset != 0)
              GestureDetector(
                onTap: onToday,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.ctBorder),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Hoy',
                      style:
                          AppFonts.geist(fontSize: 12, color: AppColors.ctText2)),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ViewPill extends StatelessWidget {
  const _ViewPill({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.ctTeal : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14,
                  color: active ? Colors.white : AppColors.ctText2),
              const SizedBox(width: 5),
              Text(
                label,
                style: AppFonts.geist(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: active ? Colors.white : AppColors.ctText2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.ctBorder),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: AppColors.ctText2),
        ),
      ),
    );
  }
}

// ── Calendar view ─────────────────────────────────────────────────────────────

class _AssignmentsCalendar extends StatelessWidget {
  const _AssignmentsCalendar({
    required this.currentMonday,
    required this.today,
    required this.loading,
    required this.assignmentsForDay,
    required this.onDayTap,
  });

  final DateTime currentMonday;
  final DateTime today;
  final bool loading;
  final List<Map<String, dynamic>> Function(DateTime) assignmentsForDay;
  final ValueChanged<DateTime> onDayTap;

  bool _isToday(DateTime d) =>
      d.year == today.year && d.month == today.month && d.day == today.day;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        children: [
          Row(
            children: List.generate(7, (i) {
              final day = currentMonday.add(Duration(days: i));
              final isWe = i >= 5;
              return Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: isWe
                        ? const Color(0xFFF8FAFC)
                        : Colors.white,
                    border: Border(
                      bottom: BorderSide(color: AppColors.ctBorder),
                      right: i < 6
                          ? BorderSide(color: AppColors.ctBorder)
                          : BorderSide.none,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(_kWeekdays[i],
                          style: AppFonts.geist(
                              fontSize: 11, color: AppColors.ctText2)),
                      const SizedBox(height: 2),
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: _isToday(day)
                              ? AppColors.ctTeal
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text('${day.day}',
                              style: AppFonts.geist(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _isToday(day)
                                    ? Colors.white
                                    : AppColors.ctText,
                              )),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(7, (i) {
                final day = currentMonday.add(Duration(days: i));
                final isWe = i >= 5;
                final dayItems = assignmentsForDay(day);
                const maxVisible = 5;
                final visible = dayItems.take(maxVisible).toList();
                final overflow = dayItems.length - maxVisible;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => onDayTap(day),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isWe
                              ? const Color(0xFFF8FAFC)
                              : Colors.white,
                          border: Border(
                            bottom: BorderSide(color: AppColors.ctBorder),
                            right: i < 6
                                ? BorderSide(color: AppColors.ctBorder)
                                : BorderSide.none,
                          ),
                        ),
                        padding: const EdgeInsets.all(6),
                        child: loading
                            ? _CalendarSkeleton()
                            : Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  ...visible.map((a) =>
                                      _AssignmentChip(assignment: a)),
                                  if (overflow > 0)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(top: 2),
                                      child: Text('+$overflow más',
                                          style: AppFonts.geist(
                                              fontSize: 10,
                                              color: AppColors.ctText2)),
                                    ),
                                ],
                              ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(
        2,
        (_) => Container(
          height: 20,
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: AppColors.ctBorder,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

class _AssignmentChip extends StatelessWidget {
  const _AssignmentChip({required this.assignment});
  final Map<String, dynamic> assignment;

  @override
  Widget build(BuildContext context) {
    final name = assignment['operator_name'] as String? ?? '—';
    final flows = assignment['flows'] as List<dynamic>? ?? [];
    final resources = assignment['resources'] as List<dynamic>? ?? [];
    final color = _behaviorColor(flows);
    final resourceSubtext = resources.isNotEmpty
        ? ((resources.first as Map<dynamic, dynamic>?)?['resource_type']
                as String? ??
            (resources.first as Map<dynamic, dynamic>?)?['catalog_slug']
                as String? ??
            '')
        : '';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: AppFonts.geist(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (resourceSubtext.isNotEmpty)
            Text(
              resourceSubtext,
              style: AppFonts.geist(
                  fontSize: 9,
                  color: color.withValues(alpha: 0.75)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

// ── Day Drawer ────────────────────────────────────────────────────────────────

class _DayDrawer extends StatelessWidget {
  const _DayDrawer({
    required this.day,
    required this.assignments,
    required this.onClose,
  });

  final DateTime day;
  final List<Map<String, dynamic>> assignments;
  final VoidCallback onClose;

  static const _months = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  @override
  Widget build(BuildContext context) {
    final title = '${day.day} de ${_months[day.month - 1]} ${day.year}';
    return Drawer(
      backgroundColor: AppColors.ctSurface,
      width: 380,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: AppFonts.onest(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ctNavy),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        size: 18, color: AppColors.ctText2),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.ctBorder),
            Expanded(
              child: assignments.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.event_busy_outlined,
                              size: 36, color: AppColors.ctText3),
                          const SizedBox(height: 8),
                          Text('Sin asignaciones este día',
                              style: AppFonts.geist(
                                  fontSize: 13,
                                  color: AppColors.ctText2)),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: assignments
                          .map((a) => _AssignmentCard(assignment: a))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({required this.assignment});
  final Map<String, dynamic> assignment;

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final name = assignment['operator_name'] as String? ?? '—';
    final phone = assignment['operator_phone'] as String?;
    final source = assignment['source'] as String?;
    final resources =
        (assignment['resources'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final flows =
        (assignment['flows'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final badge = _sourceBadge(source);
    final color = _behaviorColor(assignment['flows'] as List<dynamic>? ?? []);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: 0.15),
                child: Text(
                  _initials(name),
                  style: AppFonts.geist(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: AppFonts.geist(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ctText)),
                    if (phone != null)
                      Text(phone,
                          style: AppFonts.geist(
                              fontSize: 11, color: AppColors.ctText2)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: badge.bg,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(badge.label,
                    style: AppFonts.geist(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: badge.fg)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _formatWindow(assignment['scope'] as String?),
            style:
                AppFonts.geist(fontSize: 11, color: AppColors.ctText2),
          ),
          if (resources.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Activos',
                style: AppFonts.geist(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ctText2)),
            const SizedBox(height: 4),
            ...resources.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '• ${_resourceLabel(r)}',
                    style: AppFonts.geist(
                        fontSize: 11, color: AppColors.ctText),
                  ),
                )),
          ],
          if (flows.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Flows',
                style: AppFonts.geist(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ctText2)),
            const SizedBox(height: 4),
            ...flows.map((f) {
              final flowId = f['flow_definition_id'] as String? ?? '—';
              final behavior = f['behavior'] as String? ?? '';
              final bColor = _behaviorColor([f]);
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('• $flowId',
                          style: AppFonts.geist(
                              fontSize: 11, color: AppColors.ctText)),
                    ),
                    if (behavior.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: bColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(behavior,
                            style: AppFonts.geist(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: bColor)),
                      ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ── Table view ────────────────────────────────────────────────────────────────

class _AssignmentsTable extends StatelessWidget {
  const _AssignmentsTable({
    required this.assignments,
    required this.loading,
    required this.canManage,
    required this.onDelete,
  });

  final List<Map<String, dynamic>> assignments;
  final bool loading;
  final bool canManage;
  final Future<void> Function(String id) onDelete;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.ctSurface,
          border: Border.all(color: AppColors.ctBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: loading
              ? _TableSkeleton()
              : Table(
                  columnWidths: const {
                    0: FixedColumnWidth(180),
                    1: FixedColumnWidth(160),
                    2: FlexColumnWidth(2),
                    3: FlexColumnWidth(2),
                    4: FixedColumnWidth(90),
                    5: FixedColumnWidth(90),
                  },
                  children: [
                    _headerRow(),
                    ...assignments.asMap().entries.map(
                          (e) => _dataRow(context, e.value, e.key.isOdd),
                        ),
                  ],
                ),
        ),
      ),
    );
  }

  TableRow _headerRow() {
    const cols = [
      'Operador', 'Ventana', 'Activos', 'Flows', 'Source', 'Acciones'
    ];
    return TableRow(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.ctBorder)),
        color: AppColors.ctSurface2,
      ),
      children: cols
          .map((c) => Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                child: Text(c,
                    style: AppFonts.geist(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ctText2)),
              ))
          .toList(),
    );
  }

  TableRow _dataRow(
      BuildContext context, Map<String, dynamic> a, bool odd) {
    final resources =
        (a['resources'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final flows =
        (a['flows'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final badge = _sourceBadge(a['source'] as String?);
    final id = a['id'] as String? ?? '';

    return TableRow(
      decoration: BoxDecoration(
        color: odd
            ? AppColors.ctSurface2.withAlpha(80)
            : AppColors.ctSurface,
        border: const Border(
            bottom:
                BorderSide(color: AppColors.ctBorder, width: 0.5)),
      ),
      children: [
        // Operador
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                a['operator_name'] as String? ?? '—',
                style: AppFonts.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ctText),
              ),
              if (a['operator_phone'] != null)
                Text(
                  a['operator_phone'] as String,
                  style: AppFonts.geist(
                      fontSize: 11, color: AppColors.ctText2),
                ),
            ],
          ),
        ),
        // Ventana
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 10),
          child: Text(
            _formatWindow(a['scope'] as String?),
            style: AppFonts.geist(
                fontSize: 12, color: AppColors.ctText),
          ),
        ),
        // Activos
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 8),
          child: _ChipList(
            labels: resources.map(_resourceLabel).toList(),
            maxVisible: 2,
            chipBg: AppColors.ctTealLight,
            chipFg: AppColors.ctTealText,
          ),
        ),
        // Flows
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 8),
          child: _ChipList(
            labels: flows.map(_flowLabel).toList(),
            maxVisible: 2,
            chipBg: AppColors.ctInfoBg,
            chipFg: AppColors.ctInfoText,
          ),
        ),
        // Source
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badge.bg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              badge.label,
              style: AppFonts.geist(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: badge.fg),
            ),
          ),
        ),
        // Acciones
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.visibility_outlined,
                    size: 16, color: AppColors.ctText2),
                splashRadius: 18,
                tooltip: 'Ver',
                onPressed: () =>
                    context.go('/assignments/$id'),
              ),
              if (canManage && id.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 16, color: AppColors.ctDanger),
                  splashRadius: 18,
                  tooltip: 'Eliminar',
                  onPressed: () => onDelete(id),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TableSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        5,
        (_) => Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Container(
            height: 16,
            decoration: BoxDecoration(
              color: AppColors.ctBorder,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Chip helpers ──────────────────────────────────────────────────────────────

class _ChipList extends StatelessWidget {
  const _ChipList({
    required this.labels,
    required this.maxVisible,
    required this.chipBg,
    required this.chipFg,
  });

  final List<String> labels;
  final int maxVisible;
  final Color chipBg;
  final Color chipFg;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) {
      return Text('—',
          style: AppFonts.geist(
              fontSize: 12, color: AppColors.ctText2));
    }
    final visible = labels.take(maxVisible).toList();
    final extra = labels.length - visible.length;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        ...visible.map((l) => _Chip(label: l, bg: chipBg, fg: chipFg)),
        if (extra > 0)
          _Chip(
              label: '+$extra más',
              bg: AppColors.ctSurface2,
              fg: AppColors.ctText2),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.bg, required this.fg});
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: AppFonts.geist(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: fg),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ── Scheduler view ────────────────────────────────────────────────────────────

// ── Operator color palette ─────────────────────────────────────────────────────

const List<Color> _kOperatorPalette = [
  AppColors.ctTeal,
  Color(0xFF6366F1),
  Color(0xFFF59E0B),
  Color(0xFF10B981),
  Color(0xFFEF4444),
  Color(0xFF8B5CF6),
  Color(0xFF06B6D4),
  Color(0xFFF97316),
  Color(0xFF84CC16),
  Color(0xFFEC4899),
];

class _AssignmentsScheduler extends StatefulWidget {
  const _AssignmentsScheduler({
    required this.operators,
    required this.assignments,
    required this.currentMonday,
    required this.onAssignmentTap,
  });

  final List<Map<String, dynamic>> operators;
  final List<Map<String, dynamic>> assignments;
  final DateTime currentMonday;
  final ValueChanged<Map<String, dynamic>> onAssignmentTap;

  @override
  State<_AssignmentsScheduler> createState() => _AssignmentsSchedulerState();
}

class _AssignmentsSchedulerState extends State<_AssignmentsScheduler> {
  late EventController<Map<String, dynamic>> _eventController;
  Map<String, Color> _operatorColors = {};

  @override
  void initState() {
    super.initState();
    _eventController = EventController<Map<String, dynamic>>();
    _buildEvents();
  }

  @override
  void didUpdateWidget(_AssignmentsScheduler old) {
    super.didUpdateWidget(old);
    if (old.assignments != widget.assignments ||
        old.currentMonday != widget.currentMonday) {
      _buildEvents();
    }
  }

  void _buildEvents() {
    // Build operator → color map based on unique operator_ids in assignments
    final operatorIds = widget.assignments
        .map((a) => a['operator_id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    _operatorColors = {
      for (var i = 0; i < operatorIds.length; i++)
        operatorIds[i]: _kOperatorPalette[i % _kOperatorPalette.length],
    };

    final events = <CalendarEventData<Map<String, dynamic>>>[];
    for (final a in widget.assignments) {
      final (lo, hi) = _parseScope(a['scope'] as String?);
      if (lo == null || hi == null) continue;
      final operatorId = a['operator_id'] as String? ?? '';
      final color = _operatorColors[operatorId] ?? AppColors.ctTeal;
      final title = a['operator_name'] as String? ?? 'Operador';
      final resources = a['resources'] as List<dynamic>? ?? [];
      final description = resources.isNotEmpty
          ? ((resources.first as Map?)?['resource_type'] as String? ??
              (resources.first as Map?)?['catalog_slug'] as String? ??
              '')
          : '';
      events.add(CalendarEventData<Map<String, dynamic>>(
        date: lo.toLocal(),
        endDate: hi.toLocal(),
        startTime: lo.toLocal(),
        endTime: hi.toLocal(),
        title: title,
        description: description,
        color: color,
        event: a,
      ));
    }

    _eventController.removeWhere((_) => true);
    _eventController.addAll(events);
  }

  @override
  void dispose() {
    _eventController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final legendOps = <String, String>{};
    for (final a in widget.assignments) {
      final id = a['operator_id'] as String? ?? '';
      if (id.isNotEmpty) legendOps[id] = a['operator_name'] as String? ?? id;
    }

    return Column(
      children: [
        if (legendOps.isNotEmpty)
          _SchedulerLegend(
            operatorNames: legendOps,
            operatorColors: _operatorColors,
          ),
        Expanded(
          child: WeekView<Map<String, dynamic>>(
            controller: _eventController,
            initialDay: widget.currentMonday,
            startHour: 6,
            endHour: 22,
            startDay: WeekDays.monday,
            headerStyle: const HeaderStyle(
              decoration: BoxDecoration(color: AppColors.ctNavy),
              headerTextStyle: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              leftIconConfig: IconDataConfig(color: Colors.white),
              rightIconConfig: IconDataConfig(color: Colors.white),
            ),
            onEventTap: (events, _) {
              if (events.isNotEmpty) {
                final a = events.first.event;
                if (a != null) widget.onAssignmentTap(a);
              }
            },
          ),
        ),
      ],
    );
  }
}

class _SchedulerLegend extends StatelessWidget {
  const _SchedulerLegend({
    required this.operatorNames,
    required this.operatorColors,
  });
  final Map<String, String> operatorNames;
  final Map<String, Color> operatorColors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: operatorNames.length,
        separatorBuilder: (context0, index0) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final id = operatorNames.keys.elementAt(i);
          final name = operatorNames[id]!;
          final color = operatorColors[id] ?? AppColors.ctTeal;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(radius: 6, backgroundColor: color),
              const SizedBox(width: 6),
              Text(name,
                  style: AppFonts.geist(fontSize: 12, color: AppColors.ctText)),
            ],
          );
        },
      ),
    );
  }
}

// ── Step indicator (custom, sin Stepper widget) ───────────────────────────────

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({
    required this.currentStep,
    required this.steps,
  });

  final int currentStep;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.ctBorder)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            _StepDot(
              index: i,
              label: steps[i],
              isDone: currentStep > i,
              isActive: currentStep == i,
            ),
            if (i < steps.length - 1)
              Expanded(
                child: Container(
                  height: 1,
                  margin: const EdgeInsets.only(bottom: 16),
                  color: currentStep > i
                      ? AppColors.ctTeal
                      : AppColors.ctBorder,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.index,
    required this.label,
    required this.isDone,
    required this.isActive,
  });

  final int index;
  final String label;
  final bool isDone;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final active = isDone || isActive;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: active ? AppColors.ctTeal : AppColors.ctBorder,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : Text(
                    '${index + 1}',
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : AppColors.ctText2,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppFonts.geist(
            fontSize: 10,
            fontWeight:
                isActive ? FontWeight.w600 : FontWeight.w400,
            color: active ? AppColors.ctText : AppColors.ctText2,
          ),
        ),
      ],
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.canManage, required this.onNew});
  final bool canManage;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.assignment_outlined,
              size: 48, color: AppColors.ctText2),
          const SizedBox(height: 12),
          Text('No hay asignaciones',
              style: AppFonts.onest(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ctText2)),
          const SizedBox(height: 4),
          Text('Crea la primera asignación para comenzar.',
              style:
                  AppFonts.geist(fontSize: 13, color: AppColors.ctText2)),
          if (canManage) ...[
            const SizedBox(height: 16),
            AppButton(
              label: '+ Nueva asignación',
              variant: AppButtonVariant.teal,
              size: AppButtonSize.sm,
              onPressed: onNew,
            ),
          ],
        ],
      ),
    );
  }
}

// ── New Assignment Dialog — 3-step stepper ────────────────────────────────────

class _NewAssignmentDialog extends StatefulWidget {
  const _NewAssignmentDialog({
    required this.tenantId,
    required this.operators,
    required this.onSaved,
    required this.onCancel,
  });

  final String tenantId;
  final List<Map<String, dynamic>> operators;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  @override
  State<_NewAssignmentDialog> createState() =>
      _NewAssignmentDialogState();
}

class _NewAssignmentDialogState extends State<_NewAssignmentDialog> {
  int _step = 0;
  String? _selectedOperatorId;
  DateTime? _scopeStart;
  DateTime? _scopeEnd;
  bool _saving = false;
  String? _error;

  // Resources
  final List<String> _resCatalogSlugs = [];
  final List<String?> _resItemIds = [];       // id confirmado por Autocomplete.onSelected
  final List<String> _resItemNames = [];      // nombre legible del item seleccionado
  final List<TextEditingController> _resItemIdCtrls = [];
  final List<TextEditingController> _resTypeCtrls = [];

  // Flows — key: flow_definition_id, value: 'permissive'|'scheduled'
  final Map<String, String> _selectedFlows = {};

  List<Map<String, dynamic>> _catalogs = [];
  List<Map<String, dynamic>> _flowDefs = [];
  bool _loadingApiData = true;
  String? _apiError;

  @override
  void initState() {
    super.initState();
    _loadApiData();
  }

  Future<void> _loadApiData() async {
    if (mounted) setState(() { _loadingApiData = true; _apiError = null; });
    try {
      final catalogs =
          await CatalogsApi.listCatalogs(tenantId: widget.tenantId);
      final flows = await FlowsApi.listFlows();
      if (mounted) {
        setState(() {
          _catalogs = catalogs;
          _flowDefs = flows;
          _loadingApiData = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _apiError = e.toString(); _loadingApiData = false; });
    }
  }

  @override
  void dispose() {
    for (final c in [..._resItemIdCtrls, ..._resTypeCtrls]) {
      c.dispose();
    }
    super.dispose();
  }

  void _addResource() {
    setState(() {
      _resCatalogSlugs.add(
          _catalogs.isNotEmpty
              ? (_catalogs.first['slug'] as String? ?? '')
              : '');
      _resItemIds.add(null);
      _resItemNames.add('');
      _resItemIdCtrls.add(TextEditingController());
      _resTypeCtrls.add(TextEditingController());
    });
  }

  void _removeResource(int i) {
    setState(() {
      _resCatalogSlugs.removeAt(i);
      _resItemIds.removeAt(i);
      _resItemNames.removeAt(i);
      _resItemIdCtrls[i].dispose();
      _resItemIdCtrls.removeAt(i);
      _resTypeCtrls[i].dispose();
      _resTypeCtrls.removeAt(i);
    });
  }

bool get _step1Valid =>
      _selectedOperatorId != null &&
      _scopeStart != null &&
      _scopeEnd != null &&
      _scopeEnd!.isAfter(_scopeStart!);

  Future<void> _submit() async {
    setState(() { _saving = true; _error = null; });
    final resources = List.generate(_resCatalogSlugs.length, (i) {
      final rt = _resTypeCtrls[i].text.trim();
      final itemId = _resItemIds[i] ?? _resItemIdCtrls[i].text.trim();
      return <String, dynamic>{
        'catalog_slug': _resCatalogSlugs[i],
        'asset_item_id': itemId,
        if (rt.isNotEmpty) 'resource_type': rt,
      };
    });
    final flows = _selectedFlows.entries.map((e) => <String, dynamic>{
      'flow_definition_id': e.key,
      'behavior': e.value,
    }).toList();
    debugPrint('SUBMIT payload: operator=$_selectedOperatorId '
        'scope=$_scopeStart→$_scopeEnd '
        'resources=${resources.length} flows=${flows.length}');
    try {
      await AssignmentsApi.createAssignment(
        tenantId: widget.tenantId,
        operatorId: _selectedOperatorId!,
        scopeStart: _scopeStart!,
        scopeEnd: _scopeEnd!,
        resources: resources,
        flows: flows,
      );
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('CREATE ERROR: $e');
      if (!mounted) return;
      setState(() { _error = e.toString(); _saving = false; });
    }
  }

  void _onContinue() {
    if (_step == 0) {
      if (!_step1Valid) {
        setState(() => _error =
            'Completa todos los campos. El fin debe ser posterior al inicio.');
        return;
      }
      setState(() { _step = 1; _error = null; });
    } else if (_step == 1) {
      setState(() { _step = 2; _error = null; });
    } else if (_step == 2) {
      setState(() { _step = 3; _error = null; });
    } else {
      _submit();
    }
  }

  void _onCancel() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      widget.onCancel();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.ctBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepIndicator(
              currentStep: _step,
              steps: const [
                'Operador y ventana',
                'Activos',
                'Flows',
                'Confirmación',
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _buildCurrentStep(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: _buildStepControls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case 0: return _buildStep1();
      case 1: return _buildStep2();
      case 2: return _buildStep3();
      case 3: return _buildStep4();
      default: return _buildStep1();
    }
  }

  Widget _buildStepControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!,
                style: AppFonts.geist(
                    fontSize: 12, color: AppColors.ctDanger)),
          ),
        Row(
          children: [
            if (_step > 0) ...[
              AppButton(
                label: 'Atrás',
                variant: AppButtonVariant.outline,
                size: AppButtonSize.sm,
                onPressed: _onCancel,
              ),
              const SizedBox(width: 10),
            ],
            AppButton(
              label: _step == 3
                  ? (_saving ? 'Guardando…' : 'Confirmar')
                  : 'Siguiente',
              variant: AppButtonVariant.teal,
              size: AppButtonSize.sm,
              onPressed: _onContinue,
              isDisabled: _saving,
            ),
            const Spacer(),
            AppButton(
              label: 'Cancelar',
              variant: AppButtonVariant.outline,
              size: AppButtonSize.sm,
              onPressed: () {
                widget.onCancel();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DialogLabel('Operador'),
        const SizedBox(height: 6),
        _Dropdown<String?>(
          value: _selectedOperatorId,
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text('Seleccionar operador',
                  style: AppFonts.geist(
                      fontSize: 13, color: AppColors.ctText3)),
            ),
            ...widget.operators.map((op) => DropdownMenuItem<String?>(
                  value: op['id'] as String?,
                  child: Text(
                    op['display_name'] as String? ??
                        op['name'] as String? ??
                        '',
                    style: AppFonts.geist(
                        fontSize: 13, color: AppColors.ctText),
                  ),
                )),
          ],
          onChanged: (v) => setState(() => _selectedOperatorId = v),
        ),
        const SizedBox(height: 14),
        _DialogLabel('Inicio de ventana'),
        const SizedBox(height: 6),
        _DateTimePickerBtn(
          value: _scopeStart,
          hint: 'Seleccionar inicio',
          onChanged: (v) => setState(() => _scopeStart = v),
        ),
        const SizedBox(height: 14),
        _DialogLabel('Fin de ventana'),
        const SizedBox(height: 6),
        _DateTimePickerBtn(
          value: _scopeEnd,
          hint: 'Seleccionar fin',
          onChanged: (v) => setState(() => _scopeEnd = v),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate(_resCatalogSlugs.length, (i) => _ResourceRow(
              key: ValueKey('res_$i'),
              index: i,
              tenantId: widget.tenantId,
              catalogSlug: _resCatalogSlugs[i],
              catalogs: _catalogs,
              itemIdCtrl: _resItemIdCtrls[i],
              typeCtrl: _resTypeCtrls[i],
              onCatalogChanged: (v) => setState(() {
                _resCatalogSlugs[i] = v ?? '';
                _resItemIds[i] = null;
                _resItemNames[i] = '';
              }),
              onItemSelected: (id) => setState(() => _resItemIds[i] = id),
              onItemNameSelected: (name) => setState(() => _resItemNames[i] = name),
              onRemove: () => _removeResource(i),
            )),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _addResource,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_circle_outline,
                  size: 16, color: AppColors.ctTeal),
              const SizedBox(width: 6),
              Text('+ Agregar activo',
                  style: AppFonts.geist(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ctTeal)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStep3() {
    if (_loadingApiData) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.ctTeal),
            const SizedBox(height: 8),
            Text('Cargando flows…',
                style: AppFonts.geist(fontSize: 12, color: AppColors.ctText2)),
          ],
        ),
      );
    }
    if (_apiError != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Error al cargar flows: $_apiError',
              style: AppFonts.geist(fontSize: 12, color: AppColors.ctDanger)),
          const SizedBox(height: 8),
          AppButton(
            label: 'Reintentar',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: _loadApiData,
          ),
        ],
      );
    }
    if (_flowDefs.isEmpty) {
      return Text(
        'No hay flows configurados en este tenant.',
        style: AppFonts.geist(fontSize: 12, color: AppColors.ctText2),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Selecciona los flows a asignar:',
            style: AppFonts.geist(fontSize: 13, color: AppColors.ctText2)),
        const SizedBox(height: 8),
        ..._flowDefs.map((f) {
          final id = f['id'] as String? ?? '';
          final name = f['name'] as String? ?? f['slug'] as String? ?? id;
          final isSelected = _selectedFlows.containsKey(id);
          final behavior = _selectedFlows[id] ?? 'permissive';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: InkWell(
              onTap: () => setState(() {
                if (isSelected) {
                  _selectedFlows.remove(id);
                } else {
                  _selectedFlows[id] = 'permissive';
                }
              }),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      color:
                          isSelected ? AppColors.ctTeal : AppColors.ctText2,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(name,
                          style: AppFonts.geist(
                              fontSize: 13, color: AppColors.ctText)),
                    ),
                    if (isSelected) ...[
                      const SizedBox(width: 8),
                      _BehaviorBtn(
                        label: 'Manual',
                        value: 'permissive',
                        current: behavior,
                        onChanged: (v) =>
                            setState(() => _selectedFlows[id] = v),
                      ),
                      const SizedBox(width: 4),
                      _BehaviorBtn(
                        label: 'Automático',
                        value: 'scheduled',
                        current: behavior,
                        onChanged: (v) =>
                            setState(() => _selectedFlows[id] = v),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
        if (_selectedFlows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Sin flows seleccionados — el assignment se crea sin trigger automático',
              style: AppFonts.geist(fontSize: 11, color: AppColors.ctText2),
            ),
          ),
      ],
    );
  }

  Widget _buildStep4() {
    if (_scopeStart == null || _scopeEnd == null || _selectedOperatorId == null) {
      return Center(
        child: Text('Datos incompletos — regresa al paso 1',
            style: AppFonts.geist(fontSize: 13, color: AppColors.ctDanger)),
      );
    }
    final opName = widget.operators
            .where((o) => o['id'] == _selectedOperatorId)
            .map((o) =>
                o['display_name'] as String? ?? o['name'] as String? ?? '')
            .firstOrNull ??
        _selectedOperatorId ??
        '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.ctSurface2,
            border: Border.all(color: AppColors.ctBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Resumen',
                  style: AppFonts.onest(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ctText)),
              const SizedBox(height: 8),
              AppDetailRow(
                label: 'Operador',
                value: Text(opName, style: AppTextStyles.body.copyWith(fontSize: 12, fontWeight: FontWeight.w500)),
              ),
              AppDetailRow(
                label: 'Ventana',
                value: Text(
                  _formatWindow(
                    _scopeStart != null && _scopeEnd != null
                        ? '[${_scopeStart!.toUtc().toIso8601String()}'
                            ',${_scopeEnd!.toUtc().toIso8601String()})'
                        : null,
                  ),
                  style: AppTextStyles.body.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
              if (_resCatalogSlugs.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Activos',
                    style: AppFonts.geist(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ctText2)),
                ...List.generate(_resCatalogSlugs.length, (i) => AppDetailRow(
                      label: _resCatalogSlugs[i],
                      value: Text(
                        _resItemNames[i].isNotEmpty
                            ? _resItemNames[i]
                            : (_resItemIds[i] ?? '—'),
                        style: AppTextStyles.body.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    )),
              ],
              if (_selectedFlows.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Flows',
                    style: AppFonts.geist(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ctText2)),
                ..._selectedFlows.entries.map((e) {
                  final f = _flowDefs.firstWhere(
                      (f) => f['id'] == e.key,
                      orElse: () => {});
                  final name = f['name'] as String? ??
                      f['slug'] as String? ??
                      e.key;
                  final behaviorLabel =
                      e.value == 'scheduled' ? 'Automático' : 'Manual';
                  return AppDetailRow(
                    label: name,
                    value: Text(behaviorLabel, style: AppTextStyles.body.copyWith(fontSize: 12, fontWeight: FontWeight.w500)),
                  );
                }),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Dialog sub-widgets ────────────────────────────────────────────────────────

class _ResourceRow extends StatefulWidget {
  const _ResourceRow({
    super.key,
    required this.index,
    required this.tenantId,
    required this.catalogSlug,
    required this.catalogs,
    required this.itemIdCtrl,
    required this.typeCtrl,
    required this.onCatalogChanged,
    required this.onItemSelected,
    required this.onItemNameSelected,
    required this.onRemove,
  });

  final int index;
  final String tenantId;
  final String catalogSlug;
  final List<Map<String, dynamic>> catalogs;
  final TextEditingController itemIdCtrl;
  final TextEditingController typeCtrl;
  final ValueChanged<String?> onCatalogChanged;
  final ValueChanged<String?> onItemSelected;
  final ValueChanged<String> onItemNameSelected;
  final VoidCallback onRemove;

  @override
  State<_ResourceRow> createState() => _ResourceRowState();
}

class _ResourceRowState extends State<_ResourceRow> {
  bool _loadingItems = false;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    if (widget.catalogSlug.isNotEmpty) _loadItems();
  }

  @override
  void didUpdateWidget(_ResourceRow old) {
    super.didUpdateWidget(old);
    if (old.catalogSlug != widget.catalogSlug) {
      _items = [];
      widget.itemIdCtrl.clear();
      if (widget.catalogSlug.isNotEmpty) _loadItems();
    }
  }

  Future<void> _loadItems() async {
    final catalog = widget.catalogs.firstWhere(
      (c) => c['slug'] == widget.catalogSlug,
      orElse: () => <String, dynamic>{},
    );
    final catalogId = catalog['id'] as String?;
    if (catalogId == null || catalogId.isEmpty) return;
    setState(() => _loadingItems = true);
    try {
      final items = await CatalogsApi.listItems(
        tenantId: widget.tenantId,
        catalogId: catalogId,
      );
      if (mounted) setState(() { _items = items; _loadingItems = false; });
    } catch (e) {
      if (mounted) setState(() => _loadingItems = false);
      debugPrint('Error loading catalog items: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogSelected = widget.catalogSlug.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: widget.catalogs.isEmpty
                    ? Text('Cargando catálogos…',
                        style: AppFonts.geist(
                            fontSize: 12, color: AppColors.ctText2))
                    : _Dropdown<String>(
                        value: widget.catalogs.any(
                                (c) => c['slug'] == widget.catalogSlug)
                            ? widget.catalogSlug
                            : (widget.catalogs.first['slug'] as String? ?? ''),
                        items: widget.catalogs
                            .map((c) => DropdownMenuItem(
                                  value: c['slug'] as String? ?? '',
                                  child: Text(
                                    c['slug'] as String? ?? '',
                                    style: AppFonts.geist(
                                        fontSize: 12,
                                        color: AppColors.ctText),
                                  ),
                                ))
                            .toList(),
                        onChanged: widget.onCatalogChanged,
                      ),
              ),
              IconButton(
                icon: const Icon(Icons.close,
                    size: 16, color: AppColors.ctDanger),
                onPressed: widget.onRemove,
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_loadingItems)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.ctTeal,
                ),
              ),
            )
          else if (!catalogSelected)
            TextField(
              enabled: false,
              style: AppFonts.geist(fontSize: 12, color: AppColors.ctText2),
              decoration: const InputDecoration(
                hintText: 'Selecciona un catálogo primero',
                isDense: true,
              ),
            )
          else
            Autocomplete<Map<String, dynamic>>(
              displayStringForOption: (item) {
                final data = item['data'];
                return item['name'] as String? ??
                    (data is Map ? (data['nombre'] as String? ?? data['name'] as String? ?? data['label'] as String? ?? data['title'] as String? ?? (data.values.isNotEmpty ? data.values.first?.toString() : null)) : null) ??
                    item['id'] as String? ??
                    '';
              },
              optionsBuilder: (textEditingValue) {
                if (textEditingValue.text.isEmpty) return _items;
                final q = textEditingValue.text.toLowerCase();
                return _items.where((item) {
                  final data = item['data'];
                  final name = (item['name'] as String? ??
                          (data is Map
                              ? (data['nombre'] as String? ??
                                  data['name'] as String? ??
                                  '')
                              : ''))
                      .toLowerCase();
                  final id = (item['id'] as String? ?? '').toLowerCase();
                  return name.contains(q) || id.contains(q);
                });
              },
              onSelected: (item) {
                final id = item['id'] as String? ?? '';
                final data = item['data'] as Map<String, dynamic>?;
                final name = item['name'] as String? ??
                    data?['nombre'] as String? ??
                    data?['name'] as String? ??
                    data?['label'] as String? ??
                    id;
                widget.itemIdCtrl.text = id;
                widget.onItemSelected(id);
                widget.onItemNameSelected(name);
              },
              fieldViewBuilder:
                  (context, fieldCtrl, focusNode, onFieldSubmitted) {
                return TextField(
                  controller: fieldCtrl,
                  focusNode: focusNode,
                  style: AppFonts.geist(
                      fontSize: 12, color: AppColors.ctText),
                  decoration: const InputDecoration(
                    labelText: 'Buscar activo',
                    isDense: true,
                  ),
                );
              },
            ),
          const SizedBox(height: 6),
          TextField(
            controller: widget.typeCtrl,
            style: AppFonts.geist(fontSize: 12, color: AppColors.ctText),
            decoration: const InputDecoration(
              labelText: 'Rol del activo (opc.)',
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _DateTimePickerBtn extends StatelessWidget {
  const _DateTimePickerBtn({
    required this.value,
    required this.hint,
    required this.onChanged,
  });

  final DateTime? value;
  final String hint;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final picked = await showOmniDateTimePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          is24HourMode: true,
        );
        if (picked != null) onChanged(picked);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.ctSurface2,
          border: Border.all(
              color: value != null
                  ? AppColors.ctTeal
                  : AppColors.ctBorder2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time_outlined,
                size: 14,
                color: value != null
                    ? AppColors.ctTeal
                    : AppColors.ctText2),
            const SizedBox(width: 8),
            Text(
              value != null ? _formatDt(value!) : hint,
              style: AppFonts.geist(
                  fontSize: 13,
                  color: value != null
                      ? AppColors.ctText
                      : AppColors.ctText2),
            ),
          ],
        ),
      ),
    );
  }
}

class _BehaviorBtn extends StatelessWidget {
  const _BehaviorBtn({
    required this.label,
    required this.value,
    required this.current,
    required this.onChanged,
  });

  final String label;
  final String value;
  final String current;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final active = value == current;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.ctTeal : AppColors.ctSurface,
          border: Border.all(
              color: active ? AppColors.ctTeal : AppColors.ctBorder),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: AppFonts.geist(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppColors.ctText2,
          ),
        ),
      ),
    );
  }
}


class _DialogLabel extends StatelessWidget {
  const _DialogLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: AppFonts.geist(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.ctText2));
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.ctSurface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.ctBorder2),
      ),
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        dropdownColor: AppColors.ctSurface,
        style: AppFonts.geist(fontSize: 13, color: AppColors.ctText),
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

// Variante que acepta value nullable (para dropdowns con hint)
