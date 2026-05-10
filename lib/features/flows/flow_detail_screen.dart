import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/flows_api.dart';
import '../../core/api/operator_roles_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

const _kFieldAccentMap = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
  'æ': 'ae', 'ç': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ð': 'd', 'ñ': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ý': 'y', 'ÿ': 'y', 'þ': 'th', 'ß': 'ss',
};

String _fieldKeyify(String input) {
  final lower = input.toLowerCase();
  final buf = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    buf.write(_kFieldAccentMap[ch] ?? ch);
  }
  final key = buf
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return key.length > 63 ? key.substring(0, 63) : key;
}

String _slugify(String input) {
  final lower = input.toLowerCase();
  final buf = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    buf.write(_kFieldAccentMap[ch] ?? ch);
  }
  return buf
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

Color _hexColor(String? hex) {
  try {
    final h = (hex ?? '#9CA3AF').replaceAll('#', '');
    if (h.length != 6) return AppColors.ctText3;
    return Color(int.parse('FF$h', radix: 16));
  } catch (_) {
    return AppColors.ctText3;
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

IconData _fieldIcon(String? type) {
  switch (type) {
    case 'number':
      return Icons.pin_outlined;
    case 'date':
      return Icons.calendar_today_outlined;
    case 'boolean':
      return Icons.toggle_on_outlined;
    case 'select':
      return Icons.list_outlined;
    case 'photo':
      return Icons.photo_camera_outlined;
    case 'location':
      return Icons.location_on_outlined;
    default:
      return Icons.short_text;
  }
}

const _kFieldTypes = [
  ('text', 'Texto'),
  ('number', 'Número'),
  ('date', 'Fecha'),
  ('boolean', 'Sí / No'),
  ('select', 'Selección'),
  ('photo', 'Foto'),
  ('location', 'Ubicación'),
];

const _kTriggerSources = [
  ('conversational', 'Conversacional'),
  ('api', 'API / Sistema'),
  ('dashboard', 'Dashboard'),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class FlowDetailScreen extends ConsumerStatefulWidget {
  const FlowDetailScreen({super.key, required this.flowId});
  final String flowId;

  @override
  ConsumerState<FlowDetailScreen> createState() => _FlowDetailScreenState();
}

class _FlowDetailScreenState extends ConsumerState<FlowDetailScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _flow;
  bool _loading = true;
  String? _error;
  bool _saving = false;

  late TabController _tabCtrl;

  // Info tab controllers — initialized in _load()
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String get _derivedSlug => _slugify(_nameCtrl.text.trim());
  List<String> _triggerSources = [];

  // Campos tab state
  List<Map<String, dynamic>> _fields = [];

  // Comportamiento tab state
  List<Map<String, dynamic>> _conditions = [];
  bool _sendProactive = true;

  // Al cerrar tab state
  List<Map<String, dynamic>> _actions = [];

  // Prerequisito
  String? _prerequisiteFlowSlug;
  List<Map<String, dynamic>> _workerFlows = [];

  // Roles autorizados
  List<String> _allowedRoleIds = [];
  List<Map<String, dynamic>> _availableRoles = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading && _flow != null) return;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tenantId = ref.read(activeTenantIdProvider);
      final results = await Future.wait([
        FlowsApi.getFlow(flowId: widget.flowId),
        OperatorRolesApi.listRoles(tenantId: tenantId),
      ]);
      if (!mounted) return;
      final flow = results[0] as Map<String, dynamic>;
      final roles = List<Map<String, dynamic>>.from(
          (results[1] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e)));
      final rawFields = flow['fields'];
      final fields = rawFields is List
          ? List<Map<String, dynamic>>.from(
              rawFields.whereType<Map>().map((e) => Map<String, dynamic>.from(e)))
          : <Map<String, dynamic>>[];
      final rawSources = flow['trigger_sources'];
      final sources = rawSources is List
          ? List<String>.from(rawSources.map((s) => s.toString()))
          : <String>[];

      final rawBehavior = (flow['behavior'] as Map<String, dynamic>?) ?? {};
      final conditions = List<Map<String, dynamic>>.from(
          (rawBehavior['conditions'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e)));
      final rawOnComplete =
          (flow['on_complete'] as Map<String, dynamic>?) ?? {};
      final actions = List<Map<String, dynamic>>.from(
          (rawOnComplete['actions'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e)));

      setState(() {
        _flow = flow;
        _fields = fields;
        _triggerSources = sources;
        _conditions = conditions;
        _actions = actions;
        _sendProactive = (flow['send_proactive'] as bool?) ?? true;
        _prerequisiteFlowSlug = flow['prerequisite_flow_slug'] as String?;
        _allowedRoleIds = List<String>.from(
            (flow['allowed_role_ids'] as List? ?? []).map((e) => e.toString()));
        _availableRoles = roles;
        _nameCtrl.text = flow['name'] as String? ?? '';
        _descCtrl.text = flow['description'] as String? ?? '';
        _loading = false;
      });
      _loadWorkerFlows(flow['tenant_worker_id'] as String? ?? '');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _dioError(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadWorkerFlows(String tenantWorkerId) async {
    if (tenantWorkerId.isEmpty) return;
    try {
      final flows = await FlowsApi.getFlowsByWorker(
        tenantWorkerId: tenantWorkerId,
      );
      if (!mounted) return;
      setState(() {
        // Exclude the current flow — cannot be its own prerequisite
        _workerFlows = flows
            .where((f) => (f['id'] as String?) != widget.flowId)
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _save({bool silent = false}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final updated = await FlowsApi.updateFlow(
        flowId: widget.flowId,
        name: _nameCtrl.text.trim(),
        slug: _derivedSlug,
        description: _descCtrl.text.trim(),
        fields: _fields,
        behavior: {'conditions': _conditions},
        onComplete: {'actions': _actions},
        triggerSources: _triggerSources,
        sendProactive: _sendProactive,
        prerequisiteFlowSlug: _prerequisiteFlowSlug,
        clearPrerequisite: _prerequisiteFlowSlug == null,
        allowedRoleIds: _allowedRoleIds,
      );
      if (!mounted) return;
      final rawFields = updated['fields'];
      final fields = rawFields is List
          ? List<Map<String, dynamic>>.from(
              rawFields.whereType<Map>().map((e) => Map<String, dynamic>.from(e)))
          : _fields;
      final rawBeh = (updated['behavior'] as Map<String, dynamic>?) ?? {};
      final updatedConditions = List<Map<String, dynamic>>.from(
          (rawBeh['conditions'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e)));
      final rawOC = (updated['on_complete'] as Map<String, dynamic>?) ?? {};
      final updatedActions = List<Map<String, dynamic>>.from(
          (rawOC['actions'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e)));
      setState(() {
        _flow = updated;
        _fields = fields;
        _conditions = updatedConditions;
        _actions = updatedActions;
        _saving = false;
      });
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Flujo guardado'),
          backgroundColor: AppColors.ctOk,
          duration: Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_dioError(e)),
        backgroundColor: AppColors.ctDanger,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _fields.removeAt(oldIndex);
      _fields.insert(newIndex, item);
    });
  }

  void _confirmDeleteField(Map<String, dynamic> field, int index) {
    final label = field['label'] as String? ?? field['key'] as String? ?? 'este campo';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.ctSurface,
        title: const Text(
          'Eliminar campo',
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.ctText,
          ),
        ),
        content: Text(
          '¿Eliminar el campo "$label"? Esta acción no se puede deshacer.',
          style: const TextStyle(
            fontFamily: 'Geist',
            fontSize: 13,
            color: AppColors.ctText2,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _fields.removeAt(index));
              _save(silent: true);
            },
            child: const Text(
              'Eliminar',
              style: TextStyle(color: AppColors.ctDanger),
            ),
          ),
        ],
      ),
    );
  }

  void _openFieldDialog({Map<String, dynamic>? field, int? index}) {
    showDialog(
      context: context,
      builder: (_) => _FieldDialog(
        field: field,
        tenantId: ref.read(activeTenantIdProvider),
        tenantWorkerId: _flow?['tenant_worker_id'] as String? ?? '',
        onSaved: (updated) {
          setState(() {
            if (index != null) {
              _fields[index] = updated;
            } else {
              _fields.add(updated);
            }
          });
          _save(silent: true);
        },
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final name = _flow?['name'] as String? ?? 'este flujo';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Eliminar flujo',
          style: TextStyle(
            fontFamily: 'Geist',
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: AppColors.ctText,
          ),
        ),
        content: Text(
          '¿Eliminar "$name"? Esta acción desactivará el flujo. Las ejecuciones existentes no se verán afectadas.',
          style: const TextStyle(
            fontFamily: 'Geist',
            fontSize: 13,
            color: AppColors.ctText2,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: Color(0xFFE24C4B)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await FlowsApi.deleteFlow(flowId: widget.flowId);
      if (!mounted) return;
      context.go('/flows');
    } catch (e) {
      if (!mounted) return;
      final isDioException = e is DioException;
      final status = isDioException ? e.response?.statusCode : null;
      final msg = status == 409
          ? 'Este flujo tiene ejecuciones activas y no puede eliminarse'
          : _dioError(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.ctDanger,
      ));
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    debugPrint('FLOW_DETAIL BUILD: loading=$_loading error=$_error flow=${_flow?['name']}');
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.ctBg,
        appBar: _buildAppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _flow == null) {
      return Scaffold(
        backgroundColor: AppColors.ctBg,
        appBar: _buildAppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: AppColors.ctDanger),
              const SizedBox(height: 12),
              Text(
                _error ?? 'No se encontró el flujo',
                style: const TextStyle(
                    fontFamily: 'Geist', color: AppColors.ctText2),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton(onPressed: _load, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }

    final canManage = hasPermission(ref, 'flows', 'manage');

    return Scaffold(
      backgroundColor: AppColors.ctBg,
      appBar: _buildAppBar(),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _InfoTab(
            flow: _flow!,
            nameCtrl: _nameCtrl,
            descCtrl: _descCtrl,
            canManage: canManage,
            triggerSources: _triggerSources,
            onTriggerToggle: (source) {
              setState(() {
                if (_triggerSources.contains(source)) {
                  if (_triggerSources.length > 1) {
                    _triggerSources.remove(source);
                  }
                } else {
                  _triggerSources.add(source);
                }
              });
            },
            onDelete: _confirmDelete,
            workerFlows: _workerFlows,
            prerequisiteFlowSlug: _prerequisiteFlowSlug,
            onPrerequisiteChanged: (slug) {
              setState(() => _prerequisiteFlowSlug = slug);
              _save(silent: true);
            },
          ),
          _CamposTab(
            fields: _fields,
            canManage: canManage,
            onReorder: _onReorder,
            onEditField: (field, index) =>
                _openFieldDialog(field: field, index: index),
            onDeleteField: (field, index) =>
                _confirmDeleteField(field, index),
            onAddField: () => _openFieldDialog(),
          ),
          _ComportamientoTab(
            conditions: _conditions,
            flowFields: _fields,
            canManage: canManage,
            triggerSources: _triggerSources,
            flowId: widget.flowId,
            tenantId: ref.read(activeTenantIdProvider),
            sendProactive: _sendProactive,
            availableRoles: _availableRoles,
            allowedRoleIds: _allowedRoleIds,
            onChanged: (updated) {
              setState(() => _conditions = updated);
              _save(silent: true);
            },
            onAllowedRoleIdsChanged: (updated) {
              setState(() => _allowedRoleIds = updated);
              _save(silent: true);
            },
          ),
          _AlCerrarTab(
            actions: _actions,
            canManage: canManage,
            tenantId: ref.read(activeTenantIdProvider),
            tenantWorkerId: _flow?['tenant_worker_id'] as String? ?? '',
            currentFlowSlug: _flow?['slug'] as String? ?? '',
            flowFields: _fields,
            onChanged: (updated) {
              setState(() => _actions = updated);
              _save(silent: true);
            },
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final name = _flow?['name'] as String? ?? 'Flujo';
    return AppBar(
      backgroundColor: AppColors.ctNavy,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => context.go('/flows'),
      ),
      title: Text(
        name,
        style: AppFonts.onest(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      actions: [
        if (_flow != null)
          IconButton(
            icon: const Icon(Icons.electrical_services_outlined, color: Colors.white70),
            tooltip: 'Integraciones',
            onPressed: () {
              final name = _flow!['name'] as String? ?? 'Flujo';
              context.go('/flows/${widget.flowId}/integrations?flowName=${Uri.encodeComponent(name)}');
            },
          ),
        if (_saving)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          )
        else
          TextButton(
            onPressed: _loading ? null : _save,
            child: const Text(
              'Guardar',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.ctTeal,
              ),
            ),
          ),
      ],
      bottom: TabBar(
        controller: _tabCtrl,
        labelColor: AppColors.ctTeal,
        unselectedLabelColor: Colors.white60,
        indicatorColor: AppColors.ctTeal,
        labelStyle: const TextStyle(
            fontFamily: 'Geist', fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            const TextStyle(fontFamily: 'Geist', fontSize: 12),
        tabs: const [
          Tab(text: 'INFO'),
          Tab(text: 'CAMPOS'),
          Tab(text: 'COMPORTAMIENTO'),
          Tab(text: 'AL CERRAR'),
        ],
      ),
    );
  }
}

// ── _InfoTab ──────────────────────────────────────────────────────────────────

class _InfoTab extends StatefulWidget {
  const _InfoTab({
    required this.flow,
    required this.nameCtrl,
    required this.descCtrl,
    required this.canManage,
    required this.triggerSources,
    required this.onTriggerToggle,
    required this.onDelete,
    required this.workerFlows,
    required this.prerequisiteFlowSlug,
    required this.onPrerequisiteChanged,
  });

  final Map<String, dynamic> flow;
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final bool canManage;
  final List<String> triggerSources;
  final void Function(String source) onTriggerToggle;
  final VoidCallback onDelete;
  final List<Map<String, dynamic>> workerFlows;
  final String? prerequisiteFlowSlug;
  final void Function(String?) onPrerequisiteChanged;

  @override
  State<_InfoTab> createState() => _InfoTabState();
}

class _InfoTabState extends State<_InfoTab> {
  @override
  void initState() {
    super.initState();
    widget.nameCtrl.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    widget.nameCtrl.removeListener(_onNameChanged);
    super.dispose();
  }

  void _onNameChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final workerName = widget.flow['worker_name'] as String?;
    final workerColor = widget.flow['worker_color'] as String?;
    final slug = _slugify(widget.nameCtrl.text.trim());
    final slugValid = slug.length >= 2;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nombre
          _FormField(
            label: 'Nombre',
            controller: widget.nameCtrl,
            placeholder: 'Ej: Flujo de entregas',
          ),
          const SizedBox(height: 16),

          // Slug (read-only, derivado del nombre)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Slug',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ctText,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.ctSurface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.ctBorder),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        slug.isEmpty ? '—' : slug,
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 13,
                          color: slug.isEmpty ? AppColors.ctText2 : AppColors.ctText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      slugValid ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                      size: 16,
                      color: slugValid
                          ? const Color(0xFF107C41)
                          : const Color(0xFFE24C4B),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Identificador único. Derivado del nombre. Se usa en API e integraciones.',
                style: AppTextStyles.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Descripción
          _FormField(
            label: 'Descripción',
            controller: widget.descCtrl,
            placeholder: 'Describe el propósito de este flujo...',
            maxLines: 3,
          ),
          const SizedBox(height: 16),

          // Worker (read-only)
          if (workerName != null) ...[
            const Text(
              'Worker asignado',
              style: AppTextStyles.btnSecondary,
            ),
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.ctSurface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.ctBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _hexColor(workerColor),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    workerName,
                    style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Trigger sources
          const Text(
            '¿Desde dónde se puede iniciar este flujo?',
            style: AppTextStyles.btnSecondary,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kTriggerSources.map((entry) {
              final (value, label) = entry;
              final selected = widget.triggerSources.contains(value);
              return FilterChip(
                label: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: selected
                        ? AppColors.ctTealDark
                        : AppColors.ctText2,
                  ),
                ),
                selected: selected,
                onSelected: (_) => widget.onTriggerToggle(value),
                selectedColor: AppColors.ctTealLight,
                backgroundColor: AppColors.ctSurface2,
                checkmarkColor: AppColors.ctTealDark,
                side: BorderSide(
                  color: selected
                      ? AppColors.ctTeal
                      : AppColors.ctBorder,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Flow prerequisito
          if (widget.workerFlows.isNotEmpty) ...[
            const Text(
              'Flow prerequisito',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.ctText,
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String?>(
              initialValue: widget.prerequisiteFlowSlug,
              decoration: InputDecoration(
                filled: true,
                fillColor: widget.canManage
                    ? AppColors.ctSurface
                    : AppColors.ctSurface2,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.ctBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.ctBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: AppColors.ctTeal, width: 1.5),
                ),
              ),
              style: const TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                color: AppColors.ctText,
              ),
              dropdownColor: AppColors.ctSurface,
              onChanged: widget.canManage
                  ? (v) => widget.onPrerequisiteChanged(v)
                  : null,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'Sin prerequisito',
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 13,
                      color: AppColors.ctText3,
                    ),
                  ),
                ),
                for (final f in widget.workerFlows)
                  DropdownMenuItem<String?>(
                    value: f['slug'] as String?,
                    child: Text(
                      f['name'] as String? ?? f['slug'] as String? ?? '—',
                      style: const TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 13,
                        color: AppColors.ctText,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'El flow que debe completarse antes de iniciar este.',
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: 24),
          ],

          if (widget.canManage) ...[
            const Divider(color: AppColors.ctBorder),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: widget.onDelete,
              icon: const Icon(Icons.delete_outline,
                  size: 16, color: Color(0xFFE24C4B)),
              label: const Text(
                'Eliminar flujo',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFE24C4B),
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFE24C4B)),
                backgroundColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

// ── _CamposTab ────────────────────────────────────────────────────────────────

class _CamposTab extends StatelessWidget {
  const _CamposTab({
    required this.fields,
    required this.canManage,
    required this.onReorder,
    required this.onEditField,
    required this.onDeleteField,
    required this.onAddField,
  });

  final List<Map<String, dynamic>> fields;
  final bool canManage;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(Map<String, dynamic> field, int index) onEditField;
  final void Function(Map<String, dynamic> field, int index) onDeleteField;
  final VoidCallback onAddField;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // Header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Row(
              children: [
                Text(
                  'Campos del flujo (${fields.length})',
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ctText,
                  ),
                ),
                const Spacer(),
                if (canManage)
                  TextButton.icon(
                    onPressed: onAddField,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text(
                      '+ Agregar campo',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.ctTeal,
                    ),
                  ),
              ],
            ),
          ),
        ),

        if (fields.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'Sin campos configurados',
                  style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            sliver: SliverReorderableList(
              itemCount: fields.length,
              onReorder: canManage ? onReorder : (int a, int b) {},
              itemBuilder: (context, i) {
                final field = fields[i];
                final id = field['id']?.toString() ?? i.toString();
                return _FieldRow(
                  key: ValueKey(id),
                  field: field,
                  index: i,
                  canManage: canManage,
                  isLast: i == fields.length - 1,
                  onEdit: () => onEditField(field, i),
                  onDelete: () => onDeleteField(field, i),
                );
              },
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 20)),
      ],
    );
  }
}

// ── _FieldRow ─────────────────────────────────────────────────────────────────

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    super.key,
    required this.field,
    required this.index,
    required this.canManage,
    required this.isLast,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> field;
  final int index;
  final bool canManage;
  final bool isLast;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final label = field['label'] as String? ?? field['key'] as String? ?? '—';
    final type = field['type'] as String? ?? 'text';
    final required = field['required'] as bool? ?? false;

    final typeLabel = _kFieldTypes
        .where((e) => e.$1 == type)
        .map((e) => e.$2)
        .firstOrNull ?? type;

    return Container(
      color: AppColors.ctSurface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Row(
              children: [
                if (canManage)
                  ReorderableDragStartListener(
                    index: index,
                    child: const Icon(
                      Icons.drag_handle_rounded,
                      size: 18,
                      color: AppColors.ctText3,
                    ),
                  )
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 10),
                Icon(
                  _fieldIcon(type),
                  size: 18,
                  color: AppColors.ctTeal,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ctText,
                        ),
                      ),
                      Text(
                        typeLabel,
                        style: AppTextStyles.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (required)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.ctTealLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Requerido',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ctTealDark,
                      ),
                    ),
                  ),
                if (canManage) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        size: 16, color: AppColors.ctText2),
                    onPressed: onEdit,
                    tooltip: 'Editar campo',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 32, minHeight: 32),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 16, color: AppColors.ctDanger),
                    onPressed: onDelete,
                    tooltip: 'Eliminar campo',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 32, minHeight: 32),
                  ),
                ],
              ],
            ),
          ),
          if (!isLast)
            const Divider(height: 1, color: AppColors.ctBorder),
        ],
      ),
    );
  }
}

// ── _FieldDialog ──────────────────────────────────────────────────────────────

class _FieldDialog extends StatefulWidget {
  const _FieldDialog({
    required this.onSaved,
    required this.tenantId,
    required this.tenantWorkerId,
    this.field,
  });

  final Map<String, dynamic>? field;
  final String tenantId;
  final String tenantWorkerId;
  final void Function(Map<String, dynamic>) onSaved;

  @override
  State<_FieldDialog> createState() => _FieldDialogState();
}

// Data source options for select fields
const _kDataSources = [
  ('static', 'Opciones estáticas'),
  ('system:operators', 'Operadores del tenant'),
  ('system:operators_with_flow', 'Operadores con flow asignado'),
];

class _FieldDialogState extends State<_FieldDialog> {
  final _labelCtrl = TextEditingController();
  String _type = 'text';
  bool _required = false;

  // select type state
  String _dataSourceBase = 'system:operators';
  String? _dataSourceFlowSlug;
  String _fillStrategy = 'conversational_list';
  List<Map<String, dynamic>> _availableFlows = [];
  bool _loadingFlows = false;

  // static options state
  List<String> _staticOptions = [];
  final _optionCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  bool get _isEdit => widget.field != null;

  String get _fieldKey => _fieldKeyify(_labelCtrl.text.trim());
  bool get _fieldKeyValid => _fieldKey.length >= 2;

  String get _resolvedDataSource {
    if (_dataSourceBase == 'static') return 'static';
    if (_dataSourceBase == 'system:operators_with_flow') {
      if (_dataSourceFlowSlug == null) return _dataSourceBase;
      return 'system:operators_with_flow:$_dataSourceFlowSlug';
    }
    return _dataSourceBase;
  }

  bool get _selectValid =>
      _type != 'select' ||
      (_dataSourceBase == 'static'
          ? _staticOptions.isNotEmpty
          : (_dataSourceBase == 'system:operators' ||
              (_dataSourceBase == 'system:operators_with_flow' &&
                  _dataSourceFlowSlug != null)));

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _labelCtrl.text = widget.field!['label'] as String? ?? '';
      _type = widget.field!['type'] as String? ?? 'text';
      _required = widget.field!['required'] as bool? ?? false;
      _descCtrl.text = widget.field!['description'] as String? ?? '';
      final ds = widget.field!['data_source'] as String?;
      if (ds != null) {
        if (ds.startsWith('system:operators_with_flow:')) {
          _dataSourceBase = 'system:operators_with_flow';
          _dataSourceFlowSlug = ds.substring('system:operators_with_flow:'.length);
        } else {
          _dataSourceBase = ds;
        }
      }
      _fillStrategy = widget.field!['fill_strategy'] as String? ??
          'conversational_list';
      final rawOpts = widget.field!['options'];
      if (rawOpts is List) {
        _staticOptions = List<String>.from(rawOpts.map((e) => e.toString()));
      }
      if (_staticOptions.isNotEmpty && ds == null) _dataSourceBase = 'static';
    }
    _labelCtrl.addListener(_onLabelChanged);
    if (_type == 'select') _loadFlows();
  }

  void _onLabelChanged() => setState(() {});

  Future<void> _loadFlows() async {
    if (widget.tenantWorkerId.isEmpty) return;
    setState(() => _loadingFlows = true);
    try {
      final flows = await FlowsApi.getFlowsByWorker(
        tenantWorkerId: widget.tenantWorkerId,
      );
      if (!mounted) return;
      setState(() {
        _availableFlows = flows;
        if (_dataSourceFlowSlug != null &&
            !flows.any((f) => f['slug'] == _dataSourceFlowSlug)) {
          _dataSourceFlowSlug = null;
        }
        _loadingFlows = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingFlows = false);
    }
  }

  @override
  void dispose() {
    _labelCtrl.removeListener(_onLabelChanged);
    _labelCtrl.dispose();
    _optionCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _addStaticOption() {
    final v = _optionCtrl.text.trim();
    if (v.isEmpty || _staticOptions.contains(v)) return;
    setState(() {
      _staticOptions.add(v);
      _optionCtrl.clear();
    });
  }

  void _submit() {
    final label = _labelCtrl.text.trim();
    if (label.isEmpty || !_fieldKeyValid || !_selectValid) return;

    final updated = Map<String, dynamic>.from(widget.field ?? {});
    updated['label'] = label;
    updated['key'] = _fieldKey;
    updated['type'] = _type;
    updated['required'] = _required;
    final desc = _descCtrl.text.trim();
    if (desc.isNotEmpty) {
      updated['description'] = desc;
    } else {
      updated.remove('description');
    }
    if (_type == 'select') {
      if (_dataSourceBase == 'static') {
        updated['options'] = List<String>.from(_staticOptions);
        updated.remove('data_source');
        updated.remove('fill_strategy');
      } else {
        updated['data_source'] = _resolvedDataSource;
        updated['fill_strategy'] = _fillStrategy;
        updated.remove('options');
      }
    } else {
      updated.remove('data_source');
      updated.remove('fill_strategy');
      updated.remove('options');
    }
    if (!_isEdit || updated['id'] == null) {
      updated['id'] =
          DateTime.now().millisecondsSinceEpoch.toString();
    }

    widget.onSaved(updated);
    Navigator.pop(context);
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
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEdit ? 'Editar campo' : 'Nuevo campo',
                style: const TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ctText,
                ),
              ),
              const SizedBox(height: 20),

              // Label
              _FormField(
                label: 'Etiqueta',
                controller: _labelCtrl,
                placeholder: 'Ej: Número de guía',
              ),
              if (_labelCtrl.text.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                _FieldKeyPreview(
                  fieldKey: _fieldKey,
                  valid: _fieldKeyValid,
                ),
              ],
              const SizedBox(height: 14),

              // Description
              const Text(
                'Descripción / alias de detección',
                style: AppTextStyles.btnSecondary,
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.ctSurface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.ctBorder2),
                ),
                child: TextField(
                  controller: _descCtrl,
                  maxLines: 3,
                  style: AppTextStyles.body,
                  decoration: const InputDecoration(
                    hintText: 'Opcional',
                    hintStyle: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 13,
                      color: AppColors.ctText3,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Type
              const Text(
                'Tipo',
                style: AppTextStyles.btnSecondary,
              ),
              const SizedBox(height: 6),
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
                  value: _type,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  dropdownColor: AppColors.ctSurface,
                  items: _kFieldTypes.map((entry) {
                    final (value, label) = entry;
                    return DropdownMenuItem(
                      value: value,
                      child: Row(
                        children: [
                          Icon(_fieldIcon(value),
                              size: 16, color: AppColors.ctText2),
                          const SizedBox(width: 8),
                          Text(
                            label,
                            style: AppTextStyles.body,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _type = v);
                      if (v == 'select' && _availableFlows.isEmpty) {
                        _loadFlows();
                      }
                    }
                  },
                ),
              ),

              // Data source (select type only)
              if (_type == 'select') ...[
                const SizedBox(height: 14),
                const Text(
                  'Fuente de datos',
                  style: AppTextStyles.btnSecondary,
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.ctSurface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.ctBorder2),
                  ),
                  child: DropdownButton<String>(
                    value: _dataSourceBase,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    dropdownColor: AppColors.ctSurface,
                    items: _kDataSources.map((entry) {
                      final (value, label) = entry;
                      return DropdownMenuItem(
                        value: value,
                        child: Text(label, style: AppTextStyles.body),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _dataSourceBase = v;
                          _dataSourceFlowSlug = null;
                        });
                        if (v == 'system:operators_with_flow' &&
                            _availableFlows.isEmpty) {
                          _loadFlows();
                        }
                      }
                    },
                  ),
                ),
                if (_dataSourceBase == 'system:operators_with_flow') ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Flow asignado',
                    style: AppTextStyles.btnSecondary,
                  ),
                  const SizedBox(height: 6),
                  if (_loadingFlows)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: CircularProgressIndicator(
                            color: AppColors.ctTeal, strokeWidth: 2),
                      ),
                    )
                  else if (_availableFlows.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.ctBorder),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'No hay flujos disponibles para este worker',
                        style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                      ),
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
                        value: _dataSourceFlowSlug,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        dropdownColor: AppColors.ctSurface,
                        hint: const Text('Selecciona un flow',
                            style: TextStyle(
                                fontFamily: 'Geist',
                                fontSize: 13,
                                color: AppColors.ctText2)),
                        items: _availableFlows.map((f) {
                          final slug = f['slug'] as String? ?? '';
                          final name = f['name'] as String? ?? slug;
                          return DropdownMenuItem<String>(
                            value: slug,
                            child: Text(name,
                                style: const TextStyle(
                                    fontFamily: 'Geist',
                                    fontSize: 13,
                                    color: AppColors.ctText)),
                          );
                        }).toList(),
                        onChanged: (v) =>
                            setState(() => _dataSourceFlowSlug = v),
                      ),
                    ),
                ],
              ],

              // Static options (select + static source only)
              if (_type == 'select' && _dataSourceBase == 'static') ...[
                const SizedBox(height: 14),
                const Text(
                  'Opciones',
                  style: AppTextStyles.btnSecondary,
                ),
                const SizedBox(height: 6),
                if (_staticOptions.isNotEmpty) ...[
                  ..._staticOptions.asMap().entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.ctSurface2,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.ctBorder2),
                                ),
                                child: Text(e.value, style: AppTextStyles.body),
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _staticOptions.removeAt(e.key)),
                              child: const Icon(Icons.close,
                                  size: 16, color: AppColors.ctText2),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 4),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.ctSurface2,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.ctBorder2),
                        ),
                        child: TextField(
                          controller: _optionCtrl,
                          style: AppTextStyles.body,
                          decoration: const InputDecoration(
                            hintText: 'Nueva opción...',
                            hintStyle: TextStyle(
                              fontFamily: 'Geist',
                              fontSize: 13,
                              color: AppColors.ctText3,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding:
                                EdgeInsets.symmetric(vertical: 8),
                          ),
                          onSubmitted: (_) => _addStaticOption(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _PrimaryButton(
                      label: 'Agregar',
                      onTap: _addStaticOption,
                    ),
                  ],
                ),
              ],

              // Fill strategy (select type only, not for static)
              if (_type == 'select' && _dataSourceBase != 'static') ...[
                const SizedBox(height: 14),
                const Text(
                  'Cuando se ejecuta conversacionalmente',
                  style: AppTextStyles.btnSecondary,
                ),
                const SizedBox(height: 6),
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
                    value: _fillStrategy,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    dropdownColor: AppColors.ctSurface,
                    items: const [
                      DropdownMenuItem(
                        value: 'conversational_list',
                        child: Text('Mostrar lista de opciones al operador',
                            style: TextStyle(
                                fontFamily: 'Geist',
                                fontSize: 13,
                                color: AppColors.ctText)),
                      ),
                      DropdownMenuItem(
                        value: 'inherit_actor',
                        child: Text('Usar el operador actual',
                            style: TextStyle(
                                fontFamily: 'Geist',
                                fontSize: 13,
                                color: AppColors.ctText)),
                      ),
                      DropdownMenuItem(
                        value: 'defer_dashboard',
                        child: Text('Pedir al supervisor en Tareas',
                            style: TextStyle(
                                fontFamily: 'Geist',
                                fontSize: 13,
                                color: AppColors.ctText)),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _fillStrategy = v);
                    },
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // Required toggle
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Requerido',
                      style: AppTextStyles.btnSecondary,
                    ),
                  ),
                  Switch(
                    value: _required,
                    onChanged: (v) => setState(() => _required = v),
                    activeThumbColor: AppColors.ctTeal,
                    activeTrackColor:
                        AppColors.ctTeal.withValues(alpha: 0.3),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _GhostButton(
                    label: 'Cancelar',
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  _PrimaryButton(
                    label: 'Guardar',
                    onTap: (_fieldKeyValid && _selectValid) ? _submit : () {},
                    enabled: _fieldKeyValid && _selectValid,
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

// ── _EmptyState ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.ctText3),
          const SizedBox(height: 12),
          Text(
            message,
            style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── _ComportamientoTab ────────────────────────────────────────────────────────

class _ComportamientoTab extends StatefulWidget {
  const _ComportamientoTab({
    required this.conditions,
    required this.flowFields,
    required this.canManage,
    required this.triggerSources,
    required this.flowId,
    required this.tenantId,
    required this.sendProactive,
    required this.availableRoles,
    required this.allowedRoleIds,
    required this.onChanged,
    required this.onAllowedRoleIdsChanged,
  });

  final List<Map<String, dynamic>> conditions;
  final List<Map<String, dynamic>> flowFields;
  final bool canManage;
  final List<String> triggerSources;
  final String flowId;
  final String tenantId;
  final bool sendProactive;
  final List<Map<String, dynamic>> availableRoles;
  final List<String> allowedRoleIds;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final ValueChanged<List<String>> onAllowedRoleIdsChanged;

  @override
  State<_ComportamientoTab> createState() => _ComportamientoTabState();
}

class _ComportamientoTabState extends State<_ComportamientoTab> {
  late List<Map<String, dynamic>> _conditions;
  late bool _sendProactive;
  late List<String> _allowedRoleIds;
  bool _savingProactive = false;

  @override
  void initState() {
    super.initState();
    _conditions = List.from(widget.conditions);
    _sendProactive = widget.sendProactive;
    _allowedRoleIds = List.from(widget.allowedRoleIds);
  }

  @override
  void didUpdateWidget(_ComportamientoTab old) {
    super.didUpdateWidget(old);
    if (old.conditions != widget.conditions) {
      _conditions = List.from(widget.conditions);
    }
    if (old.sendProactive != widget.sendProactive) {
      _sendProactive = widget.sendProactive;
    }
    if (old.allowedRoleIds != widget.allowedRoleIds) {
      _allowedRoleIds = List.from(widget.allowedRoleIds);
    }
    // When conversational is removed from trigger sources, auto-disable
    // send_proactive and persist immediately.
    final wasConversational = old.triggerSources.contains('conversational');
    final isConversational = widget.triggerSources.contains('conversational');
    if (wasConversational && !isConversational && _sendProactive) {
      _patchSendProactive(false);
    }
  }

  Future<void> _patchSendProactive(bool value) async {
    setState(() {
      _sendProactive = value;
      _savingProactive = true;
    });
    try {
      await FlowsApi.updateFlow(
        flowId: widget.flowId,
        sendProactive: value,
      );
      if (!mounted) return;
      setState(() => _savingProactive = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(value
            ? 'Mensaje proactivo activado'
            : 'Mensaje proactivo desactivado'),
        backgroundColor: AppColors.ctOk,
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sendProactive = !value;
        _savingProactive = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_dioError(e)),
        backgroundColor: AppColors.ctDanger,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  // ignore: unused_element
  void _openConditionDialog(Map<String, dynamic>? condition) {
    showDialog(
      context: context,
      builder: (_) => _ConditionDialog(
        condition: condition,
        flowFields: widget.flowFields,
        onSaved: (updated) {
          setState(() {
            if (condition != null) {
              final idx = _conditions.indexWhere(
                  (c) => c['id'] == condition['id']);
              if (idx >= 0) {
                _conditions[idx] = updated;
              } else {
                _conditions.add(updated);
              }
            } else {
              _conditions.add(updated);
            }
          });
          widget.onChanged(List.from(_conditions));
        },
      ),
    );
  }

  // ignore: unused_element
  void _deleteCondition(Map<String, dynamic> condition) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.ctSurface,
        title: const Text(
          'Eliminar condición',
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.ctText,
          ),
        ),
        content: const Text(
          '¿Eliminar esta condición de branching?',
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 13,
            color: AppColors.ctText2,
          ),
        ),
        actions: [
          _GhostButton(
            label: 'Cancelar',
            onTap: () => Navigator.pop(ctx),
          ),
          const SizedBox(width: 8),
          _PrimaryButton(
            label: 'Eliminar',
            onTap: () {
              Navigator.pop(ctx);
              setState(() {
                _conditions.removeWhere((c) => c['id'] == condition['id']);
              });
              widget.onChanged(List.from(_conditions));
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // TODO: behavior.conditions — pendiente conectar al worker
          // Row(
          //   children: [
          //     const Text(
          //       'Condiciones de branching',
          //       style: TextStyle(
          //         fontFamily: 'Onest',
          //         fontSize: 14,
          //         fontWeight: FontWeight.bold,
          //         color: AppColors.ctText,
          //       ),
          //     ),
          //     const Spacer(),
          //     if (widget.canManage)
          //       TextButton(
          //         onPressed: () => _openConditionDialog(null),
          //         style: TextButton.styleFrom(
          //             foregroundColor: AppColors.ctTeal),
          //         child: const Text(
          //           '+ Agregar condición',
          //           style: TextStyle(
          //             fontFamily: 'Geist',
          //             fontSize: 12,
          //             fontWeight: FontWeight.w600,
          //           ),
          //         ),
          //       ),
          //   ],
          // ),
          // const SizedBox(height: 16),
          // if (_conditions.isEmpty)
          //   const SizedBox(
          //     height: 200,
          //     child: _EmptyState(
          //       icon: Icons.alt_route_outlined,
          //       message:
          //           'Sin condiciones definidas.\nEste flujo avanza linealmente.',
          //     ),
          //   )
          // else
          //   ListView.separated(
          //     shrinkWrap: true,
          //     physics: const NeverScrollableScrollPhysics(),
          //     itemCount: _conditions.length,
          //     separatorBuilder: (context2, i2) => const SizedBox(height: 8),
          //     itemBuilder: (_, i) => _ConditionCard(
          //       condition: _conditions[i],
          //       canManage: widget.canManage,
          //       onEdit: () => _openConditionDialog(_conditions[i]),
          //       onDelete: () => _deleteCondition(_conditions[i]),
          //     ),
          //   ),
          // const SizedBox(height: 24),
          if (widget.triggerSources.contains('conversational')) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.ctSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.ctBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Enviar mensaje proactivo al operador al iniciar este flujo',
                          style: TextStyle(
                            fontFamily: 'Geist',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ctText,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Si está activado, la plataforma envía un mensaje automático al operador cuando se abre este flujo',
                          style: TextStyle(
                            fontFamily: 'Geist',
                            fontSize: 12,
                            color: AppColors.ctText2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_savingProactive)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.ctTeal,
                      ),
                    )
                  else
                    Switch(
                      value: _sendProactive,
                      activeThumbColor: AppColors.ctTeal,
                      activeTrackColor: AppColors.ctTeal.withValues(alpha: 0.4),
                      onChanged: widget.canManage
                          ? (v) => _patchSendProactive(v)
                          : null,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          // ── Roles autorizados ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.ctSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.ctBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Roles con acceso',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ctText,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Solo los operadores con estos roles podrán iniciar este flujo. Si no se selecciona ninguno, todos los roles tienen acceso.',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 12,
                    color: AppColors.ctText2,
                  ),
                ),
                const SizedBox(height: 12),
                if (widget.availableRoles.isEmpty)
                  const Text(
                    'No hay roles definidos. Crea roles en Operadores → Roles.',
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 12,
                      color: AppColors.ctText3,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.availableRoles.map((role) {
                      final id = role['id'] as String? ?? '';
                      final label = role['label'] as String? ?? id;
                      final color = _hexColor(role['color'] as String?);
                      final selected = _allowedRoleIds.contains(id);
                      return FilterChip(
                        label: Text(
                          label,
                          style: const TextStyle(
                            fontFamily: 'Geist',
                            fontSize: 12,
                          ),
                        ),
                        selected: selected,
                        selectedColor: color.withValues(alpha: 0.15),
                        checkmarkColor: color,
                        backgroundColor: AppColors.ctBg,
                        side: BorderSide(
                          color: selected ? color : AppColors.ctBorder,
                        ),
                        onSelected: widget.canManage
                            ? (v) {
                                setState(() {
                                  if (v) {
                                    _allowedRoleIds = [..._allowedRoleIds, id];
                                  } else {
                                    _allowedRoleIds = _allowedRoleIds
                                        .where((r) => r != id)
                                        .toList();
                                  }
                                });
                                widget.onAllowedRoleIdsChanged(
                                    List.from(_allowedRoleIds));
                              }
                            : null,
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── _ConditionCard ────────────────────────────────────────────────────────────

// ignore: unused_element
class _ConditionCard extends StatelessWidget {
  const _ConditionCard({
    required this.condition,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> condition;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final field = condition['field'] as String? ?? '';
    final operator = condition['operator'] as String? ?? '';
    final value = condition['value']?.toString() ?? '';
    final label = condition['label'] as String?;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.ctBorder),
        // left accent
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: const BoxDecoration(
                color: AppColors.ctTeal,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.ctTealLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            operator,
                            style: const TextStyle(
                              fontFamily: 'Geist',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ctTealDark,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$field $operator "$value"',
                            style: const TextStyle(
                              fontFamily: 'Geist',
                              fontSize: 13,
                              color: AppColors.ctText,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (label != null && label.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: const TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 11,
                          color: AppColors.ctText2,
                        ),
                      ),
                    ],
                    if (canManage) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined,
                                size: 16, color: AppColors.ctText2),
                            onPressed: onEdit,
                            tooltip: 'Editar',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 30, minHeight: 30),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                size: 16, color: AppColors.ctDanger),
                            onPressed: onDelete,
                            tooltip: 'Eliminar',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 30, minHeight: 30),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _ConditionDialog ──────────────────────────────────────────────────────────

const _kOperators = [
  ('==', 'igual a'),
  ('!=', 'distinto de'),
  ('<', 'menor que'),
  ('<=', 'menor o igual'),
  ('>', 'mayor que'),
  ('>=', 'mayor o igual'),
  ('in', 'contiene'),
  ('not in', 'no contiene'),
];

class _ConditionDialog extends StatefulWidget {
  const _ConditionDialog({
    required this.flowFields,
    required this.onSaved,
    this.condition,
  });

  final Map<String, dynamic>? condition;
  final List<Map<String, dynamic>> flowFields;
  final void Function(Map<String, dynamic>) onSaved;

  @override
  State<_ConditionDialog> createState() => _ConditionDialogState();
}

class _ConditionDialogState extends State<_ConditionDialog> {
  String? _selectedFieldId; // stored as "fields.{id}"
  String _operator = '==';
  final _valueCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();

  bool get _isEdit => widget.condition != null;

  String? get _selectedFieldType {
    if (_selectedFieldId == null) return null;
    final rawId =
        _selectedFieldId!.startsWith('fields.')
            ? _selectedFieldId!.substring(7)
            : _selectedFieldId!;
    final match = widget.flowFields
        .where((f) => f['id']?.toString() == rawId)
        .firstOrNull;
    return match?['type'] as String?;
  }

  String get _valueHint {
    switch (_selectedFieldType) {
      case 'number':
        return 'ej. 100';
      case 'boolean':
        return 'true o false';
      case 'date':
        return 'ej. 2026-01-01';
      case 'select':
        return 'ej. opción_a';
      default:
        return 'ej. pendiente';
    }
  }

  @override
  void initState() {
    super.initState();
    final cond = widget.condition;
    if (cond != null) {
      _selectedFieldId = cond['field'] as String?;
      _operator = cond['operator'] as String? ?? '==';
      _valueCtrl.text = cond['value']?.toString() ?? '';
      _labelCtrl.text = cond['label'] as String? ?? '';
    }
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_selectedFieldId == null) return;
    if (_valueCtrl.text.trim().isEmpty) return;

    final updated = Map<String, dynamic>.from(widget.condition ?? {});
    updated['field'] = _selectedFieldId;
    updated['operator'] = _operator;
    updated['value'] = _valueCtrl.text.trim();
    final lbl = _labelCtrl.text.trim();
    if (lbl.isNotEmpty) updated['label'] = lbl;
    if (!_isEdit || updated['id'] == null) {
      updated['id'] = DateTime.now().millisecondsSinceEpoch.toString();
    }

    widget.onSaved(updated);
    Navigator.pop(context);
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
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEdit ? 'Condición' : 'Nueva condición',
                style: const TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ctText,
                ),
              ),
              const SizedBox(height: 20),

              // Campo
              const Text(
                'Campo',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ctText,
                ),
              ),
              const SizedBox(height: 6),
              _DropdownContainer(
                child: DropdownButton<String>(
                  value: _selectedFieldId,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  hint: const Text(
                    'Selecciona un campo',
                    style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 13,
                        color: AppColors.ctText3),
                  ),
                  dropdownColor: AppColors.ctSurface,
                  items: widget.flowFields.map((f) {
                    final id = f['id']?.toString() ?? '';
                    final lbl = f['label'] as String? ?? id;
                    return DropdownMenuItem(
                      value: 'fields.$id',
                      child: Text(
                        lbl,
                        style: const TextStyle(
                            fontFamily: 'Geist',
                            fontSize: 13,
                            color: AppColors.ctText),
                      ),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedFieldId = v),
                ),
              ),
              const SizedBox(height: 14),

              // Operador
              const Text(
                'Operador',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ctText,
                ),
              ),
              const SizedBox(height: 6),
              _DropdownContainer(
                child: DropdownButton<String>(
                  value: _operator,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  dropdownColor: AppColors.ctSurface,
                  items: _kOperators.map((entry) {
                    final (val, lbl) = entry;
                    return DropdownMenuItem(
                      value: val,
                      child: Text(
                        '$val — $lbl',
                        style: const TextStyle(
                            fontFamily: 'Geist',
                            fontSize: 13,
                            color: AppColors.ctText),
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _operator = v);
                  },
                ),
              ),
              const SizedBox(height: 14),

              // Valor
              _FormField(
                label: 'Valor',
                controller: _valueCtrl,
                placeholder: _valueHint,
              ),
              const SizedBox(height: 14),

              // Etiqueta
              _FormField(
                label: 'Etiqueta (opcional)',
                controller: _labelCtrl,
                placeholder: 'Descripción legible (opcional)',
              ),

              // Preview
              const SizedBox(height: 10),
              ValueListenableBuilder(
                valueListenable: _valueCtrl,
                builder: (context2, value, child) {
                  if (_selectedFieldId == null || _valueCtrl.text.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    'Expresión: $_selectedFieldId $_operator "${_valueCtrl.text}"',
                    style: const TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 11,
                      color: AppColors.ctText2,
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _GhostButton(
                      label: 'Cancelar',
                      onTap: () => Navigator.pop(context)),
                  const SizedBox(width: 10),
                  _PrimaryButton(label: 'Guardar', onTap: _submit),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _AlCerrarTab ──────────────────────────────────────────────────────────────

class _AlCerrarTab extends StatefulWidget {
  const _AlCerrarTab({
    required this.actions,
    required this.canManage,
    required this.tenantId,
    required this.tenantWorkerId,
    required this.currentFlowSlug,
    required this.flowFields,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> actions;
  final bool canManage;
  final String tenantId;
  final String tenantWorkerId;
  final String currentFlowSlug;
  final List<Map<String, dynamic>> flowFields;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  @override
  State<_AlCerrarTab> createState() => _AlCerrarTabState();
}

class _AlCerrarTabState extends State<_AlCerrarTab> {
  late List<Map<String, dynamic>> _actions;

  @override
  void initState() {
    super.initState();
    _actions = List.from(widget.actions);
  }

  @override
  void didUpdateWidget(_AlCerrarTab old) {
    super.didUpdateWidget(old);
    if (old.actions != widget.actions) {
      _actions = List.from(widget.actions);
    }
  }

  void _openActionDialog(Map<String, dynamic>? action) {
    showDialog(
      context: context,
      builder: (_) => _ActionDialog(
        action: action,
        tenantId: widget.tenantId,
        tenantWorkerId: widget.tenantWorkerId,
        currentFlowSlug: widget.currentFlowSlug,
        flowFields: widget.flowFields,
        onSaved: (updated) {
          setState(() {
            if (action != null) {
              final idx =
                  _actions.indexWhere((a) => a['id'] == action['id']);
              if (idx >= 0) {
                _actions[idx] = updated;
              } else {
                _actions.add(updated);
              }
            } else {
              _actions.add(updated);
            }
          });
          widget.onChanged(List.from(_actions));
        },
      ),
    );
  }

  void _deleteAction(Map<String, dynamic> action) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.ctSurface,
        title: const Text(
          'Eliminar acción',
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.ctText,
          ),
        ),
        content: const Text(
          '¿Eliminar esta acción?',
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 13,
            color: AppColors.ctText2,
          ),
        ),
        actions: [
          _GhostButton(
              label: 'Cancelar', onTap: () => Navigator.pop(ctx)),
          const SizedBox(width: 8),
          _PrimaryButton(
            label: 'Eliminar',
            onTap: () {
              Navigator.pop(ctx);
              setState(() {
                _actions.removeWhere((a) => a['id'] == action['id']);
              });
              widget.onChanged(List.from(_actions));
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Acciones al completar el flujo',
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.ctText,
                ),
              ),
              const Spacer(),
              if (widget.canManage)
                TextButton(
                  onPressed: () => _openActionDialog(null),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.ctTeal),
                  child: const Text(
                    '+ Agregar acción',
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Se ejecutan en orden cuando el flujo se marca como completado.',
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 12,
              color: AppColors.ctText2,
            ),
          ),
          const SizedBox(height: 16),
          if (_actions.isEmpty)
            const SizedBox(
              height: 200,
              child: _EmptyState(
                icon: Icons.check_circle_outline,
                message:
                    'Sin acciones configuradas.\nEl flujo cierra sin efectos secundarios.',
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _actions.length,
              separatorBuilder: (context2, i2) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _ActionCard(
                action: _actions[i],
                canManage: widget.canManage,
                onEdit: () => _openActionDialog(_actions[i]),
                onDelete: () => _deleteAction(_actions[i]),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── _ActionCard ───────────────────────────────────────────────────────────────

IconData _actionIcon(String? type) {
  switch (type) {
    case 'webhook_out':
      return Icons.webhook_outlined;
    case 'emit_event':
      return Icons.notifications_outlined;
    case 'google_sheets_append_row':
      return Icons.table_chart_outlined;
    default:
      return Icons.account_tree_outlined;
  }
}

String _actionLabel(String? type) {
  switch (type) {
    case 'webhook_out':
      return 'Webhook saliente';
    case 'emit_event':
      return 'Emitir evento';
    case 'google_sheets_append_row':
      return 'Google Sheets — Agregar fila';
    default:
      return 'Abrir flujo';
  }
}

String _actionSubtitle(Map<String, dynamic> action) {
  final type = action['type'] as String?;
  switch (type) {
    case 'open_flow':
      final slug = action['target_flow_slug'] as String? ?? '';
      return '→ $slug';
    case 'webhook_out':
      final id = action['integration_id'] as String? ?? '';
      final short = id.length > 8 ? id.substring(0, 8) : id;
      return '↗ $short';
    case 'emit_event':
      final name = action['event_name'] as String? ?? '';
      return '⚡ $name';
    case 'google_sheets_append_row':
      final config = action['config'] as Map? ?? {};
      final sid = config['spreadsheet_id'] as String? ?? '';
      final display = sid.length > 20 ? '${sid.substring(0, 20)}…' : sid;
      return '📊 $display';
    default:
      return '';
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.action,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> action;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final type = action['type'] as String?;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.ctBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(_actionIcon(type), size: 20, color: AppColors.ctTeal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _actionLabel(type),
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ctText,
                  ),
                ),
                Text(
                  _actionSubtitle(action),
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 12,
                    color: AppColors.ctText2,
                  ),
                ),
              ],
            ),
          ),
          if (canManage) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  size: 16, color: AppColors.ctText2),
              onPressed: onEdit,
              tooltip: 'Editar',
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 30, minHeight: 30),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 16, color: AppColors.ctDanger),
              onPressed: onDelete,
              tooltip: 'Eliminar',
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 30, minHeight: 30),
            ),
          ],
        ],
      ),
    );
  }
}

// ── _ActionDialog ─────────────────────────────────────────────────────────────

class _ActionDialog extends StatefulWidget {
  const _ActionDialog({
    required this.onSaved,
    required this.tenantId,
    required this.tenantWorkerId,
    required this.currentFlowSlug,
    this.flowFields = const [],
    this.action,
  });

  final Map<String, dynamic>? action;
  final String tenantId;
  final String tenantWorkerId;
  final String currentFlowSlug;
  final List<Map<String, dynamic>> flowFields;
  final void Function(Map<String, dynamic>) onSaved;

  @override
  State<_ActionDialog> createState() => _ActionDialogState();
}

class _ActionDialogState extends State<_ActionDialog> {
  String _type = 'open_flow';

  // open_flow — replaced TextField with dropdown
  String? _selectedFlowSlug;
  List<Map<String, dynamic>> _availableFlows = [];
  bool _loadingFlows = false;
  bool _carryAncestors = false;

  // webhook_out
  final _integrationCtrl = TextEditingController();
  bool _includeAncestors = false;

  // emit_event
  final _eventNameCtrl = TextEditingController();

  // google_sheets_append_row
  final _spreadsheetIdCtrl = TextEditingController();
  final _sheetNameCtrl = TextEditingController();
  // Each entry: (col: controller, val: controller)
  final List<(TextEditingController, TextEditingController)> _columnMappingRows = [];
  // Parallel list: selected flowField key per row (null = custom text mode)
  final List<String?> _columnMappingKeys = [];

  // condition
  String? _conditionField;
  String _conditionOp = '==';
  final _conditionValueCtrl = TextEditingController();

  bool get _isEdit => widget.action != null;

  @override
  void initState() {
    super.initState();
    final a = widget.action;
    if (a != null) {
      _type = a['type'] as String? ?? 'open_flow';
      _selectedFlowSlug = a['target_flow_slug'] as String?;
      _carryAncestors = a['carry_ancestors'] as bool? ?? false;
      _integrationCtrl.text = a['integration_id'] as String? ?? '';
      _includeAncestors = a['include_ancestors'] as bool? ?? false;
      _eventNameCtrl.text = a['event_name'] as String? ?? '';
      if (_type == 'google_sheets_append_row') {
        final cfg = a['config'] as Map? ?? {};
        _spreadsheetIdCtrl.text = cfg['spreadsheet_id'] as String? ?? '';
        _sheetNameCtrl.text = cfg['sheet_name'] as String? ?? 'Sheet1';
        final mapping = cfg['column_mapping'] as Map? ?? {};
        final fieldKeyRe = RegExp(r'^\{\{fields\.(\w+)\}\}$');
        for (final e in mapping.entries) {
          final valStr = e.value.toString();
          final m = fieldKeyRe.firstMatch(valStr);
          _columnMappingKeys.add(m?.group(1));
          _columnMappingRows.add((
            TextEditingController(text: e.key.toString()),
            TextEditingController(text: valStr),
          ));
        }
      }
      final cond = a['condition'] as String?;
      if (cond != null && cond.isNotEmpty) {
        final re = RegExp(
            r'^fields\.(\w+)\s*(==|!=|>=|<=|>|<)\s*"?([^"]*)"?\s*$');
        final m = re.firstMatch(cond);
        if (m != null) {
          _conditionField = m.group(1);
          _conditionOp = m.group(2)!;
          _conditionValueCtrl.text = m.group(3)!;
        } else {
          _conditionValueCtrl.text = cond;
        }
      }
    }
    if (_columnMappingRows.isEmpty) {
      _columnMappingRows.add((TextEditingController(text: 'A'), TextEditingController()));
      _columnMappingKeys.add(null);
    }
    _loadFlows();
  }

  Future<void> _loadFlows() async {
    if (widget.tenantWorkerId.isEmpty) return;
    setState(() => _loadingFlows = true);
    try {
      final flows = await FlowsApi.getFlowsByWorker(
        tenantWorkerId: widget.tenantWorkerId,
      );
      final filtered = flows
          .where((f) => (f['slug'] as String?) != widget.currentFlowSlug)
          .toList();
      if (!mounted) return;
      setState(() {
        _availableFlows = filtered;
        // If editing and selected slug not in list, keep it anyway
        if (_selectedFlowSlug != null &&
            !filtered.any((f) => f['slug'] == _selectedFlowSlug)) {
          _selectedFlowSlug = null;
        }
        _loadingFlows = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingFlows = false);
    }
  }

  @override
  void dispose() {
    _integrationCtrl.dispose();
    _eventNameCtrl.dispose();
    _spreadsheetIdCtrl.dispose();
    _sheetNameCtrl.dispose();
    for (final row in _columnMappingRows) {
      row.$1.dispose();
      row.$2.dispose();
    }
    _conditionValueCtrl.dispose();
    super.dispose();
  }

  String? _buildConditionExpression() {
    final val = _conditionValueCtrl.text.trim();
    if (_conditionField != null && val.isNotEmpty) {
      return 'fields.$_conditionField $_conditionOp "$val"';
    }
    if (_conditionField == null && val.isNotEmpty) {
      return val;
    }
    return null;
  }

  void _submit() {
    final updated = Map<String, dynamic>.from(widget.action ?? {});
    updated['type'] = _type;
    if (!_isEdit || updated['id'] == null) {
      updated['id'] = DateTime.now().millisecondsSinceEpoch.toString();
    }
    switch (_type) {
      case 'open_flow':
        if (_selectedFlowSlug == null) return;
        updated['target_flow_slug'] = _selectedFlowSlug!;
        updated['carry_ancestors'] = _carryAncestors;
        updated.remove('carry_fields');
        updated.remove('integration_id');
        updated.remove('include_ancestors');
        updated.remove('event_name');
        updated.remove('event_data');
        break;
      case 'webhook_out':
        if (_integrationCtrl.text.trim().isEmpty) return;
        updated['integration_id'] = _integrationCtrl.text.trim();
        updated['include_ancestors'] = _includeAncestors;
        updated.remove('target_flow_slug');
        updated.remove('carry_fields');
        updated.remove('carry_ancestors');
        updated.remove('event_name');
        updated.remove('event_data');
        break;
      case 'emit_event':
        if (_eventNameCtrl.text.trim().isEmpty) return;
        updated['event_name'] = _eventNameCtrl.text.trim();
        updated.remove('target_flow_slug');
        updated.remove('carry_fields');
        updated.remove('carry_ancestors');
        updated.remove('integration_id');
        updated.remove('include_ancestors');
        updated.remove('config');
        break;
      case 'google_sheets_append_row':
        final sid = _spreadsheetIdCtrl.text.trim();
        if (sid.isEmpty) return;
        final validRows = _columnMappingRows
            .where((r) => r.$1.text.trim().isNotEmpty)
            .toList();
        if (validRows.isEmpty) return;
        updated['config'] = {
          'spreadsheet_id': sid,
          'sheet_name': _sheetNameCtrl.text.trim().isEmpty
              ? 'Sheet1'
              : _sheetNameCtrl.text.trim(),
          'column_mapping': {
            for (final r in validRows) r.$1.text.trim(): r.$2.text.trim(),
          },
        };
        updated.remove('target_flow_slug');
        updated.remove('carry_fields');
        updated.remove('carry_ancestors');
        updated.remove('integration_id');
        updated.remove('include_ancestors');
        updated.remove('event_name');
        updated.remove('event_data');
        break;
    }
    final cond = _buildConditionExpression();
    if (cond != null) {
      updated['condition'] = cond;
    } else {
      updated.remove('condition');
    }
    widget.onSaved(updated);
    Navigator.pop(context);
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
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEdit ? 'Acción' : 'Nueva acción',
                style: const TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ctText,
                ),
              ),
              const SizedBox(height: 20),

              // Tipo
              const Text(
                'Tipo de acción',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ctText,
                ),
              ),
              const SizedBox(height: 6),
              _DropdownContainer(
                child: DropdownButton<String>(
                  value: _type,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  dropdownColor: AppColors.ctSurface,
                  items: const [
                    DropdownMenuItem(
                      value: 'open_flow',
                      child: Text('Abrir flujo',
                          style: TextStyle(
                              fontFamily: 'Geist',
                              fontSize: 13,
                              color: AppColors.ctText)),
                    ),
                    DropdownMenuItem(
                      value: 'webhook_out',
                      child: Text('Webhook saliente',
                          style: TextStyle(
                              fontFamily: 'Geist',
                              fontSize: 13,
                              color: AppColors.ctText)),
                    ),
                    DropdownMenuItem(
                      value: 'emit_event',
                      child: Text('Emitir evento',
                          style: TextStyle(
                              fontFamily: 'Geist',
                              fontSize: 13,
                              color: AppColors.ctText)),
                    ),
                    DropdownMenuItem(
                      value: 'google_sheets_append_row',
                      child: Text('Google Sheets — Agregar fila',
                          style: TextStyle(
                              fontFamily: 'Geist',
                              fontSize: 13,
                              color: AppColors.ctText)),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _type = v);
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Campos condicionales
              if (_type == 'open_flow') ...[
                const Text(
                  'Flujo destino',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ctText,
                  ),
                ),
                const SizedBox(height: 6),
                if (_loadingFlows)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: CircularProgressIndicator(
                          color: AppColors.ctTeal, strokeWidth: 2),
                    ),
                  )
                else if (_availableFlows.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.ctBorder),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'No hay flujos disponibles para este worker',
                      style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 13,
                          color: AppColors.ctText2),
                    ),
                  )
                else
                  _DropdownContainer(
                    child: DropdownButton<String>(
                      value: _selectedFlowSlug,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      dropdownColor: AppColors.ctSurface,
                      hint: const Text('Selecciona un flujo',
                          style: TextStyle(
                              fontFamily: 'Geist',
                              fontSize: 13,
                              color: AppColors.ctText2)),
                      items: _availableFlows.map((f) {
                        final slug = f['slug'] as String? ?? '';
                        final name = f['name'] as String? ?? slug;
                        return DropdownMenuItem<String>(
                          value: slug,
                          child: Text(name,
                              style: const TextStyle(
                                  fontFamily: 'Geist',
                                  fontSize: 13,
                                  color: AppColors.ctText)),
                        );
                      }).toList(),
                      onChanged: (v) =>
                          setState(() => _selectedFlowSlug = v),
                    ),
                  ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Heredar todos los ancestros',
                    style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 13,
                        color: AppColors.ctText),
                  ),
                  value: _carryAncestors,
                  onChanged: (v) => setState(() => _carryAncestors = v),
                  activeThumbColor: AppColors.ctTeal,
                  activeTrackColor: AppColors.ctTeal.withValues(alpha: 0.4),
                ),
              ] else if (_type == 'webhook_out') ...[
                _FormField(
                  label: 'ID de integración',
                  controller: _integrationCtrl,
                  placeholder: 'UUID de la flow_integration configurada',
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Incluir datos de ancestros',
                    style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 13,
                        color: AppColors.ctText),
                  ),
                  value: _includeAncestors,
                  onChanged: (v) => setState(() => _includeAncestors = v),
                  activeThumbColor: AppColors.ctTeal,
                  activeTrackColor: AppColors.ctTeal.withValues(alpha: 0.4),
                ),
              ] else if (_type == 'emit_event') ...[
                _FormField(
                  label: 'Nombre del evento',
                  controller: _eventNameCtrl,
                  placeholder: 'ej. flujo_completado',
                ),
              ] else if (_type == 'google_sheets_append_row') ...[
                _FormField(
                  label: 'ID de hoja de cálculo',
                  controller: _spreadsheetIdCtrl,
                  placeholder: '1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms',
                ),
                const SizedBox(height: 12),
                _FormField(
                  label: 'Nombre de pestaña',
                  controller: _sheetNameCtrl,
                  placeholder: 'Hoja1',
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Mapeo de columnas',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.ctText,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _columnMappingRows.add((
                          TextEditingController(),
                          TextEditingController(),
                        ));
                        _columnMappingKeys.add(null);
                      }),
                      icon: const Icon(Icons.add, size: 14,
                          color: AppColors.ctTeal),
                      label: const Text(
                        '+ Agregar columna',
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 12,
                          color: AppColors.ctTeal,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ..._columnMappingRows.asMap().entries.map((entry) {
                  final i = entry.key;
                  final row = entry.value;
                  final selectedKey = _columnMappingKeys.length > i ? _columnMappingKeys[i] : null;
                  final hasFields = widget.flowFields.isNotEmpty;
                  // If selected key is no longer in flowFields (e.g. field deleted), treat as custom
                  final effectiveKey = (selectedKey != null &&
                      widget.flowFields.any((f) => (f['key'] as String?) == selectedKey))
                      ? selectedKey
                      : null;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 70,
                              child: _ColMappingField(
                                controller: row.$1,
                                placeholder: 'A',
                                onChanged: () => setState(() {}),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6),
                              child: Text('→',
                                  style: TextStyle(
                                      fontFamily: 'Geist',
                                      fontSize: 13,
                                      color: AppColors.ctText2)),
                            ),
                            if (hasFields)
                              Expanded(
                                child: _DropdownContainer(
                                  child: DropdownButton<String?>(
                                    value: effectiveKey,
                                    isExpanded: true,
                                    underline: const SizedBox.shrink(),
                                    dropdownColor: AppColors.ctSurface,
                                    hint: const Text(
                                      'Campo del flujo…',
                                      style: TextStyle(
                                        fontFamily: 'Geist',
                                        fontSize: 13,
                                        color: AppColors.ctText3,
                                      ),
                                    ),
                                    items: [
                                      const DropdownMenuItem<String?>(
                                        value: null,
                                        child: Text(
                                          'Personalizado…',
                                          style: TextStyle(
                                            fontFamily: 'Geist',
                                            fontSize: 13,
                                            color: AppColors.ctText2,
                                          ),
                                        ),
                                      ),
                                      ...widget.flowFields.map((f) {
                                        final key = f['key'] as String? ?? '';
                                        final label = f['label'] as String? ?? key;
                                        return DropdownMenuItem<String?>(
                                          value: key,
                                          child: Text(
                                            label,
                                            style: const TextStyle(
                                              fontFamily: 'Geist',
                                              fontSize: 13,
                                              color: AppColors.ctText,
                                            ),
                                          ),
                                        );
                                      }),
                                    ],
                                    onChanged: (v) => setState(() {
                                      if (_columnMappingKeys.length > i) {
                                        _columnMappingKeys[i] = v;
                                      }
                                      if (v != null) {
                                        row.$2.text = '{{fields.$v}}';
                                      } else {
                                        row.$2.clear();
                                      }
                                    }),
                                  ),
                                ),
                              )
                            else
                              Expanded(
                                child: _ColMappingField(
                                  controller: row.$2,
                                  placeholder: '{{fields.nombre}}',
                                  onChanged: () => setState(() {}),
                                ),
                              ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline,
                                  size: 16, color: AppColors.ctDanger),
                              onPressed: _columnMappingRows.length > 1
                                  ? () => setState(() {
                                        row.$1.dispose();
                                        row.$2.dispose();
                                        _columnMappingRows.removeAt(i);
                                        _columnMappingKeys.removeAt(i);
                                      })
                                  : null,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 28, minHeight: 28),
                            ),
                          ],
                        ),
                        // Custom text field shown below when "Personalizado…" is selected
                        if (hasFields && (effectiveKey == null))
                          Padding(
                            padding: const EdgeInsets.only(left: 78, top: 4),
                            child: _ColMappingField(
                              controller: row.$2,
                              placeholder: '{{fields.nombre}} o valor fijo',
                              onChanged: () => setState(() {}),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ],

              // ── Condición (opcional) ────────────────────────────────────────
              const SizedBox(height: 20),
              const Divider(color: AppColors.ctBorder, height: 1),
              const SizedBox(height: 16),
              const Text(
                'Condición (opcional)',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ctText,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'La acción solo se ejecuta si se cumple la condición.',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 12,
                  color: AppColors.ctText2,
                ),
              ),
              const SizedBox(height: 10),

              // Campo
              const Text(
                'Campo',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ctText2,
                ),
              ),
              const SizedBox(height: 6),
              _DropdownContainer(
                child: DropdownButton<String?>(
                  value: _conditionField,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  dropdownColor: AppColors.ctSurface,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        'Sin condición',
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 13,
                          color: AppColors.ctText2,
                        ),
                      ),
                    ),
                    ...widget.flowFields.map((f) {
                      final key = f['key'] as String? ?? '';
                      final label = f['label'] as String? ?? key;
                      return DropdownMenuItem<String?>(
                        value: key,
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontFamily: 'Geist',
                            fontSize: 13,
                            color: AppColors.ctText,
                          ),
                        ),
                      );
                    }),
                  ],
                  onChanged: (v) => setState(() {
                    _conditionField = v;
                    _conditionValueCtrl.clear();
                  }),
                ),
              ),

              if (_conditionField != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    // Operador
                    SizedBox(
                      width: 110,
                      child: _DropdownContainer(
                        child: DropdownButton<String>(
                          value: _conditionOp,
                          isExpanded: true,
                          underline: const SizedBox.shrink(),
                          dropdownColor: AppColors.ctSurface,
                          items: const [
                            DropdownMenuItem(value: '==', child: Text('== igual', style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText))),
                            DropdownMenuItem(value: '!=', child: Text('!= distinto', style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText))),
                            DropdownMenuItem(value: '>',  child: Text('>  mayor', style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText))),
                            DropdownMenuItem(value: '<',  child: Text('<  menor', style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText))),
                            DropdownMenuItem(value: '>=', child: Text('>= mayor o igual', style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText))),
                            DropdownMenuItem(value: '<=', child: Text('<= menor o igual', style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText))),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _conditionOp = v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Valor
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.ctSurface2,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.ctBorder2),
                        ),
                        child: TextField(
                          controller: _conditionValueCtrl,
                          style: const TextStyle(
                              fontFamily: 'Geist',
                              fontSize: 13,
                              color: AppColors.ctText),
                          decoration: const InputDecoration(
                            hintText: 'ej. Si, Granjas, 5',
                            hintStyle: TextStyle(
                                fontFamily: 'Geist',
                                fontSize: 13,
                                color: AppColors.ctText3),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding:
                                EdgeInsets.symmetric(vertical: 8),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.ctSurface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.ctBorder2),
                  ),
                  child: TextField(
                    controller: _conditionValueCtrl,
                    style: const TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 13,
                        color: AppColors.ctText),
                    decoration: const InputDecoration(
                      hintText: 'ej. fields.receta == "Si"',
                      hintStyle: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 13,
                          color: AppColors.ctText3),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],

              // Preview
              Builder(builder: (_) {
                final expr = _buildConditionExpression();
                if (expr == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Expresión: $expr',
                    style: const TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 11,
                      color: AppColors.ctText3,
                    ),
                  ),
                );
              }),

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _GhostButton(
                      label: 'Cancelar',
                      onTap: () => Navigator.pop(context)),
                  const SizedBox(width: 10),
                  _PrimaryButton(
                    label: 'Guardar',
                    onTap: _submit,
                    enabled: switch (_type) {
                      'open_flow' => _selectedFlowSlug != null,
                      'google_sheets_append_row' =>
                        _spreadsheetIdCtrl.text.trim().isNotEmpty &&
                        _columnMappingRows.any((r) => r.$1.text.trim().isNotEmpty),
                      _ => true,
                    },
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

// ── _ColMappingField ──────────────────────────────────────────────────────────

class _ColMappingField extends StatelessWidget {
  const _ColMappingField({
    required this.controller,
    required this.placeholder,
    required this.onChanged,
  });
  final TextEditingController controller;
  final String placeholder;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.ctSurface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.ctBorder2),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(
            fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText),
        decoration: InputDecoration(
          hintText: placeholder,
          hintStyle: const TextStyle(
              fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText3),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

// ── _DropdownContainer ────────────────────────────────────────────────────────

class _DropdownContainer extends StatelessWidget {
  const _DropdownContainer({required this.child});
  final Widget child;

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
      child: child,
    );
  }
}

// ── Shared form widgets ───────────────────────────────────────────────────────

class _FormField extends StatelessWidget {
  const _FormField({
    required this.label,
    required this.controller,
    required this.placeholder,
    // ignore: unused_element_parameter
    this.subtitle,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final String placeholder;
  final String? subtitle;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Geist',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.ctText,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 11,
              color: AppColors.ctText3,
            ),
          ),
        ],
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          minLines: maxLines,
          style: const TextStyle(
            fontFamily: 'Geist',
            fontSize: 13,
            color: AppColors.ctText,
          ),
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 13,
              color: AppColors.ctText3,
            ),
            filled: true,
            fillColor: AppColors.ctSurface2,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

class _FieldKeyPreview extends StatelessWidget {
  const _FieldKeyPreview({required this.fieldKey, required this.valid});
  final String fieldKey;
  final bool valid;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          valid ? Icons.check_circle_outline : Icons.warning_amber_outlined,
          size: 13,
          color: valid ? const Color(0xFF107C41) : const Color(0xFFE24C4B),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            valid ? fieldKey : (fieldKey.isEmpty ? 'Clave inválida' : 'Clave inválida: "$fieldKey"'),
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 12,
              color: valid ? const Color(0xFF107C41) : const Color(0xFFE24C4B),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onTap,
    this.enabled = true,
  });
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.ctTeal,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.ctNavy,
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
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.ctBorder2),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Geist',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.ctText2,
          ),
        ),
      ),
    );
  }
}
