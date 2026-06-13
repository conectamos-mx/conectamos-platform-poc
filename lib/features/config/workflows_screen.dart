import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/ai_workers_api.dart';
import '../../core/api/api_client.dart';
import '../../core/api/flows_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/display_mappers.dart' as dm;
import '../../core/utils/flow_helpers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/screen_header.dart';
import 'widgets/create_flow_dialog.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _kTypeConfig = {
  'logistics':   (label: 'Logística', bg: Color(0xFFDBEAFE), fg: Color(0xFF1E40AF)),
  'sales':       (label: 'Ventas',    bg: Color(0xFFEDE9FE), fg: Color(0xFF6D28D9)),
  'collections': (label: 'Cobranza', bg: Color(0xFFFEF3C7), fg: Color(0xFFB45309)),
  'custom':      (label: 'Custom',   bg: Color(0xFFF3F4F6), fg: Color(0xFF374151)),
};

// ── Helpers ───────────────────────────────────────────────────────────────────


String _dioError(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      final d = data['detail'];
      if (d != null) return 'Error: $d';
    }
    final s = e.response?.statusCode;
    if (s != null) return 'Error $s al procesar la solicitud';
  }
  return e.toString();
}

// ── Screen ────────────────────────────────────────────────────────────────────

class WorkflowsScreen extends ConsumerStatefulWidget {
  const WorkflowsScreen({super.key, this.tenantWorkerId, this.onFlowSelected});
  final String? tenantWorkerId;
  final void Function(String flowId)? onFlowSelected;

  @override
  ConsumerState<WorkflowsScreen> createState() => _WorkflowsScreenState();
}

class _WorkflowsScreenState extends ConsumerState<WorkflowsScreen> {
  List<Map<String, dynamic>> _flows   = [];
  List<Map<String, dynamic>> _workers = [];
  bool    _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchAll());
  }

  Future<void> _fetchAll() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final dio = ref.read(apiClientProvider).dio;
      final results = await Future.wait([
        widget.tenantWorkerId != null
            ? FlowsApi.getFlowsByWorker(dio: dio, tenantWorkerId: widget.tenantWorkerId!)
            : FlowsApi.listFlows(dio: dio),
        AiWorkersApi.listWorkers(dio: dio),
      ]);
      if (!mounted) return;
      setState(() {
        _flows   = results[0];
        _workers = results[1];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = _dioError(e); });
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> flow) async {
    final id       = flow['id'] as String? ?? '';
    final isActive = flow['is_active'] as bool? ?? false;
    // Optimistic update
    setState(() {
      _flows = [
        for (final f in _flows)
          if ((f['id'] as String?) == id)
            {...f, 'is_active': !isActive}
          else
            f,
      ];
    });
    try {
      await FlowsApi.updateFlow(dio: ref.read(apiClientProvider).dio, flowId: id, isActive: !isActive);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: const Color(0xFF059669),
        content: Text(
          !isActive ? 'Flujo activado' : 'Flujo desactivado',
          style: AppTextStyles.body.copyWith(color: Colors.white),
        ),
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      // Revert
      setState(() {
        _flows = [
          for (final f in _flows)
            if ((f['id'] as String?) == id)
              {...f, 'is_active': isActive}
            else
              f,
        ];
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.ctDanger,
        content: Text(
          _dioError(e),
          style: AppTextStyles.body.copyWith(color: Colors.white),
        ),
        duration: const Duration(seconds: 3),
      ));
    }
  }

  void _openForm({Map<String, dynamic>? flow}) {
    if (flow != null) return; // edit lives in FlowDetailPanel
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CreateFlowDialog(
        tenantId: ref.read(activeTenantIdProvider),
        workers: _workers,
        fixedWorkerId: widget.tenantWorkerId,
        onCreated: (newFlowId) {
          _fetchAll();
          widget.onFlowSelected?.call(newFlowId);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(activeTenantIdProvider, (prev, next) {
      if (next.isNotEmpty && next != prev) _fetchAll();
    });

    final canManage = hasPermission(ref, 'flows', 'manage');
    return Column(
      children: [
        _ActionBar(onNew: () => _openForm(), canManage: canManage),
        Expanded(child: _buildBody(canManage)),
      ],
    );
  }

  Widget _buildBody(bool canManage) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: AppTextStyles.body.copyWith(color: AppColors.ctDanger),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            AppButton(label: 'Reintentar', variant: AppButtonVariant.teal, size: AppButtonSize.sm, onPressed: _fetchAll),
          ],
        ),
      );
    }
    if (_flows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No hay flujos configurados aún',
              style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
            ),
            const SizedBox(height: 12),
            if (canManage) AppButton(label: '+ Crear primer flujo', variant: AppButtonVariant.teal, size: AppButtonSize.sm, onPressed: () => _openForm()),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: _flows.asMap().entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _FlowCard(
              flow: entry.value,
              index: entry.key,
              onToggle: () => _toggleActive(entry.value),
              onEdit: () {
                final id = entry.value['id'] as String? ?? '';
                if (id.isEmpty) return;
                if (widget.onFlowSelected != null) {
                  widget.onFlowSelected!(id);
                } else {
                  final wId = entry.value['tenant_worker_id'] as String? ?? '';
                  if (wId.isNotEmpty) {
                    context.go('/workers/$wId?selectedFlow=$id');
                  }
                }
              },
              canManage: canManage,
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Action bar ────────────────────────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.onNew, required this.canManage});
  final VoidCallback onNew;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return ScreenHeader(
      title: 'Flujos de trabajo',
      subtitle: 'Automatizaciones configuradas para tus operadores',
      actions: [
        if (canManage) AppButton(label: '+ Nuevo flujo', variant: AppButtonVariant.teal, size: AppButtonSize.sm, onPressed: onNew),
      ],
    );
  }
}

// ── Flow card ─────────────────────────────────────────────────────────────────

class _FlowCard extends StatefulWidget {
  const _FlowCard({
    required this.flow,
    required this.index,
    required this.onToggle,
    required this.onEdit,
    required this.canManage,
  });
  final Map<String, dynamic> flow;
  final int index;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final bool canManage;

  @override
  State<_FlowCard> createState() => _FlowCardState();
}

class _FlowCardState extends State<_FlowCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final f          = widget.flow;
    final name       = f['name'] as String? ?? '—';
    final desc       = f['description'] as String? ?? '';
    final isActive   = f['is_active'] as bool? ?? false;
    final rawFields  = f['fields'];
    final fields     = rawFields is List
        ? List<Map<String, dynamic>>.from(
            rawFields.whereType<Map>().map((e) => Map<String, dynamic>.from(e)))
        : <Map<String, dynamic>>[];

    // Worker info
    final activeExCount = f['active_executions_count'] as int? ?? 0;
    final workerName  = f['worker_name'] as String?;
    final workerColor = f['worker_color'] as String?;
    final workerType  = f['worker_type'] as String? ?? f['catalog_worker_type'] as String? ?? 'custom';
    final typeEntry   = _kTypeConfig[workerType] ?? _kTypeConfig['custom']!;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          // ── Header row ──
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Number circle
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: AppColors.ctTealLight,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${widget.index + 1}',
                    style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700, color: AppColors.ctTealDark),
                  ),
                ),
                const SizedBox(width: 14),

                // Name + description + chips
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: AppTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          desc,
                          style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (isQueryFlow(f))
                            _MetadataChip(label: 'Consulta')
                          else if (fields.isNotEmpty)
                            _MetadataChip(label: '${fields.length} campo${fields.length == 1 ? '' : 's'}'),
                          if (workerName != null)
                            _WorkerChip(
                              name: workerName,
                              color: workerColor,
                            ),
                          _TypeBadge(typeEntry: typeEntry),
                          if (activeExCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.ctWarnBg,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '$activeExCount activa${activeExCount == 1 ? '' : 's'}',
                                style: AppTextStyles.bodySmall.copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ctWarnText,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // Badge + switch + edit button
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.ctOkBg
                                : AppColors.ctSurface2,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isActive ? 'Activo' : 'Inactivo',
                            style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: isActive ? AppColors.ctOkText : AppColors.ctText2),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Transform.scale(
                          scale: 0.8,
                          child: Switch(
                            value: isActive,
                            onChanged: widget.canManage ? (_) => widget.onToggle() : null,
                            activeThumbColor: AppColors.ctTeal,
                            activeTrackColor:
                                AppColors.ctTeal.withValues(alpha: 0.3),
                            inactiveThumbColor: AppColors.ctBorder2,
                            inactiveTrackColor: AppColors.ctSurface2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (widget.canManage) _EditButton(onTap: widget.onEdit),
                  ],
                ),
              ],
            ),
          ),

          // ── Expand toggle ──
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.ctBorder)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: AppColors.ctText2,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isQueryFlow(f)
                        ? 'Flujo de consulta'
                        : _expanded
                            ? 'Ocultar campos'
                            : 'Ver campos ${fields.length}',
                    style: AppTextStyles.bodySmall.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),

          // ── Expandable fields table ──
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: _FieldsTable(fields: fields),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

// ── Fields table ──────────────────────────────────────────────────────────────

class _FieldsTable extends StatelessWidget {
  const _FieldsTable({required this.fields});
  final List<Map<String, dynamic>> fields;

  static TextStyle get _headerStyle => AppTextStyles.kpiLabel.copyWith(letterSpacing: 0.4);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.ctBg,
        border: Border(top: BorderSide(color: AppColors.ctBorder)),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(9),
          bottomRight: Radius.circular(9),
        ),
      ),
      child: fields.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Sin campos configurados',
                style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: Text('CAMPO', style: _headerStyle)),
                      Expanded(flex: 2, child: Text('TIPO', style: _headerStyle)),
                      Expanded(flex: 1, child: Text('REQUERIDO', style: _headerStyle)),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.ctBorder),
                ...fields.asMap().entries.map((entry) {
                  final isLast = entry.key == fields.length - 1;
                  return Column(
                    children: [
                      _FieldRow(field: entry.value),
                      if (!isLast)
                        const Divider(height: 1, color: AppColors.ctBorder),
                    ],
                  );
                }),
              ],
            ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.field});
  final Map<String, dynamic> field;

  @override
  Widget build(BuildContext context) {
    final label    = field['label'] as String? ?? field['name'] as String? ?? '—';
    final type     = field['type'] as String? ?? '—';
    final required = field['required'] as bool? ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.ctText),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.ctSurface2,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AppColors.ctBorder),
                ),
                child: Text(
                  type,
                  style: AppTextStyles.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  required
                      ? Icons.check_circle_rounded
                      : Icons.remove_circle_outline_rounded,
                  size: 13,
                  color: required ? AppColors.ctOk : AppColors.ctText3,
                ),
                const SizedBox(width: 4),
                Text(
                  required ? 'Sí' : 'No',
                  style: AppTextStyles.bodySmall.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: required ? AppColors.ctOkText : AppColors.ctText3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.ctSurface2,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodySmall,
      ),
    );
  }
}

class _WorkerChip extends StatelessWidget {
  const _WorkerChip({required this.name, this.color});
  final String name;
  final String? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.ctSurface2,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dm.hexColor(color),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            name,
            style: AppTextStyles.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.typeEntry});
  final ({String label, Color bg, Color fg}) typeEntry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: typeEntry.bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        typeEntry.label,
        style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: typeEntry.fg),
      ),
    );
  }
}

class _EditButton extends StatefulWidget {
  const _EditButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_EditButton> createState() => _EditButtonState();
}

class _EditButtonState extends State<_EditButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.ctInfo.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: _hovered
                  ? AppColors.ctInfo.withValues(alpha: 0.4)
                  : AppColors.ctBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.edit_outlined,
                size: 13,
                color: _hovered ? AppColors.ctInfo : AppColors.ctText2,
              ),
              const SizedBox(width: 5),
              Text(
                'Editar',
                style: AppTextStyles.bodySmall.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: _hovered ? AppColors.ctInfo : AppColors.ctText2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


