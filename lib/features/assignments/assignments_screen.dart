import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:omni_datetime_picker/omni_datetime_picker.dart';
import 'package:calendar_view/calendar_view.dart';

import '../../core/api/assignments_api.dart';
import '../../core/api/catalogs_api.dart';
import '../../core/api/flows_api.dart';
import '../../core/api/operators_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
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
    final clean = raw
        .replaceAll('[', '')
        .replaceAll('(', '')
        .replaceAll(']', '')
        .replaceAll(')', '');
    final parts = clean.split(',');
    if (parts.length < 2) return (null, null);
    return (DateTime.parse(parts[0].trim()), DateTime.parse(parts[1].trim()));
  } catch (_) {
    return (null, null);
  }
}

final _dateFmt = DateFormat('d MMM', 'es_MX');
final _timeFmt = DateFormat('HH:mm');
final _dtFmt = DateFormat('dd/MM/yyyy HH:mm');

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
    'proactive'  => AppColors.ctWarn,
    _            => AppColors.ctText2,
  };
}

String _resourceLabel(Map<String, dynamic> r) {
  final type =
      r['resource_type'] as String? ?? r['catalog_slug'] as String? ?? '';
  final data = r['data'];
  String value = r['asset_item_id'] as String? ?? '—';
  if (data is Map) {
    value = data['nombre'] as String? ??
        data['placas'] as String? ??
        (data.values.isNotEmpty ? data.values.first.toString() : value);
  }
  return type.isNotEmpty ? '$type: $value' : value;
}

String _flowLabel(Map<String, dynamic> f) {
  final id = f['flow_slug'] as String? ??
      f['flow_definition_id'] as String? ??
      '—';
  final behavior = f['behavior'] as String? ?? '';
  return behavior.isNotEmpty ? '$id ($behavior)' : id;
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
      if (!mounted) return;
      setState(() {
        _assignments = List<Map<String, dynamic>>.from(data);
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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancelar',
                style: AppFonts.geist(fontSize: 13, color: AppColors.ctText2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Eliminar',
                style: AppFonts.geist(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ctDanger)),
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
                _SecondaryButton(
                  label: 'Importar CSV',
                  icon: Icons.upload_file_outlined,
                  onTap: () {},
                ),
                _PrimaryButton(
                  label: '+ Nueva asignación',
                  onTap: () => setState(() => _showNewModal = true),
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
                        TextButton(
                          onPressed: _loadAssignments,
                          child: const Text('Reintentar'),
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
            _PrimaryButton(label: '+ Nueva asignación', onTap: onNew),
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
  final List<TextEditingController> _resItemIdCtrls = [];
  final List<TextEditingController> _resTypeCtrls = [];

  // Flows
  final List<String> _flowDefIds = [];
  final List<String> _flowBehaviors = [];
  final List<TextEditingController> _flowTriggerCtrls = [];
  final List<TextEditingController> _flowWindowCtrls = [];

  List<Map<String, dynamic>> _catalogs = [];
  List<Map<String, dynamic>> _flowDefs = [];

  @override
  void initState() {
    super.initState();
    _loadApiData();
  }

  Future<void> _loadApiData() async {
    try {
      final catalogs =
          await CatalogsApi.listCatalogs(tenantId: widget.tenantId);
      final flows = await FlowsApi.listFlows();
      if (mounted) setState(() { _catalogs = catalogs; _flowDefs = flows; });
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in [..._resItemIdCtrls, ..._resTypeCtrls,
        ..._flowTriggerCtrls, ..._flowWindowCtrls]) {
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
      _resItemIdCtrls.add(TextEditingController());
      _resTypeCtrls.add(TextEditingController());
    });
  }

  void _removeResource(int i) {
    setState(() {
      _resCatalogSlugs.removeAt(i);
      _resItemIdCtrls[i].dispose();
      _resItemIdCtrls.removeAt(i);
      _resTypeCtrls[i].dispose();
      _resTypeCtrls.removeAt(i);
    });
  }

  void _addFlow() {
    setState(() {
      _flowDefIds.add(
          _flowDefs.isNotEmpty
              ? (_flowDefs.first['id'] as String? ?? '')
              : '');
      _flowBehaviors.add('scheduled');
      _flowTriggerCtrls.add(TextEditingController());
      _flowWindowCtrls.add(TextEditingController());
    });
  }

  void _removeFlow(int i) {
    setState(() {
      _flowDefIds.removeAt(i);
      _flowBehaviors.removeAt(i);
      _flowTriggerCtrls[i].dispose();
      _flowTriggerCtrls.removeAt(i);
      _flowWindowCtrls[i].dispose();
      _flowWindowCtrls.removeAt(i);
    });
  }

  bool get _step1Valid =>
      _selectedOperatorId != null &&
      _scopeStart != null &&
      _scopeEnd != null &&
      _scopeEnd!.isAfter(_scopeStart!);

  Future<void> _submit() async {
    setState(() { _saving = true; _error = null; });
    try {
      final resources = List.generate(_resCatalogSlugs.length, (i) {
        final rt = _resTypeCtrls[i].text.trim();
        return <String, dynamic>{
          'catalog_slug': _resCatalogSlugs[i],
          'asset_item_id': _resItemIdCtrls[i].text.trim(),
          if (rt.isNotEmpty) 'resource_type': rt,
        };
      });
      final flows = List.generate(_flowDefIds.length, (i) {
        final behavior = _flowBehaviors[i];
        final trigger =
            int.tryParse(_flowTriggerCtrls[i].text.trim());
        final window =
            int.tryParse(_flowWindowCtrls[i].text.trim());
        return <String, dynamic>{
          'flow_definition_id': _flowDefIds[i],
          'behavior': behavior,
          if (trigger != null) 'trigger_offset': trigger * 60,
          if (window != null && behavior == 'scheduled')
            'completion_window': window * 3600,
        };
      });
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
        child: Stepper(
          currentStep: _step,
          onStepContinue: _onContinue,
          onStepCancel: _onCancel,
          controlsBuilder: (context, details) => Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!,
                        style: AppFonts.geist(
                            fontSize: 12,
                            color: AppColors.ctDanger)),
                  ),
                Row(
                  children: [
                    _PrimaryButton(
                      label: _step == 2
                          ? (_saving ? 'Guardando…' : 'Confirmar')
                          : 'Siguiente',
                      onTap: _saving ? null : details.onStepContinue,
                    ),
                    const SizedBox(width: 10),
                    _GhostButton(
                      label: _step == 0 ? 'Cancelar' : 'Atrás',
                      onTap: details.onStepCancel ?? () {},
                    ),
                  ],
                ),
              ],
            ),
          ),
          steps: [
            Step(
              title: Text('Operador y ventana',
                  style: AppFonts.geist(
                      fontSize: 13, fontWeight: FontWeight.w500)),
              isActive: _step >= 0,
              state: _step > 0 ? StepState.complete : StepState.indexed,
              content: _buildStep1(),
            ),
            Step(
              title: Text('Activos',
                  style: AppFonts.geist(
                      fontSize: 13, fontWeight: FontWeight.w500)),
              isActive: _step >= 1,
              state: _step > 1 ? StepState.complete : StepState.indexed,
              content: _buildStep2(),
            ),
            Step(
              title: Text('Flows y confirmar',
                  style: AppFonts.geist(
                      fontSize: 13, fontWeight: FontWeight.w500)),
              isActive: _step >= 2,
              state: StepState.indexed,
              content: _buildStep3(),
            ),
          ],
        ),
      ),
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
              index: i,
              catalogSlug: _resCatalogSlugs[i],
              catalogs: _catalogs,
              itemIdCtrl: _resItemIdCtrls[i],
              typeCtrl: _resTypeCtrls[i],
              onCatalogChanged: (v) =>
                  setState(() => _resCatalogSlugs[i] = v ?? ''),
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
    final opName = widget.operators
            .where((o) => o['id'] == _selectedOperatorId)
            .map((o) => o['display_name'] as String? ?? '')
            .firstOrNull ??
        _selectedOperatorId ??
        '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate(_flowDefIds.length, (i) => _FlowRow(
              index: i,
              flowDefId: _flowDefIds[i],
              behavior: _flowBehaviors[i],
              flowDefs: _flowDefs,
              triggerCtrl: _flowTriggerCtrls[i],
              windowCtrl: _flowWindowCtrls[i],
              onFlowChanged: (v) =>
                  setState(() => _flowDefIds[i] = v ?? ''),
              onBehaviorChanged: (v) =>
                  setState(() => _flowBehaviors[i] = v ?? 'scheduled'),
              onRemove: () => _removeFlow(i),
            )),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _addFlow,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_circle_outline,
                  size: 16, color: AppColors.ctTeal),
              const SizedBox(width: 6),
              Text('+ Agregar flow',
                  style: AppFonts.geist(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ctTeal)),
            ],
          ),
        ),
        const SizedBox(height: 20),
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
              _SummaryRow(label: 'Operador', value: opName),
              _SummaryRow(
                label: 'Ventana',
                value: _formatWindow(
                  _scopeStart != null && _scopeEnd != null
                      ? '[${_scopeStart!.toUtc().toIso8601String()}'
                          ',${_scopeEnd!.toUtc().toIso8601String()})'
                      : null,
                ),
              ),
              _SummaryRow(
                  label: 'Activos',
                  value: '${_resCatalogSlugs.length}'),
              _SummaryRow(
                  label: 'Flows',
                  value: '${_flowDefIds.length}'),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Dialog sub-widgets ────────────────────────────────────────────────────────

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({
    required this.index,
    required this.catalogSlug,
    required this.catalogs,
    required this.itemIdCtrl,
    required this.typeCtrl,
    required this.onCatalogChanged,
    required this.onRemove,
  });

  final int index;
  final String catalogSlug;
  final List<Map<String, dynamic>> catalogs;
  final TextEditingController itemIdCtrl;
  final TextEditingController typeCtrl;
  final ValueChanged<String?> onCatalogChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
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
                child: catalogs.isEmpty
                    ? Text('Cargando catálogos…',
                        style: AppFonts.geist(
                            fontSize: 12, color: AppColors.ctText2))
                    : _Dropdown<String>(
                        value: catalogs.any(
                                (c) => c['slug'] == catalogSlug)
                            ? catalogSlug
                            : (catalogs.first['slug'] as String? ?? ''),
                        items: catalogs
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
                        onChanged: onCatalogChanged,
                      ),
              ),
              IconButton(
                icon: const Icon(Icons.close,
                    size: 16, color: AppColors.ctDanger),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: itemIdCtrl,
                  style: AppFonts.geist(
                      fontSize: 12, color: AppColors.ctText),
                  decoration: const InputDecoration(
                    labelText: 'asset_item_id',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: typeCtrl,
                  style: AppFonts.geist(
                      fontSize: 12, color: AppColors.ctText),
                  decoration: const InputDecoration(
                    labelText: 'resource_type (opc.)',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FlowRow extends StatelessWidget {
  const _FlowRow({
    required this.index,
    required this.flowDefId,
    required this.behavior,
    required this.flowDefs,
    required this.triggerCtrl,
    required this.windowCtrl,
    required this.onFlowChanged,
    required this.onBehaviorChanged,
    required this.onRemove,
  });

  final int index;
  final String flowDefId;
  final String behavior;
  final List<Map<String, dynamic>> flowDefs;
  final TextEditingController triggerCtrl;
  final TextEditingController windowCtrl;
  final ValueChanged<String?> onFlowChanged;
  final ValueChanged<String?> onBehaviorChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final needsOffset = behavior == 'scheduled' || behavior == 'proactive';
    final needsWindow = behavior == 'scheduled';

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
                child: flowDefs.isEmpty
                    ? Text('Cargando flows…',
                        style: AppFonts.geist(
                            fontSize: 12, color: AppColors.ctText2))
                    : _Dropdown<String>(
                        value: flowDefs.any(
                                (f) => f['id'] == flowDefId)
                            ? flowDefId
                            : (flowDefs.first['id'] as String? ?? ''),
                        items: flowDefs
                            .map((f) => DropdownMenuItem(
                                  value: f['id'] as String? ?? '',
                                  child: Text(
                                    f['name'] as String? ??
                                        f['id'] as String? ??
                                        '',
                                    style: AppFonts.geist(
                                        fontSize: 12,
                                        color: AppColors.ctText),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: onFlowChanged,
                      ),
              ),
              const SizedBox(width: 8),
              _Dropdown<String>(
                value: behavior,
                items: const [
                  DropdownMenuItem(
                      value: 'scheduled', child: Text('scheduled')),
                  DropdownMenuItem(
                      value: 'permissive', child: Text('permissive')),
                  DropdownMenuItem(
                      value: 'proactive', child: Text('proactive')),
                ],
                onChanged: onBehaviorChanged,
              ),
              IconButton(
                icon: const Icon(Icons.close,
                    size: 16, color: AppColors.ctDanger),
                onPressed: onRemove,
              ),
            ],
          ),
          if (needsOffset) ...[
            const SizedBox(height: 6),
            TextField(
              controller: triggerCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                  signed: true),
              style: AppFonts.geist(
                  fontSize: 12, color: AppColors.ctText),
              decoration: const InputDecoration(
                labelText: 'trigger_offset (min, puede ser negativo)',
                isDense: true,
              ),
            ),
          ],
          if (needsWindow) ...[
            const SizedBox(height: 6),
            TextField(
              controller: windowCtrl,
              keyboardType: TextInputType.number,
              style: AppFonts.geist(
                  fontSize: 12, color: AppColors.ctText),
              decoration: const InputDecoration(
                labelText: 'completion_window (horas)',
                isDense: true,
              ),
            ),
          ],
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
              value != null ? _dtFmt.format(value!) : hint,
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

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: AppFonts.geist(
                    fontSize: 12, color: AppColors.ctText2)),
          ),
          Expanded(
            child: Text(value,
                style: AppFonts.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ctText)),
          ),
        ],
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

// ── Shared buttons ────────────────────────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: enabled ? AppColors.ctTeal : AppColors.ctBorder,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: AppFonts.onest(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: enabled ? AppColors.ctNavy : AppColors.ctText2,
            ),
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.ctBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: AppFonts.geist(
                  fontSize: 13, color: AppColors.ctText2)),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.ctSurface,
            border: Border.all(color: AppColors.ctBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.ctText2),
              const SizedBox(width: 6),
              Text(label,
                  style: AppFonts.geist(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ctText2)),
            ],
          ),
        ),
      ),
    );
  }
}
