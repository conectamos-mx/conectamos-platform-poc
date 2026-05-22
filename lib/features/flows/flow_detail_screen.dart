import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/catalogs_api.dart';
import '../../core/api/channels_api.dart';
import '../../core/api/flows_api.dart';
import '../../shared/widgets/asset_item_selector.dart';
import '../../core/api/operator_roles_api.dart';
import '../../core/constants/field_types.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_badge.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_dropdown.dart';
import '../../shared/widgets/app_multi_select.dart';
import '../../shared/widgets/app_text_field.dart';

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
    case 'asset_ref':
      return Icons.inventory_2_outlined;
    default:
      return Icons.short_text;
  }
}

const _kTimezones = [
  ('', 'Default del tenant'),
  ('America/Mexico_City',             'México (Ciudad de México)'),
  ('America/Monterrey',               'México (Monterrey)'),
  ('America/Bogota',                  'Colombia (Bogotá)'),
  ('America/Lima',                    'Perú (Lima)'),
  ('America/Santiago',                'Chile (Santiago)'),
  ('America/Argentina/Buenos_Aires',  'Argentina (Buenos Aires)'),
  ('America/New_York',                'EE.UU. (Nueva York)'),
  ('America/Los_Angeles',             'EE.UU. (Los Ángeles)'),
  ('UTC',                             'UTC'),
];

const _kTriggerSources = [
  ('conversational', 'Conversacional'),
  ('api', 'API / Sistema'),
  ('dashboard', 'Dashboard'),
  ('scheduled', 'Programado'),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class FlowDetailPanel extends ConsumerStatefulWidget {
  const FlowDetailPanel({super.key, required this.flowId, required this.onBack});
  final String flowId;
  final VoidCallback onBack;

  @override
  ConsumerState<FlowDetailPanel> createState() => _FlowDetailPanelState();
}

class _FlowDetailPanelState extends ConsumerState<FlowDetailPanel>
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
  Map<String, dynamic> _proactiveTrigger = {};

  // Al cerrar tab state
  List<Map<String, dynamic>> _actions = [];

  // Precondiciones tab state
  List<Map<String, dynamic>> _precondiciones = [];

  // Roles autorizados
  List<String> _allowedRoleIds = [];
  List<Map<String, dynamic>> _availableRoles = [];

  // Worker flows (for delete reference check)
  List<Map<String, dynamic>> _workerFlows = [];

  // Delete modal state
  bool _showDeleteModal = false;
  bool _deleting = false;
  final _deleteConfirmCtrl = TextEditingController();

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
    _deleteConfirmCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(FlowDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flowId != widget.flowId) _load();
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
      final proactiveTrigger = rawBehavior['proactive_trigger'] is Map
          ? Map<String, dynamic>.from(
              rawBehavior['proactive_trigger'] as Map)
          : <String, dynamic>{};
      final rawOnComplete =
          (flow['on_complete'] as Map<String, dynamic>?) ?? {};
      final actions = List<Map<String, dynamic>>.from(
          (rawOnComplete['actions'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e)));
      final rawPrec = flow['preconditions'];
      final precondiciones = rawPrec is List
          ? List<Map<String, dynamic>>.from(
              rawPrec.whereType<Map>().map((e) => Map<String, dynamic>.from(e)))
          : <Map<String, dynamic>>[];

      setState(() {
        _flow = flow;
        _fields = fields;
        _triggerSources = sources;
        _conditions = conditions;
        _proactiveTrigger = proactiveTrigger;
        _actions = actions;
        _precondiciones = precondiciones;
        _sendProactive = (flow['send_proactive'] as bool?) ?? true;
        _allowedRoleIds = List<String>.from(
            (flow['allowed_role_ids'] as List? ?? []).map((e) => e.toString()));
        _availableRoles = roles;
        _nameCtrl.text = flow['name'] as String? ?? '';
        _descCtrl.text = flow['description'] as String? ?? '';
        _loading = false;
      });
      _loadWorkerFlows();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _dioError(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadWorkerFlows() async {
    final twId = _flow?['tenant_worker_id'] as String? ?? '';
    if (twId.isEmpty) return;
    try {
      final flows = await FlowsApi.getFlowsByWorker(tenantWorkerId: twId);
      if (mounted) setState(() => _workerFlows = flows);
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
        behavior: {
          'conditions': _conditions,
          if (_proactiveTrigger.isNotEmpty)
            'proactive_trigger': _proactiveTrigger,
        },
        onComplete: {'actions': _actions},
        triggerSources: _triggerSources,
        sendProactive: _sendProactive,
        allowedRoleIds: _allowedRoleIds,
        preconditions: _precondiciones,
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
      final updatedProactiveTrigger = rawBeh['proactive_trigger'] is Map
          ? Map<String, dynamic>.from(rawBeh['proactive_trigger'] as Map)
          : <String, dynamic>{};
      final rawOC = (updated['on_complete'] as Map<String, dynamic>?) ?? {};
      final updatedActions = List<Map<String, dynamic>>.from(
          (rawOC['actions'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e)));
      final rawUpdPrec = updated['preconditions'];
      final updatedPrecondiciones = rawUpdPrec is List
          ? List<Map<String, dynamic>>.from(
              rawUpdPrec.whereType<Map>().map((e) => Map<String, dynamic>.from(e)))
          : _precondiciones;
      setState(() {
        _flow = updated;
        _fields = fields;
        _conditions = updatedConditions;
        _proactiveTrigger = updatedProactiveTrigger;
        _actions = updatedActions;
        _precondiciones = updatedPrecondiciones;
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
          style: AppTextStyles.pageTitle,
        ),
        content: Text(
          '¿Eliminar el campo "$label"? Esta acción no se puede deshacer.',
          style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
        ),
        actions: [
          AppButton(
            label: 'Cancelar',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: () => Navigator.pop(ctx),
          ),
          AppButton(
            label: 'Eliminar',
            variant: AppButtonVariant.danger,
            size: AppButtonSize.sm,
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _fields.removeAt(index));
              _save(silent: true);
            },
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
        flowFields: _fields.where((f) => f['id'] != field?['id']).toList(),
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

  Future<void> _toggleActive() async {
    final current = _flow?['is_active'] as bool? ?? false;
    try {
      final updated = await FlowsApi.updateFlow(
        flowId: widget.flowId,
        isActive: !current,
      );
      if (!mounted) return;
      setState(() => _flow = updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_dioError(e)), backgroundColor: AppColors.ctDanger,
      ));
    }
  }

  List<String> _computeReferencingFlows() {
    final currentSlug = _flow?['slug'] as String? ?? '';
    final refs = <String>[];
    for (final f in _workerFlows) {
      if ((f['slug'] as String?) == currentSlug) continue;
      final precs = (f['preconditions'] as List? ?? []);
      for (final p in precs) {
        final pMap = p as Map?;
        final params = (pMap?['params'] ?? pMap?['config']) as Map? ?? {};
        final slugVal = params['sibling_slug'] as String?
            ?? params['flow_slug'] as String?
            ?? params['parent_flow_slug'] as String?
            ?? params['child_flow_slug'] as String? ?? '';
        if (slugVal == currentSlug) {
          refs.add(f['name'] as String? ?? f['slug'] as String? ?? '');
        }
      }
      final onComplete = (f['on_complete'] as Map<String, dynamic>?) ?? {};
      final actions = (onComplete['actions'] as List? ?? []);
      for (final a in actions) {
        final aMap = a as Map? ?? {};
        final slugVal = aMap['target_flow_slug'] as String?
            ?? aMap['flow_slug'] as String? ?? '';
        if (slugVal == currentSlug) {
          refs.add(f['name'] as String? ?? f['slug'] as String? ?? '');
        }
      }
    }
    return refs.toSet().toList();
  }

  Future<void> _executeDelete() async {
    setState(() => _deleting = true);
    try {
      await FlowsApi.deleteFlow(flowId: widget.flowId);
      if (!mounted) return;
      setState(() => _showDeleteModal = false);
      widget.onBack();
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      final isDio = e is DioException;
      final msg = isDio && e.response?.statusCode == 409
          ? 'Este flujo tiene ejecuciones activas y no puede eliminarse'
          : _dioError(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: AppColors.ctDanger,
      ));
    }
  }

  Future<void> _saveWithResult({List<String>? triggerSources}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await FlowsApi.updateFlow(
        flowId: widget.flowId,
        name: _nameCtrl.text.trim(),
        slug: _derivedSlug,
        description: _descCtrl.text.trim(),
        fields: _fields,
        behavior: {
          'conditions': _conditions,
          if (_proactiveTrigger.isNotEmpty)
            'proactive_trigger': _proactiveTrigger,
        },
        onComplete: {'actions': _actions},
        triggerSources: triggerSources ?? _triggerSources,
        sendProactive: _sendProactive,
        allowedRoleIds: _allowedRoleIds,
        preconditions: _precondiciones,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _parseTriggerError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      final detail = data is Map ? data['detail'] as String? ?? '' : '';
      if (detail.contains('scheduled') && detail.contains('proactive_trigger')) {
        return 'Para usar el trigger "Programado" primero configura '
            'la plantilla de WhatsApp en la tab Comportamiento.';
      }
      if (detail.isNotEmpty) return detail;
    }
    return 'No se pudo actualizar el trigger. Intenta de nuevo.';
  }

  Widget _buildDeleteModal() {
    final flowName = _flow?['name'] as String? ?? 'este flujo';
    final canConfirm = _deleteConfirmCtrl.text.trim() == flowName;
    final referencingFlows = _computeReferencingFlows();

    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          color: AppColors.ctDanger.withValues(alpha: 0.08),
          child: Center(
            child: Container(
              width: 500,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.ctSurface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.ctDanger.withValues(alpha: 0.15),
                    blurRadius: 32,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.ctRedBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.warning_amber_rounded,
                              color: AppColors.ctDanger, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('¿Eliminar "$flowName"?',
                                  style: AppTextStyles.cardTitle),
                              const SizedBox(height: 2),
                              Text(
                                'Esta acción es permanente e irreversible.',
                                style: AppTextStyles.bodySmall
                                    .copyWith(color: AppColors.ctText2),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18,
                              color: AppColors.ctText2),
                          onPressed: () => setState(() {
                            _showDeleteModal = false;
                            _deleteConfirmCtrl.clear();
                          }),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.ctBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Qué ocurrirá:',
                              style: AppTextStyles.bodySmall.copyWith(
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 10),
                          _ImpactRow(
                            icon: Icons.check_circle_outline,
                            color: AppColors.ctOk,
                            text: 'Las ejecuciones existentes no se verán afectadas '
                                '(mantienen la estructura del flujo guardada).',
                          ),
                          const SizedBox(height: 8),
                          _ImpactRow(
                            icon: Icons.block_outlined,
                            color: AppColors.ctDanger,
                            text: 'No se podrán iniciar nuevas ejecuciones de este flujo.',
                          ),
                          const SizedBox(height: 8),
                          _ImpactRow(
                            icon: Icons.warning_amber_rounded,
                            color: AppColors.ctWarn,
                            text: 'Las ejecuciones activas en curso serán bloqueadas '
                                'si el flujo tiene ejecuciones activas.',
                          ),
                          if (referencingFlows.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _ImpactRow(
                              icon: Icons.link_off_rounded,
                              color: AppColors.ctDanger,
                              text: 'Los siguientes flujos referencian este flujo y '
                                  'fallarán silenciosamente: '
                                  '${referencingFlows.join(", ")}.',
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.ctRedBg.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.ctDanger.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.ctSurface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.ctBorder),
                            ),
                            child: const Icon(Icons.account_tree_outlined,
                                size: 18, color: AppColors.ctText2),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(flowName,
                                    style: AppTextStyles.body
                                        .copyWith(fontWeight: FontWeight.w600)),
                                Text(
                                  _flow?['slug'] as String? ?? '',
                                  style: AppTextStyles.caption
                                      .copyWith(color: AppColors.ctText3,
                                          fontFamily: 'Geist'),
                                ),
                              ],
                            ),
                          ),
                          _MetricRow(
                            label: 'Ejecuciones',
                            value: (_flow?['execution_count'] as int? ?? 0)
                                .toString(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Escribe "$flowName" para confirmar:',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.ctText2),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _deleteConfirmCtrl,
                      autofocus: true,
                      style: AppTextStyles.body,
                      decoration: InputDecoration(
                        hintText: flowName,
                        hintStyle: AppTextStyles.body
                            .copyWith(color: AppColors.ctText3),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: AppColors.ctBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: AppColors.ctBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                              color: AppColors.ctDanger, width: 1.5),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        AppButton(
                          label: 'Cancelar',
                          variant: AppButtonVariant.ghost,
                          size: AppButtonSize.sm,
                          onPressed: () => setState(() {
                            _showDeleteModal = false;
                            _deleteConfirmCtrl.clear();
                          }),
                        ),
                        const SizedBox(width: 10),
                        AppButton(
                          label: _deleting
                              ? 'Eliminando...'
                              : 'Sí, eliminar "$flowName"',
                          variant: AppButtonVariant.danger,
                          size: AppButtonSize.sm,
                          isDisabled: !canConfirm || _deleting,
                          isLoading: _deleting,
                          onPressed: canConfirm ? _executeDelete : () {},
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.ctTeal));
    }
    if (_error != null || _flow == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.ctDanger),
            const SizedBox(height: 12),
            Text(_error ?? 'No se encontró el flujo',
                style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            AppButton(label: 'Reintentar', variant: AppButtonVariant.ghost,
                size: AppButtonSize.sm, onPressed: _load),
          ],
        ),
      );
    }
    final canManage = hasPermission(ref, 'flows', 'manage');
    return Stack(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
        _FlowSidePanel(
          flow: _flow!,
          isActive: _flow!['is_active'] as bool? ?? false,
          saving: _saving,
          onBack: widget.onBack,
          onToggleActive: _toggleActive,
          onDelete: () {
            _deleteConfirmCtrl.clear();
            setState(() => _showDeleteModal = true);
          },
          triggerSources: _triggerSources,
          onTriggerSourcesChanged: (updated) async {
            final previous = List<String>.from(_triggerSources);
            setState(() => _triggerSources = updated);
            try {
              await _saveWithResult(triggerSources: updated);
            } catch (e) {
              if (mounted) setState(() => _triggerSources = previous);
              final msg = _parseTriggerError(e);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(msg),
                  backgroundColor: AppColors.ctDanger,
                  duration: const Duration(seconds: 4),
                  action: SnackBarAction(
                    label: 'Ir a Comportamiento',
                    textColor: Colors.white,
                    onPressed: () => _tabCtrl.animateTo(1),
                  ),
                ));
              }
            }
          },
        ),
        Container(width: 1, color: AppColors.ctBorder),
        Expanded(
          child: Column(
            children: [
              Container(
                color: AppColors.ctSurface,
                child: Column(
                  children: [
                    const Divider(height: 1, color: AppColors.ctBorder),
                    TabBar(
                      controller: _tabCtrl,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      dividerColor: Colors.transparent,
                      labelStyle: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                      unselectedLabelStyle: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
                      labelColor: AppColors.ctTeal,
                      unselectedLabelColor: AppColors.ctText2,
                      indicatorColor: AppColors.ctTeal,
                      indicatorWeight: 2,
                      tabs: const [
                        Tab(text: 'Campos'),
                        Tab(text: 'Comportamiento'),
                        Tab(text: 'Precondiciones'),
                        Tab(text: 'Al cerrar'),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _CamposTab(
                      fields: _fields,
                      canManage: canManage,
                      onReorder: _onReorder,
                      onEditField: (field, index) => _openFieldDialog(field: field, index: index),
                      onDeleteField: (field, index) => _confirmDeleteField(field, index),
                      onAddField: () => _openFieldDialog(),
                    ),
                    _ComportamientoTab(
                      conditions: _conditions,
                      flowFields: _fields,
                      canManage: canManage,
                      triggerSources: _triggerSources,
                      flowId: widget.flowId,
                      tenantId: ref.read(activeTenantIdProvider),
                      tenantWorkerId: _flow!['tenant_worker_id'] as String? ?? '',
                      sendProactive: _sendProactive,
                      proactiveTrigger: _proactiveTrigger,
                      availableRoles: _availableRoles,
                      allowedRoleIds: _allowedRoleIds,
                      onChanged: (updated) { setState(() => _conditions = updated); _save(silent: true); },
                      onAllowedRoleIdsChanged: (updated) { setState(() => _allowedRoleIds = updated); _save(silent: true); },
                      onProactiveTriggerChanged: (updated) { setState(() => _proactiveTrigger = updated); _save(silent: true); },
                      onSendProactiveChanged: (value) => setState(() => _sendProactive = value),
                    ),
                    _PrecondicionesTab(
                      rules: _precondiciones,
                      canManage: canManage,
                      availableRoles: _availableRoles,
                      tenantId: ref.read(activeTenantIdProvider),
                      tenantWorkerId: _flow!['tenant_worker_id'] as String? ?? '',
                      currentFlowSlug: _flow!['slug'] as String? ?? '',
                      onChanged: (updated) { setState(() => _precondiciones = updated); _save(silent: true); },
                    ),
                    _AlCerrarTab(
                      actions: _actions,
                      canManage: canManage,
                      tenantId: ref.read(activeTenantIdProvider),
                      tenantWorkerId: _flow!['tenant_worker_id'] as String? ?? '',
                      currentFlowSlug: _flow!['slug'] as String? ?? '',
                      flowFields: _fields,
                      onChanged: (updated) { setState(() => _actions = updated); _save(silent: true); },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
          ],
        ),
        if (_showDeleteModal) _buildDeleteModal(),
      ],
    );
  }
}

// ── _FlowSidePanel ────────────────────────────────────────────────────────────

class _FlowSidePanel extends StatefulWidget {
  const _FlowSidePanel({
    required this.flow,
    required this.isActive,
    required this.saving,
    required this.onBack,
    required this.onToggleActive,
    required this.onDelete,
    required this.triggerSources,
    required this.onTriggerSourcesChanged,
  });

  final Map<String, dynamic> flow;
  final bool isActive;
  final bool saving;
  final VoidCallback onBack;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;
  final List<String> triggerSources;
  final ValueChanged<List<String>> onTriggerSourcesChanged;

  @override
  State<_FlowSidePanel> createState() => _FlowSidePanelState();
}

class _FlowSidePanelState extends State<_FlowSidePanel> {
  late List<String> _triggerSources;

  @override
  void initState() {
    super.initState();
    _triggerSources = List.from(widget.triggerSources);
  }

  @override
  void didUpdateWidget(_FlowSidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.triggerSources, widget.triggerSources)) {
      setState(() => _triggerSources = List.from(widget.triggerSources));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
          width: 220,
          color: AppColors.ctSurface2,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Botón volver
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: widget.onBack,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: AppColors.ctNavy,
                              border: Border.all(color: AppColors.ctNavy),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('← Volver a flujos',
                                style: AppTextStyles.bodySmall.copyWith(color: Colors.white)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 2. Nombre — solo lectura
                      Text(
                        widget.flow['name'] as String? ?? '—',
                        style: AppTextStyles.cardTitle,
                      ),
                      const SizedBox(height: 6),

                      // 3. Slug — solo lectura, copiable
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: widget.flow['slug'] as String? ?? ''));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Slug copiado'),
                            duration: Duration(seconds: 2),
                            backgroundColor: AppColors.ctOk,
                          ));
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.ctSurface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.ctBorder),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.flow['slug'] as String? ?? '—',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.ctText3,
                                      fontFamily: 'Geist',
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(Icons.copy_rounded, size: 12, color: AppColors.ctText3),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // 4. Descripción — solo lectura
                      if ((widget.flow['description'] as String?)?.isNotEmpty == true)
                        Text(
                          widget.flow['description'] as String,
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2),
                        )
                      else
                        Text(
                          'Sin descripción',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
                        ),
                      const SizedBox(height: 20),

                      const Divider(color: AppColors.ctBorder, height: 1),
                      const SizedBox(height: 16),

                      // 5. ESTADO
                      Text('ESTADO', style: AppTextStyles.kpiLabel),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          AppBadge(
                            label: widget.isActive ? 'Activo' : 'Inactivo',
                            variant: widget.isActive ? AppBadgeVariant.ok : AppBadgeVariant.neutral,
                          ),
                          const Expanded(child: SizedBox()),
                          Switch(
                            value: widget.isActive,
                            onChanged: (_) => widget.onToggleActive(),
                            activeThumbColor: AppColors.ctTeal,
                            activeTrackColor: AppColors.ctTealLight,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 6. TRIGGERS — editables
                      Text('TRIGGERS', style: AppTextStyles.kpiLabel),
                      const SizedBox(height: 8),
                      Text(
                        '¿Desde dónde puede iniciarse este flujo?',
                        style: AppTextStyles.caption.copyWith(color: AppColors.ctText3),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _kTriggerSources.map((entry) {
                          final (value, label) = entry;
                          final selected = _triggerSources.contains(value);
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                if (selected) {
                                  if (_triggerSources.length > 1) {
                                    _triggerSources.remove(value);
                                  }
                                } else {
                                  _triggerSources.add(value);
                                }
                              });
                              widget.onTriggerSourcesChanged(List.from(_triggerSources));
                            },
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: selected ? AppColors.ctTealLight : AppColors.ctSurface,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: selected ? AppColors.ctTeal : AppColors.ctBorder,
                                  ),
                                ),
                                child: Text(
                                  label,
                                  style: AppTextStyles.caption.copyWith(
                                    color: selected ? AppColors.ctTealDark : AppColors.ctText2,
                                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      const Divider(color: AppColors.ctBorder, height: 1),
                      const SizedBox(height: 16),

                      // 7. MÉTRICAS
                      Text('MÉTRICAS', style: AppTextStyles.kpiLabel),
                      const SizedBox(height: 10),
                      _MetricRow(
                        label: 'Ejecuciones totales',
                        value: (widget.flow['execution_count'] as int? ?? 0).toString(),
                      ),
                      const SizedBox(height: 6),
                      _MetricRow(
                        label: 'Campos configurados',
                        value: ((widget.flow['fields'] as List?)?.length ?? 0).toString(),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              // 8. Botón eliminar — fuera del scroll
              Padding(
                padding: const EdgeInsets.all(16),
                child: AppButton(
                  label: 'Eliminar flujo',
                  variant: AppButtonVariant.danger,
                  size: AppButtonSize.sm,
                  expand: true,
                  onPressed: widget.onDelete,
                ),
              ),
            ],
          ),
        );
  }
}

// ── _MetricRow ────────────────────────────────────────────────────────────────

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2)),
      Text(value, style: AppTextStyles.body.copyWith(
          fontWeight: FontWeight.w700, color: AppColors.ctTeal)),
    ],
  );
}

// ── _ImpactRow ───────────────────────────────────────────────────────────────

class _ImpactRow extends StatelessWidget {
  const _ImpactRow({
    required this.icon,
    required this.color,
    required this.text,
  });
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(text,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2)),
      ),
    ],
  );
}

// ── _InfoTab ──────────────────────────────────────────────────────────────────

// DEPRECATED — sesión 2026-05-21. Contenido migrado a _FlowSidePanel.
// ignore: unused_element
class _InfoTab extends StatefulWidget {
  const _InfoTab({
    required this.flow,
    required this.nameCtrl,
    required this.descCtrl,
    required this.canManage,
    required this.triggerSources,
    required this.onTriggerToggle,
    required this.onDelete,
  });

  final Map<String, dynamic> flow;
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final bool canManage;
  final List<String> triggerSources;
  final void Function(String source) onTriggerToggle;
  final VoidCallback onDelete;

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
              Text(
                'Slug',
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
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
                        style: AppTextStyles.body.copyWith(
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
                  style: AppTextStyles.bodySmall.copyWith(
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

          if (widget.canManage) ...[
            const Divider(color: AppColors.ctBorder),
            const SizedBox(height: 16),
            AppButton(
              label: 'Eliminar flujo',
              variant: AppButtonVariant.danger,
              size: AppButtonSize.sm,
              prefixIcon: const Icon(Icons.delete_outline, size: 14, color: Colors.white),
              onPressed: widget.onDelete,
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
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (canManage)
                  AppButton(
                    label: '+ Agregar campo',
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.sm,
                    onPressed: onAddField,
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

    final typeLabel = kFieldTypes
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
                        style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
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
                    child: Text(
                      'Requerido',
                      style: AppTextStyles.kpiLabel.copyWith(color: AppColors.ctTealDark),
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
    required this.flowFields,
    this.field,
  });

  final Map<String, dynamic>? field;
  final String tenantId;
  final String tenantWorkerId;
  final List<Map<String, dynamic>> flowFields;
  final void Function(Map<String, dynamic>) onSaved;

  @override
  State<_FieldDialog> createState() => _FieldDialogState();
}

// Data source options for select fields
const _kDataSources = [
  ('static', 'Opciones estáticas'),
  ('system:operators', 'Operadores del tenant'),
];

class _FieldDialogState extends State<_FieldDialog> {
  final _labelCtrl = TextEditingController();
  String _type = 'text';
  bool _required = false;

  // select type state
  String _dataSourceBase = 'system:operators';

  // static options state
  List<String> _staticOptions = [];
  final _optionCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  // asset_ref type state
  String? _catalogSlug;
  List<Map<String, dynamic>> _availableCatalogs = [];
  bool _loadingCatalogs = false;
  String? _selectedItemId;
  String? _selectedItemDisplay;

  // show_if condition state
  String? _showIfField;
  String? _showIfOp;
  String? _showIfRefType;
  final _showIfValueCtrl = TextEditingController();
  List<String> _showIfValues = []; // for op in/not_in

  bool get _isEdit => widget.field != null;
  bool get _assetRefValid => _type != 'asset_ref' || _catalogSlug != null;

  String get _fieldKey => _fieldKeyify(_labelCtrl.text.trim());
  bool get _fieldKeyValid => _fieldKey.length >= 2;

  bool get _selectValid =>
      _type != 'select' ||
      (_dataSourceBase == 'static'
          ? _staticOptions.isNotEmpty
          : _dataSourceBase == 'system:operators');

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
        // Migrate legacy operators_with_flow to system:operators
        if (ds.startsWith('system:operators_with_flow')) {
          _dataSourceBase = 'system:operators';
        } else {
          _dataSourceBase = ds;
        }
      }
      final rawOpts = widget.field!['options'];
      if (rawOpts is List) {
        _staticOptions = List<String>.from(rawOpts.map((e) => e.toString()));
      }
      if (_staticOptions.isNotEmpty && ds == null) _dataSourceBase = 'static';
    }
    _catalogSlug = widget.field?['catalog_slug'] as String?;
    _selectedItemId = widget.field?['item_id'] as String?;
    _selectedItemDisplay = widget.field?['item_display'] as String?;
    final showIf = widget.field?['show_if'] as Map<String, dynamic>?;
    if (showIf != null) {
      _showIfField = showIf['field'] as String?;
      _showIfOp = showIf['op'] as String?;
      final rawValue = showIf['value'];
      if (_showIfOp == 'in' || _showIfOp == 'not_in') {
        if (rawValue is List) {
          _showIfValues = List<String>.from(rawValue.map((e) => e.toString()));
        } else if (rawValue is String && rawValue.isNotEmpty) {
          _showIfValues = rawValue.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        }
      } else {
        _showIfValueCtrl.text = rawValue as String? ?? '';
      }
      if (_showIfField != null) {
        final ref = widget.flowFields.where((f) => f['key'] == _showIfField).firstOrNull;
        _showIfRefType = ref?['type'] as String?;
      }
    }
    _labelCtrl.addListener(_onLabelChanged);
    if (_type == 'asset_ref') _loadCatalogs();
  }

  void _onLabelChanged() => setState(() {});

  Future<void> _loadCatalogs() async {
    if (_loadingCatalogs) return;
    setState(() => _loadingCatalogs = true);
    try {
      final cats = await CatalogsApi.listCatalogs(tenantId: widget.tenantId);
      if (!mounted) return;
      setState(() => _availableCatalogs = cats);
    } catch (_) {
      if (!mounted) return;
      setState(() => _availableCatalogs = []);
    } finally {
      if (mounted) setState(() => _loadingCatalogs = false);
    }
  }

  @override
  void dispose() {
    _labelCtrl.removeListener(_onLabelChanged);
    _labelCtrl.dispose();
    _optionCtrl.dispose();
    _descCtrl.dispose();
    _showIfValueCtrl.dispose();
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
    if (label.isEmpty || !_fieldKeyValid || !_selectValid || !_assetRefValid) return;

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
      } else {
        updated['data_source'] = _dataSourceBase;
        updated.remove('options');
      }
    } else {
      updated.remove('data_source');
      updated.remove('options');
    }
    updated.remove('fill_strategy');
    if (_type == 'asset_ref') {
      updated['catalog_slug'] = _catalogSlug;
      if (_selectedItemId != null) {
        updated['item_id'] = _selectedItemId;
        updated['item_display'] = _selectedItemDisplay;
      } else {
        updated.remove('item_id');
        updated.remove('item_display');
      }
    } else {
      updated.remove('catalog_slug');
      updated.remove('item_id');
      updated.remove('item_display');
    }
    if (_showIfField != null && _showIfOp != null) {
      final isMultiOp = _showIfOp == 'in' || _showIfOp == 'not_in';
      updated['show_if'] = {
        'field': _showIfField,
        'op': _showIfOp,
        'value': isMultiOp ? _showIfValues : _showIfValueCtrl.text.trim(),
      };
    } else {
      updated.remove('show_if');
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
                style: AppTextStyles.pageTitle,
              ),
              const SizedBox(height: 20),

              // Label
              Row(
                children: [
                  Text('Etiqueta', style: AppTextStyles.formLabel),
                  const SizedBox(width: 4),
                  Text('*', style: AppTextStyles.formLabel.copyWith(color: AppColors.ctDanger)),
                ],
              ),
              const SizedBox(height: 6),
              _FormField(
                label: '',
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
              Text(
                'Contexto para el asistente',
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                'Describe cómo el operador se refiere a este dato. '
                'Tu Worker lo usa para identificar y capturar el campo correctamente.',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
              ),
              const SizedBox(height: 6),
              AppTextField(
                controller: _descCtrl,
                hint: 'Opcional — ej: "número de seguimiento", "guía del paquete"',
                maxLines: 3,
              ),
              const SizedBox(height: 14),

              // Type
              Row(
                children: [
                  Text('Tipo', style: AppTextStyles.formLabel),
                  const SizedBox(width: 4),
                  Text('*', style: AppTextStyles.formLabel.copyWith(color: AppColors.ctDanger)),
                ],
              ),
              const SizedBox(height: 6),
              AppDropdown<String>(
                value: _type,
                hint: 'Selecciona un tipo',
                items: kFieldTypes.map((entry) {
                  final (value, label) = entry;
                  return AppDropdownItem<String>(
                    value: value,
                    label: label,
                    icon: _fieldIcon(value),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _type = v;
                      if (v != 'asset_ref') {
                        _catalogSlug = null;
                        _selectedItemId = null;
                        _selectedItemDisplay = null;
                      }
                    });
                    if (v == 'asset_ref' && _availableCatalogs.isEmpty) {
                      _loadCatalogs();
                    }
                  }
                },
              ),

              // Data source (select type only)
              if (_type == 'select') ...[
                const SizedBox(height: 14),
                AppDropdown<String>(
                  label: 'Fuente de datos',
                  value: _dataSourceBase,
                  hint: 'Selecciona fuente',
                  items: _kDataSources.map((entry) {
                    final (value, label) = entry;
                    return AppDropdownItem<String>(value: value, label: label);
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _dataSourceBase = v);
                  },
                ),
              ],

              // Static options (select + static source only)
              if (_type == 'select' && _dataSourceBase == 'static') ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text('Opciones', style: AppTextStyles.formLabel),
                    const SizedBox(width: 4),
                    Text('*', style: AppTextStyles.formLabel.copyWith(color: AppColors.ctDanger)),
                  ],
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
                          decoration: InputDecoration(
                            hintText: 'Nueva opción...',
                            hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
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

              // Catalog selector (asset_ref type only)
              if (_type == 'asset_ref') ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text('Catálogo', style: AppTextStyles.formLabel),
                    const SizedBox(width: 4),
                    Text('*', style: AppTextStyles.formLabel.copyWith(color: AppColors.ctDanger)),
                  ],
                ),
                const SizedBox(height: 6),
                if (_loadingCatalogs)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: CircularProgressIndicator(
                          color: AppColors.ctTeal, strokeWidth: 2),
                    ),
                  )
                else if (_availableCatalogs.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.ctBorder),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'No hay catálogos configurados. Crea uno en Catálogos.',
                      style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                    ),
                  )
                else
                  AppDropdown<String>(
                    value: _catalogSlug,
                    hint: 'Selecciona un catálogo',
                    errorText: _catalogSlug == null && !_assetRefValid
                        ? 'Selecciona un catálogo'
                        : null,
                    items: _availableCatalogs.map((cat) {
                      final slug = cat['slug'] as String? ?? '';
                      final name = cat['name'] as String? ?? slug;
                      return AppDropdownItem<String>(value: slug, label: name);
                    }).toList(),
                    onChanged: (v) {
                      setState(() {
                        _catalogSlug = v;
                        _selectedItemId = null;
                        _selectedItemDisplay = null;
                      });
                    },
                  ),
              if (_catalogSlug != null) ...[
                const SizedBox(height: 10),
                const Text(
                  'Item predeterminado (opcional)',
                  style: AppTextStyles.btnSecondary,
                ),
                const SizedBox(height: 6),
                AssetItemSelector(
                  key: ValueKey(_catalogSlug),
                  catalogSlug: _catalogSlug!,
                  initialItemId: _selectedItemId,
                  initialDisplayText: _selectedItemDisplay,
                  onSelected: (item) {
                    setState(() {
                      _selectedItemId = item['item_id'] as String?;
                      _selectedItemDisplay = item['display_text'] as String?;
                    });
                  },
                ),
              ],
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
              const SizedBox(height: 8),

              // show_if condition
              if (widget.flowFields.isNotEmpty)
                Theme(
                  data: Theme.of(context).copyWith(
                    dividerColor: Colors.transparent,
                  ),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    initiallyExpanded: _showIfField != null,
                    title: Row(
                      children: [
                        const Icon(Icons.visibility_outlined,
                            size: 14, color: AppColors.ctText2),
                        const SizedBox(width: 6),
                        Text(
                          'Condición de visibilidad',
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w500,
                            color: AppColors.ctText2,
                          ),
                        ),
                        if (_showIfField != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.ctTeal.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'activa',
                              style: AppTextStyles.kpiLabel.copyWith(color: AppColors.ctTeal),
                            ),
                          ),
                        ],
                      ],
                    ),
                    children: [
                      const SizedBox(height: 8),
                      // Field selector
                      Text(
                        'Mostrar este campo solo si…',
                        style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      AppDropdown<String?>(
                        value: _showIfField,
                        hint: 'Selecciona un campo',
                        items: [
                          const AppDropdownItem<String?>(
                            value: null,
                            label: '— Sin condición —',
                          ),
                          ...widget.flowFields
                              .where((f) => !const ['photo', 'location']
                                  .contains(f['type'] as String? ?? ''))
                              .map((f) {
                            final key = f['key'] as String? ?? '';
                            final label = f['label'] as String? ?? key;
                            return AppDropdownItem<String?>(value: key, label: label);
                          }),
                        ],
                        onChanged: (v) {
                          final ref = v != null
                              ? widget.flowFields.where((f) => f['key'] == v).firstOrNull
                              : null;
                          setState(() {
                            _showIfField = v;
                            _showIfRefType = ref?['type'] as String?;
                            _showIfValueCtrl.text = '';
                            _showIfValues = [];
                            if (v == null) _showIfOp = null;
                          });
                        },
                      ),
                      if (_showIfField != null) ...[
                        const SizedBox(height: 8),
                        // Operator selector
                        AppDropdown<String>(
                          value: _showIfOp,
                          hint: 'Operador',
                          items: const [
                            AppDropdownItem(value: 'eq', label: 'es igual a'),
                            AppDropdownItem(value: 'neq', label: 'es distinto de'),
                            AppDropdownItem(value: 'in', label: 'está entre'),
                            AppDropdownItem(value: 'not_in', label: 'no está entre'),
                          ],
                          onChanged: (v) => setState(() {
                            _showIfOp = v;
                            _showIfValueCtrl.text = '';
                            _showIfValues = [];
                          }),
                        ),
                        const SizedBox(height: 8),
                        // Value input — type-aware + multi-select for in/not_in
                        if (_showIfOp == 'in' || _showIfOp == 'not_in')
                          Builder(builder: (_) {
                            final ref = widget.flowFields
                                .where((f) => f['key'] == _showIfField)
                                .firstOrNull;
                            final opts = (ref?['options'] as List? ?? [])
                                .map((e) => e.toString())
                                .toList();
                            if (opts.isEmpty) {
                              return AppTextField(
                                controller: _showIfValueCtrl,
                                hint: 'Valores separados por coma…',
                                helperText: 'Sin opciones definidas — escribe valores separados por coma',
                              );
                            }
                            return AppMultiSelect<String>(
                              items: opts
                                  .map((o) => AppMultiSelectItem(value: o, label: o))
                                  .toList(),
                              selectedValues: _showIfValues,
                              placeholder: 'Selecciona valores…',
                              onChanged: (vals) => setState(() => _showIfValues = vals),
                            );
                          })
                        else if (_showIfRefType == 'bool')
                          AppDropdown<String>(
                            value: _showIfValueCtrl.text.isEmpty
                                ? null
                                : _showIfValueCtrl.text,
                            hint: 'Valor',
                            items: const [
                              AppDropdownItem(value: 'true', label: 'Sí / Verdadero'),
                              AppDropdownItem(value: 'false', label: 'No / Falso'),
                            ],
                            onChanged: (v) => setState(() {
                              _showIfValueCtrl.text = v ?? '';
                            }),
                          )
                        else if (_showIfRefType == 'select')
                          Builder(builder: (_) {
                            final ref = widget.flowFields
                                .where((f) => f['key'] == _showIfField)
                                .firstOrNull;
                            final opts = (ref?['options'] as List? ?? [])
                                .map((e) => e.toString())
                                .toList();
                            if (opts.isEmpty) {
                              return AppTextField(
                                controller: _showIfValueCtrl,
                                hint: 'Valor…',
                              );
                            }
                            return AppDropdown<String>(
                              value: _showIfValueCtrl.text.isEmpty
                                  ? null
                                  : _showIfValueCtrl.text,
                              hint: 'Selecciona un valor',
                              items: opts
                                  .map((o) => AppDropdownItem(value: o, label: o))
                                  .toList(),
                              onChanged: (v) => setState(() {
                                _showIfValueCtrl.text = v ?? '';
                              }),
                            );
                          })
                        else if (_showIfRefType == 'photo')
                          AppTextField(
                            controller: _showIfValueCtrl,
                            hint: 'No disponible',
                            enabled: false,
                            helperText: 'No es posible condicionar visibilidad por foto',
                          )
                        else if (_showIfRefType == 'number')
                          AppTextField(
                            controller: _showIfValueCtrl,
                            hint: 'Valor numérico…',
                            keyboardType: TextInputType.number,
                          )
                        else
                          AppTextField(
                            controller: _showIfValueCtrl,
                            hint: 'Valor…',
                          ),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
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
    required this.tenantWorkerId,
    required this.sendProactive,
    required this.proactiveTrigger,
    required this.availableRoles,
    required this.allowedRoleIds,
    required this.onChanged,
    required this.onAllowedRoleIdsChanged,
    required this.onProactiveTriggerChanged,
    required this.onSendProactiveChanged,
  });

  final List<Map<String, dynamic>> conditions;
  final List<Map<String, dynamic>> flowFields;
  final bool canManage;
  final List<String> triggerSources;
  final String flowId;
  final String tenantId;
  final String tenantWorkerId;
  final bool sendProactive;
  final Map<String, dynamic> proactiveTrigger;
  final List<Map<String, dynamic>> availableRoles;
  final List<String> allowedRoleIds;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final ValueChanged<List<String>> onAllowedRoleIdsChanged;
  final ValueChanged<Map<String, dynamic>> onProactiveTriggerChanged;
  final ValueChanged<bool> onSendProactiveChanged;

  @override
  State<_ComportamientoTab> createState() => _ComportamientoTabState();
}

class _ComportamientoTabState extends State<_ComportamientoTab> {
  late List<Map<String, dynamic>> _conditions;
  late bool _sendProactive;
  late List<String> _allowedRoleIds;
  bool _savingProactive = false;

  // Proactive trigger state
  String? _waChannelId;
  List<Map<String, dynamic>> _approvedTemplates = [];
  bool _loadingTemplates = false;
  // Each row: (variableCtrl, sourceCtrl)
  List<(TextEditingController, TextEditingController)> _mappingRows = [];

  @override
  void initState() {
    super.initState();
    _conditions = List.from(widget.conditions);
    _sendProactive = widget.sendProactive;
    _allowedRoleIds = List.from(widget.allowedRoleIds);
    if (widget.triggerSources.contains('scheduled') &&
        widget.tenantWorkerId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadWaChannel();
        _initMappingRows();
      });
    }
  }

  @override
  void dispose() {
    for (final row in _mappingRows) {
      row.$1.dispose();
      row.$2.dispose();
    }
    super.dispose();
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
    // When scheduled trigger is added, load WA channel
    final wasScheduled = old.triggerSources.contains('scheduled');
    final isScheduled = widget.triggerSources.contains('scheduled');
    if (!wasScheduled && isScheduled && widget.tenantWorkerId.isNotEmpty) {
      _loadWaChannel();
      _initMappingRows();
    }
    // When conversational is removed from trigger sources, auto-disable
    // send_proactive and persist immediately.
    final wasConversational = old.triggerSources.contains('conversational');
    final isConversational = widget.triggerSources.contains('conversational');
    if (wasConversational && !isConversational && _sendProactive) {
      _patchSendProactive(false);
    }
  }

  Future<void> _loadWaChannel() async {
    if (widget.tenantWorkerId.isEmpty) return;
    try {
      final channels = await ChannelsApi.listChannelsByWorker(
        tenantWorkerId: widget.tenantWorkerId,
      );
      final waChannel = channels.firstWhere(
        (c) => (c['channel_type'] as String?) == 'whatsapp',
        orElse: () => {},
      );
      if (!mounted) return;
      final channelId = waChannel['id'] as String?;
      setState(() => _waChannelId = channelId);
      if (channelId != null) {
        await _loadTemplates(channelId);
      }
    } catch (_) {}
  }

  Future<void> _loadTemplates(String channelId) async {
    setState(() => _loadingTemplates = true);
    try {
      final all = await ChannelsApi.listTemplates(channelId: channelId);
      if (!mounted) return;
      setState(() {
        _approvedTemplates =
            all.where((t) => (t['status'] as String?) == 'APPROVED').toList();
        _loadingTemplates = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingTemplates = false);
    }
  }

  void _initMappingRows() {
    for (final row in _mappingRows) {
      row.$1.dispose();
      row.$2.dispose();
    }
    final existing = (widget.proactiveTrigger['variable_mapping'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    setState(() {
      _mappingRows = existing
          .map((e) => (
                TextEditingController(text: e['variable'] as String? ?? ''),
                TextEditingController(text: e['source'] as String? ?? ''),
              ))
          .toList();
    });
  }

  void _updateProactiveTrigger({
    String? templateId,
    List<(TextEditingController, TextEditingController)>? rows,
  }) {
    final effectiveTemplateId =
        templateId ?? widget.proactiveTrigger['template_id'] as String?;
    final effectiveRows = rows ?? _mappingRows;
    final mapping = effectiveRows
        .where((r) => r.$1.text.trim().isNotEmpty)
        .map((r) => {
              'variable': r.$1.text.trim(),
              'source': r.$2.text.trim(),
            })
        .toList();
    final updated = <String, dynamic>{
      'template_id': ?effectiveTemplateId,
      if (mapping.isNotEmpty) 'variable_mapping': mapping,
    };
    widget.onProactiveTriggerChanged(updated);
  }

  Future<void> _patchSendProactive(bool value) async {
    setState(() {
      _sendProactive = value;
      _savingProactive = true;
    });
    widget.onSendProactiveChanged(value);
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
      widget.onSendProactiveChanged(!value);
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
          style: AppTextStyles.pageTitle,
        ),
        content: Text(
          '¿Eliminar esta condición de branching?',
          style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
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
                      children: [
                        Text(
                          'Enviar mensaje proactivo al operador al iniciar este flujo',
                          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Si está activado, la plataforma envía un mensaje automático al operador cuando se abre este flujo',
                          style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
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
          // ── Proactive trigger (scheduled) ────────────────────────────────
          if (widget.triggerSources.contains('scheduled')) ...[
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
                  Text(
                    'Plantilla de inicio programado',
                    style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Selecciona la plantilla de WhatsApp aprobada que se enviará cuando este flujo se dispare de forma programada.',
                    style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  if (_waChannelId == null)
                    Text(
                      'No se encontró canal de WhatsApp activo en este worker.',
                      style: AppTextStyles.bodySmall.copyWith(
                        fontSize: 12,
                        color: AppColors.ctText3,
                      ),
                    )
                  else if (_loadingTemplates)
                    const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.ctTeal,
                      ),
                    )
                  else if (_approvedTemplates.isEmpty)
                    Text(
                      'No hay plantillas aprobadas. Sincroniza las plantillas en Canales.',
                      style: AppTextStyles.bodySmall.copyWith(
                        fontSize: 12,
                        color: AppColors.ctText3,
                      ),
                    )
                  else ...[
                    DropdownButtonFormField<String>(
                      value: widget.proactiveTrigger['template_id'] as String?,
                      decoration: InputDecoration(
                        labelText: 'Plantilla',
                        labelStyle: AppTextStyles.bodySmall,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: AppColors.ctBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: AppColors.ctBorder),
                        ),
                      ),
                      dropdownColor: AppColors.ctSurface,
                      style: AppTextStyles.body,
                      items: _approvedTemplates.map((t) {
                        final id = t['id'] as String? ?? t['name'] as String? ?? '';
                        final name = t['name'] as String? ?? id;
                        final lang = t['language'] as String? ?? '';
                        return DropdownMenuItem<String>(
                          value: id,
                          child: Text('$name ($lang)', style: AppTextStyles.body),
                        );
                      }).toList(),
                      onChanged: widget.canManage
                          ? (v) {
                              if (v != null) {
                                _updateProactiveTrigger(templateId: v);
                              }
                            }
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          'Mapeo de variables',
                          style: AppTextStyles.body
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        if (widget.canManage)
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _mappingRows = [
                                  ..._mappingRows,
                                  (
                                    TextEditingController(),
                                    TextEditingController(),
                                  ),
                                ];
                              });
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.ctTeal,
                              padding: EdgeInsets.zero,
                            ),
                            child: Text(
                              '+ Agregar',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.ctTeal,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (_mappingRows.isEmpty)
                      Text(
                        'Sin variables mapeadas. La plantilla se enviará sin reemplazos.',
                        style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 12, color: AppColors.ctText3),
                      )
                    else
                      ...List.generate(_mappingRows.length, (i) {
                        final row = _mappingRows[i];
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: row.$1,
                                  style: AppTextStyles.body,
                                  decoration: InputDecoration(
                                    labelText: 'Variable',
                                    labelStyle: AppTextStyles.bodySmall,
                                    hintText: 'nombre_cliente',
                                    isDense: true,
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 8),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: const BorderSide(
                                          color: AppColors.ctBorder),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: const BorderSide(
                                          color: AppColors.ctBorder),
                                    ),
                                  ),
                                  enabled: widget.canManage,
                                  onChanged: (_) =>
                                      _updateProactiveTrigger(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: row.$2,
                                  style: AppTextStyles.body,
                                  decoration: InputDecoration(
                                    labelText: 'Fuente',
                                    labelStyle: AppTextStyles.bodySmall,
                                    hintText: 'fields.nombre',
                                    isDense: true,
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 8),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: const BorderSide(
                                          color: AppColors.ctBorder),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: const BorderSide(
                                          color: AppColors.ctBorder),
                                    ),
                                  ),
                                  enabled: widget.canManage,
                                  onChanged: (_) =>
                                      _updateProactiveTrigger(),
                                ),
                              ),
                              if (widget.canManage)
                                IconButton(
                                  icon: const Icon(Icons.close,
                                      size: 16, color: AppColors.ctText3),
                                  onPressed: () {
                                    row.$1.dispose();
                                    row.$2.dispose();
                                    setState(() {
                                      _mappingRows.removeAt(i);
                                    });
                                    _updateProactiveTrigger(
                                        rows: _mappingRows);
                                  },
                                ),
                            ],
                          ),
                        );
                      }),
                    if (_mappingRows.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      AppButton(
                        label: 'Guardar mapeo',
                        variant: AppButtonVariant.primary,
                        size: AppButtonSize.sm,
                        onPressed: () {
                          if (!widget.canManage) return;
                          _updateProactiveTrigger();
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(
                            content: Text(
                                'Mapeo guardado — presiona Guardar en el flujo para persistir'),
                            backgroundColor: AppColors.ctOk,
                            duration: Duration(seconds: 2),
                          ));
                        },
                      ),
                    ],
                  ],
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
                Text(
                  'Roles con acceso',
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Solo los operadores con estos roles podrán iniciar este flujo. Si no se selecciona ninguno, todos los roles tienen acceso.',
                  style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
                ),
                const SizedBox(height: 12),
                if (widget.availableRoles.isEmpty)
                  Text(
                    'No hay roles definidos. Crea roles en Operadores → Roles.',
                    style: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: AppColors.ctText3),
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
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 12,
                            color: AppColors.ctText,
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
                            style: AppTextStyles.bodySmall.copyWith(
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
                            style: AppTextStyles.body,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (label != null && label.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: AppTextStyles.bodySmall,
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
                style: AppTextStyles.pageTitle,
              ),
              const SizedBox(height: 20),

              // Campo
              Text(
                'Campo',
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 6),
              _DropdownContainer(
                child: DropdownButton<String>(
                  value: _selectedFieldId,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  hint: Text(
                    'Selecciona un campo',
                    style: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                  ),
                  dropdownColor: AppColors.ctSurface,
                  items: widget.flowFields.map((f) {
                    final id = f['id']?.toString() ?? '';
                    final lbl = f['label'] as String? ?? id;
                    return DropdownMenuItem(
                      value: 'fields.$id',
                      child: Text(
                        lbl,
                        style: AppTextStyles.body,
                      ),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedFieldId = v),
                ),
              ),
              const SizedBox(height: 14),

              // Operador
              Text(
                'Operador',
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
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
                        style: AppTextStyles.body,
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
                    style: AppTextStyles.bodySmall,
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

  bool get _hasOpenFlowNTimes => _actions.any(
    (a) => (a['type'] as String?) == 'open_flow_n_times',
  );

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
          style: AppTextStyles.pageTitle,
        ),
        content: Text(
          '¿Eliminar esta acción?',
          style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
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
                style: AppTextStyles.pageTitle,
              ),
              const Spacer(),
              if (widget.canManage)
                AppButton(
                  label: '+ Agregar acción',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                  onPressed: () => _openActionDialog(null),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Se ejecutan en orden cuando el flujo se marca como completado.',
            style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
          ),
          if (_hasOpenFlowNTimes) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.ctInfoBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.ctInfo.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 14, color: AppColors.ctInfoText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Este flujo genera instancias hijas. '
                      'Asegúrate de que el flujo de cierre tenga una precondición '
                      '"all_children_completed" configurada.',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctInfoText),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
    case 'open_flow_n_times':
      return Icons.account_tree_outlined;
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
    case 'open_flow':
      return 'Abrir flujo';
    case 'open_flow_n_times':
      return 'Abrir flujo N veces';
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
    case 'open_flow_n_times':
      final nSlug = action['flow_slug'] as String? ?? '';
      final field = action['count_field_key'] as String? ?? '';
      return '→ $nSlug × $field';
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
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  _actionSubtitle(action),
                  style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
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
  String? _selectedCountFieldKey;

  // webhook_out
  final _integrationCtrl = TextEditingController();
  bool _includeAncestors = false;

  // emit_event
  final _eventNameCtrl = TextEditingController();

  // google_sheets_append_row
  final _spreadsheetIdCtrl = TextEditingController();
  final _sheetNameCtrl = TextEditingController();
  // catalog schemas for asset_ref fields: {catalog_slug: fields_schema}
  Map<String, List<Map<String, dynamic>>> _catalogSchemas = {};
  bool _loadingCatalogSchemas = false;
  // Each entry: (col: controller, val: controller)
  final List<(TextEditingController, TextEditingController)> _columnMappingRows = [];
  // Parallel list: selected flowField key per row (null = custom text mode)
  final List<String?> _columnMappingKeys = [];

  // condition
  String? _conditionField;
  String _conditionOp = '==';
  final _conditionValueCtrl = TextEditingController();

  // dynamic action types
  List<Map<String, dynamic>> _availableActionTypes = [];
  final Map<String, TextEditingController> _dynTextCtrls = {};
  final Map<String, String?> _dynSelectVals = {};
  final Map<String, bool> _dynBoolVals = {};

  bool get _isEdit => widget.action != null;
  bool get _isKnownType => const {
        'open_flow',
        'open_flow_n_times',
        'webhook_out',
        'emit_event',
        'google_sheets_append_row',
      }.contains(_type);

  List<Map<String, dynamic>> _fieldsForActionType(String type) {
    final match = _availableActionTypes.where((t) => t['type'] == type).firstOrNull;
    if (match == null) return [];
    return List<Map<String, dynamic>>.from(
        ((match['fields'] as List?) ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }

  void _initDynamicFields(String type, Map<String, dynamic> params) {
    for (final c in _dynTextCtrls.values) { c.dispose(); }
    _dynTextCtrls.clear();
    _dynSelectVals.clear();
    _dynBoolVals.clear();
    for (final field in _fieldsForActionType(type)) {
      final key = field['key'] as String? ?? '';
      if (key.isEmpty) continue;
      final fieldType = field['type'] as String? ?? 'text';
      final existing = params[key];
      switch (fieldType) {
        case 'text':
          _dynTextCtrls[key] = TextEditingController(text: existing?.toString() ?? '');
        case 'select':
          _dynSelectVals[key] = existing?.toString()
              ?? (field['default'] as String?);
        case 'bool':
          _dynBoolVals[key] = (existing as bool?) ?? false;
      }
    }
  }

  Future<void> _loadActionTypes() async {
    try {
      final types = await FlowsApi.getActionTypes();
      if (mounted) {
        setState(() {
          _availableActionTypes = types;
          if (!_isKnownType && widget.action != null) {
            _initDynamicFields(_type, Map<String, dynamic>.from(widget.action!));
          }
        });
      }
    } catch (e) {
      print('[_loadActionTypes] error: $e');
    }
  }

  List<Widget> _renderDynamicActionFields() {
    final fields = _fieldsForActionType(_type);
    if (fields.isEmpty) return [];
    final widgets = <Widget>[];
    for (final field in fields) {
      final key = field['key'] as String? ?? '';
      if (key.isEmpty) continue;
      final label = field['label'] as String? ?? key;
      final fieldType = field['type'] as String? ?? 'text';
      final rawOptions = field['options'] as List? ?? [];
      final options = rawOptions
          .whereType<Map>()
          .map((o) => Map<String, dynamic>.from(o))
          .toList();
      widgets.add(const SizedBox(height: 12));
      switch (fieldType) {
        case 'text':
          widgets.add(_FormField(
            label: label,
            controller: _dynTextCtrls[key] ??= TextEditingController(),
            placeholder: '',
          ));
        case 'select':
          widgets
            ..add(Text(label,
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500)))
            ..add(const SizedBox(height: 6))
            ..add(_DropdownContainer(
              child: DropdownButton<String>(
                value: _dynSelectVals[key],
                isExpanded: true,
                underline: const SizedBox.shrink(),
                dropdownColor: AppColors.ctSurface,
                hint: Text('Seleccionar',
                    style: AppTextStyles.body.copyWith(color: AppColors.ctText3)),
                items: options
                    .map((o) => DropdownMenuItem(
                          value: o['value'] as String? ?? '',
                          child: Text(o['label'] as String? ?? '',
                              style: AppTextStyles.body),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _dynSelectVals[key] = v),
              ),
            ));
        case 'bool':
          widgets.add(SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(label, style: AppTextStyles.body),
            value: _dynBoolVals[key] ?? false,
            activeThumbColor: AppColors.ctTeal,
            activeTrackColor: AppColors.ctTeal.withValues(alpha: 0.4),
            onChanged: (v) => setState(() => _dynBoolVals[key] = v),
          ));
      }
    }
    return widgets;
  }

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
      if (_type == 'open_flow_n_times') {
        _selectedFlowSlug = a['flow_slug'] as String?;
        _selectedCountFieldKey = a['count_field_key'] as String?;
      }
      if (_type == 'google_sheets_append_row') {
        final cfg = a['config'] as Map? ?? {};
        _spreadsheetIdCtrl.text = cfg['spreadsheet_id'] as String? ?? '';
        _sheetNameCtrl.text = cfg['sheet_name'] as String? ?? 'Sheet1';
        final mapping = cfg['column_mapping'] as Map? ?? {};
        final fieldKeyRe = RegExp(r'^\{\{fields\.([\w.]+)\}\}$');
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadActionTypes());
    _loadCatalogSchemas();
  }

  Future<void> _loadCatalogSchemas() async {
    debugPrint('[_loadCatalogSchemas] flowFields: ${widget.flowFields.map((f) => '${f['key']}(type=${f['type']}, slug=${f['catalog_slug']})').toList()}');
    final assetRefFields = widget.flowFields
        .where((f) =>
            (f['type'] as String?) == 'asset_ref' &&
            f['catalog_slug'] != null &&
            (f['catalog_slug'] as String).isNotEmpty)
        .toList();
    debugPrint('[_loadCatalogSchemas] assetRefFields count: ${assetRefFields.length}');
    if (assetRefFields.isEmpty) return;

    setState(() => _loadingCatalogSchemas = true);
    try {
      final slugs = assetRefFields
          .map((f) => f['catalog_slug'] as String)
          .toSet();
      debugPrint('[_loadCatalogSchemas] slugs to fetch: $slugs');
      final futures = slugs.map((slug) async {
        final catalog = await CatalogsApi.getCatalogBySlug(
          tenantId: widget.tenantId,
          slug: slug,
        );
        debugPrint('[_loadCatalogSchemas] catalog response for $slug: ${catalog.keys.toList()}');
        final schema = (catalog['fields_schema'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        debugPrint('[_loadCatalogSchemas] schema for $slug: $schema');
        return MapEntry(slug, schema);
      });
      final entries = await Future.wait(futures);
      if (!mounted) return;
      setState(() {
        _catalogSchemas = Map.fromEntries(entries);
        _loadingCatalogSchemas = false;
      });
      debugPrint('[_loadCatalogSchemas] loaded schemas: ${_catalogSchemas.keys.toList()}');
    } catch (e) {
      debugPrint('[_loadCatalogSchemas] ERROR: $e');
      if (!mounted) return;
      setState(() => _loadingCatalogSchemas = false);
    }
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
    for (final c in _dynTextCtrls.values) { c.dispose(); }
    super.dispose();
  }

  Set<String> _buildAllValidKeys() {
    final keys = <String>{};
    for (final f in widget.flowFields) {
      final key = f['key'] as String? ?? '';
      if (key.isEmpty) continue;
      final type = f['type'] as String?;
      final slug = f['catalog_slug'] as String?;
      if (type == 'asset_ref' && slug != null && _catalogSchemas.containsKey(slug)) {
        for (final col in _catalogSchemas[slug]!) {
          final colKey = col['key'] as String? ?? '';
          if (colKey.isNotEmpty) keys.add('$key.data.$colKey');
        }
      } else {
        keys.add(key);
      }
    }
    return keys;
  }

  List<DropdownMenuItem<String?>> _buildFieldDropdownItems() {
    final items = <DropdownMenuItem<String?>>[];
    for (final f in widget.flowFields) {
      final key = f['key'] as String? ?? '';
      final label = f['label'] as String? ?? key;
      final type = f['type'] as String?;
      final slug = f['catalog_slug'] as String?;
      if (type == 'asset_ref' && slug != null && _catalogSchemas.containsKey(slug)) {
        for (final col in _catalogSchemas[slug]!) {
          final colKey = col['key'] as String? ?? '';
          final colLabel = col['label'] as String? ?? colKey;
          if (colKey.isEmpty) continue;
          items.add(DropdownMenuItem<String?>(
            value: '$key.data.$colKey',
            child: Text(
              '$label > $colLabel',
              style: const TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                color: AppColors.ctText,
              ),
            ),
          ));
        }
      } else {
        items.add(DropdownMenuItem<String?>(
          value: key,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 13,
              color: AppColors.ctText,
            ),
          ),
        ));
      }
    }
    return items;
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
      case 'open_flow_n_times':
        if (_selectedFlowSlug == null) return;
        if (_selectedCountFieldKey == null) return;
        updated['flow_slug'] = _selectedFlowSlug!;
        updated['count_field_key'] = _selectedCountFieldKey!;
        updated.remove('target_flow_slug');
        updated.remove('carry_ancestors');
        updated.remove('carry_fields');
        updated.remove('integration_id');
        updated.remove('include_ancestors');
        updated.remove('event_name');
        updated.remove('event_data');
        updated.remove('config');
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
      default:
        for (final e in _dynTextCtrls.entries) { updated[e.key] = e.value.text.trim(); }
        for (final e in _dynSelectVals.entries) { updated[e.key] = e.value; }
        for (final e in _dynBoolVals.entries) { updated[e.key] = e.value; }
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
                style: AppTextStyles.pageTitle,
              ),
              const SizedBox(height: 20),

              // Tipo
              Text(
                'Tipo de acción',
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 6),
              _availableActionTypes.isEmpty
                  ? Text('Cargando tipos...',
                      style: AppTextStyles.body.copyWith(color: AppColors.ctText3))
                  : _DropdownContainer(
                      child: DropdownButton<String>(
                        value: _availableActionTypes.any((t) => t['type'] == _type)
                            ? _type
                            : null,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        dropdownColor: AppColors.ctSurface,
                        hint: Text('Seleccionar tipo',
                            style: AppTextStyles.body.copyWith(color: AppColors.ctText3)),
                        items: _availableActionTypes
                            .map((t) => DropdownMenuItem(
                                  value: t['type'] as String? ?? '',
                                  child: Text(t['label'] as String? ?? '',
                                      style: AppTextStyles.body),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _type = v;
                            if (!_isKnownType) _initDynamicFields(v, {});
                          });
                        },
                      ),
                    ),
              const SizedBox(height: 16),

              // Campos condicionales
              if (_type == 'open_flow') ...[
                Text(
                  'Flujo destino',
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
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
                    child: Text(
                      'No hay flujos disponibles para este worker',
                      style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                    ),
                  )
                else
                  _DropdownContainer(
                    child: DropdownButton<String>(
                      value: _selectedFlowSlug,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      dropdownColor: AppColors.ctSurface,
                      hint: Text('Selecciona un flujo',
                          style: AppTextStyles.body.copyWith(color: AppColors.ctText2)),
                      items: _availableFlows.map((f) {
                        final slug = f['slug'] as String? ?? '';
                        final name = f['name'] as String? ?? slug;
                        return DropdownMenuItem<String>(
                          value: slug,
                          child: Text(name,
                              style: AppTextStyles.body),
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
                    style: AppTextStyles.body,
                  ),
                  value: _carryAncestors,
                  onChanged: (v) => setState(() => _carryAncestors = v),
                  activeThumbColor: AppColors.ctTeal,
                  activeTrackColor: AppColors.ctTeal.withValues(alpha: 0.4),
                ),
              ] else if (_type == 'open_flow_n_times') ...[
                Text(
                  'Flow slug',
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                _DropdownContainer(
                  child: _loadingFlows
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: CircularProgressIndicator(
                                color: AppColors.ctTeal, strokeWidth: 2),
                          ),
                        )
                      : DropdownButton<String>(
                          value: _selectedFlowSlug,
                          isExpanded: true,
                          underline: const SizedBox.shrink(),
                          dropdownColor: AppColors.ctSurface,
                          hint: Text('Seleccionar flow',
                              style: AppTextStyles.body
                                  .copyWith(color: AppColors.ctText3)),
                          items: _availableFlows
                              .map((f) => DropdownMenuItem<String>(
                                    value: f['slug'] as String?,
                                    child: Text(
                                      '${f['name'] ?? f['slug']}',
                                      style: AppTextStyles.body,
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _selectedFlowSlug = v),
                        ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Campo de conteo',
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                _DropdownContainer(
                  child: DropdownButton<String>(
                    value: _selectedCountFieldKey,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    dropdownColor: AppColors.ctSurface,
                    hint: Text('Seleccionar campo',
                        style: AppTextStyles.body
                            .copyWith(color: AppColors.ctText3)),
                    items: widget.flowFields
                        .map((f) => DropdownMenuItem<String>(
                              value: f['key'] as String?,
                              child: Text(
                                '${f['label'] ?? f['key']}',
                                style: AppTextStyles.body,
                              ),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _selectedCountFieldKey = v),
                  ),
                ),
                if (_selectedCountFieldKey != null) ...[
                  Builder(builder: (_) {
                    final field = widget.flowFields.firstWhere(
                      (f) => (f['key'] as String?) == _selectedCountFieldKey,
                      orElse: () => <String, dynamic>{},
                    );
                    final isRequired = field['required'] as bool? ?? false;
                    final fieldType = field['type'] as String? ?? '';
                    final warnings = <String>[];
                    if (fieldType.isNotEmpty && fieldType != 'number') {
                      warnings.add('Este campo es de tipo "$fieldType". '
                          'Se recomienda usar un campo de tipo Número para evitar errores.');
                    }
                    if (!isRequired) {
                      warnings.add('Este campo no es obligatorio. '
                          'Si el operador no lo captura, no se crearán instancias hijas.');
                    }
                    if (warnings.isEmpty) return const SizedBox.shrink();
                    return Column(
                      children: [
                        const SizedBox(height: 6),
                        for (final w in warnings) ...[
                          _SemanticWarning(message: w),
                          const SizedBox(height: 4),
                        ],
                      ],
                    );
                  }),
                ],
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
                    style: AppTextStyles.body,
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
                    Text(
                      'Mapeo de columnas',
                      style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
                    ),
                    AppButton(
                      label: '+ Agregar columna',
                      variant: AppButtonVariant.ghost,
                      size: AppButtonSize.sm,
                      prefixIcon: const Icon(Icons.add, size: 14, color: AppColors.ctTeal),
                      onPressed: () => setState(() {
                        _columnMappingRows.add((
                          TextEditingController(),
                          TextEditingController(),
                        ));
                        _columnMappingKeys.add(null);
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ..._columnMappingRows.asMap().entries.map((entry) {
                  final i = entry.key;
                  final row = entry.value;
                  final selectedKey = _columnMappingKeys.length > i ? _columnMappingKeys[i] : null;
                  final hasFields = widget.flowFields.isNotEmpty;
                  // Validate against expanded keys (includes compound asset_ref keys)
                  // While schemas are loading, trust compound keys (contain dots)
                  final allKeys = _buildAllValidKeys();
                  final effectiveKey = (selectedKey != null &&
                      (allKeys.contains(selectedKey) ||
                       (_loadingCatalogSchemas && selectedKey.contains('.'))))
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
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Text('→',
                                  style: AppTextStyles.body.copyWith(color: AppColors.ctText2)),
                            ),
                            if (hasFields)
                              Expanded(
                                child: _DropdownContainer(
                                  child: DropdownButton<String?>(
                                    value: effectiveKey,
                                    isExpanded: true,
                                    underline: const SizedBox.shrink(),
                                    dropdownColor: AppColors.ctSurface,
                                    hint: Text(
                                      _loadingCatalogSchemas
                                          ? 'Cargando campos…'
                                          : 'Campo del flujo…',
                                      style: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                                    ),
                                    items: [
                                      DropdownMenuItem<String?>(
                                        value: null,
                                        child: Text(
                                          'Personalizado…',
                                          style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                                        ),
                                      ),
                                      ..._buildFieldDropdownItems(),
                                      // Temporary item while schemas load for compound keys
                                      if (_loadingCatalogSchemas &&
                                          effectiveKey != null &&
                                          effectiveKey.contains('.') &&
                                          !_buildAllValidKeys().contains(effectiveKey))
                                        DropdownMenuItem<String?>(
                                          value: effectiveKey,
                                          child: Text(
                                            'Cargando…',
                                            style: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                                          ),
                                        ),
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
              if (!_isKnownType) ..._renderDynamicActionFields(),

              // ── Condición (opcional) ────────────────────────────────────────
              const SizedBox(height: 20),
              const Divider(color: AppColors.ctBorder, height: 1),
              const SizedBox(height: 16),
              Text(
                'Condición (opcional)',
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'La acción solo se ejecuta si se cumple la condición.',
                style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 10),

              // Campo
              Text(
                'Campo',
                style: AppTextStyles.bodySmall.copyWith(
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
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        'Sin condición',
                        style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                      ),
                    ),
                    ...widget.flowFields.map((f) {
                      final key = f['key'] as String? ?? '';
                      final label = f['label'] as String? ?? key;
                      return DropdownMenuItem<String?>(
                        value: key,
                        child: Text(
                          label,
                          style: AppTextStyles.body,
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
                            DropdownMenuItem(value: '==', child: Text('== igual', style: AppTextStyles.body)),
                            DropdownMenuItem(value: '!=', child: Text('!= distinto', style: AppTextStyles.body)),
                            DropdownMenuItem(value: '>',  child: Text('>  mayor', style: AppTextStyles.body)),
                            DropdownMenuItem(value: '<',  child: Text('<  menor', style: AppTextStyles.body)),
                            DropdownMenuItem(value: '>=', child: Text('>= mayor o igual', style: AppTextStyles.body)),
                            DropdownMenuItem(value: '<=', child: Text('<= menor o igual', style: AppTextStyles.body)),
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
                          style: AppTextStyles.body,
                          decoration: InputDecoration(
                            hintText: 'ej. Si, Granjas, 5',
                            hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
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
                    style: AppTextStyles.body,
                    decoration: InputDecoration(
                      hintText: 'ej. fields.receta == "Si"',
                      hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
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
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
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
        style: AppTextStyles.body,
        decoration: InputDecoration(
          hintText: placeholder,
          hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
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
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
          ),
        ],
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
            style: AppTextStyles.bodySmall.copyWith(
              fontSize: 12,
              color: valid ? AppColors.ctOkText : AppColors.ctDanger,
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
            style: AppTextStyles.body.copyWith(
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
          style: AppTextStyles.btnSecondary.copyWith(color: AppColors.ctText2),
        ),
      ),
    );
  }
}

// ── Precondiciones ────────────────────────────────────────────────────────────


class _PrecondicionesTab extends StatefulWidget {
  const _PrecondicionesTab({
    required this.rules,
    required this.canManage,
    required this.availableRoles,
    required this.tenantId,
    required this.tenantWorkerId,
    required this.currentFlowSlug,
    required this.onChanged,
  });
  final List<Map<String, dynamic>> rules;
  final bool canManage;
  final List<Map<String, dynamic>> availableRoles;
  final String tenantId;
  final String tenantWorkerId;
  final String currentFlowSlug;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  @override
  State<_PrecondicionesTab> createState() => _PrecondicionesTabState();
}

class _PrecondicionesTabState extends State<_PrecondicionesTab> {
  late List<Map<String, dynamic>> _rules;
  List<Map<String, dynamic>> _availableTypes = [];
  List<Map<String, dynamic>> _workerFlows = [];

  @override
  void initState() {
    super.initState();
    _rules = List.from(widget.rules);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTypes();
      _loadWorkerFlows();
    });
  }

  @override
  void didUpdateWidget(_PrecondicionesTab old) {
    super.didUpdateWidget(old);
    if (old.rules != widget.rules) {
      _rules = List.from(widget.rules);
    }
  }

  Future<void> _loadTypes() async {
    try {
      final types = await FlowsApi.getPreconditionTypes();
      if (mounted) setState(() => _availableTypes = types);
    } catch (e, st) {
      print('[_loadTypes] error: $e\n$st');
    }
  }

  Future<void> _loadWorkerFlows() async {
    if (widget.tenantWorkerId.isEmpty) return;
    try {
      final flows = await FlowsApi.getFlowsByWorker(
        tenantWorkerId: widget.tenantWorkerId,
      );
      if (mounted) setState(() => _workerFlows = flows);
    } catch (_) {
      // fail silently — selectores mostrarán campo texto como fallback
    }
  }

  String _typeLabel(String type) {
    for (final t in _availableTypes) {
      if (t['type'] == type) return t['label'] as String? ?? type;
    }
    return type;
  }

  void _openRuleDialog(Map<String, dynamic>? rule) {
    showDialog(
      context: context,
      builder: (_) => _AddRuleDialog(
        rule: rule,
        availableRoles: widget.availableRoles,
        types: _availableTypes,
        workerFlows: _workerFlows,
        currentFlowSlug: widget.currentFlowSlug,
        tenantId: widget.tenantId,
        onSaved: (updated) {
          setState(() {
            if (rule != null) {
              final idx = _rules.indexWhere((r) => r['id'] == rule['id']);
              if (idx >= 0) {
                _rules[idx] = updated;
              } else {
                _rules.add(updated);
              }
            } else {
              _rules.add(updated);
            }
          });
          widget.onChanged(List.from(_rules));
        },
      ),
    );
  }

  void _deleteRule(Map<String, dynamic> rule) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.ctSurface,
        title: Text('Eliminar regla',
            style: AppTextStyles.pageTitle),
        content: Text('¿Eliminar esta regla de inicio?',
            style: AppTextStyles.body.copyWith(color: AppColors.ctText2)),
        actions: [
          _GhostButton(label: 'Cancelar', onTap: () => Navigator.pop(ctx)),
          const SizedBox(width: 8),
          _PrimaryButton(
            label: 'Eliminar',
            onTap: () {
              Navigator.pop(ctx);
              setState(() {
                _rules.removeWhere((r) => r['id'] == rule['id']);
              });
              widget.onChanged(List.from(_rules));
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
                'Reglas de inicio',
                style: AppTextStyles.pageTitle,
              ),
              const Spacer(),
              if (widget.canManage)
                AppButton(
                  label: '+ Agregar regla',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                  onPressed: () => _openRuleDialog(null),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Se verifican antes de iniciar el flujo. Si alguna falla, el flow no se ejecuta.',
            style: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: AppColors.ctText2),
          ),
          const SizedBox(height: 16),
          if (_rules.isEmpty)
            const SizedBox(
              height: 200,
              child: _EmptyState(
                icon: Icons.rule_outlined,
                message:
                    'Este flow no tiene reglas de inicio configuradas.',
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _rules.length,
              separatorBuilder: (context2, i2) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _RuleCard(
                rule: _rules[i],
                typeLabel: _typeLabel(_rules[i]['type'] as String? ?? ''),
                canManage: widget.canManage,
                onEdit: () => _openRuleDialog(_rules[i]),
                onDelete: () => _deleteRule(_rules[i]),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.rule,
    required this.typeLabel,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });
  final Map<String, dynamic> rule;
  final String typeLabel;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ruleType = rule['type'] as String? ?? '';
    final message = rule['message'] as String? ?? '';
    final config = ((rule['params'] ?? rule['config']) as Map?)?.cast<String, dynamic>() ?? {};
    final isSibling = ruleType == 'requires_completed_sibling';
    final action = rule['action'] as String? ?? 'block';
    final escalate = rule['escalate'] as bool? ?? false;
    final siblingSlug = config['sibling_slug'] as String? ?? '';
    final windowType = config['window_type'] as String? ?? 'calendar_day';
    final bodyText = isSibling
        ? (siblingSlug.isNotEmpty
            ? 'Requiere completar: $siblingSlug'
            : '(sin configurar)')
        : (message.isEmpty ? '—' : message);
    final windowLabel = windowType == 'calendar_day' ? 'Ventana: día calendario' : 'Ventana: móvil';

    return InkWell(
      onTap: canManage ? onEdit : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.ctSurface,
          border: Border.all(color: AppColors.ctBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.ctInfoBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                typeLabel,
                style: AppTextStyles.badge.copyWith(color: AppColors.ctInfoText),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: action == 'allow' ? AppColors.ctOkBg : AppColors.ctRedBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                action == 'allow' ? 'allow' : 'block',
                style: AppTextStyles.badge.copyWith(
                    color: action == 'allow' ? AppColors.ctOkText : AppColors.ctRedText),
              ),
            ),
            const SizedBox(width: 8),
            if (escalate) ...[
              const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.ctWarn),
              const SizedBox(width: 8),
            ],
            if (isSibling) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.ctBorder,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  windowLabel,
                  style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                bodyText,
                style: AppTextStyles.bodySmall.copyWith(
                    fontSize: 12,
                    color: (isSibling && siblingSlug.isEmpty)
                        ? AppColors.ctDanger
                        : AppColors.ctText2),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (canManage) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 16, color: AppColors.ctDanger),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Eliminar regla',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AddRuleDialog extends StatefulWidget {
  const _AddRuleDialog({
    required this.rule,
    required this.availableRoles,
    required this.types,
    required this.workerFlows,
    required this.currentFlowSlug,
    required this.tenantId,
    required this.onSaved,
  });
  final Map<String, dynamic>? rule;
  final List<Map<String, dynamic>> availableRoles;
  final List<Map<String, dynamic>> types;
  final List<Map<String, dynamic>> workerFlows;
  final String currentFlowSlug;
  final String tenantId;
  final ValueChanged<Map<String, dynamic>> onSaved;

  @override
  State<_AddRuleDialog> createState() => _AddRuleDialogState();
}

class _AddRuleDialogState extends State<_AddRuleDialog> {
  String? _type;
  final _messageCtrl = TextEditingController();
  String _action = 'block';
  bool _escalate = false;
  final _escalationReasonCtrl = TextEditingController();

  // Dynamic per-type field state
  final Map<String, TextEditingController> _textCtrls = {};
  final Map<String, String?> _selectVals = {};
  final Map<String, bool> _boolVals = {};
  final Map<String, String> _semanticWarnings = {};

  List<Map<String, dynamic>> _availableCatalogs = [];
  bool _loadingCatalogs = false;

  bool get _isEdit => widget.rule != null;

  List<Map<String, dynamic>> get _workerFlows => widget.workerFlows;

  Map<String, dynamic>? _flowBySlug(String slug) {
    final f = _workerFlows.firstWhere(
      (f) => (f['slug'] as String?) == slug,
      orElse: () => <String, dynamic>{},
    );
    return f.isEmpty ? null : f;
  }

  bool _isFlowSlugField(String key) => const {
    'sibling_slug', 'flow_slug', 'parent_flow_slug',
    'child_flow_slug', 'slug',
  }.contains(key);

  void _validateSemantic(String fieldKey, String selectedSlug) {
    final flow = _flowBySlug(selectedSlug);
    if (flow == null) {
      setState(() => _semanticWarnings[fieldKey] =
          'Este flujo no existe en el worker actual');
      return;
    }

    String? warning;

    // S-1: requires_completed_sibling sobre flow no conversacional
    if (_type == 'requires_completed_sibling' && fieldKey == 'sibling_slug') {
      final sources = (flow['trigger_sources'] as List? ?? [])
          .map((s) => s.toString()).toList();
      if (!sources.contains('conversational')) {
        warning = 'Este flujo no es conversacional. '
            'Puede no completarse en el contexto esperado del operador.';
      }
    }

    // S-2: all_children_completed sobre flow que no genera hijos
    if (_type == 'all_children_completed' && fieldKey == 'parent_flow_slug') {
      final onComplete = (flow['on_complete'] as Map<String, dynamic>?) ?? {};
      final actions = (onComplete['actions'] as List? ?? []);
      final hasOpenFlowNTimes = actions.any(
        (a) => (a as Map?)?['type'] == 'open_flow_n_times',
      );
      if (!hasOpenFlowNTimes) {
        warning = 'Este flujo no tiene una acción "Abrir flujo N veces" '
            'en "Al cerrar". La precondición nunca se cumplirá.';
      }
    }

    // S-3: Deadlock detection
    if (_type == 'requires_completed_sibling' && fieldKey == 'sibling_slug') {
      final siblingPrecs = (flow['preconditions'] as List? ?? []);
      final currentFlowSlug = widget.currentFlowSlug;
      final hasMirrorPrecondition = siblingPrecs.any((p) {
        final pMap = p as Map<String, dynamic>? ?? {};
        if (pMap['type'] != 'requires_completed_sibling') return false;
        final params = (pMap['params'] ?? pMap['config']) as Map? ?? {};
        final sibSlug = params['sibling_slug'] as String? ??
            params['slug'] as String? ?? '';
        return sibSlug == currentFlowSlug;
      });
      if (hasMirrorPrecondition) {
        warning = '⚠️ DEADLOCK: "${flow['name']}" también requiere '
            'que este flujo esté completado. Ninguno podrá iniciarse jamás.';
      }
    }

    setState(() {
      if (warning != null) {
        _semanticWarnings[fieldKey] = warning;
      } else {
        _semanticWarnings.remove(fieldKey);
      }
    });
  }

  List<Map<String, dynamic>> _fieldsForType(String? type) {
    if (type == null) return [];
    final match = widget.types.where((t) => t['type'] == type).firstOrNull;
    if (match == null) return [];
    return List<Map<String, dynamic>>.from(
        ((match['fields'] as List?) ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }

  void _initFields(String type, Map<String, dynamic> params) {
    for (final c in _textCtrls.values) { c.dispose(); }
    _textCtrls.clear();
    _selectVals.clear();
    _boolVals.clear();
    for (final field in _fieldsForType(type)) {
      final key = field['key'] as String? ?? '';
      if (key.isEmpty) continue;
      final fieldType = field['type'] as String? ?? 'text';
      final existing = params[key];
      switch (fieldType) {
        case 'text':
          _textCtrls[key] = TextEditingController(text: existing?.toString() ?? '');
        case 'select':
          _selectVals[key] = existing?.toString()
              ?? (field['default'] as String?);
        case 'bool':
          _boolVals[key] = (existing as bool?) ?? false;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    if (rule != null) {
      _type = rule['type'] as String?;
      _messageCtrl.text = rule['message'] as String? ?? '';
      _action = rule['action'] as String? ?? 'block';
      _escalate = rule['escalate'] as bool? ?? false;
      _escalationReasonCtrl.text = rule['escalation_reason'] as String? ?? '';
      final params = ((rule['params'] ?? rule['config']) as Map?)?.cast<String, dynamic>() ?? {};
      if (_type != null) _initFields(_type!, params);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCatalogs());
  }

  Future<void> _loadCatalogs() async {
    if (widget.tenantId.isEmpty) return;
    setState(() => _loadingCatalogs = true);
    try {
      final cats = await CatalogsApi.listCatalogs(tenantId: widget.tenantId);
      if (mounted) setState(() => _availableCatalogs = cats);
    } catch (_) {
      // fail silently — fallback a TextField
    } finally {
      if (mounted) setState(() => _loadingCatalogs = false);
    }
  }

  @override
  void dispose() {
    for (final c in _textCtrls.values) { c.dispose(); }
    _messageCtrl.dispose();
    _escalationReasonCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildConfig() {
    final config = <String, dynamic>{};
    for (final e in _textCtrls.entries) {
      if (e.value.text.trim().isNotEmpty) config[e.key] = e.value.text.trim();
    }
    for (final e in _selectVals.entries) { config[e.key] = e.value; }
    for (final e in _boolVals.entries) { config[e.key] = e.value; }
    return config;
  }

  void _submit() {
    if (_type == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecciona un tipo de regla')));
      return;
    }
    if (_messageCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El mensaje es requerido')));
      return;
    }
    final escalationReason = _escalationReasonCtrl.text.trim();
    final updated = <String, dynamic>{
      'id': (_isEdit ? widget.rule!['id'] : null) ?? 'tmp_${DateTime.now().millisecondsSinceEpoch}',
      'type': _type,
      'params': _buildConfig(),
      'message': _messageCtrl.text.trim(),
      'action': _action,
      'escalate': _escalate,
      'escalation_reason': (_escalate && escalationReason.isNotEmpty) ? escalationReason : null,
    };
    Navigator.of(context).pop();
    widget.onSaved(updated);
  }

  InputDecoration get _inputDecoration => InputDecoration(
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.ctBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.ctBorder)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );

  Widget _buildFlowSlugSelector(String key, String label) {
    final ctrl = _textCtrls[key] ??= TextEditingController();
    if (_workerFlows.isEmpty) {
      return _FormField(label: label, controller: ctrl, placeholder: 'slug del flujo');
    }
    final currentSlug = ctrl.text;
    final selectedSlug = _workerFlows.any((f) => (f['slug'] as String?) == currentSlug)
        ? currentSlug
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.formLabel.copyWith(color: AppColors.ctText2)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: selectedSlug,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.ctBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.ctBorder)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          hint: Text('Selecciona un flujo',
              style: AppTextStyles.body.copyWith(color: AppColors.ctText3)),
          items: _workerFlows.map((f) {
            final slug = f['slug'] as String? ?? '';
            final name = f['name'] as String? ?? slug;
            return DropdownMenuItem<String>(
              value: slug,
              child: Text(name, style: AppTextStyles.body),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() => ctrl.text = v);
              _validateSemantic(key, v);
            }
          },
        ),
        if (_semanticWarnings[key] != null) ...[
          const SizedBox(height: 6),
          _SemanticWarning(message: _semanticWarnings[key]!),
        ],
      ],
    );
  }

  Widget _buildCatalogSlugSelector(String key, String label) {
    final ctrl = _textCtrls[key] ??= TextEditingController();
    final currentSlug = ctrl.text;

    if (_loadingCatalogs) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTextStyles.formLabel.copyWith(color: AppColors.ctText2)),
          const SizedBox(height: 6),
          const SizedBox(
            height: 18, width: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ctTeal),
          ),
        ],
      );
    }

    if (_availableCatalogs.isEmpty) {
      return _FormField(label: label, controller: ctrl, placeholder: 'slug del catálogo');
    }

    final selectedSlug = _availableCatalogs.any(
            (c) => (c['slug'] as String?) == currentSlug)
        ? currentSlug
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTextStyles.formLabel.copyWith(color: AppColors.ctText2)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: selectedSlug,
          decoration: InputDecoration(
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.ctBorder)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.ctBorder)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          hint: Text('Selecciona un catálogo',
              style: AppTextStyles.body.copyWith(color: AppColors.ctText3)),
          items: _availableCatalogs.map((cat) {
            final slug = cat['slug'] as String? ?? '';
            final catLabel = cat['label'] as String?
                ?? cat['name'] as String?
                ?? slug;
            return DropdownMenuItem<String>(
              value: slug,
              child: Text(catLabel, style: AppTextStyles.body),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) setState(() => ctrl.text = v);
          },
        ),
      ],
    );
  }

  Widget _buildTimezoneSelector(String key, String label) {
    final ctrl = _textCtrls[key] ??= TextEditingController();
    final currentVal = ctrl.text;
    final selectedVal = _kTimezones.any((t) => t.$1 == currentVal)
        ? currentVal
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTextStyles.formLabel.copyWith(color: AppColors.ctText2)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: selectedVal,
          decoration: InputDecoration(
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.ctBorder)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.ctBorder)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: _kTimezones.map((tz) {
            return DropdownMenuItem<String>(
              value: tz.$1,
              child: Text(tz.$2, style: AppTextStyles.body),
            );
          }).toList(),
          onChanged: (v) => setState(() => ctrl.text = v ?? ''),
        ),
      ],
    );
  }

  List<Widget> _renderDynamicFields() {
    if (_type == null) return [];
    final fields = _fieldsForType(_type!);
    if (fields.isEmpty) return [];
    final widgets = <Widget>[];
    for (final field in fields) {
      final key = field['key'] as String? ?? '';
      if (key.isEmpty) continue;

      // Evaluar show_if condicional
      final showIf = field['show_if'] as Map<String, dynamic>?;
      if (showIf != null) {
        final depKey = showIf['field'] as String? ?? '';
        final depOp  = showIf['op'] as String? ?? 'eq';
        final depVal = showIf['value'] as String? ?? '';
        final currentVal = _textCtrls[depKey]?.text ?? _selectVals[depKey] ?? '';
        bool visible = false;
        if (depOp == 'eq')  visible = currentVal == depVal;
        if (depOp == 'neq') visible = currentVal != depVal;
        if (!visible) continue;
      }

      final label = field['label'] as String? ?? key;
      final fieldType = field['type'] as String? ?? 'text';
      final rawOptions = field['options'] as List? ?? [];
      final options = rawOptions
          .whereType<Map>()
          .map((o) => Map<String, dynamic>.from(o))
          .toList();
      widgets.add(const SizedBox(height: 16));
      switch (fieldType) {
        case 'text':
          if (_isFlowSlugField(key)) {
            widgets.add(_buildFlowSlugSelector(key, label));
          } else if (key == 'catalog_slug') {
            widgets.add(_buildCatalogSlugSelector(key, label));
          } else if (key == 'timezone') {
            widgets.add(_buildTimezoneSelector(key, label));
          } else {
            widgets
              ..add(Text(label,
                  style: AppTextStyles.formLabel.copyWith(color: AppColors.ctText2)))
              ..add(const SizedBox(height: 6))
              ..add(TextField(
                controller: _textCtrls[key] ??= TextEditingController(),
                style: AppTextStyles.body,
                decoration: _inputDecoration,
              ));
          }
        case 'select':
          widgets
            ..add(Text(label,
                style: AppTextStyles.formLabel.copyWith(color: AppColors.ctText2)))
            ..add(const SizedBox(height: 6))
            ..add(DropdownButtonFormField<String>(
              value: _selectVals[key],
              decoration: _inputDecoration,
              hint: Text('Seleccionar',
                  style: AppTextStyles.body.copyWith(color: AppColors.ctText3)),
              items: options
                  .map((o) => DropdownMenuItem(
                        value: o['value'] as String? ?? '',
                        child: Text(o['label'] as String? ?? '',
                            style: AppTextStyles.body),
                      ))
                  .toList(),
              onChanged: (val) => setState(() => _selectVals[key] = val),
            ));
        case 'bool':
          widgets.add(SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(label, style: AppTextStyles.body),
            value: _boolVals[key] ?? false,
            activeThumbColor: AppColors.ctTeal,
            onChanged: (val) => setState(() => _boolVals[key] = val),
          ));
      }
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isEdit ? 'Editar regla' : 'Agregar regla de inicio',
                style: AppFonts.onest(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ctText),
              ),
              const SizedBox(height: 20),

              // Tipo
              Text('Tipo de regla',
                  style: AppTextStyles.formLabel.copyWith(color: AppColors.ctText2)),
              const SizedBox(height: 6),
              widget.types.isEmpty
                  ? Text(
                      'Cargando tipos...',
                      style: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                    )
                  : DropdownButtonFormField<String>(
                      value: _type,
                      decoration: _inputDecoration,
                      hint: Text('Seleccionar tipo',
                          style: AppTextStyles.body.copyWith(color: AppColors.ctText3)),
                      items: widget.types
                          .map((t) => DropdownMenuItem(
                                value: t['type'] as String? ?? '',
                                child: Text(t['label'] as String? ?? '',
                                    style: AppTextStyles.body),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val == null) return;
                        setState(() {
                          _type = val;
                          _initFields(val, {});
                        });
                      },
                    ),

              // Campos dinámicos del tipo seleccionado
              ..._renderDynamicFields(),

              const SizedBox(height: 16),
              Text('Mensaje al operador si falla',
                  style: AppTextStyles.formLabel.copyWith(color: AppColors.ctText2)),
              const SizedBox(height: 6),
              TextField(
                controller: _messageCtrl,
                style: AppTextStyles.body,
                maxLines: 2,
                decoration: _inputDecoration.copyWith(
                    hintText:
                        'Ej: Ya iniciaste turno hoy. Espera mañana para iniciar de nuevo.',
                    hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3)),
              ),

              const SizedBox(height: 16),
              Text('Acción si falla',
                  style: AppTextStyles.formLabel.copyWith(color: AppColors.ctText2)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _action,
                decoration: _inputDecoration,
                items: [
                  DropdownMenuItem(value: 'block', child: Text('Bloquear', style: AppTextStyles.body)),
                  DropdownMenuItem(value: 'allow', child: Text('Permitir', style: AppTextStyles.body)),
                ],
                onChanged: (val) => setState(() => _action = val ?? _action),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Escalar si falla', style: AppTextStyles.body),
                value: _escalate,
                activeThumbColor: AppColors.ctTeal,
                onChanged: (val) => setState(() => _escalate = val),
              ),
              if (_escalate) ...[
                const SizedBox(height: 8),
                Text('Motivo de escalación',
                    style: AppTextStyles.formLabel.copyWith(color: AppColors.ctText2)),
                const SizedBox(height: 6),
                TextField(
                  controller: _escalationReasonCtrl,
                  style: AppTextStyles.body,
                  decoration: _inputDecoration.copyWith(
                      hintText: 'Opcional',
                      hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3)),
                ),
              ],

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _GhostButton(
                      label: 'Cancelar',
                      onTap: () => Navigator.of(context).pop()),
                  const SizedBox(width: 8),
                  _PrimaryButton(
                      label: 'Guardar regla', onTap: _submit),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _SemanticWarning ──────────────────────────────────────────────────────────

class _SemanticWarning extends StatelessWidget {
  const _SemanticWarning({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final isDeadlock = message.startsWith('⚠️ DEADLOCK');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDeadlock ? AppColors.ctRedBg : AppColors.ctWarnBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDeadlock
              ? AppColors.ctDanger.withValues(alpha: 0.4)
              : AppColors.ctWarn.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isDeadlock ? Icons.error_outline : Icons.warning_amber_rounded,
            size: 14,
            color: isDeadlock ? AppColors.ctDanger : AppColors.ctWarnText,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(
                color: isDeadlock ? AppColors.ctRedText : AppColors.ctWarnText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
