import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/ai_workers_api.dart';
import '../../core/api/flows_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/screen_header.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _kTypeConfig = {
  'logistics':   (label: 'Logística', bg: Color(0xFFDBEAFE), fg: Color(0xFF1E40AF)),
  'sales':       (label: 'Ventas',    bg: Color(0xFFEDE9FE), fg: Color(0xFF6D28D9)),
  'collections': (label: 'Cobranza', bg: Color(0xFFFEF3C7), fg: Color(0xFFB45309)),
  'custom':      (label: 'Custom',   bg: Color(0xFFF3F4F6), fg: Color(0xFF374151)),
};

// ── Helpers ───────────────────────────────────────────────────────────────────

Color _hexColor(String? hex) {
  if (hex == null) return const Color(0xFF9CA3AF);
  try {
    final h = hex.replaceAll('#', '');
    if (h.length != 6) return const Color(0xFF9CA3AF);
    return Color(int.parse('FF$h', radix: 16));
  } catch (_) {
    return const Color(0xFF9CA3AF);
  }
}

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
  const WorkflowsScreen({super.key, this.tenantWorkerId});
  final String? tenantWorkerId;

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
    showDialog(
      context: context,
      builder: (_) => _FlowFormDialog(
        flow: flow,
        workers: _workers,
        onSaved: _fetchAll,
        preselectedWorkerId: widget.tenantWorkerId,
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
              onEdit: () => context.go('/flows/${entry.value['id']}'),
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

// ── Flow form dialog ──────────────────────────────────────────────────────────

class _FlowFormDialog extends StatefulWidget {
  const _FlowFormDialog({
    required this.workers,
    required this.onSaved,
    this.flow,
    this.preselectedWorkerId,
  });
  final Map<String, dynamic>? flow;
  final List<Map<String, dynamic>> workers;
  final Future<void> Function() onSaved;
  final String? preselectedWorkerId;

  @override
  State<_FlowFormDialog> createState() => _FlowFormDialogState();
}

class _FlowFormDialogState extends State<_FlowFormDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _selectedWorkerId;
  bool _saving = false;
  String? _slugError;

  bool get _isEdit => widget.flow != null;

  String get _slug => _slugify(_nameCtrl.text.trim());
  bool get _slugValid => _isEdit || _slug.length >= 3;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _nameCtrl.text = widget.flow!['name'] as String? ?? '';
      _descCtrl.text = widget.flow!['description'] as String? ?? '';
    }
    if (widget.preselectedWorkerId != null) {
      _selectedWorkerId = widget.preselectedWorkerId;
    } else if (widget.workers.isNotEmpty) {
      _selectedWorkerId = widget.workers.first['id'] as String?;
    }
    _nameCtrl.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    if (!_isEdit && _slugError != null) {
      setState(() => _slugError = null);
    } else if (!_isEdit) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_onNameChanged);
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);
    try {
      final desc = _descCtrl.text.trim();
      if (_isEdit) {
        await FlowsApi.updateFlow(
          flowId: widget.flow!['id'] as String,
          name: name,
          description: desc.isNotEmpty ? desc : null,
        );
      } else {
        if (_selectedWorkerId == null) return;
        await FlowsApi.createFlow(
          tenantWorkerId: _selectedWorkerId!,
          name: name,
          slug: _slug,
          description: desc.isNotEmpty ? desc : null,
        );
      }
      await widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      final isDio = e is DioException;
      final is409 = isDio && e.response?.statusCode == 409;
      if (is409) {
        setState(() {
          _saving = false;
          _slugError = 'Ya existe un flujo con este nombre';
        });
      } else {
        setState(() => _saving = false);
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
  }

  @override
  Widget build(BuildContext context) {
    final editWorkerName = _isEdit
        ? (widget.flow!['worker_name'] as String? ??
            widget.flow!['display_name'] as String?)
        : null;

    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.ctBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEdit ? 'Editar flujo' : 'Nuevo flujo',
                style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist'),
              ),
              const SizedBox(height: 20),

              // Nombre
              _DialogField(
                label: 'Nombre del flujo',
                controller: _nameCtrl,
                placeholder: 'Ej: Flujo 4 · Entregas',
              ),
              if (!_isEdit && _nameCtrl.text.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                _SlugPreview(slug: _slug, error: _slugError),
              ],
              const SizedBox(height: 14),

              // Worker
              Text(
                'Worker',
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 6),
              if (_isEdit)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.ctSurface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.ctBorder2),
                  ),
                  child: Text(
                    editWorkerName ?? '—',
                    style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                  ),
                )
              else if (widget.workers.isEmpty)
                Text(
                  'No hay workers disponibles',
                  style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.ctSurface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.ctBorder2),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedWorkerId,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    dropdownColor: AppColors.ctSurface,
                    items: widget.workers.map((w) {
                      final wName  = w['display_name'] as String? ??
                          w['catalog_name'] as String? ?? '—';
                      final wColor = w['catalog_color'] as String?;
                      return DropdownMenuItem<String>(
                        value: w['id'] as String?,
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _hexColor(wColor),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              wName,
                              style: AppTextStyles.body,
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _selectedWorkerId = v),
                  ),
                ),
              const SizedBox(height: 14),

              // Descripción
              _DialogField(
                label: 'Descripción',
                controller: _descCtrl,
                placeholder: 'Describe el propósito de este flujo...',
                maxLines: 3,
              ),
              const SizedBox(height: 24),

              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancelar',
                    variant: AppButtonVariant.outline,
                    size: AppButtonSize.sm,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  AppButton(
                    label: 'Guardar',
                    variant: AppButtonVariant.teal,
                    size: AppButtonSize.sm,
                    isLoading: _saving,
                    isDisabled: !_slugValid,
                    onPressed: _submit,
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
              color: _hexColor(color),
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

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.label,
    required this.controller,
    required this.placeholder,
    this.maxLines = 1,
  });
  final String label;
  final TextEditingController controller;
  final String placeholder;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          minLines: maxLines,
          style: AppTextStyles.body,
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
            filled: true,
            fillColor: AppColors.ctSurface2,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.ctBorder2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.ctBorder2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.ctTeal),
            ),
          ),
        ),
      ],
    );
  }
}

class _SlugPreview extends StatelessWidget {
  const _SlugPreview({required this.slug, this.error});
  final String slug;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final isValid = error == null && slug.length >= 3;
    if (error != null) {
      return Row(
        children: [
          const Icon(Icons.error_outline, size: 13, color: AppColors.ctDanger),
          const SizedBox(width: 4),
          Text(
            error!,
            style: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: AppColors.ctDanger),
          ),
        ],
      );
    }
    return Row(
      children: [
        Icon(
          isValid ? Icons.check_circle_outline : Icons.warning_amber_outlined,
          size: 13,
          color: isValid ? AppColors.ctOk : AppColors.ctDanger,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            isValid ? slug : (slug.isEmpty ? 'Nombre inválido' : 'Nombre inválido (slug: "$slug")'),
            style: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: isValid ? AppColors.ctOk : AppColors.ctDanger, fontFeatures: const [FontFeature.tabularFigures()]),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

