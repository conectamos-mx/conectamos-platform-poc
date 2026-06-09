import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/ai_workers_api.dart';
import '../../core/api/flows_api.dart';
import '../../core/api/operator_roles_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/display_mappers.dart' as dm;
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_detail_row.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_wizard_shell.dart';
import '../../shared/widgets/screen_header.dart';

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

const _kAccentMap = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
  'æ': 'ae', 'ç': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ð': 'd', 'ñ': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ý': 'y', 'ÿ': 'y', 'þ': 'th', 'ß': 'ss',
};

String _slugify(String input) {
  final lower = input.toLowerCase();
  final buf = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    buf.write(_kAccentMap[ch] ?? ch);
  }
  return buf
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
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
      final results = await Future.wait([
        widget.tenantWorkerId != null
            ? FlowsApi.getFlowsByWorker(tenantWorkerId: widget.tenantWorkerId!)
            : FlowsApi.listFlows(),
        AiWorkersApi.listWorkers(),
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
      await FlowsApi.updateFlow(flowId: id, isActive: !isActive);
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
      builder: (_) => _NewFlowDialog(
        tenantId: ref.read(activeTenantIdProvider),
        workers: _workers,
        preselectedWorkerId: widget.tenantWorkerId,
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
                          if (fields.isNotEmpty)
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
                    _expanded
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

// ── New flow wizard ──────────────────────────────────────────────────────────

class _NewFlowDialog extends StatefulWidget {
  const _NewFlowDialog({
    required this.tenantId,
    required this.workers,
    required this.onCreated,
    this.preselectedWorkerId,
  });
  final String tenantId;
  final List<Map<String, dynamic>> workers;
  final String? preselectedWorkerId;
  final void Function(String flowId) onCreated;

  @override
  State<_NewFlowDialog> createState() => _NewFlowDialogState();
}

class _NewFlowDialogState extends State<_NewFlowDialog> {
  // Step 1 — Identidad
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _selectedWorkerId;
  String? _slugError;

  // Step 2 — Acceso
  List<Map<String, dynamic>> _availableRoles = [];
  final List<String> _selectedRoleIds = [];
  final List<String> _selectedTriggers = [];
  bool _loadingRoles = false;

  static const _triggerOptions = [
    ('conversational', 'Conversacional', 'El operador inicia el flujo por chat'),
    ('ingest',         'API / Ingesta',  'Se activa por carga de datos externa'),
    ('scheduled',      'Programado',     'Se ejecuta en horario autom\u00E1tico'),
    ('on_complete',    'Al completar otro flujo', 'Se abre como acci\u00F3n de cierre'),
  ];

  String get _slug => _slugify(_nameCtrl.text.trim());
  bool get _slugValid => _slug.length >= 3;
  bool get _canAdvance =>
      _nameCtrl.text.trim().isNotEmpty && _slugValid && _selectedWorkerId != null;

  @override
  void initState() {
    super.initState();
    if (widget.preselectedWorkerId != null) {
      _selectedWorkerId = widget.preselectedWorkerId;
    } else if (widget.workers.isNotEmpty) {
      _selectedWorkerId = widget.workers.first['id'] as String?;
    }
    _nameCtrl.addListener(_onNameChanged);
    _loadRoles();
  }

  void _onNameChanged() {
    if (_slugError != null) {
      setState(() => _slugError = null);
    } else {
      setState(() {});
    }
  }

  Future<void> _loadRoles() async {
    setState(() => _loadingRoles = true);
    try {
      final roles = await OperatorRolesApi.listRoles(tenantId: widget.tenantId);
      if (mounted) {
        setState(() => _availableRoles = List<Map<String, dynamic>>.from(roles));
      }
    } catch (_) {}
    finally {
      if (mounted) setState(() => _loadingRoles = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_onNameChanged);
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String _workerName(String? id) {
    if (id == null) return '\u2014';
    final w = widget.workers.where((w) => w['id'] == id).firstOrNull;
    return w?['display_name'] as String? ?? w?['catalog_name'] as String? ?? '\u2014';
  }

  Future<void> _submit() async {
    if (_selectedWorkerId == null) return;
    try {
      final result = await FlowsApi.createFlow(
        tenantWorkerId: _selectedWorkerId!,
        name: _nameCtrl.text.trim(),
        slug: _slug,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        allowedRoleIds: _selectedRoleIds.isEmpty ? null : _selectedRoleIds,
        triggerSources: _selectedTriggers.isEmpty ? null : _selectedTriggers,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onCreated(result['id'] as String);
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 409) {
        setState(() => _slugError = 'Ya existe un flujo con este nombre');
        rethrow;
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppWizardShell(
      sidebarTitle: 'Nuevo flujo',
      confirmLabel: 'Crear flujo',
      canAdvance: _canAdvance,
      onCancel: () => Navigator.of(context).pop(),
      onConfirm: _submit,
      steps: [
        AppWizardStep(title: 'Identidad', builder: (_) => _buildStep1()),
        AppWizardStep(title: 'Acceso', builder: (_) => _buildStep2()),
        AppWizardStep(title: 'Confirmar', builder: (_) => _buildStep3()),
      ],
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: _nameCtrl,
          label: 'Nombre del flujo',
          hint: 'Ej: Entrega de paquete',
        ),
        if (_nameCtrl.text.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          _SlugIndicator(slug: _slug, error: _slugError),
        ],
        const SizedBox(height: 16),
        AppTextField(
          controller: _descCtrl,
          label: 'Descripci\u00F3n (opcional)',
          hint: 'Describe el prop\u00F3sito de este flujo...',
          maxLines: 3,
        ),
        if (widget.preselectedWorkerId == null && widget.workers.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Worker',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          ...widget.workers.map((w) {
            final id = w['id'] as String? ?? '';
            final name = w['display_name'] as String? ??
                w['catalog_name'] as String? ?? '\u2014';
            final color = w['catalog_color'] as String?;
            final selected = _selectedWorkerId == id;
            return GestureDetector(
              onTap: () => setState(() => _selectedWorkerId = id),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.ctTeal.withValues(alpha: 0.08)
                        : AppColors.ctSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? AppColors.ctTeal : AppColors.ctBorder,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: dm.hexColor(color),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(name,
                            style: AppTextStyles.body.copyWith(
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                            )),
                      ),
                      if (selected)
                        const Icon(Icons.check_rounded,
                            size: 16, color: AppColors.ctTeal),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Roles con acceso',
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Selecciona qu\u00E9 roles pueden iniciar este flujo. Si no seleccionas ninguno, todos los roles tendr\u00E1n acceso.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2)),
        const SizedBox(height: 12),
        if (_loadingRoles)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ctTeal),
            )),
          )
        else if (_availableRoles.isEmpty)
          Text('No hay roles disponibles. Podr\u00E1s asignarlos despu\u00E9s.',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _availableRoles.map((role) {
              final id = role['id'] as String? ?? '';
              final name = role['label'] as String? ?? role['name'] as String? ?? id;
              final selected = _selectedRoleIds.contains(id);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (selected) {
                      _selectedRoleIds.remove(id);
                    } else {
                      _selectedRoleIds.add(id);
                    }
                  });
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.ctTeal.withValues(alpha: 0.1)
                          : AppColors.ctSurface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected ? AppColors.ctTeal : AppColors.ctBorder,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (selected) ...[
                          const Icon(Icons.check_rounded, size: 14, color: AppColors.ctTeal),
                          const SizedBox(width: 4),
                        ],
                        Text(name,
                            style: AppTextStyles.body.copyWith(
                              fontSize: 12,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                              color: selected ? AppColors.ctTealDark : AppColors.ctText2,
                            )),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        const SizedBox(height: 24),
        Text('Or\u00EDgenes de ejecuci\u00F3n',
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('\u00BFDesde d\u00F3nde puede iniciarse este flujo?',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2)),
        const SizedBox(height: 12),
        ..._triggerOptions.map((opt) {
          final selected = _selectedTriggers.contains(opt.$1);
          return GestureDetector(
            onTap: () {
              setState(() {
                if (selected) {
                  _selectedTriggers.remove(opt.$1);
                } else {
                  _selectedTriggers.add(opt.$1);
                }
              });
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.ctTeal.withValues(alpha: 0.06)
                      : AppColors.ctSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? AppColors.ctTeal : AppColors.ctBorder,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: selected ? AppColors.ctTeal : AppColors.ctBorder2,
                          width: selected ? 2 : 1.5,
                        ),
                        color: selected ? AppColors.ctTeal : Colors.transparent,
                      ),
                      child: selected
                          ? const Icon(Icons.check, size: 12, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(opt.$2, style: AppTextStyles.body.copyWith(
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
                          Text(opt.$3, style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.ctText3)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStep3() {
    final roleNames = _availableRoles
        .where((r) => _selectedRoleIds.contains(r['id'] as String))
        .map((r) => r['label'] as String? ?? r['name'] as String? ?? '')
        .join(', ');
    final triggerLabels = _triggerOptions
        .where((t) => _selectedTriggers.contains(t.$1))
        .map((t) => t.$2)
        .join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Revisa la configuraci\u00F3n antes de crear el flujo.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2)),
        const SizedBox(height: 16),
        AppDetailRow(
          label: 'Nombre',
          value: Text(_nameCtrl.text.trim(), style: AppTextStyles.body),
        ),
        const Divider(height: 1),
        AppDetailRow(
          label: 'Slug',
          value: Text(_slug, style: AppTextStyles.body.copyWith(
              fontFamily: 'Geist', color: AppColors.ctText2)),
        ),
        const Divider(height: 1),
        AppDetailRow(
          label: 'Worker',
          value: Text(_workerName(_selectedWorkerId), style: AppTextStyles.body),
        ),
        if (_descCtrl.text.trim().isNotEmpty) ...[
          const Divider(height: 1),
          AppDetailRow(
            label: 'Descripci\u00F3n',
            crossAxisAlignment: CrossAxisAlignment.start,
            value: Text(_descCtrl.text.trim(), style: AppTextStyles.bodySmall),
          ),
        ],
        const Divider(height: 1),
        AppDetailRow(
          label: 'Roles',
          value: Text(
            roleNames.isEmpty ? 'Todos los roles' : roleNames,
            style: AppTextStyles.body,
          ),
        ),
        const Divider(height: 1),
        AppDetailRow(
          label: 'Or\u00EDgenes',
          value: Text(
            triggerLabels.isEmpty ? 'Sin or\u00EDgenes seleccionados' : triggerLabels,
            style: AppTextStyles.body,
          ),
        ),
      ],
    );
  }
}

class _SlugIndicator extends StatelessWidget {
  const _SlugIndicator({required this.slug, this.error});
  final String slug;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Row(
        children: [
          const Icon(Icons.error_outline, size: 13, color: AppColors.ctDanger),
          const SizedBox(width: 4),
          Text(error!,
              style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 12, color: AppColors.ctDanger)),
        ],
      );
    }
    final valid = slug.length >= 3;
    return Row(
      children: [
        Icon(
          valid ? Icons.check_circle_outline : Icons.warning_amber_outlined,
          size: 13,
          color: valid ? AppColors.ctOk : AppColors.ctText3,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            valid ? slug : (slug.isEmpty ? 'Escribe un nombre' : 'Nombre muy corto'),
            style: AppTextStyles.bodySmall.copyWith(
                fontSize: 12,
                color: valid ? AppColors.ctOk : AppColors.ctText3),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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


