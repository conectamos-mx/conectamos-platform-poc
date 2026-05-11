import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/assignments_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/screen_header.dart';

// ── Color tokens por tipo de asignación ───────────────────────────────────────

const _kTypeColors = <String, Color>{
  'crum_daily':       AppColors.ctTeal,
  'vehicle_daily':    Color(0xFFF59E0B),
  'route_assignment': Color(0xFF8B5CF6),
};

const _kTypeLabels = <String, String>{
  'crum_daily':       'CRUM Diario',
  'vehicle_daily':    'Vehículo Diario',
  'route_assignment': 'Ruta',
};

Color _typeColor(String? type) =>
    _kTypeColors[type] ?? AppColors.ctText2;

String _typeLabel(String? type) =>
    _kTypeLabels[type] ?? (type ?? '—');

// ── Helpers de fecha ──────────────────────────────────────────────────────────

const _kWeekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const _kMonths = [
  'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
  'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
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
  return '${monday.day} ${_kMonths[monday.month - 1]} – ${sunday.day} ${_kMonths[sunday.month - 1]} ${monday.year}';
}

// ── Screen ────────────────────────────────────────────────────────────────────

class AssignmentsScreen extends ConsumerStatefulWidget {
  const AssignmentsScreen({super.key});

  @override
  ConsumerState<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends ConsumerState<AssignmentsScreen> {
  String _view = 'calendar'; // 'calendar' | 'table'
  int _weekOffset = 0;
  List<Map<String, dynamic>> _assignments = [];
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAssignments());
  }

  Future<void> _loadAssignments() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final tenantId = ref.read(activeTenantIdProvider);
      final monday = _currentMonday;
      final futures = List.generate(7, (i) {
        final day = monday.add(Duration(days: i));
        return AssignmentsApi.getAssignments(
          tenantId: tenantId,
          scopeDate: _isoDate(day),
        );
      });
      final results = await Future.wait(futures);
      final data = results.expand((list) => list).toList();
      if (!mounted) return;
      setState(() { _assignments = data; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<Map<String, dynamic>> _assignmentsForDay(DateTime day) {
    final iso = _isoDate(day);
    return _assignments.where((a) => a['scope_date'] == iso).toList();
  }

  @override
  Widget build(BuildContext context) {
    final canManage = hasPermission(ref, 'assignments', 'manage');

    return Scaffold(
      backgroundColor: AppColors.ctBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenHeader(
            title: 'Asignaciones',
            subtitle: 'Asigna recursos a operadores con horario.',
            actions: [
              _SecondaryButton(
                label: 'Importar CSV',
                icon: Icons.upload_file_outlined,
                onTap: canManage ? () {} : null,
              ),
              if (canManage)
                _PrimaryButton(
                  label: '+ Nueva asignación',
                  onTap: () => setState(() => _showNewModal = true),
                ),
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
                    child: Text(_error!,
                        style: AppFonts.geist(
                            fontSize: 13, color: AppColors.ctDanger)),
                  )
                : _view == 'calendar'
                    ? _AssignmentsCalendar(
                        currentMonday: _currentMonday,
                        today: _today,
                        assignments: _assignments,
                        loading: _loading,
                        assignmentsForDay: _assignmentsForDay,
                        onDayTap: (day) =>
                            setState(() => _drawerDay = day),
                      )
                    : _AssignmentsTable(
                        assignments: _assignments,
                        loading: _loading,
                        canManage: canManage,
                        onDelete: (id) async {
                          final tenantId = ref.read(activeTenantIdProvider);
                          await AssignmentsApi.deleteAssignment(
                              tenantId: tenantId, assignmentId: id);
                          _loadAssignments();
                        },
                      ),
          ),
        ],
      ),
      // Day detail drawer
      endDrawer: _drawerDay == null
          ? null
          : _DayDrawer(
              day: _drawerDay!,
              assignments: _assignmentsForDay(_drawerDay!),
              onClose: () => setState(() => _drawerDay = null),
            ),
      // New assignment modal
      floatingActionButton: null,
    ).also((_) {
      if (_showNewModal) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_showNewModal) return;
          showDialog(
            context: context,
            builder: (_) => _NewAssignmentDialog(
              tenantId: ref.read(activeTenantIdProvider),
              defaultDate: _drawerDay ?? _today,
              onSaved: () {
                setState(() => _showNewModal = false);
                _loadAssignments();
              },
              onCancel: () => setState(() => _showNewModal = false),
            ),
          ).then((_) => setState(() => _showNewModal = false));
          setState(() => _showNewModal = false);
        });
      }
    });
  }
}

extension _Also on Widget {
  Widget also(void Function(Widget) fn) {
    fn(this);
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
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Week nav (calendar only)
          if (view == 'calendar') ...[
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.ctBorder),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Hoy',
                      style: AppFonts.geist(
                          fontSize: 12, color: AppColors.ctText2)),
                ),
              ),
          ],
          const Spacer(),
          // Legend
          Wrap(
            spacing: 12,
            children: _kTypeColors.entries.map((e) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: e.value,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _kTypeLabels[e.key] ?? e.key,
                    style: AppFonts.geist(
                        fontSize: 11, color: AppColors.ctText2),
                  ),
                ],
              );
            }).toList(),
          ),
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
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

// ── Calendar ──────────────────────────────────────────────────────────────────

class _AssignmentsCalendar extends StatelessWidget {
  const _AssignmentsCalendar({
    required this.currentMonday,
    required this.today,
    required this.assignments,
    required this.loading,
    required this.assignmentsForDay,
    required this.onDayTap,
  });

  final DateTime currentMonday;
  final DateTime today;
  final List<Map<String, dynamic>> assignments;
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
          // Day headers
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
                      Text(
                        _kWeekdays[i],
                        style: AppFonts.geist(
                            fontSize: 11, color: AppColors.ctText2),
                      ),
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
                          child: Text(
                            '${day.day}',
                            style: AppFonts.geist(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _isToday(day)
                                  ? Colors.white
                                  : AppColors.ctText,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
          // Day cells
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
                            bottom:
                                BorderSide(color: AppColors.ctBorder),
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
                                      child: Text(
                                        '+$overflow más',
                                        style: AppFonts.geist(
                                            fontSize: 10,
                                            color: AppColors.ctText2),
                                      ),
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

// ── Assignment Chip (compact, for calendar) ───────────────────────────────────

class _AssignmentChip extends StatelessWidget {
  const _AssignmentChip({required this.assignment});
  final Map<String, dynamic> assignment;

  @override
  Widget build(BuildContext context) {
    final type = assignment['assignment_type'] as String?;
    final color = _typeColor(type);
    final name = assignment['operator_name'] as String? ?? '—';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        name,
        style: AppFonts.geist(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: color,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ── Assignment Chip Full (for drawer) ─────────────────────────────────────────

class _AssignmentChipFull extends StatelessWidget {
  const _AssignmentChipFull({required this.assignment});
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
    final type = assignment['assignment_type'] as String?;
    final color = _typeColor(type);
    final name = assignment['operator_name'] as String? ?? '—';
    final phone = assignment['operator_phone'] as String?;
    final source = assignment['source'] as String?;
    final data = assignment['data'] as Map?;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
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
                color: color,
              ),
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
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _TypeBadge(type: type, color: color),
                    if (source == 'google_sheets')
                      _SourceBadge(
                          label: 'Sheets',
                          color: const Color(0xFF16A34A)),
                    if (source == 'manual' || source == null)
                      _SourceBadge(
                          label: 'Manual',
                          color: AppColors.ctText2),
                  ],
                ),
                if (data != null && data.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ...data.entries.map((e) => Text(
                        '${e.key}: ${e.value}',
                        style: AppFonts.geist(
                            fontSize: 11, color: AppColors.ctText2),
                      )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type, required this.color});
  final String? type;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        _typeLabel(type),
        style: AppFonts.geist(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: AppFonts.geist(
            fontSize: 10, fontWeight: FontWeight.w500, color: color),
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
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
  ];

  @override
  Widget build(BuildContext context) {
    final title = '${day.day} de ${_months[day.month - 1]} ${day.year}';

    return Drawer(
      backgroundColor: AppColors.ctSurface,
      width: 360,
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
                        color: AppColors.ctNavy,
                      ),
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
                          Text(
                            'Sin asignaciones este día',
                            style: AppFonts.geist(
                                fontSize: 13,
                                color: AppColors.ctText2),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: assignments
                          .map((a) => _AssignmentChipFull(assignment: a))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Table ─────────────────────────────────────────────────────────────────────

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
  final void Function(String id) onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.ctBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            // Header row
            _TableRow(
              isHeader: true,
              cells: const [
                'Operador', 'Fecha', 'Tipo', 'Datos', 'Fuente', ''
              ],
            ),
            const Divider(height: 1, color: AppColors.ctBorder),
            Expanded(
              child: loading
                  ? _TableSkeleton()
                  : assignments.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.assignment_outlined,
                                  size: 36, color: AppColors.ctText3),
                              const SizedBox(height: 8),
                              Text(
                                'No hay asignaciones',
                                style: AppFonts.geist(
                                    fontSize: 13,
                                    color: AppColors.ctText2),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: assignments.length,
                          separatorBuilder: (context2, idx) => const Divider(
                              height: 1, color: AppColors.ctBorder),
                          itemBuilder: (context, i) {
                            final a = assignments[i];
                            final type =
                                a['assignment_type'] as String?;
                            final color = _typeColor(type);
                            final name =
                                a['operator_name'] as String? ?? '—';
                            final date =
                                a['scope_date'] as String? ?? '—';
                            final source = a['source'] as String?;
                            final id = a['id'] as String? ?? '';
                            final data = a['data'] as Map?;
                            final dataStr = data?.entries
                                    .map((e) => '${e.key}: ${e.value}')
                                    .join(', ') ??
                                '—';

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              child: Row(
                                children: [
                                  // Operator
                                  Expanded(
                                    flex: 3,
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 14,
                                          backgroundColor: color
                                              .withValues(alpha: 0.15),
                                          child: Text(
                                            name.isNotEmpty
                                                ? name[0].toUpperCase()
                                                : '?',
                                            style: AppFonts.geist(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: color,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(name,
                                              style: AppFonts.geist(
                                                  fontSize: 12,
                                                  color: AppColors.ctText),
                                              overflow:
                                                  TextOverflow.ellipsis),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Date
                                  Expanded(
                                    flex: 2,
                                    child: Text(date,
                                        style: AppFonts.geist(
                                            fontSize: 12,
                                            color: AppColors.ctText2)),
                                  ),
                                  // Type badge
                                  Expanded(
                                    flex: 2,
                                    child: _TypeBadge(
                                        type: type, color: color),
                                  ),
                                  // Data
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      dataStr,
                                      style: AppFonts.geist(
                                          fontSize: 11,
                                          color: AppColors.ctText2),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  // Source
                                  Expanded(
                                    flex: 2,
                                    child: _SourceBadge(
                                      label: source == 'google_sheets'
                                          ? 'Sheets'
                                          : 'Manual',
                                      color:
                                          source == 'google_sheets'
                                              ? const Color(0xFF16A34A)
                                              : AppColors.ctText2,
                                    ),
                                  ),
                                  // Actions
                                  if (canManage)
                                    SizedBox(
                                      width: 32,
                                      child: PopupMenuButton<String>(
                                        icon: const Icon(
                                            Icons.more_horiz,
                                            size: 16,
                                            color: AppColors.ctText2),
                                        onSelected: (v) {
                                          if (v == 'delete' &&
                                              id.isNotEmpty) {
                                            onDelete(id);
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Eliminar'),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    const SizedBox(width: 32),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.isHeader, required this.cells});
  final bool isHeader;
  final List<String> cells;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: cells.map((c) {
          return Expanded(
            flex: c.isEmpty ? 1 : 2,
            child: Text(
              c,
              style: isHeader
                  ? AppFonts.geist(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ctText2)
                  : AppFonts.geist(
                      fontSize: 12, color: AppColors.ctText),
            ),
          );
        }).toList(),
      ),
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

// ── New Assignment Dialog ─────────────────────────────────────────────────────

class _NewAssignmentDialog extends ConsumerStatefulWidget {
  const _NewAssignmentDialog({
    required this.tenantId,
    required this.defaultDate,
    required this.onSaved,
    required this.onCancel,
  });

  final String tenantId;
  final DateTime defaultDate;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  @override
  ConsumerState<_NewAssignmentDialog> createState() =>
      _NewAssignmentDialogState();
}

class _NewAssignmentDialogState
    extends ConsumerState<_NewAssignmentDialog> {
  final _operatorCtrl = TextEditingController();
  final _dataCtrl = TextEditingController();
  String _assignmentType = 'crum_daily';
  late DateTime _scopeDate;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scopeDate = widget.defaultDate;
  }

  @override
  void dispose() {
    _operatorCtrl.dispose();
    _dataCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_operatorCtrl.text.trim().isEmpty) return;
    setState(() { _saving = true; _error = null; });
    try {
      await AssignmentsApi.createAssignment(
        tenantId: widget.tenantId,
        body: {
          'operator_id': _operatorCtrl.text.trim(),
          'assignment_type': _assignmentType,
          'scope_date': _isoDate(_scopeDate),
          'data': {'notes': _dataCtrl.text.trim()},
          'source': 'manual',
        },
      );
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _saving = false; });
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
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nueva asignación',
                  style: AppFonts.onest(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ctText)),
              const SizedBox(height: 20),
              // Operator ID
              _DialogField(
                label: 'ID del operador',
                controller: _operatorCtrl,
                placeholder: 'UUID del operador',
              ),
              const SizedBox(height: 14),
              // Type
              _DialogLabel('Tipo de asignación'),
              const SizedBox(height: 6),
              _Dropdown<String>(
                value: _assignmentType,
                items: _kTypeLabels.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value,
                              style: AppFonts.geist(
                                  fontSize: 13,
                                  color: AppColors.ctText)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _assignmentType = v);
                },
              ),
              const SizedBox(height: 14),
              // Date
              _DialogLabel('Fecha (scope_date)'),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _scopeDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) {
                    setState(() => _scopeDate = picked);
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.ctSurface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.ctBorder2),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 14, color: AppColors.ctText2),
                      const SizedBox(width: 8),
                      Text(
                        _isoDate(_scopeDate),
                        style: AppFonts.geist(
                            fontSize: 13, color: AppColors.ctText),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Data / notes
              _DialogField(
                label: 'Datos adicionales',
                controller: _dataCtrl,
                placeholder: 'Ej: Granjas, zona norte…',
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: AppFonts.geist(
                        fontSize: 12, color: AppColors.ctDanger)),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _GhostButton(
                    label: 'Cancelar',
                    onTap: () {
                      widget.onCancel();
                      Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(width: 10),
                  _PrimaryButton(
                    label: _saving ? 'Guardando…' : 'Guardar',
                    onTap: _saving ? null : _submit,
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

// ── Shared dialog components ──────────────────────────────────────────────────

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

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.label,
    required this.controller,
    this.placeholder,
  });

  final String label;
  final TextEditingController controller;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DialogLabel(label),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.ctSurface2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.ctBorder2),
          ),
          child: TextField(
            controller: controller,
            style: AppFonts.geist(fontSize: 13, color: AppColors.ctText),
            decoration: InputDecoration(
              hintText: placeholder,
              hintStyle: AppFonts.geist(
                  fontSize: 13, color: AppColors.ctText3),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
      ],
    );
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
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: enabled ? AppColors.ctTeal : AppColors.ctBorder,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: AppFonts.geist(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: enabled ? Colors.white : AppColors.ctText2,
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.ctBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: AppFonts.geist(
                fontSize: 13, color: AppColors.ctText2),
          ),
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.ctBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.ctText2),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppFonts.geist(
                    fontSize: 13, color: AppColors.ctText2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
