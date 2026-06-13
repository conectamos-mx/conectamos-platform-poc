import 'dart:async';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/api/catalogs_api.dart';
import '../../core/api/connections_api.dart';
import '../../core/api/channels_api.dart';
import '../../core/api/flows_api.dart';
import '../../core/api/groups_api.dart';
import '../../shared/widgets/asset_item_selector.dart';
import '../../core/api/operator_roles_api.dart';
import '../../core/constants/field_types.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/display_mappers.dart' as dm;
import '../../shared/widgets/app_badge.dart';
import '../../shared/widgets/app_button.dart';
import '../config/template_create_dialog.dart';
import 'widgets/action_mini_diagram.dart';
import 'widgets/precond_mini_diagram.dart';
import 'widgets/variable_picker_dropdown.dart';

import '../../shared/widgets/app_dropdown.dart';
import '../../shared/widgets/app_metric_config_row.dart';
import '../../shared/widgets/app_multi_select.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../core/utils/flow_helpers.dart';

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
  ('ingest', 'API / Ingest'),
  ('scheduled', 'Programado'),
  ('on_complete', 'Al completar otro flujo'),
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

  TabController? _tabCtrl;

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

  // Query config state (query flows only)
  Map<String, dynamic> _queryConfig = {};
  Map<String, String> _queryFieldErrors = {};

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabCtrl?.dispose();
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
        FlowsApi.getFlow(dio: ref.read(apiClientProvider).dio, flowId: widget.flowId),
        OperatorRolesApi.listRoles(dio: ref.read(apiClientProvider).dio, tenantId: tenantId),
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
      final queryConfig = rawBehavior['query_config'] is Map
          ? Map<String, dynamic>.from(
              rawBehavior['query_config'] as Map)
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
        _queryConfig = queryConfig;
        _queryFieldErrors = {};
        _nameCtrl.text = flow['name'] as String? ?? '';
        _descCtrl.text = flow['description'] as String? ?? '';
        _loading = false;
      });
      _tabCtrl?.dispose();
      _tabCtrl = TabController(
        length: isQueryFlow(flow) ? 2 : 4,
        vsync: this,
      );
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
      final flows = await FlowsApi.getFlowsByWorker(dio: ref.read(apiClientProvider).dio, tenantWorkerId: twId);
      if (mounted) setState(() => _workerFlows = flows);
    } catch (_) {}
  }

  Future<void> _save({bool silent = false}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final updated = await FlowsApi.updateFlow(
        dio: ref.read(apiClientProvider).dio,
        flowId: widget.flowId,
        name: _nameCtrl.text.trim(),
        slug: _derivedSlug,
        description: _descCtrl.text.trim(),
        fields: _fields,
        behavior: {
          if (_queryConfig.isNotEmpty) 'query_config': _queryConfig,
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
      final updatedQueryConfig = rawBeh['query_config'] is Map
          ? Map<String, dynamic>.from(rawBeh['query_config'] as Map)
          : _queryConfig;
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
        _queryConfig = updatedQueryConfig;
        _queryFieldErrors = {};
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
      if (e is DioException &&
          e.response?.statusCode == 422 &&
          _flow != null &&
          isQueryFlow(_flow!)) {
        final apiErr = ApiError.from(e);
        if (apiErr != null) {
          setState(() {
            final field = apiErr.meta['field'] as String?;
            _queryFieldErrors = {
              if (field != null) field: apiErr.message else '_general': apiErr.message,
            };
          });
          return;
        }
      }
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
    _save(silent: true);
  }

  List<String> _findFieldReferences(String fieldKey) {
    final refs = <String>[];
    for (final f in _fields) {
      final showIf = f['show_if'] as Map<String, dynamic>?;
      if (showIf != null && showIf['field'] == fieldKey) {
        refs.add('Campo "${f['label'] ?? f['key']}" (condición de visibilidad)');
      }
    }
    for (final action in _actions) {
      if ((action as Map)['count_field_key'] == fieldKey) {
        refs.add('Acción "${action['type']}" en Al cerrar (campo de conteo)');
      }
      final colMap = action['config']?['column_mapping'] as Map?;
      if (colMap != null && colMap.containsKey(fieldKey)) {
        refs.add('Acción "${action['type']}" en Al cerrar (mapeo de columna)');
      }
    }
    final varMapping = _proactiveTrigger['variable_mapping'] as List?;
    if (varMapping != null) {
      for (final vm in varMapping) {
        if ((vm as Map)['source'] == 'fields.$fieldKey') {
          refs.add('Mensaje proactivo (variable_mapping)');
        }
      }
    }
    return refs;
  }

  void _confirmDeleteField(Map<String, dynamic> field, int index) {
    final label = field['label'] as String? ?? field['key'] as String? ?? 'este campo';
    final fieldKey = field['key'] as String? ?? '';
    final refs = _findFieldReferences(fieldKey);

    if (refs.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.ctSurface,
          title: Text(
            'No se puede eliminar "$label"',
            style: AppTextStyles.pageTitle,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Este campo está siendo usado en:',
                style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
              ),
              const SizedBox(height: 8),
              ...refs.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ', style: AppTextStyles.body.copyWith(color: AppColors.ctDanger)),
                        Expanded(
                          child: Text(r, style: AppTextStyles.body.copyWith(color: AppColors.ctText2)),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 8),
              Text(
                'Edita o elimina esas referencias primero.',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
              ),
            ],
          ),
          actions: [
            AppButton(
              label: 'Entendido',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      );
      return;
    }

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
        dio: ref.read(apiClientProvider).dio,
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
        dio: ref.read(apiClientProvider).dio,
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
      await FlowsApi.deleteFlow(dio: ref.read(apiClientProvider).dio, flowId: widget.flowId);
      if (!mounted) return;
      setState(() => _showDeleteModal = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Flujo "${_flow?['name'] ?? ''}" eliminado.'),
        backgroundColor: AppColors.ctOk,
      ));
      widget.onBack();
    } on FlowDeleteBlockedException catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _showDeleteModal = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message), backgroundColor: AppColors.ctDanger,
      ));
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_dioError(e)), backgroundColor: AppColors.ctDanger,
      ));
    }
  }

  Future<void> _saveWithResult({List<String>? triggerSources}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await FlowsApi.updateFlow(
        dio: ref.read(apiClientProvider).dio,
        flowId: widget.flowId,
        name: _nameCtrl.text.trim(),
        slug: _derivedSlug,
        description: _descCtrl.text.trim(),
        fields: _fields,
        behavior: {
          if (_queryConfig.isNotEmpty) 'query_config': _queryConfig,
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
            'la plantilla de mensaje proactivo en esta misma tab.';
      }
      if (detail.isNotEmpty) return detail;
    }
    return 'No se pudo actualizar el trigger. Intenta de nuevo.';
  }

  Widget _buildDeleteModal() {
    final flowName = _flow?['name'] as String? ?? 'este flujo';
    final activeCount = _flow?['active_executions_count'] as int? ?? 0;
    final hasActive = activeCount > 0;
    final canConfirm = !hasActive && _deleteConfirmCtrl.text.trim() == flowName;
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
                    if (hasActive)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.ctRedBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.ctDanger.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline, size: 18, color: AppColors.ctDanger),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'No se puede eliminar: hay $activeCount ejecuci${activeCount == 1 ? 'ón activa' : 'ones activas'} en curso.',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.ctRedText,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Espera a que finalicen o márcalas como abandonadas antes de eliminar este flujo.',
                                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (!hasActive)
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
                              text: 'Las ejecuciones históricas se conservan intactas '
                                  '(datos para reportes y auditoría).',
                            ),
                            const SizedBox(height: 8),
                            _ImpactRow(
                              icon: Icons.block_outlined,
                              color: AppColors.ctDanger,
                              text: 'No se podrán iniciar nuevas ejecuciones de este flujo.',
                            ),
                            const SizedBox(height: 8),
                            _ImpactRow(
                              icon: Icons.info_outline,
                              color: AppColors.ctText2,
                              text: 'El flujo dejará de aparecer en la lista.',
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
                          if (hasActive)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.ctRedBg,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '$activeCount activa${activeCount == 1 ? '' : 's'}',
                                style: AppTextStyles.bodySmall.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ctRedText,
                                ),
                              ),
                            )
                          else
                            Text(
                              'Sin ejecuciones activas',
                              style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      hasActive
                          ? 'No puedes eliminar este flujo mientras tenga ejecuciones activas.'
                          : 'Escribe "$flowName" para confirmar:',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.ctText2),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _deleteConfirmCtrl,
                      autofocus: !hasActive,
                      enabled: !hasActive,
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
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: AppColors.ctBorder),
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
    final isQuery = isQueryFlow(_flow!);
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
                      tabs: isQuery
                          ? const [
                              Tab(text: 'Consulta'),
                              Tab(text: 'Comportamiento'),
                            ]
                          : const [
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
                  children: isQuery
                      ? [
                          _ConsultaTab(
                            queryConfig: _queryConfig,
                            fieldErrors: _queryFieldErrors,
                            tenantId: ref.read(activeTenantIdProvider),
                            dio: ref.read(apiClientProvider).dio,
                            canManage: canManage,
                            onChanged: (updated) {
                              setState(() {
                                _queryConfig = updated;
                                _queryFieldErrors = {};
                              });
                              _save(silent: true);
                            },
                          ),
                          _ComportamientoTab(
                            dio: ref.read(apiClientProvider).dio,
                            conditions: _conditions,
                            flowFields: _fields,
                            canManage: canManage,
                            triggerSources: _triggerSources,
                            flowId: widget.flowId,
                            tenantId: ref.read(activeTenantIdProvider),
                            tenantWorkerId: _flow!['tenant_worker_id'] as String? ?? '',
                            proactiveTrigger: _proactiveTrigger,
                            availableRoles: _availableRoles,
                            allowedRoleIds: _allowedRoleIds,
                            onChanged: (updated) { setState(() => _conditions = updated); _save(silent: true); },
                            onAllowedRoleIdsChanged: (updated) { setState(() => _allowedRoleIds = updated); _save(silent: true); },
                            onProactiveTriggerChanged: (updated) { setState(() => _proactiveTrigger = updated); _save(silent: true); },
                            onTriggerSourcesChanged: (updated) async {
                              final previous = List<String>.from(_triggerSources);
                              setState(() => _triggerSources = updated);
                              try {
                                await _saveWithResult(triggerSources: updated);
                              } catch (e) {
                                if (!context.mounted) return;
                                setState(() => _triggerSources = previous);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(_parseTriggerError(e)),
                                  backgroundColor: AppColors.ctDanger,
                                  duration: const Duration(seconds: 4),
                                ));
                              }
                            },
                          ),
                        ]
                      : [
                          _CamposTab(
                            fields: _fields,
                            canManage: canManage,
                            onReorder: _onReorder,
                            onEditField: (field, index) => _openFieldDialog(field: field, index: index),
                            onDeleteField: (field, index) => _confirmDeleteField(field, index),
                            onAddField: () => _openFieldDialog(),
                          ),
                          _ComportamientoTab(
                            dio: ref.read(apiClientProvider).dio,
                            conditions: _conditions,
                            flowFields: _fields,
                            canManage: canManage,
                            triggerSources: _triggerSources,
                            flowId: widget.flowId,
                            tenantId: ref.read(activeTenantIdProvider),
                            tenantWorkerId: _flow!['tenant_worker_id'] as String? ?? '',
                            proactiveTrigger: _proactiveTrigger,
                            availableRoles: _availableRoles,
                            allowedRoleIds: _allowedRoleIds,
                            onChanged: (updated) { setState(() => _conditions = updated); _save(silent: true); },
                            onAllowedRoleIdsChanged: (updated) { setState(() => _allowedRoleIds = updated); _save(silent: true); },
                            onProactiveTriggerChanged: (updated) { setState(() => _proactiveTrigger = updated); _save(silent: true); },
                            onTriggerSourcesChanged: (updated) async {
                              final previous = List<String>.from(_triggerSources);
                              setState(() => _triggerSources = updated);
                              try {
                                await _saveWithResult(triggerSources: updated);
                              } catch (e) {
                                if (!context.mounted) return;
                                setState(() => _triggerSources = previous);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(_parseTriggerError(e)),
                                  backgroundColor: AppColors.ctDanger,
                                  duration: const Duration(seconds: 4),
                                ));
                              }
                            },
                          ),
                          _PrecondicionesTab(
                            rules: _precondiciones,
                            canManage: canManage,
                            availableRoles: _availableRoles,
                            tenantId: ref.read(activeTenantIdProvider),
                            tenantWorkerId: _flow!['tenant_worker_id'] as String? ?? '',
                            currentFlowSlug: _flow!['slug'] as String? ?? '',
                            currentFlowFields: _fields,
                            dio: ref.read(apiClientProvider).dio,
                            onChanged: (updated) { setState(() => _precondiciones = updated); _save(silent: true); },
                          ),
                          _AlCerrarTab(
                            actions: _actions,
                            canManage: canManage,
                            tenantId: ref.read(activeTenantIdProvider),
                            tenantWorkerId: _flow!['tenant_worker_id'] as String? ?? '',
                            currentFlowSlug: _flow!['slug'] as String? ?? '',
                            flowFields: _fields,
                            dio: ref.read(apiClientProvider).dio,
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
  });

  final Map<String, dynamic> flow;
  final bool isActive;
  final bool saving;
  final VoidCallback onBack;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  @override
  State<_FlowSidePanel> createState() => _FlowSidePanelState();
}

class _FlowSidePanelState extends State<_FlowSidePanel> {
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

                      const Divider(color: AppColors.ctBorder, height: 1),
                      const SizedBox(height: 16),

                      // 6. MÉTRICAS
                      Text('MÉTRICAS', style: AppTextStyles.kpiLabel),
                      const SizedBox(height: 10),
                      _MetricRow(
                        label: 'Ejecuciones totales',
                        value: (widget.flow['execution_count'] as int? ?? 0).toString(),
                      ),
                      const SizedBox(height: 6),
                      _MetricRow(
                        label: 'Ejecuciones activas',
                        value: (widget.flow['active_executions_count'] as int? ?? 0).toString(),
                      ),
                      if (!isQueryFlow(widget.flow)) ...[
                        const SizedBox(height: 6),
                        _MetricRow(
                          label: 'Campos configurados',
                          value: ((widget.flow['fields'] as List?)?.length ?? 0).toString(),
                        ),
                      ],
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
                      color: dm.hexColor(workerColor),
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

// ── _ConsultaTab ──────────────────────────────────────────────────────────────

class _ConsultaTab extends StatefulWidget {
  const _ConsultaTab({
    required this.queryConfig,
    required this.fieldErrors,
    required this.tenantId,
    required this.dio,
    required this.canManage,
    required this.onChanged,
  });
  final Map<String, dynamic> queryConfig;
  final Map<String, String> fieldErrors;
  final String tenantId;
  final Dio dio;
  final bool canManage;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_ConsultaTab> createState() => _ConsultaTabState();
}

class _ConsultaTabState extends State<_ConsultaTab> {
  List<Map<String, dynamic>> _catalogSchema = [];
  bool _loadingSchema = false;
  String? _schemaError;

  List<Map<String, dynamic>> _metrics = [];
  List<String> _filterFields = [];
  List<String> _groupByFields = [];
  String? _dateField;
  String? _operatorBinding;

  String get _entity => widget.queryConfig['entity'] as String? ?? '';

  static const _kAllOps = ['count', 'sum', 'avg', 'min', 'max', 'distinct_count'];

  @override
  void initState() {
    super.initState();
    _syncFromConfig();
    if (_entity.isNotEmpty) _loadCatalogSchema();
  }

  @override
  void didUpdateWidget(_ConsultaTab old) {
    super.didUpdateWidget(old);
    if (old.queryConfig != widget.queryConfig) _syncFromConfig();
  }

  void _syncFromConfig() {
    final qc = widget.queryConfig;
    _metrics = List<Map<String, dynamic>>.from(
      (qc['metrics'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e)),
    );
    _filterFields = List<String>.from(
      (qc['filter_fields'] as List? ?? []).map((e) => e.toString()),
    );
    _groupByFields = List<String>.from(
      (qc['group_by_fields'] as List? ?? []).map((e) => e.toString()),
    );
    _dateField = qc['date_field'] as String?;
    _operatorBinding = qc['operator_binding'] as String?;
  }

  Future<void> _loadCatalogSchema() async {
    setState(() {
      _loadingSchema = true;
      _schemaError = null;
    });
    try {
      final catalog = await CatalogsApi.getCatalogBySlug(
        dio: widget.dio,
        tenantId: widget.tenantId,
        slug: _entity,
      );
      if (!mounted) return;
      final schema = (catalog['fields_schema'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      setState(() {
        _catalogSchema = schema;
        _loadingSchema = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _schemaError = 'Error al cargar esquema del cat\u00E1logo';
        _loadingSchema = false;
      });
    }
  }

  String _schemaLabel(String key) {
    if (key == '*') return '';
    for (final f in _catalogSchema) {
      if (f['key'] == key) return f['label'] as String? ?? key;
    }
    return key;
  }

  List<AppDropdownItem<String>> get _fieldItems => [
        const AppDropdownItem(value: '*', label: '* (todos \u2014 solo conteo)'),
        ..._catalogSchema.map((f) => AppDropdownItem<String>(
              value: f['key'] as String? ?? '',
              label: f['label'] as String? ?? f['key'] as String? ?? '',
            )),
      ];

  List<AppMultiSelectItem<String>> get _schemaItems =>
      _catalogSchema.map((f) => AppMultiSelectItem<String>(
            value: f['key'] as String? ?? '',
            label: f['label'] as String? ?? f['key'] as String? ?? '',
          )).toList();

  Map<String, dynamic> _buildConfig() => {
        'entity': _entity,
        'metrics': _metrics,
        'filter_fields': _filterFields,
        'group_by_fields': _groupByFields,
        if (_dateField != null) 'date_field': _dateField,
        if (_operatorBinding != null) 'operator_binding': _operatorBinding,
      };

  void _emitChange() => widget.onChanged(_buildConfig());

  // ── Metric management ──────────────────────────────────────────────────────

  void _addMetric() {
    setState(() {
      _metrics = [..._metrics, {'key': '', 'ops': <String>[]}];
    });
  }

  void _removeMetric(int index) {
    setState(() {
      _metrics = [..._metrics]..removeAt(index);
    });
    _emitChange();
  }

  void _updateMetricKey(int index, String? key) {
    if (key == null) return;
    setState(() {
      final m = Map<String, dynamic>.from(_metrics[index]);
      m['key'] = key;
      if (key == '*') {
        m['ops'] = ['count'];
        m.remove('display_name');
      }
      if (m['display_name'] == _schemaLabel(key)) m.remove('display_name');
      _metrics = [..._metrics]..[index] = m;
    });
    _emitChange();
  }

  void _updateMetricOps(int index, List<String> ops) {
    setState(() {
      final m = Map<String, dynamic>.from(_metrics[index]);
      m['ops'] = ops;
      _metrics = [..._metrics]..[index] = m;
    });
    _emitChange();
  }

  void _commitDisplayName(int index, String value) {
    final m = Map<String, dynamic>.from(_metrics[index]);
    final key = m['key'] as String? ?? '';
    final inherited = _schemaLabel(key);
    if (value.isEmpty || value == inherited) {
      m.remove('display_name');
    } else {
      m['display_name'] = value;
    }
    setState(() => _metrics = [..._metrics]..[index] = m);
    _emitChange();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loadingSchema) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.ctTeal),
      );
    }
    if (_schemaError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_schemaError!,
                style: AppTextStyles.body.copyWith(color: AppColors.ctDanger)),
            const SizedBox(height: 12),
            AppButton(
              label: 'Reintentar',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              onPressed: _loadCatalogSchema,
            ),
          ],
        ),
      );
    }

    final generalError = widget.fieldErrors['_general'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (generalError != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.ctDanger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.ctDanger.withValues(alpha: 0.3)),
              ),
              child: Text(generalError,
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctDanger)),
            ),
            const SizedBox(height: 16),
          ],

          // ── Cat\u00E1logo (read-only) ──
          Text('CAT\u00C1LOGO', style: AppTextStyles.kpiLabel),
          const SizedBox(height: 8),
          AppDropdown<String>(
            items: [AppDropdownItem(value: _entity, label: _entity)],
            value: _entity,
            enabled: false,
            onChanged: (_) {},
          ),

          const SizedBox(height: 24),

          // ── M\u00E9tricas ──
          Row(
            children: [
              Expanded(
                child: Text('M\u00C9TRICAS', style: AppTextStyles.kpiLabel),
              ),
              if (widget.canManage)
                AppButton(
                  label: '+ Agregar',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                  onPressed: _addMetric,
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_metrics.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Sin m\u00E9tricas configuradas.',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3)),
            )
          else
            ...List.generate(_metrics.length, _buildMetricRow),
          if (widget.fieldErrors['metrics'] != null) ...[
            const SizedBox(height: 4),
            Text(widget.fieldErrors['metrics']!,
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctDanger)),
          ],

          const SizedBox(height: 24),

          // ── Campos de filtro ──
          Text('CAMPOS DE FILTRO (m\u00E1x. 5)', style: AppTextStyles.kpiLabel),
          const SizedBox(height: 8),
          AppMultiSelect<String>(
            items: _schemaItems,
            selectedValues: _filterFields,
            placeholder: 'Selecciona campos de filtro...',
            searchable: true,
            onChanged: widget.canManage
                ? (vals) {
                    if (vals.length > 5) return;
                    setState(() => _filterFields = vals);
                    _emitChange();
                  }
                : (_) {},
          ),
          if (widget.fieldErrors['filter_fields'] != null) ...[
            const SizedBox(height: 4),
            Text(widget.fieldErrors['filter_fields']!,
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctDanger)),
          ],

          const SizedBox(height: 24),

          // ── Campos de agrupaci\u00F3n ──
          Text('CAMPOS DE AGRUPACI\u00D3N', style: AppTextStyles.kpiLabel),
          const SizedBox(height: 8),
          AppMultiSelect<String>(
            items: _schemaItems,
            selectedValues: _groupByFields,
            placeholder: 'Selecciona campos de agrupaci\u00F3n...',
            searchable: true,
            onChanged: widget.canManage
                ? (vals) {
                    setState(() => _groupByFields = vals);
                    _emitChange();
                  }
                : (_) {},
          ),

          const SizedBox(height: 24),

          // ── Campo de fecha ──
          Text('CAMPO DE FECHA', style: AppTextStyles.kpiLabel),
          const SizedBox(height: 8),
          AppDropdown<String>(
            items: _dateFieldItems(),
            value: _dateField,
            hint: 'Ninguno (opcional)',
            enabled: widget.canManage,
            onChanged: (v) {
              setState(() => _dateField = v);
              _emitChange();
            },
          ),

          const SizedBox(height: 24),

          // ── Vinculaci\u00F3n de operador ──
          Text('VINCULACI\u00D3N DE OPERADOR', style: AppTextStyles.kpiLabel),
          const SizedBox(height: 4),
          Text('Define c\u00F3mo se vincula el operador con los datos del cat\u00E1logo.',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2)),
          const SizedBox(height: 8),
          AppDropdown<String>(
            items: const [
              AppDropdownItem(value: '', label: 'Sin vinculaci\u00F3n'),
              AppDropdownItem(value: 'phone', label: 'Tel\u00E9fono'),
              AppDropdownItem(value: 'external_id', label: 'ID externo'),
            ],
            value: _operatorBinding ?? '',
            enabled: widget.canManage,
            onChanged: (v) {
              setState(() => _operatorBinding = v == '' ? null : v);
              _emitChange();
            },
          ),
        ],
      ),
    );
  }

  List<AppDropdownItem<String>> _dateFieldItems() {
    final dateFields = _catalogSchema.where((f) {
      final type = f['type'] as String? ?? '';
      return type == 'date' || type == 'datetime' || type == 'timestamp';
    }).toList();
    final source = dateFields.isNotEmpty ? dateFields : _catalogSchema;
    return source
        .map((f) => AppDropdownItem<String>(
              value: f['key'] as String? ?? '',
              label: f['label'] as String? ?? f['key'] as String? ?? '',
            ))
        .toList();
  }

  Widget _buildMetricRow(int index) {
    final m = _metrics[index];
    final key = m['key'] as String? ?? '';
    final ops =
        List<String>.from((m['ops'] as List? ?? []).map((e) => e.toString()));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppMetricConfigRow(
        key: ValueKey('metric_$index'),
        fieldItems: _fieldItems,
        selectedKey: key.isEmpty ? null : key,
        ops: ops,
        allOps: _kAllOps,
        inheritedLabel: _schemaLabel(key),
        displayName: m['display_name'] as String?,
        canManage: widget.canManage,
        onKeyChanged: (v) => _updateMetricKey(index, v),
        onOpsChanged: (v) => _updateMetricOps(index, v),
        onDisplayNameCommitted: (v) => _commitDisplayName(index, v),
        onRemove: () => _removeMetric(index),
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

  String _resolveFieldLabel(String key) {
    final match = fields.where((f) => f['key'] == key).firstOrNull;
    return match?['label'] as String? ?? match?['key'] as String? ?? key;
  }

  Map<String, List<Map<String, dynamic>>> _groupByCondition(
      List<Map<String, dynamic>> conds) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final f in conds) {
      final si = f['show_if'] as Map<String, dynamic>;
      final field = si['field'] as String? ?? '';
      final value = si['value'];
      final valueStr =
          value is List ? value.join(', ') : value.toString();
      final key = '$field::$valueStr';
      groups.putIfAbsent(key, () => []).add(f);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final alwaysFields =
        fields.where((f) => f['show_if'] == null).toList();
    final conditionalFields =
        fields.where((f) => f['show_if'] != null).toList();
    final condGroups = _groupByCondition(conditionalFields);

    return CustomScrollView(
      slivers: [
        // Header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Campos del flujo (${fields.length})',
                      style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    if (canManage)
                      AppButton(
                        label: '+ Agregar campo',
                        variant: AppButtonVariant.primary,
                        size: AppButtonSize.sm,
                        onPressed: onAddField,
                      ),
                  ],
                ),
                if (fields.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Builder(builder: (_) {
                    final requiredCount = fields.where((f) => f['required'] == true).length;
                    final optionalCount = fields.where((f) => f['required'] != true && f['show_if'] == null).length;
                    final conditionalCount = fields.where((f) => f['show_if'] != null).length;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (requiredCount > 0)
                          _CountBadge(
                            icon: '⭐',
                            count: requiredCount,
                            label: requiredCount == 1 ? 'requerido' : 'requeridos',
                            bgColor: AppColors.ctTealLight,
                            textColor: AppColors.ctNavy,
                          ),
                        if (optionalCount > 0)
                          _CountBadge(
                            icon: '○',
                            count: optionalCount,
                            label: optionalCount == 1 ? 'opcional' : 'opcionales',
                            bgColor: AppColors.ctSurface,
                            textColor: AppColors.ctText2,
                            borderColor: AppColors.ctBorder,
                          ),
                        if (conditionalCount > 0)
                          _CountBadge(
                            icon: '↳',
                            count: conditionalCount,
                            label: conditionalCount == 1 ? 'condicional' : 'condicionales',
                            bgColor: AppColors.ctTealLight,
                            textColor: AppColors.ctTeal,
                          ),
                      ],
                    );
                  }),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      Text('⭐ Requerido · Debe completarse siempre',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3)),
                      Text('○ Opcional · Puede dejarse vacío',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3)),
                      Text('↳ Condicional · Aparece solo si se cumple la condición',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3)),
                    ],
                  ),
                ],
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
        else ...[
          // ── Siempre presentes ──
          if (alwaysFields.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _SectionDivider(
                  label: 'SIEMPRE PRESENTES — ${alwaysFields.length}',
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverReorderableList(
                itemCount: alwaysFields.length,
                onReorder: canManage
                    ? (oldIdx, newIdx) {
                        // Map local indices back to global indices
                        final globalOld = fields.indexOf(alwaysFields[oldIdx]);
                        var globalNew = newIdx >= alwaysFields.length
                            ? fields.indexOf(alwaysFields.last) + 1
                            : fields.indexOf(alwaysFields[newIdx]);
                        if (globalNew > globalOld) globalNew--;
                        onReorder(globalOld, globalNew > globalOld ? globalNew + 1 : globalNew);
                      }
                    : (int a, int b) {},
                itemBuilder: (context, i) {
                  final field = alwaysFields[i];
                  final id = field['id']?.toString() ?? 'a$i';
                  return _FieldRow(
                    key: ValueKey(id),
                    field: field,
                    index: i,
                    canManage: canManage,
                    isLast: i == alwaysFields.length - 1,
                    onEdit: () => onEditField(field, fields.indexOf(field)),
                    onDelete: () => onDeleteField(field, fields.indexOf(field)),
                  );
                },
              ),
            ),
          ],

          // ── Condicionales ──
          if (conditionalFields.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _SectionDivider(
                  label: 'CONDICIONALES — ${conditionalFields.length}',
                  labelColor: AppColors.ctTeal,
                ),
              ),
            ),
            ...condGroups.entries.expand((entry) {
              final parts = entry.key.split('::');
              final fieldKey = parts.first;
              final valueStr = parts.length > 1 ? parts.sublist(1).join('::') : '';
              final fieldLabel = _resolveFieldLabel(fieldKey);
              final groupFields = entry.value;

              return [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.ctTealLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: RichText(
                        text: TextSpan(
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctNavy),
                          children: [
                            const TextSpan(text: '↳ Si '),
                            TextSpan(
                              text: fieldLabel,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const TextSpan(text: ' = '),
                            TextSpan(
                              text: valueStr,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.ctTeal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverReorderableList(
                    itemCount: groupFields.length,
                    onReorder: canManage
                        ? (oldIdx, newIdx) {
                            // Map local group indices → global _fields indices
                            final globalIndices = groupFields
                                .map((f) => fields.indexOf(f))
                                .toList();
                            final oldGlobal = globalIndices[oldIdx];
                            int targetGlobal;
                            if (newIdx >= groupFields.length) {
                              targetGlobal = globalIndices.last + 1;
                            } else {
                              targetGlobal = globalIndices[newIdx];
                            }
                            if (oldIdx < newIdx) {
                              targetGlobal -= 1;
                            }
                            // Convert post-removal insert position to
                            // pre-removal convention expected by _onReorder
                            final newGlobal = targetGlobal >= oldGlobal
                                ? targetGlobal + 1
                                : targetGlobal;
                            onReorder(oldGlobal, newGlobal);
                          }
                        : (int a, int b) {},
                    itemBuilder: (context, i) {
                      final field = groupFields[i];
                      return _FieldRow(
                        key: ValueKey(field['id']?.toString() ?? 'c$i'),
                        field: field,
                        index: i,
                        canManage: canManage,
                        isLast: i == groupFields.length - 1,
                        indented: true,
                        onEdit: () =>
                            onEditField(field, fields.indexOf(field)),
                        onDelete: () =>
                            onDeleteField(field, fields.indexOf(field)),
                      );
                    },
                  ),
                ),
              ];
            }),
          ],
        ],

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
    this.indented = false,
  });

  final Map<String, dynamic> field;
  final int index;
  final bool canManage;
  final bool isLast;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool indented;

  @override
  Widget build(BuildContext context) {
    final label = field['label'] as String? ?? field['key'] as String? ?? '—';
    final type = field['type'] as String? ?? 'text';
    final required = field['required'] as bool? ?? false;

    final typeLabel = kFieldTypes
        .where((e) => e.$1 == type)
        .map((e) => e.$2)
        .firstOrNull ?? type;

    return Padding(
      padding: EdgeInsets.only(left: indented ? 16.0 : 0.0),
      child: Container(
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
      ),
    );
  }
}

// ── _CountBadge ──────────────────────────────────────────────────────────────

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.icon,
    required this.count,
    required this.label,
    required this.bgColor,
    required this.textColor,
    this.borderColor,
  });
  final String icon;
  final int count;
  final String label;
  final Color bgColor;
  final Color textColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: borderColor != null ? Border.all(color: borderColor!) : null,
      ),
      child: Text(
        '$icon $count $label',
        style: AppTextStyles.bodySmall.copyWith(
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ── _SectionDivider ──────────────────────────────────────────────────────────

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({required this.label, this.labelColor});
  final String label;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final color = labelColor ?? AppColors.ctText3;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppColors.ctBorder, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: AppTextStyles.kpiLabel.copyWith(
                color: color,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Expanded(child: Divider(color: AppColors.ctBorder, height: 1)),
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
    required this.dio,
    this.field,
  });

  final Map<String, dynamic>? field;
  final String tenantId;
  final String tenantWorkerId;
  final List<Map<String, dynamic>> flowFields;
  final void Function(Map<String, dynamic>) onSaved;
  final Dio dio;

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
  String? _fillStrategy;

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
      _fillStrategy = widget.field!['fill_strategy'] as String?;
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
      final cats = await CatalogsApi.listCatalogs(dio: widget.dio, tenantId: widget.tenantId);
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
    if (_fillStrategy != null) {
      updated['fill_strategy'] = _fillStrategy;
    } else {
      updated.remove('fill_strategy');
    }
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
              const SizedBox(height: 14),

              // Fill strategy
              AppDropdown<String?>(
                label: '¿Cómo se captura este campo?',
                value: _fillStrategy,
                hint: 'Conversacional',
                items: const [
                  AppDropdownItem(
                    value: null,
                    label: 'Conversacional',
                    subtitle: 'El Worker lo solicita al operador durante la conversación',
                  ),
                  AppDropdownItem(
                    value: 'defer_dashboard',
                    label: 'Desde el dashboard',
                    subtitle: 'Un supervisor lo llena manualmente desde el panel de ejecuciones',
                  ),
                ],
                onChanged: (v) => setState(() => _fillStrategy = v),
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
                        else if (_showIfRefType == 'bool' || _showIfRefType == 'boolean')
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
    required this.dio,
    required this.conditions,
    required this.flowFields,
    required this.canManage,
    required this.triggerSources,
    required this.flowId,
    required this.tenantId,
    required this.tenantWorkerId,
    required this.proactiveTrigger,
    required this.availableRoles,
    required this.allowedRoleIds,
    required this.onChanged,
    required this.onAllowedRoleIdsChanged,
    required this.onProactiveTriggerChanged,
    required this.onTriggerSourcesChanged,
  });

  final Dio dio;
  final List<Map<String, dynamic>> conditions;
  final List<Map<String, dynamic>> flowFields;
  final bool canManage;
  final List<String> triggerSources;
  final String flowId;
  final String tenantId;
  final String tenantWorkerId;
  final Map<String, dynamic> proactiveTrigger;
  final List<Map<String, dynamic>> availableRoles;
  final List<String> allowedRoleIds;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final ValueChanged<List<String>> onAllowedRoleIdsChanged;
  final ValueChanged<Map<String, dynamic>> onProactiveTriggerChanged;
  final ValueChanged<List<String>> onTriggerSourcesChanged;

  @override
  State<_ComportamientoTab> createState() => _ComportamientoTabState();
}

class _ComportamientoTabState extends State<_ComportamientoTab> {
  late List<Map<String, dynamic>> _conditions;
  late List<String> _allowedRoleIds;
  late List<String> _triggerSources;

  // Proactive trigger state
  String? _waChannelId;
  List<Map<String, dynamic>> _approvedTemplates = [];
  bool _loadingTemplates = false;
  Map<String, String> _mappingRows = {};

  @override
  void initState() {
    super.initState();
    _conditions = List.from(widget.conditions);
    _allowedRoleIds = List.from(widget.allowedRoleIds);
    _triggerSources = List.from(widget.triggerSources);
    if (widget.tenantWorkerId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadWaChannel();
        _initMappingRows();
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void didUpdateWidget(_ComportamientoTab old) {
    super.didUpdateWidget(old);
    if (old.conditions != widget.conditions) {
      _conditions = List.from(widget.conditions);
    }
    if (old.allowedRoleIds != widget.allowedRoleIds) {
      _allowedRoleIds = List.from(widget.allowedRoleIds);
    }
    if (!listEquals(old.triggerSources, widget.triggerSources)) {
      setState(() => _triggerSources = List.from(widget.triggerSources));
    }
  }

  Future<void> _loadWaChannel() async {
    if (widget.tenantWorkerId.isEmpty) return;
    try {
      final channels = await ChannelsApi.listChannelsByWorker(
        dio: widget.dio,
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
      final all = await ChannelsApi.listTemplates(dio: widget.dio, channelId: channelId);
      if (!mounted) return;
      setState(() {
        _approvedTemplates =
            all.where((t) => (t['status'] as String?) == 'APPROVED').toList();
        _loadingTemplates = false;
      });
      // Auto-init mapping rows from selected template
      final tid = widget.proactiveTrigger['template_id'] as String?;
      if (tid != null) {
        final t = _approvedTemplates
            .where((t) => (t['id'] as String? ?? t['name'] as String? ?? '') == tid)
            .firstOrNull;
        if (t != null) _initMappingFromTemplate(t);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingTemplates = false);
    }
  }

  void _initMappingFromTemplate(Map<String, dynamic> template) {
    // 1. Variables declaradas en el template
    final declared = ((template['variables'] as List<dynamic>?) ?? [])
        .map((v) => {
              'slot': (v as Map)['slot'] as int? ?? 0,
              'key': v['key'] as String? ?? '',
            })
        .toList();

    // 2. Slots presentes en body_text via {{N}}
    final body = template['body_text'] as String? ?? '';
    final bodySlots = RegExp(r'\{\{(\d+)\}\}')
        .allMatches(body)
        .map((m) => int.tryParse(m.group(1) ?? '') ?? 0)
        .where((s) => s > 0)
        .toSet();

    // 3. Agregar entradas sintéticas para slots en body pero no en variables
    final declaredSlots = declared.map((v) => v['slot'] as int).toSet();
    final missing = bodySlots.difference(declaredSlots);
    for (final slot in missing.toList()..sort()) {
      declared.add({'slot': slot, 'key': 'variable_$slot'});
    }

    // 4. Ordenar por slot
    declared.sort((a, b) =>
        (a['slot'] as int).compareTo(b['slot'] as int));

    // 5. Existing mapping para preservar selecciones previas
    final existing = Map<String, String>.fromEntries(
      ((widget.proactiveTrigger['variable_mapping'] as List<dynamic>?) ?? [])
          .map((e) => MapEntry(
                (e as Map)['variable'] as String? ?? '',
                e['source'] as String? ?? '',
              ))
          .where((e) => e.key.isNotEmpty),
    );

    setState(() {
      _mappingRows = {
        for (final v in declared)
          (v['key'] as String): existing[v['key'] as String] ?? '',
      };
    });
  }

  void _initMappingRows() {
    // Legacy fallback: load from existing variable_mapping without template
    final existing = (widget.proactiveTrigger['variable_mapping'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    setState(() {
      _mappingRows = {
        for (final e in existing)
          (e['variable'] as String? ?? ''): (e['source'] as String? ?? ''),
      };
    });
  }

  void _updateProactiveTrigger({String? templateId}) {
    final effectiveTemplateId =
        templateId ?? widget.proactiveTrigger['template_id'] as String?;
    final mapping = _mappingRows.entries
        .where((e) => e.key.isNotEmpty && e.value.isNotEmpty)
        .map((e) => {'variable': e.key, 'source': e.value})
        .toList();
    final updated = <String, dynamic>{
      // ignore: use_null_aware_elements
      if (effectiveTemplateId != null) 'template_id': effectiveTemplateId,
      if (mapping.isNotEmpty) 'variable_mapping': mapping,
    };
    widget.onProactiveTriggerChanged(updated);
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

  Widget _buildTemplateBodyPreview(String body) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'(\{\{\d+\}\})');
    int lastEnd = 0;
    for (final match in regex.allMatches(body)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: body.substring(lastEnd, match.start),
          style: AppTextStyles.body,
        ));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: AppTextStyles.body.copyWith(
          color: AppColors.ctTeal,
          fontWeight: FontWeight.w600,
        ),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < body.length) {
      spans.add(TextSpan(
        text: body.substring(lastEnd),
        style: AppTextStyles.body,
      ));
    }
    return RichText(text: TextSpan(children: spans));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1. Disparadores ────────────────────────────────────────────
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
                  'Disparadores del flujo',
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  '¿Desde dónde puede iniciarse este flujo?',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _kTriggerSources.map((entry) {
                    final (value, label) = entry;
                    final selected = _triggerSources.contains(value);
                    return GestureDetector(
                      onTap: widget.canManage
                          ? () {
                              setState(() {
                                if (selected) {
                                  if (_triggerSources.length > 1) {
                                    _triggerSources.remove(value);
                                  }
                                } else {
                                  _triggerSources.add(value);
                                }
                              });
                              widget.onTriggerSourcesChanged(
                                  List.from(_triggerSources));
                            }
                          : null,
                      child: MouseRegion(
                        cursor: widget.canManage
                            ? SystemMouseCursors.click
                            : SystemMouseCursors.basic,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.ctTealLight
                                : AppColors.ctSurface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected
                                  ? AppColors.ctTeal
                                  : AppColors.ctBorder,
                            ),
                          ),
                          child: Text(
                            label,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: selected
                                  ? AppColors.ctTealDark
                                  : AppColors.ctText2,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 2. Plantilla de mensaje proactivo ─────────────────────────
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
                  'Plantilla de mensaje proactivo para eventos programados',
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Se enviará al operador cuando este flujo sea iniciado por una asignación programada.',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
                ),
                const SizedBox(height: 12),
                if (_waChannelId == null)
                  Text(
                    'No se encontró canal de WhatsApp activo en este worker.',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
                  )
                else if (_loadingTemplates)
                  const SizedBox(
                    height: 24, width: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.ctTeal),
                  )
                else if (_approvedTemplates.isEmpty)
                  Text(
                    'No hay plantillas aprobadas. Sincroniza las plantillas en Canales.',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
                  )
                else ...[
                    AppDropdown<String?>(
                      label: 'Plantilla',
                      value: widget.proactiveTrigger['template_id'] as String?,
                      hint: 'Selecciona plantilla',
                      enabled: widget.canManage,
                      items: [
                        const AppDropdownItem<String?>(
                            value: null, label: '— Sin plantilla —'),
                        ..._approvedTemplates.map((t) {
                          final id = t['id'] as String? ?? t['name'] as String? ?? '';
                          final name = t['name'] as String? ?? id;
                          final lang = t['language'] as String? ?? '';
                          return AppDropdownItem<String?>(
                            value: id,
                            label: '$name ($lang)',
                          );
                        }),
                        const AppDropdownItem<String?>(
                          value: '__create__',
                          label: '＋ Crear nueva plantilla',
                        ),
                      ],
                      onChanged: (v) {
                        if (v == '__create__') {
                          if (_waChannelId == null) return;
                          showDialog<void>(
                            context: context,
                            builder: (_) => TemplateCreateDialog(
                              channelId: _waChannelId!,
                              tenantId: widget.tenantId,
                            ),
                          ).then((_) {
                            if (_waChannelId != null) {
                              _loadTemplates(_waChannelId!);
                            }
                          });
                          return;
                        }
                        if (v == null) {
                          setState(() => _mappingRows = {});
                          widget.onProactiveTriggerChanged({});
                        } else {
                          _updateProactiveTrigger(templateId: v);
                          final t = _approvedTemplates
                              .where((t) =>
                                  (t['id'] as String? ?? t['name'] as String? ?? '') == v)
                              .firstOrNull;
                          if (t != null) _initMappingFromTemplate(t);
                        }
                      },
                    ),
                    // ── Template preview ──
                    Builder(builder: (_) {
                      final tid = widget.proactiveTrigger['template_id'] as String?;
                      final sel = tid == null
                          ? null
                          : _approvedTemplates
                              .where((t) => (t['id'] as String? ?? t['name'] as String? ?? '') == tid)
                              .firstOrNull;
                      if (sel == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.ctSurface,
                            border: Border.all(color: AppColors.ctBorder),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((sel['header_text'] as String?) != null) ...[
                                Text(
                                  sel['header_text'] as String,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.ctText2,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                              ],
                              _buildTemplateBodyPreview(
                                sel['body_text'] as String? ?? '',
                              ),
                              if ((sel['footer_text'] as String?) != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  sel['footer_text'] as String,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.ctText3,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                    // ── Mapeo de variables (auto-generado desde template) ──
                    if (_mappingRows.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('Mapeo de variables',
                          style: AppTextStyles.body
                              .copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      ..._mappingRows.entries.map((entry) {
                        final key = entry.key;
                        final source = entry.value;
                        // Find slot from template variables
                        final tid = widget.proactiveTrigger['template_id'] as String?;
                        final tpl = tid == null
                            ? null
                            : _approvedTemplates
                                .where((t) =>
                                    (t['id'] as String? ?? t['name'] as String? ?? '') == tid)
                                .firstOrNull;
                        final vars = (tpl?['variables'] as List<dynamic>?) ?? [];
                        final vDef = vars
                            .where((v) => (v as Map)['key'] == key)
                            .firstOrNull as Map?;
                        final slot = vDef?['slot'] as int? ?? 0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: AppColors.ctSurface,
                                    border: Border.all(color: AppColors.ctBorder),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    key.startsWith('variable_')
                                        ? '{{$slot}}'
                                        : '$key  {{$slot}}',
                                    style: AppTextStyles.body,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: AppDropdown<String>(
                                  value: source.isEmpty ? null : source,
                                  hint: 'Campo fuente',
                                  enabled: widget.canManage,
                                  items: const [
                                    AppDropdownItem<String>(
                                        value: '', label: '— Sin campo —'),
                                    AppDropdownItem<String>(
                                      value: 'system:operator.name',
                                      label: 'Nombre del operador',
                                    ),
                                    AppDropdownItem<String>(
                                      value: 'system:operator.phone',
                                      label: 'Teléfono del operador',
                                    ),
                                    AppDropdownItem<String>(
                                      value: 'system:tenant.name',
                                      label: 'Nombre de la empresa',
                                    ),
                                    AppDropdownItem<String>(
                                      value: 'system:flow.name',
                                      label: 'Nombre del flujo',
                                    ),
                                    AppDropdownItem<String>(
                                      value: 'system:flow.fields_summary',
                                      label: 'Campos del flujo (lista)',
                                    ),
                                  ],
                                  onChanged: (v) {
                                    if (!widget.canManage) return;
                                    setState(() => _mappingRows[key] = v ?? '');
                                    _updateProactiveTrigger();
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      if (_mappingRows.isNotEmpty &&
                          _mappingRows.values.every((v) => v.isNotEmpty)) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            AppButton(
                              label: 'Guardar mapeo',
                              variant: AppButtonVariant.primary,
                              size: AppButtonSize.sm,
                              onPressed: () {
                                if (!widget.canManage) return;
                                _updateProactiveTrigger();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Mapeo guardado'),
                                    backgroundColor: AppColors.ctOk,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ],
              ),
          ),
          const SizedBox(height: 16),

          // ── 3. Roles autorizados ───────────────────────────────────────
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
                const SizedBox(height: 8),
                Text(
                  'Solo los operadores con estos roles podrán iniciar este flujo. Si no se selecciona ninguno, todos los roles tienen acceso.',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
                ),
                const SizedBox(height: 12),
                if (widget.availableRoles.isEmpty)
                  Text(
                    'No hay roles definidos. Crea roles en Operadores → Roles.',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.availableRoles.map((role) {
                      final id = role['id'] as String? ?? '';
                      final label = role['label'] as String? ?? id;
                      final color = dm.hexColor(role['color'] as String?);
                      final selected = _allowedRoleIds.contains(id);
                      return FilterChip(
                        label: Text(label,
                            style: AppTextStyles.bodySmall.copyWith(
                                fontSize: 12, color: AppColors.ctText)),
                        selected: selected,
                        selectedColor: color.withValues(alpha: 0.15),
                        checkmarkColor: color,
                        backgroundColor: AppColors.ctBg,
                        side: BorderSide(
                            color: selected ? color : AppColors.ctBorder),
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
    required this.dio,
  });

  final List<Map<String, dynamic>> actions;
  final bool canManage;
  final String tenantId;
  final String tenantWorkerId;
  final String currentFlowSlug;
  final List<Map<String, dynamic>> flowFields;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final Dio dio;

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
        dio: widget.dio,
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

  void _toggleAction(Map<String, dynamic> action) {
    setState(() {
      final idx = _actions.indexWhere((a) => a['id'] == action['id']);
      if (idx < 0) return;
      _actions[idx] = {
        ..._actions[idx],
        'enabled': !(_actions[idx]['enabled'] as bool? ?? true),
      };
    });
    widget.onChanged(List.from(_actions));
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
                  variant: AppButtonVariant.primary,
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
          if (_actions.isNotEmpty) ...[
            _OnCompleteTimeline(actions: _actions),
            const SizedBox(height: 16),
          ],
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
                index: i,
                canManage: widget.canManage,
                onEdit: () => _openActionDialog(_actions[i]),
                onDelete: () => _deleteAction(_actions[i]),
                onToggle: () => _toggleAction(_actions[i]),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── _ActionCard ───────────────────────────────────────────────────────────────

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
    case 'notify_group':
      return 'Enviar notificación';
    case 'google_sheets_update_row':
      return 'Google Sheets — Actualizar fila';
    case 'excel_onedrive_append_row':
      return 'Excel OneDrive — Agregar fila';
    case 'excel_onedrive_update_row':
      return 'Excel OneDrive — Actualizar fila';
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
    case 'notify_group':
      final gName = action['_group_display_name'] as String? ?? action['group_id'] as String? ?? '';
      final destType = action['destination_type'] as String? ?? 'group';
      final prefix = destType == 'control_tower' ? '🗼' : '📢';
      return '$prefix $gName';
    case 'google_sheets_update_row':
      final uConfig = action['config'] as Map? ?? {};
      final uSid = uConfig['spreadsheet_id'] as String? ?? '';
      final uDisplay = uSid.length > 20 ? '${uSid.substring(0, 20)}…' : uSid;
      return '📊 $uDisplay';
    case 'excel_onedrive_append_row':
      final eConfig = action['config'] as Map? ?? {};
      final fileId = eConfig['file_id'] as String? ?? '';
      final eDisplay = fileId.length > 20 ? '${fileId.substring(0, 20)}…' : fileId;
      return '📊 $eDisplay';
    case 'excel_onedrive_update_row':
      final euConfig = action['config'] as Map? ?? {};
      final euFileId = euConfig['file_id'] as String? ?? '';
      final euDisplay = euFileId.length > 20 ? '${euFileId.substring(0, 20)}…' : euFileId;
      return '📊 $euDisplay';
    default:
      return '';
  }
}

Color _actionCatColor(String? type) => switch (type) {
      'open_flow' || 'open_flow_n_times' => const Color(0xFF8B5CF6),
      'webhook_out' => const Color(0xFF3B82F6),
      'google_sheets_append_row' || 'google_sheets_update_row' || 'excel_onedrive_append_row' || 'excel_onedrive_update_row' => const Color(0xFF10B981),
      'emit_event' => const Color(0xFFF59E0B),
      _ => AppColors.ctTeal,
    };

String _actionCatLabel(String? type) => switch (type) {
      'open_flow' || 'open_flow_n_times' => 'Encadenar flujos',
      'webhook_out' => 'Sistemas externos',
      'google_sheets_append_row' || 'google_sheets_update_row' || 'excel_onedrive_append_row' || 'excel_onedrive_update_row' => 'Hojas de cálculo',
      'emit_event' => 'Eventos internos',
      _ => 'Acción',
    };

class _ActionCard extends StatefulWidget {
  const _ActionCard({
    required this.action,
    required this.index,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final Map<String, dynamic> action;
  final int index;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final type = widget.action['type'] as String? ?? '';
    final condition = widget.action['condition'] as String?;
    final enabled = widget.action['enabled'] as bool? ?? true;
    final catColor = _actionCatColor(type);
    final catLabel = _actionCatLabel(type);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.6,
        child: InkWell(
          onTap: widget.canManage ? widget.onEdit : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.ctSurface,
              border: Border.all(color: AppColors.ctBorder),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // [1] Strip izquierdo
                  Container(
                    width: 38,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          catColor.withValues(alpha: 0.07),
                          catColor.withValues(alpha: 0.04),
                        ],
                      ),
                      border: Border(
                        right: BorderSide(color: catColor.withValues(alpha: 0.12)),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: catColor,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${widget.index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // [2] Mini diagrama
                  Container(
                    width: 120,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFAFAFA),
                      border: Border(
                        right: BorderSide(color: Color(0xFFF1F1F1)),
                      ),
                    ),
                    child: Center(
                      child: ActionMiniDiagram(type: type, catColor: catColor),
                    ),
                  ),

                  // [3] Body
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Badges row
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: catColor.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: catColor.withValues(alpha: 0.15)),
                                ),
                                child: Text(
                                  catLabel,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: catColor,
                                  ),
                                ),
                              ),
                              if (!enabled)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFFE5E7EB)),
                                  ),
                                  child: const Text(
                                    'Pausada',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF6B7280),
                                    ),
                                  ),
                                ),
                              if (condition != null && condition.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFFFDE68A)),
                                  ),
                                  child: const Text(
                                    '\u2935 Condicional',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF92400E),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Title
                          Text(
                            _actionLabel(type),
                            style: AppTextStyles.body.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1E2722),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          // Subtitle
                          Text(
                            _actionSubtitle(widget.action),
                            style: AppTextStyles.bodySmall.copyWith(
                              fontSize: 13,
                              color: const Color(0xFF4C5D73),
                            ),
                          ),
                          // Condition detail
                          if (condition != null && condition.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFFDE68A)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 3,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF59E0B),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: RichText(
                                      text: TextSpan(
                                        children: [
                                          TextSpan(
                                            text: 'Solo si ',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF92400E),
                                            ),
                                          ),
                                          TextSpan(
                                            text: condition,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontFamily: 'Geist',
                                              color: const Color(0xFF7C2D12),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // [4] Actions
                  if (widget.canManage)
                    AnimatedOpacity(
                      opacity: _hovered ? 1.0 : 0.45,
                      duration: const Duration(milliseconds: 150),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: const BoxDecoration(
                          border: Border(
                            left: BorderSide(color: Color(0xFFF1F1F1)),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Toggle
                            GestureDetector(
                              onTap: widget.onToggle,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: Container(
                                  width: 36,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: enabled ? catColor : const Color(0xFFE5E7EB),
                                  ),
                                  child: AnimatedAlign(
                                    duration: const Duration(milliseconds: 150),
                                    alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
                                    child: Container(
                                      width: 16,
                                      height: 16,
                                      margin: const EdgeInsets.symmetric(horizontal: 2),
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 15),
                              color: const Color(0xFF4C5D73),
                              onPressed: widget.onEdit,
                              tooltip: 'Editar',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            ),
                            const SizedBox(height: 4),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 15),
                              color: AppColors.ctDanger,
                              onPressed: widget.onDelete,
                              tooltip: 'Eliminar',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── _OnCompleteTimeline ──────────────────────────────────────────────────────

class _OnCompleteTimeline extends StatelessWidget {
  const _OnCompleteTimeline({required this.actions});
  final List<Map<String, dynamic>> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF1F1F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '\uD83C\uDFAC  L\u00CDNEA DE TIEMPO AL CERRAR EL FLUJO',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.08,
              color: const Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                _timelineChip(actions[i], i),
                if (i < actions.length - 1)
                  Text(' \u2192 ',
                      style: TextStyle(
                          fontSize: 11, color: const Color(0xFFD1D5DB))),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFF15803D).withValues(alpha: 0.3)),
                ),
                child: Text(
                  '\u2713 Flujo completo',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF15803D),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timelineChip(Map<String, dynamic> action, int index) {
    final type = action['type'] as String? ?? '';
    final catColor = _actionCatColor(type);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: catColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: catColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: catColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _actionLabel(type),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: catColor,
            ),
          ),
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
    required this.dio,
    this.flowFields = const [],
    this.action,
  });

  final Map<String, dynamic>? action;
  final String tenantId;
  final String tenantWorkerId;
  final String currentFlowSlug;
  final List<Map<String, dynamic>> flowFields;
  final void Function(Map<String, dynamic>) onSaved;
  final Dio dio;

  @override
  State<_ActionDialog> createState() => _ActionDialogState();
}

class _ActionDialogState extends State<_ActionDialog> {
  late bool _showTypeCatalog;
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

  // google_sheets_append_row / update_row
  final _spreadsheetIdCtrl = TextEditingController();
  final _sheetNameCtrl = TextEditingController();
  final _lookupColumnCtrl = TextEditingController();
  String? _lookupValueFieldKey;
  final _sheetUrlCtrl = TextEditingController();
  List<String> _availableSheetsForAction = [];
  List<String> _availableColumns = [];
  String? _selectedSheetForAction;
  bool _loadingSheetPreview = false;
  bool _googleConnected = false;
  bool _checkingGoogleOAuth = false;
  Timer? _sheetUrlDebounce;
  // catalog schemas for asset_ref fields: {catalog_slug: fields_schema}
  Map<String, List<Map<String, dynamic>>> _catalogSchemas = {};
  bool _loadingCatalogSchemas = false;
  // parent flows that have open_flow actions pointing to this flow
  List<Map<String, dynamic>> _parentFlows = [];
  // Each entry: (col: controller, val: controller)
  final List<(TextEditingController, TextEditingController)> _columnMappingRows = [];
  // Parallel list: selected flowField key per row (null = custom text mode)
  final List<String?> _columnMappingKeys = [];
  // Headers mode for google_sheets
  bool _hasHeaders = false;
  List<String> _sheetHeaders = [];
  bool _loadingHeaders = false;
  String? _headersError;

  // excel_onedrive_append_row
  final _excelFileIdCtrl = TextEditingController();
  final _excelSheetNameCtrl = TextEditingController();
  bool _loadingExcelHeaders = false;
  String? _excelHeadersError;
  bool _microsoftConnected = false;
  bool _checkingMicrosoftOAuth = false;
  bool _loadingOnedriveFiles = false;
  List<Map<String, dynamic>> _onedriveFiles = [];
  String? _selectedExcelFileId;
  bool _loadingExcelPreview = false;
  bool _excelPreviewLoaded = false;
  List<String> _availableExcelSheets = [];
  String? _selectedExcelSheet;
  List<String> _excelPreviewColumns = [];

  // notify_group
  // notify_group / enviar notificación
  String _notificationDestinationType = 'group'; // 'group' o 'control_tower'
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _controlTowers = [];
  bool _loadingGroups = false;
  bool _loadingControlTowers = false;
  String? _selectedGroupId;
  final _messageTemplateCtrl = TextEditingController();
  bool _workerGenerates = false;
  bool _useWaTemplate = false;
  String? _selectedWaTemplateId;
  List<Map<String, dynamic>> _waTemplateMappingRows = [];

  // condition
  String? _conditionField;
  String _conditionOp = '==';
  final _conditionValueCtrl = TextEditingController();

  // proactive message (open_flow)
  bool _sendProactive = false;
  String? _waChannelId;
  List<Map<String, dynamic>> _approvedTemplates = [];
  bool _loadingTemplates = false;
  String? _selectedTemplateId;
  List<Map<String, dynamic>> _proactiveMappingRows = [];

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
        'notify_group',
        'google_sheets_update_row',
        'excel_onedrive_append_row',
        'excel_onedrive_update_row',
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
      final types = await FlowsApi.getActionTypes(dio: widget.dio);
      if (mounted) {
        setState(() {
          _availableActionTypes = types;
          if (!_isKnownType && widget.action != null) {
            _initDynamicFields(_type, Map<String, dynamic>.from(widget.action!));
          }
        });
      }
    } catch (e) {
      debugPrint('[_loadActionTypes] error: $e');
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
    _showTypeCatalog = widget.action == null;
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
      if (_type == 'notify_group') {
        // Nuevo campo: destination_type ('group' o 'control_tower')
        _notificationDestinationType = a['destination_type'] as String? ?? 'group';
        _selectedGroupId = a['group_id'] as String?;
        _messageTemplateCtrl.text = a['message_template'] as String? ?? '';
        _workerGenerates = a['worker_generates'] as bool? ?? false;

        // Cargar configuración de plantilla WA
        _selectedWaTemplateId = a['wa_template_id'] as String?;
        if (_selectedWaTemplateId != null && _selectedWaTemplateId!.isNotEmpty) {
          _useWaTemplate = true;
          final mapping = a['wa_variable_mapping'] as List?;
          if (mapping != null) {
            _waTemplateMappingRows = mapping
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }
        }
      }
      if (_type == 'google_sheets_append_row' || _type == 'google_sheets_update_row') {
        final cfg = a['config'] as Map? ?? {};
        _spreadsheetIdCtrl.text = cfg['spreadsheet_id'] as String? ?? '';
        _sheetNameCtrl.text = cfg['sheet_name'] as String? ?? 'Sheet1';
        _selectedSheetForAction = cfg['sheet_name'] as String?;
        _hasHeaders = cfg['has_headers'] as bool? ?? false;
        final mapping = cfg['column_mapping'] as Map? ?? {};
        final fieldKeyRe = RegExp(r'^\{\{fields\.([\w.]+)\}\}$');
        final metaKeyRe = RegExp(r'^\{\{(operator|execution)\.([\w.]+)\}\}$');
        for (final e in mapping.entries) {
          final valStr = e.value.toString();
          final fieldMatch = fieldKeyRe.firstMatch(valStr);
          final metaMatch = metaKeyRe.firstMatch(valStr);
          String? parsedKey;
          if (fieldMatch != null) {
            parsedKey = fieldMatch.group(1);
          } else if (metaMatch != null) {
            parsedKey = '__meta.${metaMatch.group(1)}.${metaMatch.group(2)}';
          }
          _columnMappingKeys.add(parsedKey);
          _columnMappingRows.add((
            TextEditingController(text: e.key.toString()),
            TextEditingController(text: valStr),
          ));
        if (_type == 'google_sheets_update_row') {
          _lookupColumnCtrl.text = cfg['lookup_column'] as String? ?? '';
          _lookupValueFieldKey = cfg['lookup_value_field_key'] as String?;
        }
        }
      }
      if (_type == 'excel_onedrive_append_row' || _type == 'excel_onedrive_update_row') {
        final cfg = a['config'] as Map? ?? {};
        _selectedExcelFileId = cfg['file_id'] as String? ?? '';
        _excelFileIdCtrl.text = _selectedExcelFileId ?? '';
        final sheetName = cfg['sheet_name'] as String? ?? 'Sheet1';
        _excelSheetNameCtrl.text = sheetName;
        _selectedExcelSheet = sheetName;
        _hasHeaders = cfg['has_headers'] as bool? ?? false;
        final mapping = cfg['column_mapping'] as Map? ?? {};
        final fieldKeyRe = RegExp(r'^\{\{fields\.([\w.]+)\}\}$');
        final metaKeyRe = RegExp(r'^\{\{(operator|execution)\.([\w.]+)\}\}$');
        for (final e in mapping.entries) {
          final valStr = e.value.toString();
          final fieldMatch = fieldKeyRe.firstMatch(valStr);
          final metaMatch = metaKeyRe.firstMatch(valStr);
          String? parsedKey;
          if (fieldMatch != null) {
            parsedKey = fieldMatch.group(1);
          } else if (metaMatch != null) {
            parsedKey = '__meta.${metaMatch.group(1)}.${metaMatch.group(2)}';
          }
          _columnMappingKeys.add(parsedKey);
          _columnMappingRows.add((
            TextEditingController(text: e.key.toString()),
            TextEditingController(text: valStr),
          ));
        }
        if (_type == 'excel_onedrive_update_row') {
          _lookupColumnCtrl.text = cfg['lookup_column'] as String? ?? '';
          _lookupValueFieldKey = cfg['lookup_value_field_key'] as String?;
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
    _initProactiveMappingRows();
    _loadFlows();
    _loadCatalogSchemas();
    _loadParentFlows();
    _loadGroups();
    _loadControlTowers();
    _loadWaChannel();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadActionTypes());
    _loadCatalogSchemas();
    if (_type == 'google_sheets_append_row' || _type == 'google_sheets_update_row') {
      _checkGoogleOAuthForAction();
      // Si tiene headers habilitado al editar, cargar automáticamente
      if (_hasHeaders && _spreadsheetIdCtrl.text.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fetchSheetHeaders();
        });
      }
    }
    if (_type == 'excel_onedrive_append_row' || _type == 'excel_onedrive_update_row') {
      _checkMicrosoftOAuthForAction();
      // Si tiene un file_id al editar, cargar preview automáticamente
      if (_selectedExcelFileId != null && _selectedExcelFileId!.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadExcelPreview();
        });
      }
      // Si tiene headers habilitado al editar, cargar automáticamente
      if (_hasHeaders && _excelFileIdCtrl.text.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fetchExcelHeaders();
        });
      }
    }
    _sheetUrlCtrl.addListener(_onSheetUrlChangedForAction);
  }

  Future<void> _loadGroups() async {
    setState(() => _loadingGroups = true);
    try {
      final data = await GroupsApi.listGroupsByTenant(dio: widget.dio);
      if (mounted) setState(() { _groups = data; _loadingGroups = false; });
    } catch (e) {
      if (mounted) setState(() => _loadingGroups = false);
    }
  }

  Future<void> _loadControlTowers() async {
    setState(() => _loadingControlTowers = true);
    try {
      final data = await GroupsApi.listControlTowers(dio: widget.dio);
      if (mounted) setState(() { _controlTowers = data; _loadingControlTowers = false; });
    } catch (e) {
      if (mounted) setState(() => _loadingControlTowers = false);
    }
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
          dio: widget.dio,
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

  Future<void> _loadParentFlows() async {
    try {
      final allFlows = await FlowsApi.listFlows(dio: widget.dio);
      final parents = <Map<String, dynamic>>[];

      for (final flow in allFlows) {
        final onComplete = flow['on_complete'] as Map<String, dynamic>?;
        final actions = onComplete?['actions'] as List? ?? [];

        for (final action in actions) {
          if (action is! Map) continue;
          if (action['action_type'] != 'open_flow') continue;

          final config = action['config'] as Map? ?? {};
          final targetSlug = action['flow_slug'] as String? ??
                            action['target_flow_slug'] as String? ??
                            config['flow_slug'] as String? ??
                            config['target_flow_slug'] as String?;

          if (targetSlug == widget.currentFlowSlug) {
            parents.add(flow);
            break; // Solo agregar una vez por flujo
          }
        }
      }

      if (!mounted) return;
      setState(() => _parentFlows = parents);
    } catch (e) {
      debugPrint('[_loadParentFlows] ERROR: $e');
    }
  }

  List<Widget> _buildGoogleSheetsFields() {
    if (_checkingGoogleOAuth) {
      return [
        const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ctTeal),
          ),
        ),
      ];
    }
    if (!_googleConnected) {
      return [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            border: Border.all(color: const Color(0xFFF59E0B)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 16, color: Color(0xFFB45309)),
                  const SizedBox(width: 8),
                  Text(
                    'Tu cuenta de Google no est\u00E1 conectada.',
                    style: AppTextStyles.bodySmall.copyWith(
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF92400E)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppButton(
                label: 'Conectar Google',
                variant: AppButtonVariant.primary,
                size: AppButtonSize.sm,
                onPressed: () {
                  Navigator.of(context).pop();
                  context.go('/connections');
                },
              ),
            ],
          ),
        ),
      ];
    }
    return [
      Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              size: 16, color: Color(0xFF16A34A)),
          const SizedBox(width: 6),
          Text('Google conectado',
              style: AppTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF16A34A))),
        ],
      ),
      const SizedBox(height: 12),
      _FormField(
        label: 'URL del Google Sheet',
        controller: _sheetUrlCtrl,
        placeholder: 'https://docs.google.com/spreadsheets/d/\u2026',
      ),
      if (_loadingSheetPreview) ...[
        const SizedBox(height: 6),
        const LinearProgressIndicator(color: AppColors.ctTeal),
      ],
      if (_availableSheetsForAction.isNotEmpty) ...[
        const SizedBox(height: 12),
        AppDropdown<String?>(
          label: 'Hoja (pesta\u00F1a)',
          value: _selectedSheetForAction,
          hint: 'Seleccionar hoja',
          items: _availableSheetsForAction
              .map((s) => AppDropdownItem<String?>(value: s, label: s))
              .toList(),
          onChanged: (s) {
            setState(() => _selectedSheetForAction = s);
            if (s != null) _loadSheetPreviewForAction(sheetName: s);
          },
        ),
      ],
      // Fallback: if editing with existing spreadsheet_id but no URL entered yet
      if (_sheetUrlCtrl.text.trim().isEmpty && _spreadsheetIdCtrl.text.trim().isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFA),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.ctBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 14, color: AppColors.ctText3),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ID actual: ${_spreadsheetIdCtrl.text}',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 12),
      Row(
        children: [
          Checkbox(
            value: _hasHeaders,
            onChanged: (val) {
              setState(() {
                _hasHeaders = val ?? false;
                if (_hasHeaders) {
                  _fetchSheetHeaders();
                } else {
                  _sheetHeaders = [];
                  _headersError = null;
                }
              });
            },
            activeColor: AppColors.ctTeal,
          ),
          const SizedBox(width: 8),
          Text('¿La primera fila tiene nombres de columnas (headers)?',
              style: AppTextStyles.body),
        ],
      ),
      if (_loadingHeaders) ...[
        const SizedBox(height: 6),
        const LinearProgressIndicator(color: AppColors.ctTeal),
      ],
      if (_headersError != null) ...[
        const SizedBox(height: 6),
        Text(_headersError!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctDanger)),
      ],
      if (_hasHeaders && _sheetHeaders.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text('${_sheetHeaders.length} columnas encontradas',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2)),
      ],
    ];
  }

  static String _columnLetter(int index) {
    int n = index + 1;
    String result = '';
    while (n > 0) {
      n--;
      result = String.fromCharCode((n % 26) + 65) + result;
      n ~/= 26;
    }
    return result;
  }

  Future<void> _checkGoogleOAuthForAction() async {
    setState(() => _checkingGoogleOAuth = true);
    try {
      final status = await ConnectionsApi.getGoogleStatus(dio: widget.dio);
      if (mounted) setState(() => _googleConnected = status['connected'] == true);
    } catch (_) {
      if (mounted) setState(() => _googleConnected = false);
    } finally {
      if (mounted) setState(() => _checkingGoogleOAuth = false);
    }
  }

  Future<void> _checkMicrosoftOAuthForAction() async {
    setState(() => _checkingMicrosoftOAuth = true);
    try {
      final status = await ConnectionsApi.getMicrosoftStatus(
        dio: widget.dio,
        tenantId: widget.tenantId,
      );
      debugPrint('[_checkMicrosoftOAuthForAction] Full status response: $status');
      final connections = status['connections'] as List? ?? [];
      debugPrint('[_checkMicrosoftOAuthForAction] Connections: $connections');
      final msConnection = connections.firstWhere(
        (c) => c['provider'] == 'microsoft',
        orElse: () => {},
      );
      debugPrint('[_checkMicrosoftOAuthForAction] MS connection: $msConnection');
      final isConnected = msConnection['status'] == 'active';
      debugPrint('[_checkMicrosoftOAuthForAction] Is connected: $isConnected');
      if (mounted) {
        setState(() => _microsoftConnected = isConnected);
        if (isConnected) _loadOnedriveFilesForAction();
      }
    } catch (e) {
      debugPrint('[_checkMicrosoftOAuthForAction] Error: $e');
      if (mounted) setState(() => _microsoftConnected = false);
    } finally {
      if (mounted) setState(() => _checkingMicrosoftOAuth = false);
    }
  }

  Future<void> _loadOnedriveFilesForAction() async {
    setState(() => _loadingOnedriveFiles = true);
    try {
      final files = await ConnectionsApi.getOnedriveFiles(
        dio: widget.dio,
        tenantId: widget.tenantId,
      );
      if (mounted) {
        setState(() {
          _onedriveFiles = files;
          _loadingOnedriveFiles = false;
        });
      }
    } catch (e) {
      debugPrint('[_loadOnedriveFilesForAction] Error: $e');
      if (mounted) setState(() => _loadingOnedriveFiles = false);
    }
  }

  Future<void> _loadExcelPreview({String? sheetName}) async {
    if (_selectedExcelFileId == null) return;
    setState(() {
      _loadingExcelPreview = true;
      _excelPreviewLoaded = false;
    });
    try {
      final result = await CatalogsApi.getOnedrivePreview(
        dio: widget.dio,
        tenantId: widget.tenantId,
        fileId: _selectedExcelFileId!,
        sheetName: sheetName ?? _selectedExcelSheet,
      );
      if (!mounted) return;
      setState(() {
        _availableExcelSheets = List<String>.from(result['sheets'] as List? ?? []);
        _selectedExcelSheet = result['selected_sheet'] as String?;
        _excelPreviewColumns = List<String>.from(result['columns'] as List? ?? []);
        _excelPreviewLoaded = true;
        _loadingExcelPreview = false;
      });
    } catch (e) {
      debugPrint('[_loadExcelPreview] Error: $e');
      if (!mounted) return;
      setState(() => _loadingExcelPreview = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar preview: $e'),
            backgroundColor: AppColors.ctDanger,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _fetchSheetHeaders() async {
    final url = _sheetUrlCtrl.text.trim();
    String spreadsheetId = '';

    // Intenta extraer de URL primero
    if (url.isNotEmpty && url.contains('spreadsheets/d/')) {
      final extractedId = RegExp(r'/spreadsheets/d/([a-zA-Z0-9-_]+)')
          .firstMatch(url)?.group(1) ?? '';
      spreadsheetId = extractedId;
    }

    // Si no hay ID de URL, usa el spreadsheetIdCtrl (útil al editar)
    if (spreadsheetId.isEmpty) {
      spreadsheetId = _spreadsheetIdCtrl.text.trim();
    }

    if (spreadsheetId.isEmpty) {
      setState(() {
        _headersError = 'Ingresa una URL válida de Google Sheets o ID de spreadsheet';
        _sheetHeaders = [];
      });
      return;
    }
    final sheetName = _selectedSheetForAction ?? (_sheetNameCtrl.text.trim().isEmpty ? 'Sheet1' : _sheetNameCtrl.text.trim());
    setState(() {
      _loadingHeaders = true;
      _headersError = null;
    });
    try {
      final headers = await ConnectionsApi.getSheetHeaders(
        dio: widget.dio,
        spreadsheetId: spreadsheetId,
        sheetName: sheetName,
      );
      if (mounted) {
        setState(() {
          _sheetHeaders = headers;
          _loadingHeaders = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _headersError = 'Error al cargar headers: $e';
          _sheetHeaders = [];
          _loadingHeaders = false;
        });
      }
    }
  }

  void _onSheetUrlChangedForAction() {
    _sheetUrlDebounce?.cancel();
    final url = _sheetUrlCtrl.text.trim();
    if (url.contains('spreadsheets/d/')) {
      _sheetUrlDebounce = Timer(
        const Duration(milliseconds: 800),
        () { if (mounted) _loadSheetPreviewForAction(); },
      );
    }
  }

  Future<void> _fetchExcelHeaders() async {
    final fileId = _excelFileIdCtrl.text.trim();
    if (fileId.isEmpty) {
      setState(() {
        _excelHeadersError = 'Ingresa un ID de archivo de Excel válido';
      });
      return;
    }
    final sheetName = _excelSheetNameCtrl.text.trim().isEmpty ? 'Sheet1' : _excelSheetNameCtrl.text.trim();
    setState(() {
      _loadingExcelHeaders = true;
      _excelHeadersError = null;
    });
    try {
      final headers = await ConnectionsApi.getExcelHeaders(
        dio: widget.dio,
        fileId: fileId,
        sheetName: sheetName,
      );
      if (mounted) {
        setState(() {
          _sheetHeaders = headers;
          _loadingExcelHeaders = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _excelHeadersError = 'Error al cargar headers: $e';
          _sheetHeaders = [];
          _loadingExcelHeaders = false;
        });
      }
    }
  }

  Future<void> _loadSheetPreviewForAction({String? sheetName}) async {
    if (_sheetUrlCtrl.text.trim().isEmpty) return;
    setState(() => _loadingSheetPreview = true);
    try {
      final result = await CatalogsApi.sheetsPreview(
        dio: widget.dio,
        tenantId: widget.tenantId,
        sheetUrl: _sheetUrlCtrl.text.trim(),
        sheetName: sheetName ?? _selectedSheetForAction,
      );
      if (!mounted) return;
      setState(() {
        _availableSheetsForAction = List<String>.from(result['sheets'] as List? ?? []);
        _availableColumns = List<String>.from(result['columns'] as List? ?? []);
        _selectedSheetForAction = result['selected_sheet'] as String?;
        _loadingSheetPreview = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingSheetPreview = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error al cargar preview: $e'),
        backgroundColor: AppColors.ctDanger,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  static bool _hasOnComplete(Map<String, dynamic> f) {
    final raw = f['trigger_sources'];
    if (raw is List) return raw.contains('on_complete');
    return false;
  }

  Future<void> _loadFlows() async {
    if (widget.tenantWorkerId.isEmpty) return;
    setState(() => _loadingFlows = true);
    try {
      final flows = await FlowsApi.getFlowsByWorker(
        dio: widget.dio,
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

  Future<void> _loadWaChannel() async {
    if (widget.tenantWorkerId.isEmpty) return;
    try {
      final channels = await ChannelsApi.listChannelsByWorker(
        dio: widget.dio,
        tenantWorkerId: widget.tenantWorkerId,
      );
      final waChannel = channels.firstWhere(
        (c) => (c['channel_type'] as String?) == 'whatsapp',
        orElse: () => {},
      );
      if (!mounted) return;
      final channelId = waChannel['id'] as String?;
      setState(() => _waChannelId = channelId);
      if (channelId != null) await _loadTemplatesForAction(channelId);
    } catch (_) {}
  }

  Future<void> _loadTemplatesForAction(String channelId) async {
    setState(() => _loadingTemplates = true);
    try {
      final all = await ChannelsApi.listTemplates(dio: widget.dio, channelId: channelId);
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

  void _initProactiveMappingRows() {
    final pm = widget.action?['proactive_message'] as Map<String, dynamic>?;
    if (pm != null) {
      _sendProactive = true;
      _selectedTemplateId = pm['template_id'] as String?;
      final existing = (pm['variable_mapping'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _proactiveMappingRows = existing;
    }
  }

  void _initProactiveMappingFromTemplate(Map<String, dynamic> template) {
    // 1. Variables declared in template
    final declared = ((template['variables'] as List<dynamic>?) ?? [])
        .map((v) => {
              'slot': (v as Map)['slot'] as int? ?? 0,
              'key': v['key'] as String? ?? '',
            })
        .toList();

    // 2. Slots in body_text via {{N}}
    final body = template['body_text'] as String? ?? '';
    final bodySlots = RegExp(r'\{\{(\d+)\}\}')
        .allMatches(body)
        .map((m) => int.tryParse(m.group(1) ?? '') ?? 0)
        .where((s) => s > 0)
        .toSet();

    // 3. Synthetic entries for slots in body but not in variables
    final declaredSlots = declared.map((v) => v['slot'] as int).toSet();
    final missing = bodySlots.difference(declaredSlots);
    for (final slot in missing.toList()..sort()) {
      declared.add({'slot': slot, 'key': 'variable_$slot'});
    }

    // 4. Sort by slot
    declared.sort((a, b) =>
        (a['slot'] as int).compareTo(b['slot'] as int));

    // 5. Preserve existing mapping sources
    final existing = Map<String, String>.fromEntries(
      _proactiveMappingRows
          .map((e) => MapEntry(
                e['variable'] as String? ?? '',
                e['source'] as String? ?? '',
              ))
          .where((e) => e.key.isNotEmpty),
    );

    setState(() {
      _proactiveMappingRows = declared.map((v) {
        final key = v['key'] as String;
        return <String, dynamic>{
          'variable': key,
          'source': existing[key] ?? '',
          'slot': v['slot'] as int,
        };
      }).toList();
    });
  }

  void _initWaTemplateMappingFromTemplate(Map<String, dynamic> template) {
    // Similar a _initProactiveMappingFromTemplate
    final declared = ((template['variables'] as List<dynamic>?) ?? [])
        .map((v) => {
              'slot': (v as Map)['slot'] as int? ?? 0,
              'key': v['key'] as String? ?? '',
            })
        .toList();

    final body = template['body_text'] as String? ?? '';
    final bodySlots = RegExp(r'\{\{(\d+)\}\}')
        .allMatches(body)
        .map((m) => int.tryParse(m.group(1) ?? '') ?? 0)
        .where((s) => s > 0)
        .toSet();

    final declaredSlots = declared.map((v) => v['slot'] as int).toSet();
    final missing = bodySlots.difference(declaredSlots);
    for (final slot in missing.toList()..sort()) {
      declared.add({'slot': slot, 'key': 'variable_$slot'});
    }

    declared.sort((a, b) =>
        (a['slot'] as int).compareTo(b['slot'] as int));

    final existing = Map<String, String>.fromEntries(
      _waTemplateMappingRows
          .map((e) => MapEntry(
                e['variable'] as String? ?? '',
                e['source'] as String? ?? '',
              ))
          .where((e) => e.key.isNotEmpty),
    );

    setState(() {
      _waTemplateMappingRows = declared.map((v) {
        final key = v['key'] as String;
        return <String, dynamic>{
          'variable': key,
          'source': existing[key] ?? '',
          'slot': v['slot'] as int,
        };
      }).toList();
    });
  }

  Widget _buildActionTemplateBodyPreview(String body) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'(\{\{\d+\}\})');
    int lastEnd = 0;
    for (final match in regex.allMatches(body)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: body.substring(lastEnd, match.start),
          style: AppTextStyles.body,
        ));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: AppTextStyles.body.copyWith(
          color: AppColors.ctTeal,
          fontWeight: FontWeight.w600,
        ),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < body.length) {
      spans.add(TextSpan(
        text: body.substring(lastEnd),
        style: AppTextStyles.body,
      ));
    }
    return RichText(text: TextSpan(children: spans));
  }

  @override
  void dispose() {
    _integrationCtrl.dispose();
    _eventNameCtrl.dispose();
    _spreadsheetIdCtrl.dispose();
    _sheetNameCtrl.dispose();
    _lookupColumnCtrl.dispose();
    _sheetUrlCtrl.removeListener(_onSheetUrlChangedForAction);
    _sheetUrlCtrl.dispose();
    _sheetUrlDebounce?.cancel();
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
    // Include all metadata variable keys
    keys.addAll(kAllMetaKeys);
    return keys;
  }

  List<AppDropdownItem<String?>> _buildFieldDropdownItems() {
    debugPrint('[_buildFieldDropdownItems] START - catalogSchemas keys: ${_catalogSchemas.keys.toList()}');
    final items = <AppDropdownItem<String?>>[];
    for (final f in widget.flowFields) {
      final key = f['key'] as String? ?? '';
      final label = f['label'] as String? ?? key;
      final type = f['type'] as String?;
      final slug = f['catalog_slug'] as String?;
      debugPrint('[_buildFieldDropdownItems] field: $key, type: $type, slug: $slug, hasSchema: ${_catalogSchemas.containsKey(slug ?? '')}');
      if (type == 'asset_ref' && slug != null && _catalogSchemas.containsKey(slug)) {
        debugPrint('[_buildFieldDropdownItems] expanding asset_ref field: $key with slug: $slug');
        for (final col in _catalogSchemas[slug]!) {
          final colKey = col['key'] as String? ?? '';
          final colLabel = col['label'] as String? ?? colKey;
          if (colKey.isEmpty) continue;
          debugPrint('[_buildFieldDropdownItems] adding expanded item: $key.data.$colKey -> $label > $colLabel');
          items.add(AppDropdownItem<String?>(
            value: '$key.data.$colKey',
            label: '$label > $colLabel',
          ));
        }
      } else {
        items.add(AppDropdownItem<String?>(
          value: key,
          label: label,
        ));
      }
    }
    debugPrint('[_buildFieldDropdownItems] DONE - total items: ${items.length}');
    return items;
  }

  /// Builds dropdown items for template variables (notify_group, etc).
  /// Includes fields, ancestors, execution metadata, and operator metadata.
  List<AppDropdownItem<String>> _buildTemplateVariableItems() {
    final items = <AppDropdownItem<String>>[];

    // ── Campos del flujo ──
    if (widget.flowFields.isNotEmpty) {
      items.add(const AppDropdownItem<String>(
        value: '',
        label: '━━━ Campos del flujo ━━━',
        enabled: false,
      ));
      for (final f in widget.flowFields) {
        final key = f['key'] as String? ?? '';
        final label = f['label'] as String? ?? key;
        final type = f['type'] as String?;
        final slug = f['catalog_slug'] as String?;

        if (key.isEmpty) continue;

        // Expandir campos de catálogo (asset_ref) con sus propiedades
        if (type == 'asset_ref' && slug != null && _catalogSchemas.containsKey(slug)) {
          for (final col in _catalogSchemas[slug]!) {
            final colKey = col['key'] as String? ?? '';
            final colLabel = col['label'] as String? ?? colKey;
            if (colKey.isNotEmpty) {
              items.add(AppDropdownItem<String>(
                value: '{{fields.$key.data.$colKey}}',
                label: '$label > $colLabel',
              ));
            }
          }
        } else {
          items.add(AppDropdownItem<String>(
            value: '{{fields.$key}}',
            label: label,
          ));
        }
      }
    }

    // ── Ancestors (campos de flujos padre) ──
    if (_parentFlows.isNotEmpty) {
      items.add(const AppDropdownItem<String>(
        value: '',
        label: '━━━ Campos heredados ━━━',
        enabled: false,
      ));

      for (final parentFlow in _parentFlows) {
        final parentName = parentFlow['name'] as String? ?? 'Flujo padre';
        final parentFields = parentFlow['fields'] as List? ?? [];

        for (final field in parentFields) {
          if (field is! Map) continue;
          final key = field['key'] as String? ?? '';
          final label = field['label'] as String? ?? key;
          if (key.isNotEmpty) {
            items.add(AppDropdownItem<String>(
              value: '{{ancestors.$key}}',
              label: '$parentName > $label',
            ));
          }
        }
      }
    }

    // ── Execution metadata ──
    items.add(const AppDropdownItem<String>(
      value: '',
      label: '━━━ Metadata de la Ejecución ━━━',
      enabled: false,
    ));
    items.add(const AppDropdownItem<String>(
      value: '{{execution.execution_id}}',
      label: 'ID de ejecución',
    ));
    items.add(const AppDropdownItem<String>(
      value: '{{execution.flow_definition_id}}',
      label: 'ID de definición del flujo',
    ));
    items.add(const AppDropdownItem<String>(
      value: '{{execution.flow_name}}',
      label: 'Nombre del flujo',
    ));
    items.add(const AppDropdownItem<String>(
      value: '{{execution.created_at}}',
      label: 'Fecha de creación (ISO)',
    ));
    items.add(const AppDropdownItem<String>(
      value: '{{execution.completed_at}}',
      label: 'Fecha de completado (ISO)',
    ));
    items.add(const AppDropdownItem<String>(
      value: '{{execution.date}}',
      label: 'Fecha (YYYY-MM-DD)',
    ));
    items.add(const AppDropdownItem<String>(
      value: '{{execution.time}}',
      label: 'Hora (HH:MM:SS)',
    ));
    items.add(const AppDropdownItem<String>(
      value: '{{execution.channel_name}}',
      label: 'Nombre del canal',
    ));
    items.add(const AppDropdownItem<String>(
      value: '{{execution.worker_name}}',
      label: 'Nombre del worker',
    ));

    // ── Operator metadata ──
    items.add(const AppDropdownItem<String>(
      value: '',
      label: '━━━ Metadata del Operador ━━━',
      enabled: false,
    ));
    items.add(const AppDropdownItem<String>(
      value: '{{operator.id}}',
      label: 'ID del operador',
    ));
    items.add(const AppDropdownItem<String>(
      value: '{{operator.name}}',
      label: 'Nombre del operador',
    ));
    items.add(const AppDropdownItem<String>(
      value: '{{operator.email}}',
      label: 'Email del operador',
    ));
    items.add(const AppDropdownItem<String>(
      value: '{{operator.phone}}',
      label: 'Teléfono del operador',
    ));

    return items;
  }

  /// Builds a single column-mapping row used by both append_row and
  /// update_row Google Sheets actions.
  Widget _buildColumnMappingRow(int i) {
    final row = _columnMappingRows[i];
    final selectedKey = _columnMappingKeys.length > i ? _columnMappingKeys[i] : null;
    final hasFields = widget.flowFields.isNotEmpty;
    final allKeys = _buildAllValidKeys();
    final isMetaKey = selectedKey != null && selectedKey.startsWith('__meta.');
    final effectiveKey = isMetaKey
        ? selectedKey
        : (selectedKey != null &&
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
              // Column selector (header name or letter)
              if (_hasHeaders && _sheetHeaders.isNotEmpty)
                SizedBox(
                  width: 150,
                  child: AppDropdown<String?>(
                    value: row.$1.text.isEmpty ? null : row.$1.text,
                    hint: 'Columna...',
                    items: _sheetHeaders
                        .map((h) => AppDropdownItem<String?>(value: h, label: h))
                        .toList(),
                    onChanged: (v) => setState(() {
                      row.$1.text = v ?? '';
                    }),
                  ),
                )
              else
                SizedBox(
                  width: 70,
                  child: _ColMappingField(
                    controller: row.$1,
                    placeholder: _hasHeaders ? 'Columna' : 'A',
                    onChanged: () => setState(() {}),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text('\u2192',
                    style: AppTextStyles.body.copyWith(color: AppColors.ctText2)),
              ),
              // Value selector: VariablePickerDropdown with search
              if (hasFields)
                Expanded(
                  child: VariablePickerDropdown(
                    flowFields: widget.flowFields,
                    catalogSchemas: _catalogSchemas,
                    loadingCatalogSchemas: _loadingCatalogSchemas,
                    selectedKey: effectiveKey,
                    onSelected: (key, template) => setState(() {
                      if (_columnMappingKeys.length > i) {
                        _columnMappingKeys[i] = key;
                      }
                      if (key != null) {
                        row.$2.text = template;
                      } else {
                        row.$2.clear();
                      }
                    }),
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
          // Custom text field shown below when "Personalizado" is selected
          if (hasFields && effectiveKey == null)
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
  }

  static List<AppDropdownItem<String>> _conditionOpsForType(String? type) {
    switch (type) {
      case 'number':
      case 'date':
        return const [
          AppDropdownItem(value: '==', label: '== igual'),
          AppDropdownItem(value: '!=', label: '!= distinto'),
          AppDropdownItem(value: '>',  label: '>  mayor'),
          AppDropdownItem(value: '<',  label: '<  menor'),
          AppDropdownItem(value: '>=', label: '>= mayor o igual'),
          AppDropdownItem(value: '<=', label: '<= menor o igual'),
        ];
      default:
        return const [
          AppDropdownItem(value: '==', label: '== igual'),
          AppDropdownItem(value: '!=', label: '!= distinto'),
        ];
    }
  }

  Widget _buildConditionValueWidget(String? fieldType, Map<String, dynamic>? field) {
    if (fieldType == 'select') {
      final options = (field?['options'] as List?) ?? [];
      if (options.isNotEmpty) {
        return AppDropdown<String?>(
          value: _conditionValueCtrl.text.isNotEmpty ? _conditionValueCtrl.text : null,
          hint: 'Seleccionar valor',
          items: options
              .map((o) => AppDropdownItem<String?>(
                    value: o.toString(),
                    label: o.toString(),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _conditionValueCtrl.text = v ?? ''),
        );
      }
    }
    return TextField(
      controller: _conditionValueCtrl,
      style: AppTextStyles.body,
      keyboardType: fieldType == 'number' ? TextInputType.number : TextInputType.text,
      inputFormatters: fieldType == 'number'
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))]
          : [],
      decoration: InputDecoration(
        hintText: fieldType == 'number' ? 'ej. 5' : 'ej. Si, Granjas',
        hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
        filled: true,
        fillColor: AppColors.ctSurface2,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.ctBorder2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.ctTeal, width: 1.5),
        ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  String? _buildConditionExpression() {
    final val = _conditionValueCtrl.text.trim();
    if (_conditionField != null && val.isNotEmpty) {
      return 'fields.$_conditionField $_conditionOp "$val"';
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
        if (_sendProactive && _selectedTemplateId == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Selecciona una plantilla aprobada para el mensaje proactivo'),
            backgroundColor: AppColors.ctDanger,
          ));
          return;
        }
        updated['target_flow_slug'] = _selectedFlowSlug!;
        updated['carry_ancestors'] = _carryAncestors;
        if (_sendProactive && _selectedTemplateId != null) {
          updated['proactive_message'] = {
            'template_id': _selectedTemplateId,
            'variable_mapping': _proactiveMappingRows
                .where((r) => (r['variable'] as String? ?? '').isNotEmpty)
                .map((r) => {'variable': r['variable'], 'source': r['source']})
                .toList(),
          };
        } else {
          updated.remove('proactive_message');
        }

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

        updated.remove('carry_ancestors');
        updated.remove('event_name');
        updated.remove('event_data');
        break;
      case 'emit_event':
        if (_eventNameCtrl.text.trim().isEmpty) return;
        updated['event_name'] = _eventNameCtrl.text.trim();
        updated.remove('target_flow_slug');

        updated.remove('carry_ancestors');
        updated.remove('integration_id');
        updated.remove('include_ancestors');
        updated.remove('config');
        break;
      case 'notify_group':
        if (_selectedGroupId == null) return;
        if (_messageTemplateCtrl.text.trim().isEmpty) return;
        updated['destination_type'] = _notificationDestinationType;
        updated['group_id'] = _selectedGroupId!;
        updated['message_template'] = _messageTemplateCtrl.text.trim();
        updated['worker_generates'] = _workerGenerates;
        // Store the display name for subtitle rendering
        final List<Map<String, dynamic>> sourceList =
            _notificationDestinationType == 'control_tower' ? _controlTowers : _groups;
        final matchedItem = sourceList.where((g) => g['id'] == _selectedGroupId).firstOrNull;
        if (matchedItem != null) {
          updated['_group_display_name'] = matchedItem['display_name'] as String? ?? '';
        }
        // Plantilla WhatsApp (nuevo formato)
        if (_useWaTemplate && _selectedWaTemplateId != null) {
          updated['wa_template_id'] = _selectedWaTemplateId;
          updated['wa_variable_mapping'] = _waTemplateMappingRows
              .where((r) => (r['variable'] as String? ?? '').isNotEmpty)
              .map((r) => {'variable': r['variable'], 'source': r['source']})
              .toList();
        } else {
          updated.remove('wa_template_id');
          updated.remove('wa_variable_mapping');
        }
        updated.remove('target_flow_slug');
        updated.remove('carry_fields');
        updated.remove('carry_ancestors');
        updated.remove('integration_id');
        updated.remove('include_ancestors');
        updated.remove('event_name');
        updated.remove('event_data');
        updated.remove('config');
        break;
      case 'google_sheets_append_row':
        final url = _sheetUrlCtrl.text.trim();
        final extractedId = RegExp(r'/spreadsheets/d/([a-zA-Z0-9-_]+)')
            .firstMatch(url)?.group(1) ?? '';
        final sid = extractedId.isNotEmpty
            ? extractedId
            : _spreadsheetIdCtrl.text.trim();
        if (sid.isEmpty) return;
        final validRows = _columnMappingRows
            .where((r) => r.$1.text.trim().isNotEmpty)
            .toList();
        if (validRows.isEmpty) return;
        updated['config'] = {
          'spreadsheet_id': sid,
          'sheet_name': _selectedSheetForAction ??
              (_sheetNameCtrl.text.trim().isEmpty
                  ? 'Sheet1'
                  : _sheetNameCtrl.text.trim()),
          'column_mapping': {
            for (final r in validRows) r.$1.text.trim(): r.$2.text.trim(),
          },
          'has_headers': _hasHeaders,
        };
        updated.remove('target_flow_slug');

        updated.remove('carry_ancestors');
        updated.remove('integration_id');
        updated.remove('include_ancestors');
        updated.remove('event_name');
        updated.remove('event_data');
        break;
      case 'google_sheets_update_row':
        final url = _sheetUrlCtrl.text.trim();
        final extractedId = RegExp(r'/spreadsheets/d/([a-zA-Z0-9-_]+)')
            .firstMatch(url)?.group(1) ?? '';
        final sid = extractedId.isNotEmpty
            ? extractedId
            : _spreadsheetIdCtrl.text.trim();
        if (sid.isEmpty) return;
        final validRows = _columnMappingRows
            .where((r) => r.$1.text.trim().isNotEmpty)
            .toList();
        if (validRows.isEmpty) return;
        updated['config'] = {
          'spreadsheet_id': sid,
          'sheet_name': _selectedSheetForAction ??
              (_sheetNameCtrl.text.trim().isEmpty
                  ? 'Sheet1'
                  : _sheetNameCtrl.text.trim()),
          'column_mapping': {
            for (final r in validRows) r.$1.text.trim(): r.$2.text.trim(),
          },
          'lookup_column': _lookupColumnCtrl.text.trim(),
          'lookup_value_field_key': _lookupValueFieldKey ?? '',
          'has_headers': _hasHeaders,
        };
        updated.remove('target_flow_slug');
        updated.remove('carry_ancestors');
        updated.remove('integration_id');
        updated.remove('include_ancestors');
        updated.remove('event_name');
        updated.remove('event_data');
        break;
      case 'excel_onedrive_append_row':
        final fileId = _excelFileIdCtrl.text.trim();
        if (fileId.isEmpty) return;
        final validRows = _columnMappingRows
            .where((r) => r.$1.text.trim().isNotEmpty)
            .toList();
        if (validRows.isEmpty) return;
        updated['config'] = {
          'file_id': fileId,
          'sheet_name': _excelSheetNameCtrl.text.trim().isEmpty
              ? 'Sheet1'
              : _excelSheetNameCtrl.text.trim(),
          'column_mapping': {
            for (final r in validRows) r.$1.text.trim(): r.$2.text.trim(),
          },
          'has_headers': _hasHeaders,
        };
        updated.remove('target_flow_slug');
        updated.remove('carry_ancestors');
        updated.remove('integration_id');
        updated.remove('include_ancestors');
        updated.remove('event_name');
        updated.remove('event_data');
        break;
      case 'excel_onedrive_update_row':
        final euFileId = _excelFileIdCtrl.text.trim();
        if (euFileId.isEmpty) return;
        final euValidRows = _columnMappingRows
            .where((r) => r.$1.text.trim().isNotEmpty)
            .toList();
        if (euValidRows.isEmpty) return;
        updated['config'] = {
          'file_id': euFileId,
          'sheet_name': _excelSheetNameCtrl.text.trim().isEmpty
              ? 'Sheet1'
              : _excelSheetNameCtrl.text.trim(),
          'column_mapping': {
            for (final r in euValidRows) r.$1.text.trim(): r.$2.text.trim(),
          },
          'lookup_column': _lookupColumnCtrl.text.trim(),
          'lookup_value_field_key': _lookupValueFieldKey ?? '',
          'has_headers': _hasHeaders,
        };
        updated.remove('target_flow_slug');
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

  static const _kActionCategories = [
    ('flow', 'Encadenar flujos', 'Abre otros flujos al completar este', Color(0xFF8B5CF6), ['open_flow', 'open_flow_n_times']),
    ('external', 'Sistemas externos', 'Env\u00EDa datos a servicios externos', Color(0xFF3B82F6), ['webhook_out']),
    ('sheets', 'Hojas de c\u00E1lculo', 'Escribe o actualiza datos en Google Sheets o Excel OneDrive', Color(0xFF10B981), ['google_sheets_append_row', 'google_sheets_update_row', 'excel_onedrive_append_row', 'excel_onedrive_update_row']),
    ('events', 'Eventos internos', 'Emite eventos para otros sistemas', Color(0xFFF59E0B), ['emit_event']),
    ('groups', 'Notificaciones push', 'Env\u00EDa notificaciones a grupos o torres de control', Color(0xFF00D1A3), ['notify_group']),
  ];

  static const _kActionExamples = <String, String>{
    'open_flow': 'Al completar "Inicio de Ruta", abre "Registro de Entrega".',
    'open_flow_n_times': 'Abre N instancias de un flujo basado en un campo num\u00E9rico.',
    'webhook_out': 'Env\u00EDa los datos capturados a un endpoint HTTP externo.',
    'google_sheets_append_row': 'Agrega una fila nueva con los datos del flujo.',
    'google_sheets_update_row': 'Actualiza una fila existente en la hoja.',
    'excel_onedrive_append_row': 'Agrega una fila nueva en Excel OneDrive con los datos del flujo.',
    'excel_onedrive_update_row': 'Actualiza una fila existente en Excel OneDrive.',
    'emit_event': 'Emite un evento interno para otros flujos o servicios.',
    'notify_group': 'Env\u00EDa una notificaci\u00F3n a un grupo o torre de control cuando se completa el flujo.',
  };

  bool _hasActionTypesInCategory(List<String> types) {
    return types.any((t) => t != 'emit_event' && _availableActionTypes.any((at) => at['type'] == t));
  }

  Widget _buildTypeCatalog() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nueva acci\u00F3n al cerrar',
                        style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w700, fontSize: 17)),
                    const SizedBox(height: 4),
                    Text(
                      'Elige qu\u00E9 debe ocurrir cuando el flujo se complete',
                      style: AppTextStyles.bodySmall.copyWith(
                          color: const Color(0xFF4C5D73)),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: AppColors.ctText2),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1, color: AppColors.ctBorder),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final cat in _kActionCategories) ...[
                  if (_hasActionTypesInCategory(cat.$5)) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: cat.$4,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(cat.$2,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: cat.$4)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(cat.$3,
                              style: AppTextStyles.bodySmall.copyWith(
                                  fontSize: 11, color: const Color(0xFF6B7280))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: cat.$5
                          .where((t) => t != 'emit_event' && _availableActionTypes.any((at) => at['type'] == t))
                          .map((type) => SizedBox(
                                width: 200,
                                child: _ActionTypeCard(
                                  type: type,
                                  label: _actionLabel(type),
                                  example: _kActionExamples[type] ?? '',
                                  catColor: cat.$4,
                                  onTap: () {
                                    setState(() {
                                      _type = type;
                                      _showTypeCatalog = false;
                                      if (!_isKnownType) _initDynamicFields(type, {});
                                    });
                                    if (type == 'google_sheets_append_row' || type == 'google_sheets_update_row') {
                                      _checkGoogleOAuthForAction();
                                    }
                                    if (type == 'excel_onedrive_append_row' || type == 'excel_onedrive_update_row') {
                                      _checkMicrosoftOAuthForAction();
                                    }
                                  },
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                ],
                if (_availableActionTypes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.ctTeal),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final catColor = _actionCatColor(_type);

    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: _showTypeCatalog ? 680 : 520,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: _showTypeCatalog
            ? _buildTypeCatalog()
            : _buildActionForm(catColor),
      ),
    );
  }

  Widget _buildActionForm(Color catColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
          child: Row(
            children: [
              if (!_isEdit) ...[
                GestureDetector(
                  onTap: () => setState(() => _showTypeCatalog = true),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text('\u2190 Tipo',
                        style: AppTextStyles.bodySmall.copyWith(
                            color: const Color(0xFF6B7280))),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isEdit ? 'Editar acci\u00F3n' : _actionLabel(_type),
                      style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w700, fontSize: 17),
                    ),
                    const SizedBox(height: 2),
                    Text(_kActionExamples[_type] ?? '',
                        style: AppTextStyles.bodySmall.copyWith(
                            color: const Color(0xFF4C5D73))),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: AppColors.ctText2),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1, color: AppColors.ctBorder),
        // Body
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero diagram
                Container(
                  width: double.infinity,
                  height: 100,
                  margin: const EdgeInsets.only(top: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        catColor.withValues(alpha: 0.08),
                        catColor.withValues(alpha: 0.02),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: catColor.withValues(alpha: 0.12)),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 150,
                      height: 90,
                      child: FittedBox(
                        child: ActionMiniDiagram(type: _type, catColor: catColor),
                      ),
                    ),
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
                else
                  Builder(builder: (_) {
                    final chainable = _availableFlows.where(_hasOnComplete).toList();
                    final selectedIsInvalid = _selectedFlowSlug != null &&
                        !chainable.any((f) => f['slug'] == _selectedFlowSlug);
                    final items = <AppDropdownItem<String?>>[
                      ...chainable.map((f) {
                        final slug = f['slug'] as String? ?? '';
                        final name = f['name'] as String? ?? slug;
                        return AppDropdownItem<String?>(value: slug, label: name);
                      }),
                      if (selectedIsInvalid)
                        AppDropdownItem<String?>(
                          value: _selectedFlowSlug,
                          label: '${_availableFlows.firstWhere(
                                (f) => f['slug'] == _selectedFlowSlug,
                                orElse: () => {'name': _selectedFlowSlug!},
                              )['name'] ?? _selectedFlowSlug} (sin permiso de encadenamiento)',
                        ),
                    ];
                    if (items.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.ctBorder),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'No hay flows configurados para encadenamiento',
                          style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppDropdown<String?>(
                          hint: 'Selecciona un flujo',
                          value: _selectedFlowSlug,
                          items: items,
                          onChanged: (v) => setState(() => _selectedFlowSlug = v),
                        ),
                        if (selectedIsInvalid)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'El flujo seleccionado no tiene "on_complete" en trigger_sources.',
                              style: AppTextStyles.caption.copyWith(color: AppColors.ctDanger),
                            ),
                          ),
                      ],
                    );
                  }),
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
                const Divider(height: 24, color: AppColors.ctBorder),
                // ── Mensaje proactivo ──
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Enviar mensaje proactivo al operador',
                      style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    'Se enviará una plantilla de WhatsApp al abrir el flujo',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
                  ),
                  value: _sendProactive,
                  onChanged: (v) => setState(() {
                    _sendProactive = v;
                    if (!v) {
                      _selectedTemplateId = null;
                      _proactiveMappingRows = [];
                    }
                  }),
                  activeThumbColor: AppColors.ctTeal,
                ),
                if (_sendProactive) ...[
                  const SizedBox(height: 8),
                  if (_loadingTemplates)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.ctTeal),
                      ),
                    )
                  else if (_waChannelId == null)
                    Text(
                      'No se encontró canal WhatsApp activo para este worker',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctDanger),
                    )
                  else if (_approvedTemplates.isEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('No hay plantillas aprobadas.',
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3)),
                        const SizedBox(height: 6),
                        AppButton(
                          label: 'Crear plantilla',
                          variant: AppButtonVariant.ghost,
                          size: AppButtonSize.sm,
                          onPressed: () {
                            if (_waChannelId == null) return;
                            showDialog<void>(
                              context: context,
                              builder: (_) => TemplateCreateDialog(
                                channelId: _waChannelId!,
                                tenantId: widget.tenantId,
                              ),
                            ).then((_) {
                              if (_waChannelId != null) _loadTemplatesForAction(_waChannelId!);
                            });
                          },
                        ),
                      ],
                    )
                  else ...[
                    AppDropdown<String?>(
                      label: 'Plantilla',
                      value: _selectedTemplateId,
                      hint: 'Selecciona una plantilla aprobada',
                      items: [
                        const AppDropdownItem<String?>(value: null, label: '\u2014 Sin plantilla \u2014'),
                        ..._approvedTemplates.map((t) {
                          final id = t['id'] as String? ?? t['name'] as String? ?? '';
                          final name = t['name'] as String? ?? id;
                          final lang = t['language'] as String? ?? '';
                          return AppDropdownItem<String?>(
                            value: id,
                            label: '$name ($lang)',
                          );
                        }),
                        const AppDropdownItem<String?>(
                          value: '__create__',
                          label: '\uFF0B Crear nueva plantilla',
                        ),
                      ],
                      onChanged: (v) {
                        if (v == '__create__') {
                          if (_waChannelId == null) return;
                          showDialog<void>(
                            context: context,
                            builder: (_) => TemplateCreateDialog(
                              channelId: _waChannelId!,
                              tenantId: widget.tenantId,
                            ),
                          ).then((_) {
                            if (_waChannelId != null) _loadTemplatesForAction(_waChannelId!);
                          });
                          return;
                        }
                        if (v == null) {
                          setState(() {
                            _selectedTemplateId = null;
                            _proactiveMappingRows = [];
                          });
                        } else {
                          setState(() => _selectedTemplateId = v);
                          final t = _approvedTemplates
                              .where((t) => (t['id'] as String? ?? t['name'] as String? ?? '') == v)
                              .firstOrNull;
                          if (t != null) _initProactiveMappingFromTemplate(t);
                        }
                      },
                    ),
                    // ── Template preview ──
                    Builder(builder: (_) {
                      final sel = _selectedTemplateId == null
                          ? null
                          : _approvedTemplates
                              .where((t) => (t['id'] as String? ?? t['name'] as String? ?? '') == _selectedTemplateId)
                              .firstOrNull;
                      if (sel == null) return const SizedBox.shrink();
                      final body = sel['body_text'] as String?;
                      if (body == null || body.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.ctSurface2,
                            border: Border.all(color: AppColors.ctBorder),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((sel['header_text'] as String?) != null) ...[
                                Text(
                                  sel['header_text'] as String,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.ctText2,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                              ],
                              _buildActionTemplateBodyPreview(body),
                              if ((sel['footer_text'] as String?) != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  sel['footer_text'] as String,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.ctText3,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                    // ── Mapeo de variables (auto-generado desde template) ──
                    if (_proactiveMappingRows.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('Mapeo de variables',
                          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      ...List.generate(_proactiveMappingRows.length, (i) {
                        final row = _proactiveMappingRows[i];
                        final varKey = row['variable'] as String? ?? '';
                        final slot = row['slot'] as int? ?? (i + 1);
                        final varLabel = varKey.startsWith('variable_')
                            ? '{{$slot}}'
                            : '$varKey  {{$slot}}';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: AppColors.ctSurface,
                                    border: Border.all(color: AppColors.ctBorder),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(varLabel, style: AppTextStyles.body),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: AppDropdown<String>(
                                  value: (row['source'] as String?)?.isEmpty == true
                                      ? null
                                      : row['source'] as String?,
                                  hint: 'Campo fuente',
                                  items: const [
                                    AppDropdownItem<String>(value: '', label: '\u2014 Sin campo \u2014'),
                                    AppDropdownItem<String>(value: 'system:operator.name', label: 'Nombre del operador'),
                                    AppDropdownItem<String>(value: 'system:operator.phone', label: 'Tel\u00E9fono del operador'),
                                    AppDropdownItem<String>(value: 'system:tenant.name', label: 'Nombre de la empresa'),
                                    AppDropdownItem<String>(value: 'system:flow.name', label: 'Nombre del flujo'),
                                    AppDropdownItem<String>(value: 'system:flow.fields_summary', label: 'Campos del flujo (lista)'),
                                  ],
                                  onChanged: (v) {
                                    setState(() => _proactiveMappingRows[i] = {
                                      ..._proactiveMappingRows[i],
                                      'source': v ?? '',
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ],
              ] else if (_type == 'open_flow_n_times') ...[
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
                else
                  Builder(builder: (_) {
                    final chainable = _availableFlows.where(_hasOnComplete).toList();
                    final selectedIsInvalid = _selectedFlowSlug != null &&
                        !chainable.any((f) => f['slug'] == _selectedFlowSlug);
                    final items = <AppDropdownItem<String?>>[
                      ...chainable.map((f) {
                        final slug = f['slug'] as String? ?? '';
                        final name = f['name'] as String? ?? slug;
                        return AppDropdownItem<String?>(value: slug, label: name);
                      }),
                      if (selectedIsInvalid)
                        AppDropdownItem<String?>(
                          value: _selectedFlowSlug,
                          label: '${_availableFlows.firstWhere(
                                (f) => f['slug'] == _selectedFlowSlug,
                                orElse: () => {'name': _selectedFlowSlug!},
                              )['name'] ?? _selectedFlowSlug} (sin permiso de encadenamiento)',
                        ),
                    ];
                    if (items.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.ctBorder),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'No hay flows configurados para encadenamiento',
                          style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppDropdown<String?>(
                          hint: 'Selecciona un flujo',
                          value: _selectedFlowSlug,
                          items: items,
                          onChanged: (v) => setState(() => _selectedFlowSlug = v),
                        ),
                        if (selectedIsInvalid)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'El flujo seleccionado no tiene "on_complete" en trigger_sources.',
                              style: AppTextStyles.caption.copyWith(color: AppColors.ctDanger),
                            ),
                          ),
                      ],
                    );
                  }),
                const SizedBox(height: 12),
                Text(
                  'Campo de conteo',
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Builder(builder: (_) {
                  final numericFields = widget.flowFields
                      .where((f) => (f['type'] as String?) == 'number')
                      .toList();
                  if (numericFields.isEmpty) {
                    return _SemanticWarning(
                      message: 'Este flujo no tiene campos de tipo Número. '
                          'Agrega uno en la pestaña Campos antes de configurar esta acción.',
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppDropdown<String?>(
                        value: _selectedCountFieldKey,
                        hint: 'Seleccionar campo numérico',
                        items: numericFields
                            .map((f) => AppDropdownItem<String?>(
                                  value: f['key'] as String?,
                                  label: '${f['label'] ?? f['key']}',
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedCountFieldKey = v),
                      ),
                      if (_selectedCountFieldKey != null)
                        Builder(builder: (_) {
                          final field = widget.flowFields.firstWhere(
                            (f) => (f['key'] as String?) == _selectedCountFieldKey,
                            orElse: () => <String, dynamic>{},
                          );
                          final isRequired = field['required'] as bool? ?? false;
                          if (isRequired) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: _SemanticWarning(
                              message: 'Este campo no es obligatorio. '
                                  'Si el operador no lo captura, no se crearán instancias hijas.',
                            ),
                          );
                        }),
                    ],
                  );
                }),
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
              ] else if (_type == 'notify_group') ...[
                // Selector de tipo de destino
                Text(
                  'Tipo de destino',
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                AppDropdown<String>(
                  value: _notificationDestinationType,
                  items: const [
                    AppDropdownItem<String>(
                      value: 'group',
                      label: 'Grupo',
                    ),
                    AppDropdownItem<String>(
                      value: 'control_tower',
                      label: 'Torre de Control',
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _notificationDestinationType = v;
                        _selectedGroupId = null; // Reset selection
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Selector de grupo o torre
                Text(
                  _notificationDestinationType == 'control_tower'
                      ? 'Torre de Control'
                      : 'Grupo',
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Builder(builder: (context) {
                  final isLoadingData = _notificationDestinationType == 'control_tower'
                      ? _loadingControlTowers
                      : _loadingGroups;

                  // Solo mostrar las activas en el selector (excluir inactive)
                  final allData = _notificationDestinationType == 'control_tower'
                      ? _controlTowers
                      : _groups;
                  final dataList = allData.where((item) {
                    final itemStatus = item['status'] as String? ?? 'active';
                    return itemStatus == 'active';
                  }).toList();

                  final emptyMessage = _notificationDestinationType == 'control_tower'
                      ? 'No hay torres de control activas'
                      : 'No hay grupos activos en este tenant';
                  final hintText = _notificationDestinationType == 'control_tower'
                      ? 'Seleccionar torre de control'
                      : 'Seleccionar grupo';

                  if (isLoadingData) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: CircularProgressIndicator(
                            color: AppColors.ctTeal, strokeWidth: 2),
                      ),
                    );
                  }

                  if (dataList.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.ctBorder),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        emptyMessage,
                        style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                      ),
                    );
                  }

                  return AppDropdown<String>(
                    value: dataList.any((g) => g['id'] == _selectedGroupId)
                        ? _selectedGroupId
                        : null,
                    hint: hintText,
                    items: dataList.map((g) {
                      final id = g['id'] as String? ?? '';
                      final name = g['display_name'] as String? ?? id;
                      final chType = g['channel_type'] as String? ?? '';
                      return AppDropdownItem<String>(
                        value: id,
                        label: '$name ($chType)',
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _selectedGroupId = v),
                  );
                }),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Checkbox(
                      value: _workerGenerates,
                      onChanged: (val) {
                        setState(() {
                          _workerGenerates = val ?? false;
                        });
                      },
                      activeColor: AppColors.ctTeal,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('El AI Worker genera el mensaje dinámicamente',
                              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500)),
                          const SizedBox(height: 2),
                          Text(
                            'Si está activado, Claude genera el mensaje. Si está desactivado, se usa la plantilla estática.',
                            style: AppTextStyles.bodySmall.copyWith(fontSize: 11, color: AppColors.ctText2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Plantilla del mensaje',
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  'Soporta variables de campos (fields.*), heredados (ancestors.*), execution (execution.*) y operador (operator.*).',
                  style: AppTextStyles.bodySmall.copyWith(fontSize: 11, color: AppColors.ctText2),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _messageTemplateCtrl,
                  maxLines: 5,
                  style: AppTextStyles.body.copyWith(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'ej. 🔔 Notificación de {{execution.flow_name}}\n📅 Fecha: {{execution.date}}\n👤 Operador: {{operator.name}}',
                    hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3, fontSize: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppColors.ctBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppColors.ctBorder),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 8),
                // ── Selector de variables ──
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: AppDropdown<String>(
                        hint: 'Selecciona una variable para insertar',
                        searchable: true,
                        searchHint: 'Buscar variable...',
                        items: _buildTemplateVariableItems(),
                        onChanged: (value) {
                          if (value != null && value.isNotEmpty && value.startsWith('{{')) {
                            // Insertar la variable en la posición del cursor
                            final currentText = _messageTemplateCtrl.text;
                            final cursorPos = _messageTemplateCtrl.selection.baseOffset;
                            final newText = cursorPos >= 0
                                ? currentText.substring(0, cursorPos) + value + currentText.substring(cursorPos)
                                : currentText + value;
                            _messageTemplateCtrl.text = newText;
                            // Mover cursor después de la variable insertada
                            final newCursorPos = cursorPos >= 0 ? cursorPos + value.length : newText.length;
                            _messageTemplateCtrl.selection = TextSelection.collapsed(offset: newCursorPos);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Ejemplo de template completo',
                      child: IconButton(
                        icon: const Icon(Icons.info_outline, size: 20),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Ejemplo de plantilla'),
                              content: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Ejemplo completo:',
                                      style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.ctSurface,
                                        border: Border.all(color: AppColors.ctBorder),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '🔔 Notificación de {{execution.flow_name}}\n\n'
                                        '📅 Fecha: {{execution.date}} {{execution.time}}\n'
                                        '👤 Operador: {{operator.name}}\n'
                                        '📧 Email: {{operator.email}}\n'
                                        '📱 Teléfono: {{operator.phone}}\n'
                                        '📊 Canal: {{execution.channel_name}}\n\n'
                                        'ID: {{execution.execution_id}}',
                                        style: AppTextStyles.body.copyWith(
                                          fontFamily: 'Geist',
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cerrar'),
                                ),
                              ],
                            ),
                          );
                        },
                        color: AppColors.ctTeal,
                      ),
                    ),
                  ],
                ),
                // ── Plantilla WhatsApp (fallback ventana cerrada) ──────────────────
                Builder(builder: (context) {
                  // Solo mostrar si el grupo es de WhatsApp
                  final selectedGroup = _groups.where((g) => g['id'] == _selectedGroupId).firstOrNull;
                  final isWhatsApp = selectedGroup != null && (selectedGroup['channel_type'] as String?) == 'whatsapp';

                  if (!isWhatsApp) return const SizedBox.shrink();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      const Divider(color: AppColors.ctBorder, height: 1),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(
                            'Plantilla WhatsApp (fallback ventana cerrada)',
                            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
                          ),
                          const Spacer(),
                          Switch(
                            value: _useWaTemplate,
                            onChanged: (v) => setState(() {
                              _useWaTemplate = v;
                              if (!v) {
                                _selectedWaTemplateId = null;
                                _waTemplateMappingRows = [];
                              }
                            }),
                            activeThumbColor: AppColors.ctTeal,
                          ),
                        ],
                      ),
                      if (_useWaTemplate) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Se usa si la ventana del grupo está cerrada (>24h).',
                          style: AppTextStyles.bodySmall.copyWith(fontSize: 11, color: AppColors.ctText2),
                        ),
                        const SizedBox(height: 8),
                        if (_loadingTemplates)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.ctTeal),
                            ),
                          )
                        else if (_waChannelId == null)
                          Text(
                            'No se encontró canal WhatsApp activo para este worker',
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctDanger),
                          )
                        else if (_approvedTemplates.isEmpty)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('No hay plantillas aprobadas.',
                                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3)),
                              const SizedBox(height: 6),
                              AppButton(
                                label: 'Crear plantilla',
                                variant: AppButtonVariant.ghost,
                                size: AppButtonSize.sm,
                                onPressed: () {
                                  if (_waChannelId == null) return;
                                  showDialog<void>(
                                    context: context,
                                    builder: (_) => TemplateCreateDialog(
                                      channelId: _waChannelId!,
                                      tenantId: widget.tenantId,
                                    ),
                                  ).then((_) {
                                    if (_waChannelId != null) _loadTemplatesForAction(_waChannelId!);
                                  });
                                },
                              ),
                            ],
                          )
                        else ...[
                          AppDropdown<String?>(
                            label: 'Plantilla',
                            value: _selectedWaTemplateId,
                            hint: 'Selecciona una plantilla aprobada',
                            items: [
                              const AppDropdownItem<String?>(value: null, label: '\u2014 Sin plantilla \u2014'),
                              ..._approvedTemplates.map((t) {
                                final id = t['id'] as String? ?? t['name'] as String? ?? '';
                                final name = t['name'] as String? ?? id;
                                final lang = t['language'] as String? ?? '';
                                return AppDropdownItem<String?>(
                                  value: id,
                                  label: '$name ($lang)',
                                );
                              }),
                              const AppDropdownItem<String?>(
                                value: '__create__',
                                label: '\uFF0B Crear nueva plantilla',
                              ),
                            ],
                            onChanged: (v) {
                              if (v == '__create__') {
                                if (_waChannelId == null) return;
                                showDialog<void>(
                                  context: context,
                                  builder: (_) => TemplateCreateDialog(
                                    channelId: _waChannelId!,
                                    tenantId: widget.tenantId,
                                  ),
                                ).then((_) {
                                  if (_waChannelId != null) _loadTemplatesForAction(_waChannelId!);
                                });
                                return;
                              }
                              if (v == null) {
                                setState(() {
                                  _selectedWaTemplateId = null;
                                  _waTemplateMappingRows = [];
                                });
                              } else {
                                setState(() => _selectedWaTemplateId = v);
                                final t = _approvedTemplates
                                    .where((t) => (t['id'] as String? ?? t['name'] as String? ?? '') == v)
                                    .firstOrNull;
                                if (t != null) _initWaTemplateMappingFromTemplate(t);
                              }
                            },
                          ),
                          // ── Template preview ──
                          Builder(builder: (_) {
                            final sel = _selectedWaTemplateId == null
                                ? null
                                : _approvedTemplates
                                    .where((t) => (t['id'] as String? ?? t['name'] as String? ?? '') == _selectedWaTemplateId)
                                    .firstOrNull;
                            if (sel == null) return const SizedBox.shrink();
                            final body = sel['body_text'] as String?;
                            if (body == null || body.isEmpty) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.ctSurface2,
                                  border: Border.all(color: AppColors.ctBorder),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if ((sel['header_text'] as String?) != null) ...[
                                      Text(
                                        sel['header_text'] as String,
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: AppColors.ctText2,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                    ],
                                    _buildActionTemplateBodyPreview(body),
                                    if ((sel['footer_text'] as String?) != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        sel['footer_text'] as String,
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: AppColors.ctText3,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }),
                          // ── Mapeo de variables ──
                          if (_waTemplateMappingRows.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text('Variables',
                                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500)),
                            const SizedBox(height: 6),
                            ...List.generate(_waTemplateMappingRows.length, (i) {
                              final row = _waTemplateMappingRows[i];
                              final varKey = row['variable'] as String? ?? '';
                              final slot = row['slot'] as int? ?? (i + 1);
                              final varLabel = varKey.startsWith('variable_')
                                  ? '{{$slot}}'
                                  : '$varKey  {{$slot}}';
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: AppColors.ctSurface,
                                          border: Border.all(color: AppColors.ctBorder),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(varLabel, style: AppTextStyles.body),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: TextEditingController(
                                          text: row['source'] as String? ?? '',
                                        ),
                                        decoration: InputDecoration(
                                          hintText: '{{fields.nombre}}',
                                          hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(6),
                                            borderSide: const BorderSide(color: AppColors.ctBorder),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(6),
                                            borderSide: const BorderSide(color: AppColors.ctBorder),
                                          ),
                                          contentPadding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 10),
                                        ),
                                        style: AppTextStyles.body,
                                        onChanged: (v) {
                                          _waTemplateMappingRows[i] = {
                                            ..._waTemplateMappingRows[i],
                                            'source': v,
                                          };
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ],
                      ],
                    ],
                  );
                }),
              ] else if (_type == 'google_sheets_append_row') ...[
                ..._buildGoogleSheetsFields(),
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
                ..._columnMappingRows.asMap().entries.map((e) => _buildColumnMappingRow(e.key)),
              ] else if (_type == 'google_sheets_update_row') ...[
                ..._buildGoogleSheetsFields(),
                const SizedBox(height: 16),
                Text('Columna de b\u00FAsqueda',
                    style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                if (_hasHeaders && _sheetHeaders.isNotEmpty)
                  AppDropdown<String?>(
                    hint: 'Selecciona columna\u2026',
                    value: _lookupColumnCtrl.text.isNotEmpty
                        ? _lookupColumnCtrl.text : null,
                    items: _sheetHeaders
                        .map((h) => AppDropdownItem<String?>(value: h, label: h))
                        .toList(),
                    onChanged: (v) => setState(() =>
                        _lookupColumnCtrl.text = v ?? ''),
                  )
                else if (_availableColumns.isNotEmpty)
                  AppDropdown<String?>(
                    hint: 'Selecciona columna\u2026',
                    value: _lookupColumnCtrl.text.isNotEmpty
                        ? _lookupColumnCtrl.text : null,
                    items: List.generate(_availableColumns.length, (i) {
                      final letter = _columnLetter(i);
                      final name = _availableColumns[i];
                      return AppDropdownItem<String?>(
                        value: letter,
                        label: '$letter \u2014 $name',
                      );
                    }),
                    onChanged: (v) => setState(() =>
                        _lookupColumnCtrl.text = v ?? ''),
                  )
                else
                  _FormField(
                    label: '',
                    controller: _lookupColumnCtrl,
                    placeholder: _hasHeaders ? 'Nombre de columna' : 'ej. A',
                  ),
                const SizedBox(height: 12),
                Text('Campo fuente del valor de b\u00FAsqueda',
                    style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Builder(builder: (context) {
                  final allKeys = _buildAllValidKeys();
                  final effectiveLookupKey = (_lookupValueFieldKey != null &&
                      (allKeys.contains(_lookupValueFieldKey) ||
                       (_loadingCatalogSchemas && _lookupValueFieldKey!.contains('.'))))
                      ? _lookupValueFieldKey
                      : null;
                  return AppDropdown<String?>(
                    hint: _loadingCatalogSchemas
                        ? 'Cargando campos\u2026'
                        : 'Campo del flujo\u2026',
                    value: effectiveLookupKey,
                    items: [
                      ..._buildFieldDropdownItems(),
                      if (_loadingCatalogSchemas &&
                          _lookupValueFieldKey != null &&
                          _lookupValueFieldKey!.contains('.') &&
                          !allKeys.contains(_lookupValueFieldKey))
                        AppDropdownItem<String?>(
                          value: _lookupValueFieldKey,
                          label: 'Cargando\u2026',
                        ),
                    ],
                    onChanged: (v) => setState(() => _lookupValueFieldKey = v),
                  );
                }),
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
                ..._columnMappingRows.asMap().entries.map((e) => _buildColumnMappingRow(e.key)),
              ] else if (_type == 'excel_onedrive_append_row') ...[
                // Excel OneDrive UI
                if (_checkingMicrosoftOAuth)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ctTeal),
                    ),
                  )
                else if (!_microsoftConnected)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                size: 16, color: Color(0xFFB45309)),
                            const SizedBox(width: 8),
                            Text(
                              'Tu cuenta de Microsoft no está conectada.',
                              style: AppTextStyles.bodySmall.copyWith(
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFB45309),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Para usar Excel OneDrive, conecta tu cuenta de Microsoft en Configuración → Integraciones.',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: const Color(0xFF92400E),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  if (_loadingOnedriveFiles) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(color: AppColors.ctTeal),
                    const SizedBox(height: 6),
                    Text(
                      'Cargando archivos de OneDrive…',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2),
                    ),
                  ] else if (_onedriveFiles.isEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'No se encontraron archivos Excel en OneDrive',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2),
                    ),
                  ] else ...[
                    Text('Archivo Excel', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    AppDropdown<String?>(
                      hint: 'Selecciona un archivo…',
                      value: _selectedExcelFileId,
                      items: _onedriveFiles.map((f) {
                        final id = f['id'] as String?;
                        final name = f['name'] as String? ?? id ?? '';
                        return AppDropdownItem<String?>(value: id, label: name);
                      }).toList(),
                      onChanged: (v) {
                        setState(() {
                          _selectedExcelFileId = v;
                          _excelFileIdCtrl.text = v ?? '';
                          _selectedExcelSheet = null;
                          _availableExcelSheets = [];
                          _excelPreviewLoaded = false;
                        });
                        _loadExcelPreview();
                      },
                    ),
                    if (_loadingExcelPreview) ...[
                      const SizedBox(height: 6),
                      const LinearProgressIndicator(color: AppColors.ctTeal),
                    ],
                    if (_excelPreviewLoaded && _availableExcelSheets.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('Hoja', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 6),
                      AppDropdown<String?>(
                        hint: 'Selecciona una hoja…',
                        value: _selectedExcelSheet,
                        items: _availableExcelSheets.map((sheet) {
                          return AppDropdownItem<String?>(value: sheet, label: sheet);
                        }).toList(),
                        onChanged: (s) {
                          setState(() => _selectedExcelSheet = s);
                          if (s != null) {
                            _excelSheetNameCtrl.text = s;
                            _loadExcelPreview(sheetName: s);
                          }
                        },
                      ),
                      if (_excelPreviewColumns.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Se detectaron ${_excelPreviewColumns.length} columnas: '
                          '${_excelPreviewColumns.take(5).join(', ')}'
                          '${_excelPreviewColumns.length > 5 ? '…' : ''}',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2),
                        ),
                      ],
                    ],
                  ],
                  // Campo manual solo como fallback cuando no hay hojas automáticas
                  if (_onedriveFiles.isEmpty || _availableExcelSheets.isEmpty) ...[
                    const SizedBox(height: 12),
                    _FormField(
                      label: 'Nombre de la hoja (manual)',
                      controller: _excelSheetNameCtrl,
                      placeholder: 'Sheet1',
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Checkbox(
                        value: _hasHeaders,
                        onChanged: (v) => setState(() {
                          _hasHeaders = v ?? false;
                          if (_hasHeaders && _excelFileIdCtrl.text.isNotEmpty) {
                            _fetchExcelHeaders();
                          }
                        }),
                        activeColor: AppColors.ctTeal,
                      ),
                      const SizedBox(width: 8),
                      Text('La hoja tiene headers (primera fila)',
                          style: AppTextStyles.bodySmall),
                    ],
                  ),
                  if (_hasHeaders && _excelFileIdCtrl.text.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    AppButton(
                      label: 'Cargar headers',
                      variant: AppButtonVariant.outline,
                      size: AppButtonSize.sm,
                      onPressed: () {
                        if (!_loadingExcelHeaders) _fetchExcelHeaders();
                      },
                      prefixIcon: _loadingExcelHeaders
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.ctTeal))
                          : const Icon(Icons.refresh, size: 14),
                    ),
                  ],
                  if (_excelHeadersError != null) ...[
                    const SizedBox(height: 8),
                    Text(_excelHeadersError!,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.ctDanger)),
                  ],
                ],
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
                ..._columnMappingRows.asMap().entries.map((e) => _buildColumnMappingRow(e.key)),
              ] else if (_type == 'excel_onedrive_update_row') ...[
                // Excel OneDrive Update Row UI
                if (_checkingMicrosoftOAuth)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ctTeal),
                    ),
                  )
                else if (!_microsoftConnected)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                size: 16, color: Color(0xFFB45309)),
                            const SizedBox(width: 8),
                            Text(
                              'Tu cuenta de Microsoft no está conectada.',
                              style: AppTextStyles.bodySmall.copyWith(
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFB45309),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Para usar Excel OneDrive, conecta tu cuenta de Microsoft en Configuración → Integraciones.',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: const Color(0xFF92400E),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  if (_loadingOnedriveFiles) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(color: AppColors.ctTeal),
                    const SizedBox(height: 6),
                    Text(
                      'Cargando archivos de OneDrive…',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2),
                    ),
                  ] else if (_onedriveFiles.isEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'No se encontraron archivos Excel en OneDrive',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2),
                    ),
                  ] else ...[
                    Text('Archivo Excel', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    AppDropdown<String?>(
                      hint: 'Selecciona un archivo…',
                      value: _selectedExcelFileId,
                      items: _onedriveFiles.map((f) {
                        final id = f['id'] as String?;
                        final name = f['name'] as String? ?? id ?? '';
                        return AppDropdownItem<String?>(value: id, label: name);
                      }).toList(),
                      onChanged: (v) {
                        setState(() {
                          _selectedExcelFileId = v;
                          _excelFileIdCtrl.text = v ?? '';
                          _selectedExcelSheet = null;
                          _availableExcelSheets = [];
                          _excelPreviewLoaded = false;
                        });
                        _loadExcelPreview();
                      },
                    ),
                    if (_loadingExcelPreview) ...[
                      const SizedBox(height: 6),
                      const LinearProgressIndicator(color: AppColors.ctTeal),
                    ],
                    if (_excelPreviewLoaded && _availableExcelSheets.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('Hoja', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 6),
                      AppDropdown<String?>(
                        hint: 'Selecciona una hoja…',
                        value: _selectedExcelSheet,
                        items: _availableExcelSheets.map((sheet) {
                          return AppDropdownItem<String?>(value: sheet, label: sheet);
                        }).toList(),
                        onChanged: (s) {
                          setState(() => _selectedExcelSheet = s);
                          if (s != null) {
                            _excelSheetNameCtrl.text = s;
                            _loadExcelPreview(sheetName: s);
                          }
                        },
                      ),
                      if (_excelPreviewColumns.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Se detectaron ${_excelPreviewColumns.length} columnas: '
                          '${_excelPreviewColumns.take(5).join(', ')}'
                          '${_excelPreviewColumns.length > 5 ? '…' : ''}',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2),
                        ),
                      ],
                    ],
                  ],
                  // Campo manual solo como fallback cuando no hay hojas automáticas
                  if (_onedriveFiles.isEmpty || _availableExcelSheets.isEmpty) ...[
                    const SizedBox(height: 12),
                    _FormField(
                      label: 'Nombre de la hoja (manual)',
                      controller: _excelSheetNameCtrl,
                      placeholder: 'Sheet1',
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Checkbox(
                        value: _hasHeaders,
                        onChanged: (v) => setState(() {
                          _hasHeaders = v ?? false;
                          if (_hasHeaders && _excelFileIdCtrl.text.isNotEmpty) {
                            _fetchExcelHeaders();
                          }
                        }),
                        activeColor: AppColors.ctTeal,
                      ),
                      const SizedBox(width: 8),
                      Text('La hoja tiene headers (primera fila)',
                          style: AppTextStyles.bodySmall),
                    ],
                  ),
                  if (_hasHeaders && _excelFileIdCtrl.text.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    AppButton(
                      label: 'Cargar headers',
                      variant: AppButtonVariant.outline,
                      size: AppButtonSize.sm,
                      onPressed: () {
                        if (!_loadingExcelHeaders) _fetchExcelHeaders();
                      },
                      prefixIcon: _loadingExcelHeaders
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.ctTeal))
                          : const Icon(Icons.refresh, size: 14),
                    ),
                  ],
                  if (_excelHeadersError != null) ...[
                    const SizedBox(height: 8),
                    Text(_excelHeadersError!,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.ctDanger)),
                  ],
                ],
                const SizedBox(height: 16),
                Text('Columna de búsqueda',
                    style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                if (_hasHeaders && _sheetHeaders.isNotEmpty)
                  AppDropdown<String?>(
                    hint: 'Selecciona columna…',
                    value: _lookupColumnCtrl.text.isNotEmpty
                        ? _lookupColumnCtrl.text : null,
                    items: _sheetHeaders
                        .map((h) => AppDropdownItem<String?>(value: h, label: h))
                        .toList(),
                    onChanged: (v) => setState(() =>
                        _lookupColumnCtrl.text = v ?? ''),
                  )
                else
                  _FormField(
                    label: '',
                    controller: _lookupColumnCtrl,
                    placeholder: _hasHeaders ? 'Nombre de columna' : 'ej. A',
                  ),
                const SizedBox(height: 12),
                Text('Campo fuente del valor de búsqueda',
                    style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Builder(builder: (context) {
                  final allKeys = _buildAllValidKeys();
                  final effectiveLookupKey = (_lookupValueFieldKey != null &&
                      (allKeys.contains(_lookupValueFieldKey) ||
                       (_loadingCatalogSchemas && _lookupValueFieldKey!.contains('.'))))
                      ? _lookupValueFieldKey
                      : null;
                  return AppDropdown<String?>(
                    hint: _loadingCatalogSchemas
                        ? 'Cargando campos…'
                        : 'Campo del flujo…',
                    value: effectiveLookupKey,
                    items: [
                      ..._buildFieldDropdownItems(),
                      if (_loadingCatalogSchemas &&
                          _lookupValueFieldKey != null &&
                          _lookupValueFieldKey!.contains('.') &&
                          !allKeys.contains(_lookupValueFieldKey))
                        AppDropdownItem<String?>(
                          value: _lookupValueFieldKey,
                          label: 'Cargando…',
                        ),
                    ],
                    onChanged: (v) => setState(() => _lookupValueFieldKey = v),
                  );
                }),
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
                ..._columnMappingRows.asMap().entries.map((e) => _buildColumnMappingRow(e.key)),
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
              Builder(builder: (_) {
                const conditionableTypes = {'text', 'number', 'boolean', 'select', 'date'};
                final conditionableFields = widget.flowFields
                    .where((f) => conditionableTypes.contains(f['type'] as String?))
                    .toList();
                final selectedField = conditionableFields
                    .where((f) => f['key'] == _conditionField)
                    .firstOrNull;
                final fieldType = selectedField?['type'] as String?;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppDropdown<String?>(
                      label: 'Campo',
                      value: _conditionField,
                      hint: 'Sin condici\u00F3n',
                      items: [
                        const AppDropdownItem<String?>(value: null, label: 'Sin condici\u00F3n'),
                        ...conditionableFields.map((f) {
                          final key = f['key'] as String? ?? '';
                          final label = f['label'] as String? ?? key;
                          return AppDropdownItem<String?>(value: key, label: label);
                        }),
                      ],
                      onChanged: (v) => setState(() {
                        _conditionField = v;
                        _conditionValueCtrl.clear();
                        final newField = conditionableFields
                            .where((f) => f['key'] == v)
                            .firstOrNull;
                        final newType = newField?['type'] as String?;
                        final ops = _conditionOpsForType(newType);
                        if (!ops.any((o) => o.value == _conditionOp)) {
                          _conditionOp = '==';
                        }
                      }),
                    ),

                    if (_conditionField != null) ...[
                      const SizedBox(height: 10),
                      if (fieldType == 'boolean') ...[
                        // Boolean: chips, no operator dropdown
                        Row(
                          children: [
                            for (final entry in [('true', 'Verdadero'), ('false', 'Falso')]) ...[
                              if (entry.$1 == 'false') const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => setState(() => _conditionValueCtrl.text = entry.$1),
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: _conditionValueCtrl.text == entry.$1
                                          ? AppColors.ctTeal.withValues(alpha: 0.12)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: _conditionValueCtrl.text == entry.$1
                                            ? AppColors.ctTeal
                                            : AppColors.ctBorder,
                                      ),
                                    ),
                                    child: Text(
                                      entry.$2,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: _conditionValueCtrl.text == entry.$1
                                            ? FontWeight.w600 : FontWeight.w400,
                                        color: _conditionValueCtrl.text == entry.$1
                                            ? AppColors.ctTeal : AppColors.ctText2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ] else ...[
                        Row(
                          children: [
                            SizedBox(
                              width: 160,
                              child: AppDropdown<String>(
                                value: _conditionOp,
                                hint: 'Operador',
                                items: _conditionOpsForType(fieldType),
                                onChanged: (v) {
                                  if (v != null) setState(() => _conditionOp = v);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: _buildConditionValueWidget(fieldType, selectedField)),
                          ],
                        ),
                      ],
                      // Preview
                      Builder(builder: (_) {
                        final expr = _buildConditionExpression();
                        if (expr == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Expresi\u00F3n: $expr',
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
                          ),
                        );
                      }),
                    ],
                  ],
                );
              }),

              const SizedBox(height: 8),
            ],
          ),
        ),
        ),
        // Footer
        Container(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 14),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.ctBorder)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                label: 'Cancelar',
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.sm,
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              AppButton(
                label: _isEdit ? 'Guardar cambios' : 'Crear acci\u00F3n',
                variant: AppButtonVariant.primary,
                size: AppButtonSize.sm,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── _ActionTypeCard ──────────────────────────────────────────────────────────

class _ActionTypeCard extends StatefulWidget {
  const _ActionTypeCard({
    required this.type,
    required this.label,
    required this.example,
    required this.catColor,
    required this.onTap,
  });
  final String type;
  final String label;
  final String example;
  final Color catColor;
  final VoidCallback onTap;

  @override
  State<_ActionTypeCard> createState() => _ActionTypeCardState();
}

class _ActionTypeCardState extends State<_ActionTypeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.ctSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? widget.catColor.withValues(alpha: 0.4)
                  : const Color(0xFFE5E7EB),
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: widget.catColor.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: ActionMiniDiagram(
                      type: widget.type, catColor: widget.catColor),
                ),
              ),
              const SizedBox(height: 8),
              Text(widget.label,
                  style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 2),
              Text(
                widget.example,
                style: AppTextStyles.bodySmall.copyWith(
                    fontSize: 11, color: const Color(0xFF6B7280)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
    return TextField(
      controller: controller,
      style: AppTextStyles.body,
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
        filled: true,
        fillColor: AppColors.ctSurface2,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.ctBorder2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.ctTeal, width: 1.5),
        ),
      ),
      onChanged: (_) => onChanged(),
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
    required this.currentFlowFields,
    required this.onChanged,
    required this.dio,
  });
  final List<Map<String, dynamic>> rules;
  final bool canManage;
  final List<Map<String, dynamic>> availableRoles;
  final String tenantId;
  final String tenantWorkerId;
  final String currentFlowSlug;
  final List<Map<String, dynamic>> currentFlowFields;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final Dio dio;

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
      final types = await FlowsApi.getPreconditionTypes(dio: widget.dio);
      if (mounted) setState(() => _availableTypes = types);
    } catch (e, st) {
      debugPrint('[_loadTypes] error: $e\n$st');
    }
  }

  Future<void> _loadWorkerFlows() async {
    if (widget.tenantWorkerId.isEmpty) return;
    try {
      final flows = await FlowsApi.getFlowsByWorker(
        dio: widget.dio,
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
        currentFlowFields: widget.currentFlowFields,
        tenantId: widget.tenantId,
        dio: widget.dio,
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
    final declared = _rules.where((r) => r['source'] != 'chaining').toList();
    final inherited = _rules.where((r) => r['source'] == 'chaining').toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── [A] Header ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Precondiciones',
                      style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          color: const Color(0xFF1E2722)),
                    ),
                    const SizedBox(height: 6),
                    RichText(
                      text: TextSpan(
                        style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 13,
                            color: const Color(0xFF4C5D73),
                            height: 1.55),
                        children: const [
                          TextSpan(
                              text: 'Reglas que el sistema evalúa antes de permitir que el operador inicie este flow. Se evalúan en orden — un bloqueo '),
                          TextSpan(
                              text: 'duro',
                              style: TextStyle(fontStyle: FontStyle.italic)),
                          TextSpan(
                              text: ' detiene la cadena, un bloqueo '),
                          TextSpan(
                              text: 'suave',
                              style: TextStyle(fontStyle: FontStyle.italic)),
                          TextSpan(
                              text: ' registra el fallo y continúa.'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.canManage) ...[
                const SizedBox(width: 16),
                AppButton(
                  label: '+ Nueva precondición',
                  variant: AppButtonVariant.primary,
                  size: AppButtonSize.sm,
                  onPressed: () => _openRuleDialog(null),
                ),
              ],
            ],
          ),

          // ── [B] EvaluationChainPreview ──
          if (declared.isNotEmpty) ...[
            const SizedBox(height: 20),
            _EvaluationChainPreview(rules: declared),
          ],

          // ── [C] Inherited by chaining ──
          if (inherited.isNotEmpty) ...[
            const SizedBox(height: 20),
            _precondSectionLabel(
              '🔗 HEREDADAS POR ENCADENAMIENTO — ${inherited.length}',
              const Color(0xFF8B5CF6),
            ),
            const SizedBox(height: 10),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: inherited.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _RuleCard(
                rule: inherited[i],
                index: i,
                typeLabel: _typeLabel(inherited[i]['type'] as String? ?? ''),
                canManage: false,
                onEdit: () {},
                onDelete: () {},
              ),
            ),
          ],

          // ── [D] Declared in this flow ──
          if (declared.isNotEmpty) ...[
            const SizedBox(height: 20),
            _precondSectionLabel(
              'DECLARADAS EN ESTE FLOW — ${declared.length}',
              const Color(0xFF6B7280),
            ),
            const SizedBox(height: 10),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: declared.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _RuleCard(
                rule: declared[i],
                index: i,
                typeLabel: _typeLabel(declared[i]['type'] as String? ?? ''),
                canManage: widget.canManage,
                onEdit: () => _openRuleDialog(declared[i]),
                onDelete: () => _deleteRule(declared[i]),
              ),
            ),
          ],

          // ── Empty state ──
          if (declared.isEmpty && inherited.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: SizedBox(
                height: 200,
                child: _EmptyState(
                  icon: Icons.rule_outlined,
                  message: 'Este flow no tiene reglas de inicio configuradas.',
                ),
              ),
            ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static Widget _precondSectionLabel(String label, Color color) => Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.5)),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: color.withValues(alpha: 0.2), height: 1)),
        ],
      );
}

// ── _EvaluationChainPreview ──────────────────────────────────────────────────

class _EvaluationChainPreview extends StatelessWidget {
  const _EvaluationChainPreview({required this.rules});
  final List<Map<String, dynamic>> rules;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF1F1F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '▶  ORDEN DE EVALUACIÓN AL INICIAR EL FLOW',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.08,
              color: const Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < rules.length; i++) ...[
                _chainChip(rules[i], i),
                if (i < rules.length - 1)
                  Text(' → ',
                      style: TextStyle(
                          fontSize: 11, color: const Color(0xFFD1D5DB))),
              ],
              // Final chip: ✓ Iniciar flow
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFF15803D).withValues(alpha: 0.3)),
                ),
                child: Text(
                  '✓ Iniciar flow',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF15803D),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chainChip(Map<String, dynamic> rule, int index) {
    final type = rule['type'] as String? ?? '';
    final catColor = _precondCatColor(type);
    final shortLabel = _kPrecondShortLabels[type] ?? type;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: catColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: catColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: catColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            shortLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: catColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Category color for precondition types ────────────────────────────────────

Color _precondCatColor(String type) =>
    _kPrecondCatColors[type] ?? AppColors.ctTeal;

const _kPrecondShortLabels = {
  'no_active_execution': 'Sin instancia abierta',
  'requires_active_execution': 'Otro flow en curso',
  'no_concurrent_execution': 'Sin duplicado',
  'no_execution_in_window': 'Una vez en ventana',
  'requires_completed_sibling': 'Hermano completado',
  'no_active_sibling': 'Sin hermano activo',
  'all_children_completed': 'Hijos completados',
  'requires_parent': 'Solo como hijo',
  'operator_role_in': 'Rol requerido',
  'requires_active_assignment': 'Asignación vigente',
  'field_unique_in_window': 'Campo único',
  'time_window': 'En horario',
};

const _kPrecondCatColors = {
  'no_active_execution': Color(0xFF3B82F6),
  'requires_active_execution': Color(0xFF3B82F6),
  'no_concurrent_execution': Color(0xFF3B82F6),
  'no_execution_in_window': Color(0xFF3B82F6),
  'requires_completed_sibling': Color(0xFF8B5CF6),
  'no_active_sibling': Color(0xFF8B5CF6),
  'all_children_completed': Color(0xFF8B5CF6),
  'requires_parent': Color(0xFF8B5CF6),
  'operator_role_in': Color(0xFFF59E0B),
  'requires_active_assignment': Color(0xFFF59E0B),
  'field_unique_in_window': Color(0xFF10B981),
  'time_window': Color(0xFF10B981),
};

const _kPrecondTypeMeta = <String, ({String label, String example, String cat})>{
  'no_active_execution': (label: 'Sin ejecución activa', example: 'No puede iniciar "Inicio de Ruta" si ya tiene uno en curso.', cat: 'state'),
  'requires_active_execution': (label: 'Requiere ejecución activa', example: 'No puede iniciar "Cierre de Entrega" sin un "Inicio de Ruta" activo.', cat: 'state'),
  'no_execution_in_window': (label: 'Máximo una vez en la ventana', example: 'El operador no puede iniciar "Check-in de Turno" más de una vez por día.', cat: 'state'),
  'requires_completed_sibling': (label: 'Flow hermano completado', example: 'No puede iniciar "Segunda Ruta" sin completar "Primera Ruta" hoy.', cat: 'relation'),
  'all_children_completed': (label: 'Todos los hijos completados', example: 'No puede iniciar "Cierre de Turno" sin completar todas las entregas registradas.', cat: 'relation'),
  'requires_parent': (label: 'Solo como flow hijo', example: 'Este flow nunca debe iniciarse manualmente — solo el sistema lo abre.', cat: 'relation'),
  'operator_role_in': (label: 'Rol del operador requerido', example: 'Solo "Supervisor" puede iniciar "Auditoría de Inventario".', cat: 'operator'),
  'requires_active_assignment': (label: 'Asignación activa requerida', example: 'No puede iniciar "Inicio de Ruta" sin una ruta asignada hoy.', cat: 'operator'),
  'field_unique_in_window': (label: 'Campo único en ventana', example: 'El número de guía no puede repetirse en las últimas 24h.', cat: 'data'),
  'time_window': (label: 'Solo en horario permitido', example: 'Solo entre 6:00 y 9:00 AM.', cat: 'data'),
};

const _kPrecondCategories = [
  ('state', 'Estado del flow', '⚡', Color(0xFF3B82F6)),
  ('relation', 'Relación con otros flows', '🔗', Color(0xFF8B5CF6)),
  ('operator', 'Contexto del operador', '👤', Color(0xFFF59E0B)),
  ('data', 'Datos y tiempo', '🕐', Color(0xFF10B981)),
];

const _kPrecondCatLabels = {
  'no_active_execution': 'Estado',
  'requires_active_execution': 'Estado',
  'no_concurrent_execution': 'Estado',
  'no_execution_in_window': 'Estado',
  'requires_completed_sibling': 'Relación',
  'no_active_sibling': 'Relación',
  'all_children_completed': 'Relación',
  'requires_parent': 'Relación',
  'operator_role_in': 'Operador',
  'requires_active_assignment': 'Operador',
  'field_unique_in_window': 'Datos',
  'time_window': 'Datos',
};

class _RuleCard extends StatefulWidget {
  const _RuleCard({
    required this.rule,
    required this.index,
    required this.typeLabel,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });
  final Map<String, dynamic> rule;
  final int index;
  final String typeLabel;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_RuleCard> createState() => _RuleCardState();
}

class _RuleCardState extends State<_RuleCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ruleType = widget.rule['type'] as String? ?? '';
    final message = widget.rule['message'] as String? ?? '';
    final action = widget.rule['action'] as String? ?? 'block';
    final escalate = widget.rule['escalate'] as bool? ?? false;
    final catColor = _precondCatColor(ruleType);
    final catLabel = _kPrecondCatLabels[ruleType] ?? '';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.canManage ? widget.onEdit : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.ctSurface,
            border: Border.all(color: AppColors.ctBorder),
            borderRadius: BorderRadius.circular(10),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // [1] Strip izquierdo
                Container(
                  width: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        catColor.withValues(alpha: 0.07),
                        catColor.withValues(alpha: 0.04),
                      ],
                    ),
                    border: Border(
                      right: BorderSide(color: catColor.withValues(alpha: 0.12)),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: catColor,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${widget.index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  ),
                ),

                // [2] Mini diagrama
                Container(
                  width: 120,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFAFAFA),
                    border: Border(
                      right: BorderSide(color: Color(0xFFF1F1F1)),
                    ),
                  ),
                  child: Center(
                    child: PrecondMiniDiagram(type: ruleType, catColor: catColor),
                  ),
                ),

                // [3] Body
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Badges row
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            // Category badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: catColor.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: catColor.withValues(alpha: 0.15)),
                              ),
                              child: Text(
                                catLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: catColor,
                                ),
                              ),
                            ),
                            // Block mode badge
                            _BlockModeBadge(action: action, escalate: escalate),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Title
                        Text(
                          widget.typeLabel,
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1E2722),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Description
                        _RuleSummary(rule: widget.rule),
                        // Message
                        if (message.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAFAFA),
                              borderRadius: BorderRadius.circular(6),
                              border: Border(
                                left: BorderSide(color: catColor, width: 3),
                              ),
                            ),
                            child: RichText(
                              text: TextSpan(
                                style: AppTextStyles.bodySmall.copyWith(
                                    color: const Color(0xFF4C5D73)),
                                children: [
                                  TextSpan(
                                    text: 'Mensaje: ',
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  TextSpan(text: message),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // [4] Actions
                if (widget.canManage)
                  AnimatedOpacity(
                    opacity: _hovered ? 1.0 : 0.5,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: const BoxDecoration(
                        border: Border(
                          left: BorderSide(color: Color(0xFFF1F1F1)),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 15),
                            color: const Color(0xFF4C5D73),
                            onPressed: widget.onEdit,
                            tooltip: 'Editar',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          ),
                          const SizedBox(height: 4),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 15),
                            color: AppColors.ctDanger,
                            onPressed: widget.onDelete,
                            tooltip: 'Eliminar',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── _BlockModeBadge ──────────────────────────────────────────────────────────

class _BlockModeBadge extends StatelessWidget {
  const _BlockModeBadge({required this.action, required this.escalate});
  final String action;
  final bool escalate;

  @override
  Widget build(BuildContext context) {
    final isHard = action != 'allow';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isHard ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isHard ? const Color(0xFFFECACA) : const Color(0xFFFDE68A),
        ),
      ),
      child: Text(
        isHard
            ? '■ Bloqueo duro'
            : '~ Bloqueo suave${escalate ? ' · ↑ escala' : ''}',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isHard ? const Color(0xFF7F1D1D) : const Color(0xFF92400E),
        ),
      ),
    );
  }
}

// ── _RuleSummary ─────────────────────────────────────────────────────────────

class _RuleSummary extends StatelessWidget {
  const _RuleSummary({required this.rule});
  final Map<String, dynamic> rule;

  @override
  Widget build(BuildContext context) {
    final type = rule['type'] as String? ?? '';
    final config = ((rule['params'] ?? rule['config']) as Map?)
            ?.cast<String, dynamic>() ??
        {};
    const base = TextStyle(fontSize: 12, color: Color(0xFF4C5D73));
    const bold = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1E2722));

    final spans = _buildSpans(type, config, base, bold);
    return RichText(text: TextSpan(style: base, children: spans));
  }

  String _scopeLabel(String? scope) => switch (scope) {
        'operator' => 'el operador',
        'operator+day' => 'el operador hoy',
        'tenant+day' => 'cualquier operador hoy',
        _ => scope ?? 'el operador',
      };

  String _windowLabel(String? windowType, String? duration, String? tz) {
    return switch (windowType) {
      'calendar_day' => 'el día de hoy${tz != null ? ' ($tz)' : ''}',
      'shift' => 'su turno activo',
      'rolling' => 'las últimas ${duration ?? '24h'}',
      'ever' => 'algún momento',
      _ => windowType ?? 'el día',
    };
  }

  List<TextSpan> _buildSpans(
      String type, Map<String, dynamic> c, TextStyle base, TextStyle bold) {
    return switch (type) {
      'no_active_execution' => [
          TextSpan(text: 'Bloquear si '),
          TextSpan(text: _scopeLabel(c['scope'] as String?), style: bold),
          TextSpan(text: ' ya tiene una instancia activa.'),
        ],
      'requires_active_execution' => [
          TextSpan(text: 'Solo permitir si '),
          TextSpan(text: _scopeLabel(c['scope'] as String?), style: bold),
          TextSpan(text: ' tiene una instancia activa.'),
        ],
      'no_concurrent_execution' => [
          TextSpan(text: 'El operador no puede tener '),
          TextSpan(text: 'dos instancias', style: bold),
          TextSpan(text: ' de este flow corriendo al mismo tiempo.'),
        ],
      'no_execution_in_window' => [
          TextSpan(text: 'El operador solo puede ejecutar '),
          TextSpan(text: _scopeLabel(c['scope'] as String?), style: bold),
          TextSpan(text: ' '),
          TextSpan(
              text: switch (c['window_type'] as String?) {
                'rolling' => 'una vez cada ${c['window'] as String? ?? '24h'}',
                'shift' => 'una vez por turno',
                _ => 'una vez por día',
              },
              style: bold),
          TextSpan(text: '.'),
        ],
      'requires_completed_sibling' => [
          TextSpan(text: (c['window_type'] as String?) == 'ever'
              ? 'El operador debe haber completado '
              : 'Debe haber completado '),
          TextSpan(
              text: c['sibling_slug'] as String? ?? '(sin configurar)',
              style: bold),
          if ((c['window_type'] as String?) == 'ever')
            TextSpan(text: ' al menos una vez')
          else ...[
            TextSpan(text: ' en '),
            TextSpan(
                text: _windowLabel(
                    c['window_type'] as String?,
                    c['window'] as String?,
                    c['timezone'] as String?),
                style: bold),
          ],
          if (c['also_no_active'] == true)
            TextSpan(text: ' y no tener uno activo'),
          TextSpan(text: '.'),
        ],
      'no_active_sibling' => [
          TextSpan(text: 'Bloquear si el operador ya tiene activo '),
          TextSpan(
              text: c['sibling_slug'] as String? ?? '(sin configurar)',
              style: bold),
          TextSpan(text: '.'),
        ],
      'all_children_completed' => [
          TextSpan(text: 'Bloquear si no se han completado los '),
          TextSpan(
              text: c['count_field_key'] as String? ?? 'N', style: bold),
          TextSpan(text: ' flujos hijos de '),
          TextSpan(
              text: c['child_flow_slug'] as String? ?? '(sin configurar)',
              style: bold),
          TextSpan(text: '.'),
        ],
      'requires_parent' => [
          TextSpan(text: 'Este flow '),
          TextSpan(text: 'no puede iniciarse manualmente', style: bold),
          TextSpan(text: ' — solo como hijo de otro flow.'),
        ],
      'operator_role_in' => [
          TextSpan(text: 'El operador debe tener el rol de '),
          TextSpan(
              text: (c['roles'] as List?)?.join(', ') ?? '(sin configurar)',
              style: bold),
          TextSpan(text: '.'),
        ],
      'requires_active_assignment' => [
          TextSpan(text: 'El operador debe tener una asignación activa de '),
          TextSpan(
              text: c['catalog_slug'] as String? ?? '(sin configurar)',
              style: bold),
          TextSpan(text: '.'),
        ],
      'field_unique_in_window' => [
          TextSpan(text: 'El campo '),
          TextSpan(
              text: c['field_key'] as String? ?? '(sin campo)', style: bold),
          TextSpan(text: ' no debe repetirse en '),
          TextSpan(
              text: _windowLabel(
                  c['window_type'] as String?,
                  c['window'] as String?,
                  c['timezone'] as String?),
              style: bold),
          TextSpan(text: '.'),
        ],
      'time_window' => [
          TextSpan(text: 'Solo entre las '),
          TextSpan(
              text: c['start_time'] as String? ?? '??:??', style: bold),
          TextSpan(text: ' y las '),
          TextSpan(text: c['end_time'] as String? ?? '??:??', style: bold),
          if (c['timezone'] != null) ...[
            TextSpan(text: ' ('),
            TextSpan(text: c['timezone'] as String, style: bold),
            TextSpan(text: ')'),
          ],
          TextSpan(text: '.'),
        ],
      _ => [TextSpan(text: type)],
    };
  }
}

class _AddRuleDialog extends StatefulWidget {
  const _AddRuleDialog({
    required this.rule,
    required this.availableRoles,
    required this.types,
    required this.workerFlows,
    required this.currentFlowSlug,
    required this.currentFlowFields,
    required this.tenantId,
    required this.onSaved,
    required this.dio,
  });
  final Map<String, dynamic>? rule;
  final List<Map<String, dynamic>> availableRoles;
  final List<Map<String, dynamic>> types;
  final List<Map<String, dynamic>> workerFlows;
  final String currentFlowSlug;
  final List<Map<String, dynamic>> currentFlowFields;
  final String tenantId;
  final ValueChanged<Map<String, dynamic>> onSaved;
  final Dio dio;

  @override
  State<_AddRuleDialog> createState() => _AddRuleDialogState();
}

class _AddRuleDialogState extends State<_AddRuleDialog> {
  late bool _showTypeCatalog;
  String? _type;
  final _messageCtrl = TextEditingController();
  String _action = 'block';
  bool _escalate = false;
  final _escalationReasonCtrl = TextEditingController();

  // Dynamic per-type field state
  final Map<String, TextEditingController> _textCtrls = {};
  final Map<String, TextEditingController> _durationCtrls = {};
  final Map<String, String?> _selectVals = {};
  final Map<String, bool> _boolVals = {};
  final Map<String, List<String>> _multiSelectVals = {};
  final Map<String, int> _durationValues = {};
  final Map<String, String> _durationUnits = {};
  final Map<String, String> _semanticWarnings = {};
  final Set<String> _fieldErrors = {};
  final Map<String, List<Map<String, dynamic>>> _fetchedFlowFields = {};
  final Set<String> _loadingFlowFields = {};

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

  void _clearDependentFieldKeys(String changedKey) {
    if (_type == null) return;
    for (final field in _fieldsForType(_type!)) {
      if (field['type'] != 'flow_field_key') continue;
      final source = field['source_flow_field'] as String? ?? 'self';
      if (source == changedKey) {
        final depKey = field['key'] as String? ?? '';
        _textCtrls[depKey]?.text = '';
      }
    }
    // Clear cached fields for old slug so they reload for new slug
    final oldSlug = _textCtrls[changedKey]?.text ?? '';
    if (oldSlug.isNotEmpty) _fetchedFlowFields.remove(oldSlug);
  }

  void _fetchFlowFields(String slug) {
    if (_fetchedFlowFields.containsKey(slug)) return;
    if (_loadingFlowFields.contains(slug)) return;
    final flow = _flowBySlug(slug);
    if (flow == null) return;
    final flowId = flow['id'] as String?;
    if (flowId == null || flowId.isEmpty) return;
    _loadingFlowFields.add(slug);
    FlowsApi.getFlow(dio: widget.dio, flowId: flowId).then((data) {
      if (!mounted) return;
      final rawFields = data['fields'] as List?;
      final fields = rawFields != null
          ? List<Map<String, dynamic>>.from(
              rawFields.whereType<Map>().map((e) => Map<String, dynamic>.from(e)))
          : <Map<String, dynamic>>[];
      setState(() {
        _fetchedFlowFields[slug] = fields;
        _loadingFlowFields.remove(slug);
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() {
        _fetchedFlowFields[slug] = [];
        _loadingFlowFields.remove(slug);
      });
    });
  }

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
    for (final c in _durationCtrls.values) { c.dispose(); }
    _textCtrls.clear();
    _durationCtrls.clear();
    _selectVals.clear();
    _boolVals.clear();
    _multiSelectVals.clear();
    _durationValues.clear();
    _durationUnits.clear();
    _fieldErrors.clear();
    for (final field in _fieldsForType(type)) {
      final key = field['key'] as String? ?? '';
      if (key.isEmpty) continue;
      final fieldType = field['type'] as String? ?? 'text';
      final existing = params[key];
      switch (fieldType) {
        case 'text':
          // Parse duration fields like "24h", "30m", "3d"
          if (key == 'window' && existing is String && existing.isNotEmpty) {
            final match = RegExp(r'^(\d+)([mhd])$').firstMatch(existing);
            if (match != null) {
              _durationValues[key] = int.tryParse(match.group(1)!) ?? 24;
              _durationUnits[key] = match.group(2)!;
            } else {
              _durationValues[key] = 24;
              _durationUnits[key] = 'h';
            }
            _durationCtrls[key] = TextEditingController(
                text: (_durationValues[key] ?? 24).toString());
          } else if (key == 'window') {
            _durationValues[key] = 24;
            _durationUnits[key] = 'h';
            _durationCtrls[key] = TextEditingController(text: '24');
          }
          _textCtrls[key] = TextEditingController(text: existing?.toString() ?? '');
        case 'time':
          final defaultTime = key == 'start_time' ? '08:00'
              : key == 'end_time' ? '18:00' : '';
          _textCtrls[key] = TextEditingController(
              text: existing?.toString().isNotEmpty == true ? existing.toString() : defaultTime);
        case 'flow_field_key':
          _textCtrls[key] = TextEditingController(text: existing?.toString() ?? '');
        case 'select':
          _selectVals[key] = existing?.toString()
              ?? (field['default'] as String?);
        case 'bool':
          _boolVals[key] = (existing as bool?) ?? false;
        case 'role_multi_select':
        case 'catalog_multi_select':
          if (existing is List) {
            _multiSelectVals[key] = List<String>.from(existing.map((e) => e.toString()));
          } else if (existing is String && existing.isNotEmpty) {
            _multiSelectVals[key] = existing.split(',').map((s) => s.trim()).toList();
          } else {
            _multiSelectVals[key] = [];
          }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _showTypeCatalog = widget.rule == null;
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
      final cats = await CatalogsApi.listCatalogs(dio: widget.dio, tenantId: widget.tenantId);
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
    for (final c in _durationCtrls.values) { c.dispose(); }
    _messageCtrl.dispose();
    _escalationReasonCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildConfig() {
    final config = <String, dynamic>{};
    for (final e in _textCtrls.entries) {
      // Duration fields: override with structured value
      if (_durationValues.containsKey(e.key)) {
        final n = _durationValues[e.key] ?? 24;
        final u = _durationUnits[e.key] ?? 'h';
        config[e.key] = '$n$u';
        continue;
      }
      if (e.value.text.trim().isNotEmpty) config[e.key] = e.value.text.trim();
    }
    for (final e in _selectVals.entries) { config[e.key] = e.value; }
    for (final e in _boolVals.entries) { config[e.key] = e.value; }
    for (final e in _multiSelectVals.entries) {
      if (e.value.isNotEmpty) config[e.key] = e.value;
    }
    return config;
  }

  Map<String, dynamic> _buildConfigSnapshot() {
    final map = <String, dynamic>{};
    _textCtrls.forEach((k, v) {
      if (_durationValues.containsKey(k)) {
        final n = _durationValues[k] ?? 24;
        final u = _durationUnits[k] ?? 'h';
        map[k] = '$n$u';
        return;
      }
      if (v.text.isNotEmpty) map[k] = v.text;
    });
    _selectVals.forEach((k, v) { if (v != null) map[k] = v; });
    _boolVals.forEach((k, v) { map[k] = v; });
    _multiSelectVals.forEach((k, v) { if (v.isNotEmpty) map[k] = v; });
    return map;
  }

  bool _isFieldVisible(Map<String, dynamic> field) {
    final showIf = field['show_if'] as Map<String, dynamic>?;
    if (showIf == null) return true;
    final depKey = showIf['field'] as String? ?? '';
    final depOp = showIf['op'] as String? ?? 'eq';
    final depVal = showIf['value'] as String? ?? '';
    final currentVal = _textCtrls[depKey]?.text ?? _selectVals[depKey] ?? '';
    if (depOp == 'eq') return currentVal == depVal;
    if (depOp == 'neq') return currentVal != depVal;
    return true;
  }

  bool _isFieldFilled(String key, String fieldType) {
    return switch (fieldType) {
      'text' => _durationValues.containsKey(key)
          ? (_durationValues[key] ?? 0) > 0
          : (_textCtrls[key]?.text.trim().isNotEmpty ?? false),
      'time' || 'flow_field_key' => _textCtrls[key]?.text.trim().isNotEmpty ?? false,
      'select' => _selectVals[key] != null && _selectVals[key]!.isNotEmpty,
      'role_multi_select' || 'catalog_multi_select' => (_multiSelectVals[key] ?? []).isNotEmpty,
      _ => true,
    };
  }

  void _submit() {
    if (_type == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecciona un tipo de regla')));
      return;
    }
    // Validate required fields
    final errors = <String>{};
    for (final field in _fieldsForType(_type!)) {
      final key = field['key'] as String? ?? '';
      if (key.isEmpty) continue;
      if (field['required'] != true) continue;
      if (!_isFieldVisible(field)) continue;
      final fieldType = field['type'] as String? ?? 'text';
      if (!_isFieldFilled(key, fieldType)) {
        errors.add(key);
      }
    }
    if (errors.isNotEmpty) {
      setState(() {
        _fieldErrors.clear();
        _fieldErrors.addAll(errors);
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Completa los campos requeridos')));
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
        AppDropdown<String>(
          label: label,
          value: selectedSlug,
          hint: 'Selecciona un flujo',
          items: _workerFlows.map((f) {
            final slug = f['slug'] as String? ?? '';
            final name = f['name'] as String? ?? slug;
            return AppDropdownItem<String>(value: slug, label: name);
          }).toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() {
                ctrl.text = v;
                _clearDependentFieldKeys(key);
              });
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

    return AppDropdown<String>(
      label: label,
      value: selectedSlug,
      hint: 'Selecciona un catálogo',
      items: _availableCatalogs.map((cat) {
        final slug = cat['slug'] as String? ?? '';
        final catLabel = cat['label'] as String?
            ?? cat['name'] as String?
            ?? slug;
        return AppDropdownItem<String>(value: slug, label: catLabel);
      }).toList(),
      onChanged: (v) {
        if (v != null) setState(() => ctrl.text = v);
      },
    );
  }

  Widget _buildTimezoneSelector(String key, String label) {
    final ctrl = _textCtrls[key] ??= TextEditingController();
    final currentVal = ctrl.text;
    final selectedVal = _kTimezones.any((t) => t.$1 == currentVal)
        ? currentVal
        : null;
    return AppDropdown<String?>(
      label: label,
      value: selectedVal,
      hint: 'Default del tenant',
      items: _kTimezones.map((tz) {
        return AppDropdownItem<String?>(
          value: tz.$1.isEmpty ? null : tz.$1,
          label: tz.$2,
        );
      }).toList(),
      onChanged: (v) => setState(() => ctrl.text = v ?? ''),
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
      final safeOptions = rawOptions.map((o) {
        if (o is Map) return Map<String, dynamic>.from(o);
        final s = o.toString();
        return <String, dynamic>{'value': s, 'label': s};
      }).toList();
      widgets.add(const SizedBox(height: 16));
      switch (fieldType) {
        case 'text':
          if (_isFlowSlugField(key)) {
            widgets.add(_buildFlowSlugSelector(key, label));
          } else if (key == 'catalog_slug') {
            widgets.add(_buildCatalogSlugSelector(key, label));
          } else if (key == 'timezone') {
            widgets.add(_buildTimezoneSelector(key, label));
          } else if (key == 'window') {
            final durUnit = _durationUnits[key] ?? 'h';
            final durCtrl = _durationCtrls[key] ??=
                TextEditingController(text: (_durationValues[key] ?? 24).toString());
            widgets
              ..add(Text(label,
                  style: AppTextStyles.formLabel.copyWith(color: AppColors.ctText2)))
              ..add(const SizedBox(height: 6))
              ..add(Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: durCtrl,
                      style: AppTextStyles.body,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: _inputDecoration.copyWith(hintText: '24'),
                      onChanged: (v) {
                        final n = int.tryParse(v) ?? 1;
                        setState(() => _durationValues[key] = n.clamp(1, 999));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 140,
                    child: AppDropdown<String>(
                      value: durUnit,
                      hint: 'Unidad',
                      items: const [
                        AppDropdownItem(value: 'm', label: 'Minutos'),
                        AppDropdownItem(value: 'h', label: 'Horas'),
                        AppDropdownItem(value: 'd', label: 'Días'),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _durationUnits[key] = v);
                      },
                    ),
                  ),
                ],
              ));
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
        case 'time':
          final timeCtrl = _textCtrls[key] ??= TextEditingController();
          widgets
            ..add(Text(label,
                style: AppTextStyles.formLabel.copyWith(color: AppColors.ctText2)))
            ..add(const SizedBox(height: 6))
            ..add(GestureDetector(
              onTap: () async {
                final parts = timeCtrl.text.split(':');
                final initial = TimeOfDay(
                  hour: int.tryParse(parts.elementAtOrNull(0) ?? '') ?? 8,
                  minute: int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0,
                );
                final picked = await showTimePicker(
                  context: context,
                  initialTime: initial,
                );
                if (picked != null) {
                  final hh = picked.hour.toString().padLeft(2, '0');
                  final mm = picked.minute.toString().padLeft(2, '0');
                  setState(() => timeCtrl.text = '$hh:$mm');
                }
              },
              child: AbsorbPointer(
                child: TextField(
                  controller: timeCtrl,
                  style: AppTextStyles.body,
                  decoration: _inputDecoration.copyWith(
                    hintText: '08:00',
                    suffixIcon: const Icon(Icons.access_time, size: 18),
                  ),
                ),
              ),
            ));
        case 'flow_field_key':
          final sourceFlowField = field['source_flow_field'] as String? ?? 'self';
          final typeFilter = (field['field_type_filter'] as List?)?.cast<String>();
          final flowFieldCtrl = _textCtrls[key] ??= TextEditingController();
          List<Map<String, dynamic>> sourceFields;
          bool waitingForDep = false;
          bool loadingFields = false;
          if (sourceFlowField == 'self') {
            sourceFields = widget.currentFlowFields;
          } else {
            final depSlug = _textCtrls[sourceFlowField]?.text ?? _selectVals[sourceFlowField] ?? '';
            if (depSlug.isEmpty) {
              waitingForDep = true;
              sourceFields = [];
            } else if (_fetchedFlowFields.containsKey(depSlug)) {
              sourceFields = _fetchedFlowFields[depSlug]!;
            } else {
              _fetchFlowFields(depSlug);
              loadingFields = true;
              sourceFields = [];
            }
          }
          final filteredFields = typeFilter != null
              ? sourceFields.where((f) => typeFilter.contains(f['type'])).toList()
              : sourceFields;
          widgets
            ..add(Text(label,
                style: AppTextStyles.formLabel.copyWith(color: AppColors.ctText2)))
            ..add(const SizedBox(height: 6));
          if (waitingForDep) {
            widgets.add(Text('Selecciona primero el flow relacionado',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3)));
          } else if (loadingFields) {
            widgets.add(const SizedBox(
              height: 40,
              child: Center(child: SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ctTeal),
              )),
            ));
          } else if (filteredFields.isEmpty && sourceFields.isNotEmpty) {
            widgets.add(Text('No hay campos del tipo requerido en este flow',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3)));
          } else if (filteredFields.isEmpty) {
            widgets.add(TextField(
              controller: flowFieldCtrl,
              style: AppTextStyles.body,
              decoration: _inputDecoration.copyWith(
                hintText: 'ej. numero_guia',
                helperText: 'Debe coincidir exactamente con el key del campo en el flow',
                helperStyle: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.ctText3, fontSize: 11),
              ),
            ));
          } else {
            final currentVal = flowFieldCtrl.text;
            final selectedVal = filteredFields.any((f) => (f['key'] as String?) == currentVal)
                ? currentVal
                : null;
            widgets.add(AppDropdown<String>(
              value: selectedVal,
              hint: 'Selecciona un campo',
              items: filteredFields.map((f) {
                final fKey = f['key'] as String? ?? '';
                final fLabel = f['label'] as String? ?? f['name'] as String? ?? fKey;
                return AppDropdownItem<String>(value: fKey, label: fLabel);
              }).toList(),
              onChanged: (v) {
                if (v != null) setState(() => flowFieldCtrl.text = v);
              },
            ));
          }
        case 'select':
          final displayAs = field['display_as'] as String?;
          if (displayAs == 'radio') {
            final catColor = _type != null ? _precondCatColor(_type!) : AppColors.ctTeal;
            widgets
              ..add(Text(label,
                  style: AppTextStyles.formLabel.copyWith(color: AppColors.ctText2)))
              ..add(const SizedBox(height: 6))
              ..add(_AppRadioGroup(
                options: safeOptions,
                value: _selectVals[key],
                color: catColor,
                onChanged: (val) => setState(() => _selectVals[key] = val),
              ));
          } else {
            widgets.add(AppDropdown<String>(
              label: label,
              value: _selectVals[key],
              hint: 'Seleccionar',
              items: safeOptions
                  .map((o) => AppDropdownItem<String>(
                        value: o['value'] as String? ?? '',
                        label: o['label'] as String? ?? '',
                      ))
                  .toList(),
              onChanged: (val) => setState(() => _selectVals[key] = val),
            ));
          }
        case 'bool':
          widgets.add(SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(label, style: AppTextStyles.body),
            value: _boolVals[key] ?? false,
            activeThumbColor: AppColors.ctTeal,
            onChanged: (val) => setState(() => _boolVals[key] = val),
          ));
        case 'role_multi_select':
          final selected = _multiSelectVals[key] ?? [];
          final catColor = _type != null ? _precondCatColor(_type!) : AppColors.ctTeal;
          widgets
            ..add(Text(label,
                style: AppTextStyles.formLabel.copyWith(color: AppColors.ctText2)))
            ..add(const SizedBox(height: 6));
          if (widget.availableRoles.isEmpty) {
            widgets.add(Text('No hay roles disponibles',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3)));
          } else {
            widgets.add(Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.availableRoles.map((role) {
                final id = role['id'] as String? ?? '';
                final name = role['label'] as String? ?? role['name'] as String? ?? id;
                final isSelected = selected.contains(id);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      final list = List<String>.from(selected);
                      if (isSelected) { list.remove(id); } else { list.add(id); }
                      _multiSelectVals[key] = list;
                    });
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? catColor.withValues(alpha: 0.12) : const Color(0xFFFAFAFA),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? catColor : const Color(0xFFE5E7EB),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSelected) ...[
                            Icon(Icons.check_rounded, size: 14, color: catColor),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                              color: isSelected ? catColor : const Color(0xFF4C5D73),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ));
          }
        case 'catalog_multi_select':
          final catSelected = _multiSelectVals[key] ?? [];
          final catColor = _type != null ? _precondCatColor(_type!) : AppColors.ctTeal;
          widgets
            ..add(Text(label,
                style: AppTextStyles.formLabel.copyWith(color: AppColors.ctText2)))
            ..add(const SizedBox(height: 6));
          if (_availableCatalogs.isEmpty) {
            widgets.add(Text('No hay catálogos disponibles',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3)));
          } else {
            widgets.add(Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _availableCatalogs.map((cat) {
                final slug = cat['slug'] as String? ?? '';
                final catLabel = cat['label'] as String?
                    ?? cat['name'] as String?
                    ?? slug;
                final isSelected = catSelected.contains(slug);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      final list = List<String>.from(catSelected);
                      if (isSelected) { list.remove(slug); } else { list.add(slug); }
                      _multiSelectVals[key] = list;
                    });
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? catColor.withValues(alpha: 0.12) : const Color(0xFFFAFAFA),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? catColor : const Color(0xFFE5E7EB),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSelected) ...[
                            Icon(Icons.check_rounded, size: 14, color: catColor),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            catLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                              color: isSelected ? catColor : const Color(0xFF4C5D73),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ));
          }
        case 'timezone':
          widgets.add(_buildTimezoneSelector(key, label));
      }
      if (_fieldErrors.contains(key)) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Este campo es requerido',
              style: TextStyle(fontSize: 12, color: AppColors.ctDanger)),
        ));
      }
    }
    return widgets;
  }

  Widget _buildBlockModeSelector() {
    Widget option(String value, String label, Color bg, Color border, Color text) {
      final selected = _action == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _action = value),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: selected ? bg : const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? border : const Color(0xFFE5E7EB),
                ),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? text : const Color(0xFF6B7280),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Modo de bloqueo',
            style: AppTextStyles.formLabel.copyWith(color: AppColors.ctText2)),
        const SizedBox(height: 4),
        Text(
          'El bloqueo duro detiene la evaluación. El suave registra el fallo y continúa con las siguientes reglas.',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            option('block', '■ Bloqueo duro',
                const Color(0xFFFEE2E2), const Color(0xFFEF4444), const Color(0xFF7F1D1D)),
            const SizedBox(width: 8),
            option('allow', '~ Bloqueo suave',
                const Color(0xFFFEF3C7), const Color(0xFFF59E0B), const Color(0xFF92400E)),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final catColor = _type != null ? _precondCatColor(_type!) : AppColors.ctTeal;
    final typeMeta = _type != null ? _kPrecondTypeMeta[_type!] : null;

    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: _showTypeCatalog
            ? _buildTypeCatalog()
            : _buildForm(catColor, typeMeta),
      ),
    );
  }

  Widget _buildTypeCatalog() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nueva precondición',
                        style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w700, fontSize: 17)),
                    const SizedBox(height: 4),
                    Text(
                      'Elige qué condición debe evaluarse antes de iniciar el flow',
                      style: AppTextStyles.bodySmall.copyWith(
                          color: const Color(0xFF4C5D73)),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: AppColors.ctText2),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1, color: AppColors.ctBorder),
        // Body
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final cat in _kPrecondCategories) ...[
                  if (_hasTypesInCategory(cat.$1)) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(cat.$3, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text(cat.$2,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: cat.$4)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildTypeGrid(cat.$1, cat.$4),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  bool _hasTypesInCategory(String category) {
    final availableTypeIds = widget.types.map((t) => t['type'] as String).toSet();
    return _kPrecondTypeMeta.entries
        .any((e) => e.value.cat == category && availableTypeIds.contains(e.key));
  }

  Widget _buildTypeGrid(String category, Color catColor) {
    final availableTypeIds = widget.types.map((t) => t['type'] as String).toSet();
    final types = _kPrecondTypeMeta.entries
        .where((e) => e.value.cat == category && availableTypeIds.contains(e.key))
        .toList();
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: types.map((e) {
        final type = e.key;
        final meta = e.value;
        return SizedBox(
          width: 200,
          child: _PrecondTypeCard(
            type: type,
            label: meta.label,
            example: meta.example,
            catColor: catColor,
            onTap: () => setState(() {
              _type = type;
              _showTypeCatalog = false;
              _initFields(type, {});
            }),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildForm(Color catColor, ({String label, String example, String cat})? typeMeta) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
          child: Row(
            children: [
              if (!_isEdit) ...[
                GestureDetector(
                  onTap: () => setState(() {
                    _showTypeCatalog = true;
                    _type = null;
                  }),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text('← Tipo',
                        style: AppTextStyles.bodySmall.copyWith(
                            color: const Color(0xFF6B7280))),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      typeMeta?.label ?? _type ?? '',
                      style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w700, fontSize: 17),
                    ),
                    if (typeMeta != null) ...[
                      const SizedBox(height: 2),
                      Text(typeMeta.example,
                          style: AppTextStyles.bodySmall.copyWith(
                              color: const Color(0xFF4C5D73))),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: AppColors.ctText2),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1, color: AppColors.ctBorder),
        // Body
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero diagram
                _PrecondHeroDiagram(
                  type: _type ?? '',
                  config: _buildConfigSnapshot(),
                  catColor: catColor,
                  currentFlowName: widget.currentFlowSlug,
                  flows: widget.workerFlows,
                  roles: widget.availableRoles,
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: AppColors.ctBorder),

                // Dynamic fields
                ..._renderDynamicFields(),

                const SizedBox(height: 16),
                Text('Mensaje al operador si falla',
                    style: AppTextStyles.formLabel.copyWith(
                        color: AppColors.ctText2)),
                const SizedBox(height: 6),
                TextField(
                  controller: _messageCtrl,
                  style: AppTextStyles.body,
                  maxLines: 2,
                  decoration: _inputDecoration.copyWith(
                      hintText:
                          'Ej: Ya iniciaste turno hoy. Espera mañana para iniciar de nuevo.',
                      hintStyle: AppTextStyles.body.copyWith(
                          color: AppColors.ctText3)),
                ),

                const SizedBox(height: 16),
                _buildBlockModeSelector(),

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
                      style: AppTextStyles.formLabel.copyWith(
                          color: AppColors.ctText2)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _escalationReasonCtrl,
                    style: AppTextStyles.body,
                    decoration: _inputDecoration.copyWith(
                        hintText: 'Opcional',
                        hintStyle: AppTextStyles.body.copyWith(
                            color: AppColors.ctText3)),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        // Footer
        Container(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 14),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.ctBorder)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                label: 'Cancelar',
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.sm,
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              AppButton(
                label: _isEdit ? 'Guardar cambios' : 'Crear precondición',
                variant: AppButtonVariant.primary,
                size: AppButtonSize.sm,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── _AppRadioGroup ───────────────────────────────────────────────────────────

class _AppRadioGroup extends StatelessWidget {
  const _AppRadioGroup({
    required this.options,
    required this.value,
    required this.color,
    required this.onChanged,
  });
  final List<Map<String, dynamic>> options;
  final String? value;
  final Color color;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: options.map((o) {
        final optValue = o['value'] as String? ?? '';
        final optLabel = o['label'] as String? ?? optValue;
        final optDesc = o['description'] as String?;
        final selected = value == optValue;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: GestureDetector(
            onTap: () => onChanged(optValue),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? color.withValues(alpha: 0.06) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? color : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? color : const Color(0xFFD1D5DB),
                          width: selected ? 5 : 1.5,
                        ),
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(optLabel,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                color: selected ? color : const Color(0xFF1E2722),
                              )),
                          if (optDesc != null && optDesc.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(optDesc,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: const Color(0xFF6B7280),
                                )),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── _PrecondTypeCard ─────────────────────────────────────────────────────────

class _PrecondTypeCard extends StatefulWidget {
  const _PrecondTypeCard({
    required this.type,
    required this.label,
    required this.example,
    required this.catColor,
    required this.onTap,
  });
  final String type;
  final String label;
  final String example;
  final Color catColor;
  final VoidCallback onTap;

  @override
  State<_PrecondTypeCard> createState() => _PrecondTypeCardState();
}

class _PrecondTypeCardState extends State<_PrecondTypeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.ctSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? widget.catColor.withValues(alpha: 0.4)
                  : const Color(0xFFE5E7EB),
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: widget.catColor.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: PrecondMiniDiagram(
                      type: widget.type, catColor: widget.catColor),
                ),
              ),
              const SizedBox(height: 8),
              Text(widget.label,
                  style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 2),
              Text(
                widget.example,
                style: AppTextStyles.bodySmall.copyWith(
                    fontSize: 11, color: const Color(0xFF6B7280)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _PrecondHeroDiagram ──────────────────────────────────────────────────────

class _PrecondHeroDiagram extends StatelessWidget {
  const _PrecondHeroDiagram({
    required this.type,
    required this.config,
    required this.catColor,
    required this.currentFlowName,
    required this.flows,
    required this.roles,
  });
  final String type;
  final Map<String, dynamic> config;
  final Color catColor;
  final String currentFlowName;
  final List<Map<String, dynamic>> flows;
  final List<Map<String, dynamic>> roles;

  String _flowName(String? slug) {
    if (slug == null || slug.isEmpty) return '—';
    final f = flows.where((f) => f['slug'] == slug).firstOrNull;
    return f?['name'] as String? ?? slug;
  }

  String _scopeLabel(String? scope) => switch (scope) {
        'operator' => 'Solo este operador',
        'operator+day' => 'Operador + día',
        'tenant+day' => 'Todo el tenant hoy',
        _ => scope ?? 'operador',
      };

  String _windowLabel(Map<String, dynamic> c) {
    final wt = c['window_type'] as String?;
    final dur = c['window'] as String? ?? c['duration'] as String? ?? '24h';
    final tz = c['timezone'] as String?;
    return switch (wt) {
      'calendar_day' => 'día de hoy${tz != null ? ' ($tz)' : ''}',
      'shift' => 'turno activo',
      'rolling' => 'últimas $dur',
      'ever' => 'alguna vez',
      _ => 'día de hoy',
    };
  }

  Widget _flowBox(String label, String sublabel, Color borderColor, Color bgColor,
      {bool dashed = false}) {
    return Container(
      constraints: const BoxConstraints(minHeight: 60, maxWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor.withValues(alpha: dashed ? 0.4 : 1.0),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: borderColor),
              maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
          const SizedBox(height: 2),
          Text(sublabel,
              style: TextStyle(fontSize: 10, color: const Color(0xFF9CA3AF)),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _operatorCircle() => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: catColor.withValues(alpha: 0.15),
          border: Border.all(color: catColor),
        ),
        child: const Center(child: Text('👤', style: TextStyle(fontSize: 20))),
      );

  Widget _arrowH() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 24, height: 2, color: catColor.withValues(alpha: 0.4)),
          Icon(Icons.arrow_right_rounded, size: 16, color: catColor),
        ],
      );

  Widget _xMark(String label) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.close, color: Color(0xFFEF4444), size: 28),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFEF4444))),
        ],
      );

  Widget _pill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      );

  Widget _miniBox(String label, Color color, {Widget? icon}) => Container(
        width: 50,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Center(
            child: icon ??
                Text(label,
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: color))),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 160,
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF1F1F1)),
      ),
      child: Center(child: _buildDiagram()),
    );
  }

  Widget _buildDiagram() => switch (type) {
        'no_active_execution' => _noActiveExecution(),
        'requires_active_execution' => _requiresActiveExecution(),
        'no_concurrent_execution' => _noConcurrentExecution(),
        'no_execution_in_window' => _noExecutionInWindow(),
        'requires_completed_sibling' => _requiresCompletedSibling(),
        'no_active_sibling' => _noActiveSibling(),
        'all_children_completed' => _allChildrenCompleted(),
        'requires_parent' => _requiresParent(),
        'operator_role_in' => _operatorRoleIn(),
        'requires_active_assignment' => _requiresActiveAssignment(),
        'field_unique_in_window' => _fieldUniqueInWindow(),
        'time_window' => _timeWindow(),
        _ => Icon(Icons.help_outline, size: 32, color: catColor.withValues(alpha: 0.3)),
      };

  Widget _noActiveExecution() {
    final slug = config['slug'] as String? ?? config['flow_slug'] as String?;
    final hasSlug = slug != null && slug.isNotEmpty;
    final targetName = hasSlug ? _flowName(slug) : 'este flow';
    final targetColor = hasSlug ? const Color(0xFFEF4444) : const Color(0xFF9CA3AF);
    final targetBg = hasSlug ? const Color(0xFFFEE2E2) : const Color(0xFFF5F5F5);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('YA EN CURSO', style: TextStyle(fontSize: 8, color: Color(0xFF9CA3AF))),
              const SizedBox(height: 4),
              _flowBox(targetName, 'activo', targetColor, targetBg),
            ]),
            const SizedBox(width: 12),
            _xMark('no permitido'),
            const SizedBox(width: 12),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('INTENTO DE INICIO', style: TextStyle(fontSize: 8, color: Color(0xFF9CA3AF))),
              const SizedBox(height: 4),
              _flowBox(currentFlowName, 'bloqueado', catColor, catColor.withValues(alpha: 0.08)),
            ]),
          ],
        ),
        const SizedBox(height: 8),
        _pill('SCOPE: ${_scopeLabel(config['scope'] as String?)}', catColor),
      ],
    );
  }

  Widget _requiresActiveExecution() {
    final slug = config['slug'] as String? ?? config['flow_slug'] as String?;
    final hasSlug = slug != null && slug.isNotEmpty;
    final requiredName = hasSlug ? _flowName(slug) : 'otro flow';
    final requiredColor = hasSlug ? const Color(0xFF15803D) : const Color(0xFF9CA3AF);
    final requiredBg = hasSlug ? const Color(0xFFDCFCE7) : const Color(0xFFF5F5F5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('DEBE ESTAR ACTIVO', style: TextStyle(fontSize: 8, color: Color(0xFF9CA3AF))),
          const SizedBox(height: 4),
          _flowBox(requiredName, 'en curso', requiredColor, requiredBg),
        ]),
        const SizedBox(width: 12),
        _arrowH(),
        const SizedBox(width: 12),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('ESTE FLOW', style: TextStyle(fontSize: 8, color: Color(0xFF9CA3AF))),
          const SizedBox(height: 4),
          _flowBox(currentFlowName, 'puede iniciar', catColor, catColor.withValues(alpha: 0.08)),
        ]),
      ],
    );
  }

  Widget _noConcurrentExecution() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 160,
            height: 85,
            child: Stack(
              children: [
                Positioned(left: 0, top: 0,
                    child: _flowBox(currentFlowName, 'instancia 1', catColor, catColor.withValues(alpha: 0.08))),
                Positioned(left: 20, top: 15,
                    child: _flowBox(currentFlowName, 'instancia 2', catColor, catColor.withValues(alpha: 0.08))),
                Positioned.fill(
                  child: CustomPaint(painter: _DiagLinePainter(const Color(0xFFEF4444))),
                ),
              ],
            ),
          ),
          Text('no permitido',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFEF4444))),
        ],
      );

  Widget _noExecutionInWindow() {
    final wt = config['window_type'] as String? ?? 'day';
    final window = config['window'] as String? ?? '24h';
    final scope = config['scope'] as String?;
    final catSlug = config['catalog_slug'] as String?;
    final windowLabel = switch (wt) {
      'rolling' => 'Últimas $window',
      'shift' => 'Turno activo',
      _ => 'Día calendario',
    };
    final scopeLabel = _scopeLabel(scope);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 280,
          height: 48,
          child: CustomPaint(
            painter: _WindowTimelinePainter(
              catColor: catColor,
              windowMode: wt,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            _pill(windowLabel, catColor),
            _pill(scopeLabel, catColor),
            if (wt == 'shift' && catSlug != null)
              _pill(catSlug, catColor),
          ],
        ),
      ],
    );
  }

  Widget _requiresCompletedSibling() {
    final slug = config['sibling_slug'] as String? ?? config['slug'] as String?;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('PREVIO', style: TextStyle(fontSize: 8, color: Color(0xFF9CA3AF))),
          const SizedBox(height: 4),
          _flowBox(_flowName(slug), _windowLabel(config), const Color(0xFF15803D), const Color(0xFFDCFCE7)),
        ]),
        const SizedBox(width: 12),
        _arrowH(),
        const SizedBox(width: 12),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('AHORA', style: TextStyle(fontSize: 8, color: Color(0xFF9CA3AF))),
          const SizedBox(height: 4),
          _flowBox(currentFlowName, 'puede iniciar', catColor, catColor.withValues(alpha: 0.08)),
        ]),
      ],
    );
  }

  Widget _noActiveSibling() {
    final slug = config['flow_slug'] as String? ?? config['sibling_slug'] as String? ?? config['slug'] as String?;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('NO DEBE ESTAR ACTIVO', style: TextStyle(fontSize: 8, color: Color(0xFF9CA3AF))),
          const SizedBox(height: 4),
          _flowBox(_flowName(slug), 'bloquearía', const Color(0xFFEF4444), const Color(0xFFFEE2E2)),
        ]),
        const SizedBox(width: 12),
        _xMark('conflicto'),
        const SizedBox(width: 12),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('ESTE FLOW', style: TextStyle(fontSize: 8, color: Color(0xFF9CA3AF))),
          const SizedBox(height: 4),
          _flowBox(currentFlowName, 'no puede iniciar', catColor, catColor.withValues(alpha: 0.08)),
        ]),
      ],
    );
  }

  Widget _allChildrenCompleted() {
    final parentSlug = config['parent_flow_slug'] as String?;
    final countKey = config['count_field_key'] as String?;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _flowBox(_flowName(parentSlug), countKey != null ? '$countKey esperados' : 'flow padre',
            catColor, catColor.withValues(alpha: 0.08)),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _miniBox('✓', const Color(0xFF15803D),
                icon: Icon(Icons.check, size: 14, color: Color(0xFF15803D))),
            const SizedBox(width: 4),
            _miniBox('✓', const Color(0xFF15803D),
                icon: Icon(Icons.check, size: 14, color: Color(0xFF15803D))),
            const SizedBox(width: 4),
            _miniBox('⧗', const Color(0xFF9CA3AF)),
            const SizedBox(width: 4),
            _miniBox('⧗', const Color(0xFF9CA3AF)),
          ],
        ),
      ],
    );
  }

  Widget _requiresParent() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _flowBox('flow padre', 'abre este flow', catColor, catColor.withValues(alpha: 0.08), dashed: true),
          Icon(Icons.arrow_downward, color: catColor, size: 20),
          _flowBox(currentFlowName, 'solo como hijo', catColor, catColor.withValues(alpha: 0.04), dashed: true),
        ],
      );

  Widget _operatorRoleIn() {
    final rawIds = config['role_ids'];
    final List<String> roleIds;
    if (rawIds is List) {
      roleIds = List<String>.from(rawIds);
    } else if (rawIds is String && rawIds.isNotEmpty) {
      roleIds = [rawIds];
    } else {
      roleIds = [];
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _operatorCircle(),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: roleIds.isEmpty
              ? [_pill('rol A', catColor), _pill('rol B', catColor)]
              : roleIds.map((id) {
                  final r = roles.where((r) => r['id'] == id).firstOrNull;
                  return _pill(r?['label'] as String? ?? id, catColor);
                }).toList(),
        ),
      ],
    );
  }

  Widget _requiresActiveAssignment() {
    final catSlug = config['catalog_id'] as String? ?? config['catalog_slug'] as String?;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _operatorCircle(),
        const SizedBox(width: 12),
        _arrowH(),
        const SizedBox(width: 12),
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            color: catColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: catColor),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('📋', style: TextStyle(fontSize: 24)),
              Text(catSlug ?? 'catálogo',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: catColor),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fieldUniqueInWindow() {
    final fieldKey = config['field_key'] as String? ?? 'campo';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _miniBox('A', catColor),
            const SizedBox(width: 4),
            _miniBox('B', const Color(0xFF9CA3AF)),
            const SizedBox(width: 4),
            _miniBox('A', const Color(0xFFEF4444)),
          ],
        ),
        const SizedBox(height: 6),
        Text('duplicado: $fieldKey',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFEF4444))),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pill(_windowLabel(config), catColor),
            const SizedBox(width: 6),
            _pill(_scopeLabel(config['scope'] as String?), catColor),
          ],
        ),
      ],
    );
  }

  Widget _timeWindow() {
    final start = config['start'] as String? ?? config['start_time'] as String? ?? '00:00';
    final end = config['end'] as String? ?? config['end_time'] as String? ?? '23:59';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('🕐', style: TextStyle(fontSize: 24)),
        const SizedBox(height: 6),
        SizedBox(
          width: 240,
          height: 20,
          child: CustomPaint(
            painter: _TimeWindowPainter(
              startFraction: _timeFraction(start),
              endFraction: _timeFraction(end),
              color: catColor,
            ),
          ),
        ),
        SizedBox(
          width: 240,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('00:00', style: TextStyle(fontSize: 9, color: Color(0xFF9CA3AF))),
              Text('23:59', style: TextStyle(fontSize: 9, color: Color(0xFF9CA3AF))),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pill(start, catColor),
            const SizedBox(width: 6),
            Text('→', style: TextStyle(color: Color(0xFF9CA3AF))),
            const SizedBox(width: 6),
            _pill(end, catColor),
          ],
        ),
      ],
    );
  }

  double _timeFraction(String time) {
    final parts = time.split(':');
    if (parts.length < 2) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return (h * 60 + m) / 1440;
  }
}

class _DiagLinePainter extends CustomPainter {
  _DiagLinePainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, 0),
      Paint()..color = color..strokeWidth = 2,
    );
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TimeWindowPainter extends CustomPainter {
  _TimeWindowPainter({required this.startFraction, required this.endFraction, required this.color});
  final double startFraction;
  final double endFraction;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    // Background line
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()..color = const Color(0xFFE5E7EB)..strokeWidth = 3,
    );
    // Ticks
    canvas.drawLine(Offset(0, 2), Offset(0, size.height - 2),
        Paint()..color = const Color(0xFFD1D5DB)..strokeWidth = 1);
    canvas.drawLine(Offset(size.width, 2), Offset(size.width, size.height - 2),
        Paint()..color = const Color(0xFFD1D5DB)..strokeWidth = 1);
    // Allowed zone
    final left = size.width * startFraction;
    final right = size.width * endFraction;
    final rect = Rect.fromLTRB(left, 0, right, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = color.withValues(alpha: 0.3),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = color..strokeWidth = 1..style = PaintingStyle.stroke,
    );
  }
  @override
  bool shouldRepaint(_TimeWindowPainter old) =>
      old.startFraction != startFraction || old.endFraction != endFraction || old.color != color;
}

class _WindowTimelinePainter extends CustomPainter {
  _WindowTimelinePainter({required this.catColor, this.windowMode = 'day'});
  final Color catColor;
  final String windowMode;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    // Background line
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY),
        Paint()..color = const Color(0xFFE5E7EB)..strokeWidth = 2);
    // Ticks
    canvas.drawLine(Offset(0, midY - 4), Offset(0, midY + 4),
        Paint()..color = const Color(0xFFD1D5DB)..strokeWidth = 1);
    canvas.drawLine(Offset(size.width, midY - 4), Offset(size.width, midY + 4),
        Paint()..color = const Color(0xFFD1D5DB)..strokeWidth = 1);
    // Window rect — wider for shift
    final wLeft = windowMode == 'shift' ? size.width * 0.10 : size.width * 0.15;
    final wRight = windowMode == 'shift' ? size.width * 0.80 : size.width * 0.75;
    final wRect = Rect.fromLTRB(wLeft, midY - 10, wRight, midY + 10);
    canvas.drawRRect(RRect.fromRectAndRadius(wRect, const Radius.circular(3)),
        Paint()..color = catColor.withValues(alpha: 0.2));
    canvas.drawRRect(RRect.fromRectAndRadius(wRect, const Radius.circular(3)),
        Paint()..color = catColor..strokeWidth = 1.5..style = PaintingStyle.stroke);
    // Execution point ✓ at 45%
    final exX = size.width * 0.45;
    canvas.drawCircle(Offset(exX, midY), 7, Paint()..color = catColor);
    final tp = TextPainter(
      text: const TextSpan(text: '✓', style: TextStyle(fontSize: 9, color: Colors.white)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(exX - tp.width / 2, midY - tp.height / 2));
    // X blocked at 85%
    final bx = size.width * 0.85;
    canvas.drawCircle(Offset(bx, midY), 7, Paint()..color = const Color(0xFFFEE2E2));
    canvas.drawCircle(Offset(bx, midY), 7,
        Paint()..color = const Color(0xFFEF4444)..strokeWidth = 1..style = PaintingStyle.stroke);
    final xp = TextPainter(
      text: const TextSpan(text: '✕',
          style: TextStyle(fontSize: 8, color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    xp.paint(canvas, Offset(bx - xp.width / 2, midY - xp.height / 2));
  }

  @override
  bool shouldRepaint(_WindowTimelinePainter old) =>
      old.catColor != catColor || old.windowMode != windowMode;
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
