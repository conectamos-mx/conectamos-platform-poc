import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_button.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum _BroadcastResultType { success, warning, error }

// ── Variables estándar de texto libre ─────────────────────────────────────────

const _kFreeVars = [
  (key: '{nombre}',   label: 'nombre'),
  (key: '{telefono}', label: 'teléfono'),
  (key: '{flujo}',    label: 'flujo'),
  (key: '{hora}',     label: 'hora'),
  (key: '{dia}',      label: 'día'),
  (key: '{fecha}',    label: 'fecha'),
  (key: '{tenant}',   label: 'tenant'),
];

String _resolveFreeText(
    String text, Map<String, dynamic>? op, String tenantName) {
  if (text.isEmpty) return text;
  final now = DateTime.now();
  const days = [
    'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'
  ];
  String flowName = 'Sin flujo';
  if (op != null) {
    final flows = op['flows'];
    if (flows is List && flows.isNotEmpty) {
      final first = flows.first;
      flowName = first is Map
          ? (first['name']?.toString() ?? 'Sin flujo')
          : first.toString();
    }
  }
  return text
      .replaceAll(
          '{nombre}',
          op?['display_name']?.toString() ??
              op?['name']?.toString() ??
              'Operador')
      .replaceAll('{telefono}', op?['phone']?.toString() ?? '')
      .replaceAll('{flujo}', flowName)
      .replaceAll(
          '{hora}',
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}')
      .replaceAll('{dia}', days[now.weekday - 1])
      .replaceAll(
          '{fecha}',
          '${now.day.toString().padLeft(2, '0')}/'
          '${now.month.toString().padLeft(2, '0')}/'
          '${now.year}')
      .replaceAll('{tenant}', tenantName);
}

// ── Providers ─────────────────────────────────────────────────────────────────

final _bcastOperatorsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, tenantId) async {
    if (tenantId.isEmpty) return [];
    final res = await ApiClient.instance.get('/operators');
    final data = res.data;
    final List raw = data is List ? data : [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  },
);

final _bcastTemplatesProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, tenantId) async {
    if (tenantId.isEmpty) return [];
    final res = await ApiClient.instance.get(
      '/templates',
      queryParameters: {'status': 'APPROVED'},
    );
    final data = res.data;
    final List raw =
        data is List ? data : (data['items'] ?? data['templates'] ?? []) as List;
    return raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((t) =>
            (t['status']?.toString().toUpperCase() ?? '') == 'APPROVED')
        .toList();
  },
);

/// Devuelve el wa_waba_id configurado para el tenant activo.
final _bcastTenantCredsProvider =
    FutureProvider.autoDispose.family<String?, String>(
  (ref, tenantId) async {
    if (tenantId.isEmpty) return null;
    try {
      final res = await ApiClient.instance.get('/tenants/$tenantId');
      return (res.data as Map?)?['wa_waba_id']?.toString();
    } catch (_) {
      return null;
    }
  },
);

final _bcastHistoryProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, tenantId) async {
    if (tenantId.isEmpty) return [];
    try {
      final res = await ApiClient.instance.get('/broadcasts');
      final data = res.data;
      final List raw = data is List ? data : (data['items'] ?? []) as List;
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  },
);

// ── Helper: resuelve preview de plantilla ─────────────────────────────────────

String _resolvePreview(Map<String, dynamic> template) {
  const examples = <String, String>{
    'nombre_operador':   'José Miguel',
    'telefono_operador': '5215559537449',
    'nombre_tenant':     'TMR-Prixz',
    'fecha_hoy':         '14/04/2026',
    'hora_actual':       '10:30 AM',
  };
  String preview = template['body_text']?.toString() ?? '';
  final vars = template['variables'];
  if (vars is List) {
    for (final v in vars) {
      if (v is! Map) continue;
      final slot = v['slot'] as int? ?? 0;
      final type = v['type'] as String? ?? 'free';
      final key  = v['key']  as String? ?? '';
      final val  = type == 'system'
          ? (examples[key] ?? '[$key]')
          : (key.isNotEmpty ? '[$key]' : '{{$slot}}');
      if (slot > 0) preview = preview.replaceAll('{{$slot}}', val);
    }
  }
  return preview;
}

List<String> _resolveTemplateVariables(Map<String, dynamic> template) {
  const examples = <String, String>{
    'nombre_operador':   'José Miguel',
    'telefono_operador': '5215559537449',
    'nombre_tenant':     'TMR-Prixz',
    'fecha_hoy':         '14/04/2026',
    'hora_actual':       '10:30 AM',
  };
  final vars = template['variables'];
  if (vars is! List || vars.isEmpty) return [];
  final sorted = vars
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList()
    ..sort((a, b) =>
        ((a['slot'] as int?) ?? 0).compareTo((b['slot'] as int?) ?? 0));
  return sorted.map((v) {
    final type = v['type'] as String? ?? 'free';
    final key  = v['key']  as String? ?? '';
    if (type == 'system') return examples[key] ?? '[$key]';
    return key.isNotEmpty ? '[$key]' : '[variable]';
  }).toList();
}

// ── Pantalla ──────────────────────────────────────────────────────────────────

class BroadcastScreen extends ConsumerStatefulWidget {
  const BroadcastScreen({super.key, this.channelId, this.channelType});

  /// Cuando se abre como modal, estos parámetros reemplazan los query params.
  final String? channelId;
  final String? channelType;

  @override
  ConsumerState<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends ConsumerState<BroadcastScreen> {
  // Canal activo (leído de query params en build)
  String _channelId   = '';
  String _channelType = 'whatsapp';

  // Mensaje
  bool _useTemplate = false;
  final _msgCtrl = TextEditingController();
  String? _selectedTemplateId;

  // Filtros de segmento
  final _selectedStatuses = <String>{'active'};
  final _selectedFlows = <String>{};

  // Selección explícita de operadores. {} = todos los filtrados seleccionados.
  Set<String> _selectedOperatorIds = {};

  // Estado envío
  bool _sending = false;
  bool _confirming = false;
  String? _result;
  _BroadcastResultType _resultType = _BroadcastResultType.success;
  List<Map<String, dynamic>> _resultErrors = [];

  // Historial
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    // FIX 1: listener para actualizar la vista previa en tiempo real
    _msgCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filterOperators(
      List<Map<String, dynamic>> operators) {
    return operators.where((op) {
      final status = op['status']?.toString() ?? 'active';
      if (_selectedStatuses.isNotEmpty &&
          !_selectedStatuses.contains(status)) {
        return false;
      }
      if (_selectedFlows.isNotEmpty) {
        final flows = op['flows'];
        final opFlows = flows is List
            ? flows.map((f) => f.toString()).toSet()
            : <String>{};
        if (opFlows.intersection(_selectedFlows).isEmpty) return false;
      }
      return true;
    }).toList();
  }

  static bool _windowOpen(Map<String, dynamic> op) {
    final raw = op['last_inbound_at'] as String?;
    if (raw == null) return false;
    final dt = DateTime.tryParse(raw);
    if (dt == null) return false;
    return DateTime.now().difference(dt).inHours < 24;
  }

  Future<void> _sendBroadcast(
    List<Map<String, dynamic>> filteredOps,
    Set<String> effectiveSelectedIds,
    Set<String> allFilteredIds,
    List<Map<String, dynamic>> templates,
  ) async {
    if (_channelId.isEmpty) {
      setState(() {
        _result     = 'No hay canal activo. Regresa y selecciona un canal.';
        _resultType = _BroadcastResultType.error;
      });
      return;
    }

    setState(() { _sending = true; _result = null; });
    try {
      final userId =
          Supabase.instance.client.auth.currentUser?.id ?? '';

      Map<String, dynamic>? selectedTemplate;
      if (_useTemplate && _selectedTemplateId != null) {
        selectedTemplate = templates.firstWhere(
          (t) => t['id']?.toString() == _selectedTemplateId,
          orElse: () => {},
        );
      }

      // FIX 2: usar operator_ids cuando la selección es parcial
      final isPartialSelection =
          effectiveSelectedIds.length < allFilteredIds.length;

      // BUG-B01: resolver variables antes de enviar.
      // TODO(backend): idealmente el backend resuelve {nombre}/{flujo}/etc.
      // por destinatario. Mientras tanto, se usan los datos del primer operador
      // seleccionado como aproximación para todas las variables personales.
      String resolvedText = _msgCtrl.text.trim();
      if (!_useTemplate && resolvedText.isNotEmpty) {
        final firstOp = effectiveSelectedIds.isNotEmpty
            ? filteredOps.firstWhere(
                (op) => effectiveSelectedIds.contains(op['id']?.toString()),
                orElse: () => filteredOps.isNotEmpty ? filteredOps.first : {},
              )
            : filteredOps.isNotEmpty
                ? filteredOps.first
                : null;
        if (firstOp != null && firstOp.isNotEmpty) {
          final tenantDisplayName = ref.read(activeTenantDisplayProvider);
          resolvedText = _resolveFreeText(resolvedText, firstOp, tenantDisplayName);
        }
      }

      final body = <String, dynamic>{
        'sent_by_user_id':    userId,
        'channel_id':         _channelId,
        'message_text':       _useTemplate ? null : resolvedText,
        'template_id':        _useTemplate ? _selectedTemplateId : null,
        'template_variables': _useTemplate && selectedTemplate != null
            ? _resolveTemplateVariables(selectedTemplate)
            : <String>[],
      };

      if (isPartialSelection) {
        body['operator_ids'] = effectiveSelectedIds.toList();
      } else {
        body['segment_filters'] = {
          'status': _selectedStatuses.toList(),
          'flows':  _selectedFlows.toList(),
        };
      }

      final res = await ApiClient.instance.post(
        '/broadcasts',
        data: body,
        options: Options(
            validateStatus: (s) => s != null && s >= 200 && s < 300),
      );

      final d           = res.data is Map ? res.data as Map : {};
      final sentCount   = (d['sent_count']      ?? d['sent']   ?? 0) as num;
      final failedCount = (d['failed_count']    ?? d['failed'] ?? 0) as num;
      final total       = (d['recipient_count'] ?? d['total']  ??
          effectiveSelectedIds.length) as num;

      final errorsRaw = d['errors'];
      final errors = errorsRaw is List
          ? errorsRaw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];

      final _BroadcastResultType type;
      final String resultMsg;
      if (sentCount == 0 && failedCount > 0) {
        type      = _BroadcastResultType.error;
        resultMsg = '❌ Envío fallido: $failedCount de $total destinatarios fallaron.';
      } else if (sentCount > 0 && failedCount > 0) {
        type      = _BroadcastResultType.warning;
        resultMsg = '⚠️ Enviado parcialmente: $sentCount enviados, $failedCount fallaron.';
      } else {
        type      = _BroadcastResultType.success;
        resultMsg = '✅ Enviado a $sentCount operadores.';
      }

      if (!mounted) return;
      setState(() {
        _sending      = false;
        _confirming   = false;
        _result       = resultMsg;
        _resultType   = type;
        _resultErrors = errors;
      });
      ref.invalidate(_bcastHistoryProvider(ref.read(activeTenantIdProvider)));
    } on DioException catch (e) {
      if (!mounted) return;
      final raw = e.response?.data is Map
          ? e.response!.data['detail']?.toString()
          : e.response?.data?.toString();
      setState(() {
        _sending      = false;
        _confirming   = false;
        _result       = _parseErrorMessage(raw ?? e.message ?? '');
        _resultType   = _BroadcastResultType.error;
        _resultErrors = [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending      = false;
        _confirming   = false;
        _result       = _parseErrorMessage(e.toString());
        _resultType   = _BroadcastResultType.error;
        _resultErrors = [];
      });
    }
  }

  String _parseErrorMessage(dynamic error) {
    try {
      final detail = error.toString();
      if (detail.contains('131037') || detail.contains('display name')) {
        return 'El número aún no tiene el nombre de perfil aprobado por Meta. '
            'Por favor espera la aprobación antes de iniciar nuevas conversaciones.';
      }
      if (detail.contains('131026') || detail.contains('not in whitelist')) {
        return 'Este número no está registrado como destinatario de prueba.';
      }
      return 'Error al enviar el mensaje. Intenta de nuevo.';
    } catch (_) {
      return 'Error al enviar el mensaje. Intenta de nuevo.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isModal = widget.channelId != null;
    if (isModal) {
      _channelId   = widget.channelId!;
      _channelType = widget.channelType ?? 'whatsapp';
    } else {
      final params = GoRouterState.of(context).uri.queryParameters;
      _channelId   = params['channel_id']   ?? '';
      _channelType = params['channel_type'] ?? 'whatsapp';
    }

    final isTelegram = _channelType == 'telegram';
    if (isTelegram && _useTemplate) _useTemplate = false;

    final tenantId       = ref.watch(activeTenantIdProvider);
    final tenantName     = ref.watch(activeTenantDisplayProvider);
    final operatorsAsync = ref.watch(_bcastOperatorsProvider(tenantId));
    final templatesAsync = ref.watch(_bcastTemplatesProvider(tenantId));
    final credsAsync     = ref.watch(_bcastTenantCredsProvider(tenantId));

    final operators    = operatorsAsync.valueOrNull ?? [];
    final templatesRaw = templatesAsync.valueOrNull ?? [];
    final activeWabaId = credsAsync.valueOrNull;

    final templatesHaveWabaId =
        templatesRaw.any((t) => t.containsKey('waba_id'));
    final templates =
        (templatesHaveWabaId && activeWabaId != null && activeWabaId.isNotEmpty)
            ? templatesRaw
                .where((t) => t['waba_id']?.toString() == activeWabaId)
                .toList()
            : templatesRaw;
    final showWabaWarning = templatesRaw.isNotEmpty && !templatesHaveWabaId;

    final filtered = _filterOperators(operators);

    // FIX 2: IDs de los filtrados + selección efectiva
    final filteredIds = filtered
        .map((op) => op['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    // {} significa "todos seleccionados"; de lo contrario intersección.
    final effectiveSelectedIds = _selectedOperatorIds.isEmpty
        ? filteredIds
        : _selectedOperatorIds.intersection(filteredIds);

    final selectedOperators = filtered
        .where((op) =>
            effectiveSelectedIds.contains(op['id']?.toString() ?? ''))
        .toList();

    // closedWindowCount: operadores seleccionados con ventana cerrada (WA only)
    // null last_inbound_at → _windowOpen retorna false (ventana cerrada)
    final closedWindowCount = isTelegram
        ? 0
        : selectedOperators.where((op) => !_windowOpen(op)).length;

    // Flujos únicos en todos los operadores
    final allFlows   = <String>{};
    final flowLabels = <String, String>{};
    for (final op in operators) {
      final f = op['flows'];
      if (f is List) {
        for (final fl in f) {
          final key = fl.toString();
          allFlows.add(key);
          if (fl is Map) {
            final workerName = fl['worker_name'] as String?;
            final name = fl['name'] as String?;
            if (name != null) {
              flowLabels[key] =
                  workerName != null ? '$workerName · $name' : name;
            }
          }
        }
      }
    }

    // Bloqueo: texto libre + WA + al menos un seleccionado con ventana cerrada
    final closedWindowBlock =
        !_useTemplate && !isTelegram && closedWindowCount > 0;
    final canSend = _useTemplate
        ? _selectedTemplateId != null
        : !closedWindowBlock && _msgCtrl.text.trim().isNotEmpty;

    // FIX 3: primer operador seleccionado para preview de variables
    final firstSelectedOp =
        selectedOperators.isNotEmpty ? selectedOperators.first : null;

    return Material(
      color: Colors.white,
      borderRadius: isModal ? BorderRadius.circular(16) : BorderRadius.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
      children: [
        _BroadcastHeader(
          onClose: isModal
              ? () => Navigator.of(context).pop()
              : () => context.go('/conversations'),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 760;

              final formWidget = _FormColumn(
                useTemplate:       _useTemplate,
                msgCtrl:           _msgCtrl,
                templates:         templates,
                selectedTemplateId: _selectedTemplateId,
                closedWindowCount: closedWindowCount,
                closedWindowBlock: closedWindowBlock,
                selectedCount:     effectiveSelectedIds.length,
                selectedStatuses:  _selectedStatuses,
                selectedFlows:     _selectedFlows,
                allFlows:          allFlows,
                flowLabels:        flowLabels,
                canSend:           canSend,
                sending:           _sending,
                confirming:        _confirming,
                result:            _result,
                resultType:        _resultType,
                resultErrors:      _resultErrors,
                showWabaWarning:   showWabaWarning,
                channelId:         _channelId,
                channelType:       _channelType,
                onToggleMode: (v) => setState(() {
                  _useTemplate        = v;
                  _selectedTemplateId = null;
                  _result             = null;
                }),
                onSelectTemplate: (id) =>
                    setState(() { _selectedTemplateId = id; _result = null; }),
                onToggleStatus: (s) => setState(() {
                  if (_selectedStatuses.contains(s)) {
                    _selectedStatuses.remove(s);
                  } else {
                    _selectedStatuses.add(s);
                  }
                  _result = null;
                }),
                onToggleFlow: (f) => setState(() {
                  if (_selectedFlows.contains(f)) {
                    _selectedFlows.remove(f);
                  } else {
                    _selectedFlows.add(f);
                  }
                  _result = null;
                }),
                onInsertVariable: (variable) {
                  final text   = _msgCtrl.text;
                  final sel    = _msgCtrl.selection;
                  final offset = sel.isValid ? sel.baseOffset : text.length;
                  final newText =
                      text.substring(0, offset) + variable + text.substring(offset);
                  _msgCtrl.value = TextEditingValue(
                    text:      newText,
                    selection: TextSelection.collapsed(
                        offset: offset + variable.length),
                  );
                },
                onSend: (!canSend ||
                        effectiveSelectedIds.isEmpty ||
                        _sending ||
                        !hasPermission(ref, 'broadcasts', 'send'))
                    ? null
                    : () => setState(() { _confirming = true; }),
                onConfirm: () => _sendBroadcast(
                    filtered, effectiveSelectedIds, filteredIds, templates),
                onCancelConfirm: () =>
                    setState(() => _confirming = false),
              );

              final selectedTemplate =
                  _useTemplate && _selectedTemplateId != null
                      ? templates
                          .cast<Map<String, dynamic>?>()
                          .firstWhere(
                            (t) =>
                                t!['id']?.toString() == _selectedTemplateId,
                            orElse: () => null)
                      : null;

              final previewWidget = _PreviewColumn(
                useTemplate:          _useTemplate,
                msgCtrl:              _msgCtrl,
                selectedTemplate:     selectedTemplate,
                filtered:             filtered,
                effectiveSelectedIds: effectiveSelectedIds,
                channelType:          _channelType,
                firstSelectedOp:      firstSelectedOp,
                tenantName:           tenantName,
                onToggleOperator: (id) => setState(() {
                  if (_selectedOperatorIds.isEmpty) {
                    // Todos estaban seleccionados — deseleccionar este
                    _selectedOperatorIds = Set.from(filteredIds)..remove(id);
                  } else if (_selectedOperatorIds.contains(id)) {
                    _selectedOperatorIds =
                        Set.from(_selectedOperatorIds)..remove(id);
                    // Si quedó igual a todos los filtrados, resetear a vacío
                    if (_selectedOperatorIds.containsAll(filteredIds) &&
                        filteredIds.containsAll(_selectedOperatorIds)) {
                      _selectedOperatorIds = {};
                    }
                  } else {
                    _selectedOperatorIds =
                        Set.from(_selectedOperatorIds)..add(id);
                    if (_selectedOperatorIds.containsAll(filteredIds) &&
                        filteredIds.containsAll(_selectedOperatorIds)) {
                      _selectedOperatorIds = {};
                    }
                  }
                  _result = null;
                }),
              );

              if (wide) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: formWidget),
                            const SizedBox(width: 20),
                            Expanded(flex: 2, child: previewWidget),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _HistorySection(
                        tenantId: tenantId,
                        show:     _showHistory,
                        onToggle: () =>
                            setState(() => _showHistory = !_showHistory),
                      ),
                    ],
                  ),
                );
              } else {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      formWidget,
                      const SizedBox(height: 20),
                      previewWidget,
                      const SizedBox(height: 24),
                      _HistorySection(
                        tenantId: tenantId,
                        show:     _showHistory,
                        onToggle: () =>
                            setState(() => _showHistory = !_showHistory),
                      ),
                    ],
                  ),
                );
              }
            },
          ),
        ),
      ],
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _BroadcastHeader extends StatelessWidget {
  const _BroadcastHeader({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.ctSurface,
        border: Border(bottom: BorderSide(color: AppColors.ctBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Nuevo broadcast',
                  style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist'),
                ),
                SizedBox(height: 1),
                Text(
                  'Envía un mensaje masivo a tus operadores',
                  style: AppTextStyles.topbarSubtitle,
                ),
              ],
            ),
          ),
          _CloseButton(onTap: onClose),
        ],
      ),
    );
  }
}

class _CloseButton extends StatefulWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.ctSurface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(
            Icons.close_rounded,
            size: 18,
            color: AppColors.ctText2,
          ),
        ),
      ),
    );
  }
}

// ── Columna izquierda: formulario ─────────────────────────────────────────────

class _FormColumn extends StatelessWidget {
  const _FormColumn({
    required this.useTemplate,
    required this.msgCtrl,
    required this.templates,
    required this.selectedTemplateId,
    required this.closedWindowCount,
    required this.closedWindowBlock,
    required this.selectedCount,
    required this.selectedStatuses,
    required this.selectedFlows,
    required this.allFlows,
    required this.flowLabels,
    required this.canSend,
    required this.sending,
    required this.confirming,
    required this.result,
    required this.resultType,
    required this.resultErrors,
    required this.showWabaWarning,
    required this.channelId,
    required this.channelType,
    required this.onToggleMode,
    required this.onSelectTemplate,
    required this.onToggleStatus,
    required this.onToggleFlow,
    required this.onInsertVariable,
    required this.onSend,
    required this.onConfirm,
    required this.onCancelConfirm,
  });

  final bool useTemplate;
  final TextEditingController msgCtrl;
  final List<Map<String, dynamic>> templates;
  final String? selectedTemplateId;
  final int closedWindowCount;
  final bool closedWindowBlock;
  final int selectedCount;
  final Set<String> selectedStatuses;
  final Set<String> selectedFlows;
  final Set<String> allFlows;
  final Map<String, String> flowLabels;
  final bool canSend;
  final bool sending;
  final bool confirming;
  final String? result;
  final _BroadcastResultType resultType;
  final List<Map<String, dynamic>> resultErrors;
  final bool showWabaWarning;
  final String channelId;
  final String channelType;
  final ValueChanged<bool> onToggleMode;
  final ValueChanged<String?> onSelectTemplate;
  final ValueChanged<String> onToggleStatus;
  final ValueChanged<String> onToggleFlow;
  final ValueChanged<String> onInsertVariable;
  final VoidCallback? onSend;
  final VoidCallback onConfirm;
  final VoidCallback onCancelConfirm;

  @override
  Widget build(BuildContext context) {
    final isTelegram = channelType == 'telegram';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Canal activo (read-only) ───────────────────────────────────────
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: channelId.isEmpty
                ? AppColors.ctWarnBg
                : (isTelegram
                    ? const Color(0xFFEDE9FE)
                    : AppColors.ctOkBg),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: channelId.isEmpty
                  ? const Color(0xFFFCD34D)
                  : (isTelegram
                      ? const Color(0xFFA78BFA)
                      : AppColors.ctTeal),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                channelId.isEmpty
                    ? Icons.warning_amber_rounded
                    : (isTelegram
                        ? Icons.send_rounded
                        : Icons.chat_bubble_outline_rounded),
                size: 14,
                color: channelId.isEmpty
                    ? AppColors.ctWarnText
                    : (isTelegram
                        ? const Color(0xFF7C3AED)
                        : AppColors.ctOkText),
              ),
              const SizedBox(width: 8),
              Text(
                channelId.isEmpty
                    ? 'No hay canal seleccionado'
                    : 'Enviando a canal ${isTelegram ? 'Telegram' : 'WhatsApp'}',
                style: AppTextStyles.bodySmall.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: channelId.isEmpty ? AppColors.ctWarnText : (isTelegram ? const Color(0xFF7C3AED) : AppColors.ctOkText)),
              ),
            ],
          ),
        ),

        // ── Sección Mensaje ────────────────────────────────────────────────
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(label: 'Mensaje'),
              const SizedBox(height: 14),

              if (!isTelegram) ...[
                _ModeToggle(useTemplate: useTemplate, onChanged: onToggleMode),
                const SizedBox(height: 16),
              ],

              if (!useTemplate || isTelegram) ...[
                _BuildTextField(ctrl: msgCtrl),
                // FIX 3: chips de variables estándar
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _kFreeVars.map((v) => _VarChip(
                    label: v.label,
                    onTap: () => onInsertVariable(v.key),
                  )).toList(),
                ),
              ] else ...[
                if (showWabaWarning) ...[
                  _WarningBanner(
                    message: '⚠️ Verifica que tus credenciales de Meta '
                        'estén actualizadas antes de enviar.',
                  ),
                  const SizedBox(height: 10),
                ],
                if (templates.isEmpty)
                  Text(
                    'No hay plantillas APPROVED disponibles.',
                    style: AppTextStyles.navItem,
                  )
                else
                  _TemplateDropdown(
                    templates:  templates,
                    selectedId: selectedTemplateId,
                    onChanged:  onSelectTemplate,
                  ),
              ],

              // Banner advertencia no bloqueante: solo texto libre + WA
              if (!useTemplate && closedWindowCount > 0 && !isTelegram) ...[
                const SizedBox(height: 10),
                _WarningBanner(
                  message: '$closedWindowCount operador'
                      '${closedWindowCount > 1 ? 'es tienen' : ' tiene'}'
                      ' la ventana cerrada. Deselecciónalos o cambia a'
                      ' Plantilla para continuar.',
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Sección Destinatarios ──────────────────────────────────────────
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(label: '¿A quién enviar?'),
              const SizedBox(height: 14),

              const _Label(text: 'Estado del operador'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FilterChip(
                    label:    'Activos',
                    value:    'active',
                    selected: selectedStatuses.contains('active'),
                    onTap:    onToggleStatus,
                  ),
                  _FilterChip(
                    label:    'En incidencia',
                    value:    'incident',
                    selected: selectedStatuses.contains('incident'),
                    onTap:    onToggleStatus,
                  ),
                  _FilterChip(
                    label:    'Inactivos',
                    value:    'inactive',
                    selected: selectedStatuses.contains('inactive'),
                    onTap:    onToggleStatus,
                  ),
                ],
              ),

              if (allFlows.isNotEmpty) ...[
                const SizedBox(height: 16),
                const _Label(text: 'Flujo asignado'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: allFlows.map((f) {
                    final lbl = flowLabels[f] ?? f;
                    final sel = selectedFlows.contains(f);
                    return sel
                        ? _FlowCard(
                            label: lbl, value: f, onRemove: onToggleFlow)
                        : _AddFlowChip(
                            label: lbl, value: f, onTap: onToggleFlow);
                  }).toList(),
                ),
              ],

              const SizedBox(height: 16),

              // Contador — muestra seleccionados, no filtrados totales
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: selectedCount > 0
                      ? AppColors.ctTealLight
                      : AppColors.ctSurface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.group_rounded,
                      size: 14,
                      color: selectedCount > 0
                          ? AppColors.ctTeal
                          : AppColors.ctText3,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$selectedCount operador'
                      '${selectedCount != 1 ? 'es' : ''} seleccionado'
                      '${selectedCount != 1 ? 's' : ''}',
                      style: AppTextStyles.tenantName.copyWith(
                        color: selectedCount > 0
                            ? AppColors.ctTeal
                            : AppColors.ctText3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Confirmar / Enviar ─────────────────────────────────────────────
        if (confirming) ...[
          _ConfirmBox(
            count:     selectedCount,
            onConfirm: onConfirm,
            onCancel:  onCancelConfirm,
            sending:   sending,
          ),
          const SizedBox(height: 12),
        ] else ...[
          _SendButton(
            enabled: canSend && selectedCount > 0 && !sending,
            loading: sending,
            count:   selectedCount,
            onTap:   onSend,
          ),
          const SizedBox(height: 12),
        ],

        if (result != null)
          _ResultBanner(
            message: result!,
            type:    resultType,
            errors:  resultErrors,
          ),
      ],
    );
  }
}

// ── Columna derecha: preview + lista destinatarios ────────────────────────────

class _PreviewColumn extends StatelessWidget {
  const _PreviewColumn({
    required this.useTemplate,
    required this.msgCtrl,
    required this.selectedTemplate,
    required this.filtered,
    required this.effectiveSelectedIds,
    required this.channelType,
    required this.firstSelectedOp,
    required this.tenantName,
    required this.onToggleOperator,
  });

  final bool useTemplate;
  final TextEditingController msgCtrl;
  final Map<String, dynamic>? selectedTemplate;
  final List<Map<String, dynamic>> filtered;
  final Set<String> effectiveSelectedIds;
  final String channelType;
  final Map<String, dynamic>? firstSelectedOp;
  final String tenantName;
  final ValueChanged<String> onToggleOperator;

  @override
  Widget build(BuildContext context) {
    // FIX 1: previewText se resuelve con variables del primer destinatario
    String previewText = '';
    if (useTemplate && selectedTemplate != null) {
      previewText = _resolvePreview(selectedTemplate!);
    } else if (!useTemplate) {
      // FIX 3: resolver variables estándar
      previewText = _resolveFreeText(msgCtrl.text, firstSelectedOp, tenantName);
    }

    // FIX 1: título dinámico
    final firstName = firstSelectedOp?['display_name']?.toString() ??
        firstSelectedOp?['name']?.toString();
    final previewTitle = firstName != null
        ? 'Vista previa · $firstName'
        : 'Vista previa del mensaje';

    final isWa = channelType == 'whatsapp';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Preview burbuja
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(label: previewTitle),
              const SizedBox(height: 12),
              if (previewText.isEmpty)
                Text(
                  'El mensaje aparecerá aquí...',
                  style: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: AppColors.ctText3, fontStyle: FontStyle.italic),
                )
              else
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 320),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFD9FDD3),
                      borderRadius: BorderRadius.only(
                        topLeft:     Radius.circular(12),
                        topRight:    Radius.circular(2),
                        bottomLeft:  Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                    ),
                    child: Text(
                      previewText,
                      style: AppTextStyles.body,
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Lista de destinatarios — TODOS, con checkbox
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: _SectionTitle(label: 'Destinatarios'),
                  ),
                  Text(
                    '${effectiveSelectedIds.length}/${filtered.length}',
                    style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700, color: AppColors.ctTeal),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (filtered.isEmpty)
                Text(
                  'Ningún operador coincide con los filtros.',
                  style: AppTextStyles.navItem,
                )
              else
                ...filtered.map((op) {
                  final opId    = op['id']?.toString() ?? '';
                  final name    = op['display_name']?.toString() ??
                      op['name']?.toString() ?? '—';
                  final phone   = op['phone']?.toString() ?? '';
                  final photoUrl = op['profile_picture_url']?.toString();
                  final selected = effectiveSelectedIds.contains(opId);

                  // windowOpen: bool (false = cerrada), solo chip en WA
                  final bool? windowOpen = isWa
                      ? _BroadcastScreenState._windowOpen(op)
                      : null;
                  final isClosed = windowOpen == false;

                  Widget row = Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        _BcastAvatar(name: name, photoUrl: photoUrl),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: AppTextStyles.btnSecondary,
                              ),
                              if (phone.isNotEmpty)
                                Text(
                                  phone,
                                  style: AppTextStyles.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        // Window chip
                        if (windowOpen != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: windowOpen
                                  ? AppColors.ctOkBg
                                  : AppColors.ctRedBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              windowOpen ? 'Abierta' : 'Cerrada',
                              style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600, color: windowOpen ? AppColors.ctOkText : AppColors.ctRedText),
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        // Checkbox
                        if (opId.isNotEmpty)
                          GestureDetector(
                            onTap: () => onToggleOperator(opId),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.ctTeal
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.ctTeal
                                      : AppColors.ctBorder,
                                  width: 1.5,
                                ),
                              ),
                              child: selected
                                  ? const Icon(Icons.check_rounded,
                                      size: 13, color: AppColors.ctNavy)
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  );

                  // FIX 2: opacidad reducida + tooltip para ventana cerrada seleccionada
                  if (isClosed && selected) {
                    row = Tooltip(
                      message: 'Sin ventana de 24h — usa plantilla o deselecciona',
                      preferBelow: false,
                      waitDuration: const Duration(milliseconds: 400),
                      decoration: BoxDecoration(
                        color: AppColors.ctNavy,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      textStyle: AppTextStyles.bodySmall.copyWith(color: Colors.white),
                      child: Opacity(opacity: 0.5, child: row),
                    );
                  }

                  return row;
                }),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Sección historial ─────────────────────────────────────────────────────────

class _HistorySection extends ConsumerWidget {
  const _HistorySection({
    required this.tenantId,
    required this.show,
    required this.onToggle,
  });
  final String tenantId;
  final bool show;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(_bcastHistoryProvider(tenantId));

    return Container(
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Broadcasts anteriores',
                      style: AppTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Icon(
                    show
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: AppColors.ctText2,
                  ),
                ],
              ),
            ),
          ),
          if (show) ...[
            const Divider(height: 1, color: AppColors.ctBorder),
            Padding(
              padding: const EdgeInsets.all(16),
              child: historyAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child:
                        CircularProgressIndicator(color: AppColors.ctTeal),
                  ),
                ),
                error: (e, _) => Text(
                  'Error al cargar historial: $e',
                  style: AppTextStyles.navItem,
                ),
                data: (history) => history.isEmpty
                    ? Text(
                        'No hay broadcasts enviados aún.',
                        style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                      )
                    : Column(
                        children: history
                            .map((b) => _HistoryItem(broadcast: b))
                            .toList(),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  const _HistoryItem({required this.broadcast});
  final Map<String, dynamic> broadcast;

  @override
  Widget build(BuildContext context) {
    final createdAt = broadcast['created_at']?.toString() ?? '';
    DateTime? dt;
    try {
      dt = DateTime.parse(createdAt).toLocal();
    } catch (_) {}
    final dateStr = dt != null
        ? '${dt.day.toString().padLeft(2, '0')}/'
            '${dt.month.toString().padLeft(2, '0')}/'
            '${dt.year} '
            '${dt.hour.toString().padLeft(2, '0')}:'
            '${dt.minute.toString().padLeft(2, '0')}'
        : createdAt;

    final sent    = broadcast['sent']   ?? broadcast['total_sent']   ?? '—';
    final failed  = broadcast['failed'] ?? broadcast['total_failed'] ?? 0;
    final status  = broadcast['status']?.toString() ?? 'sent';
    final msgText = broadcast['message_text']?.toString() ??
        broadcast['template_id']?.toString() ?? '';
    final preview = msgText.length > 60
        ? '${msgText.substring(0, 60)}...'
        : msgText;

    return InkWell(
      onTap: () => showDialog(
        context: context,
        builder: (_) => _BroadcastDetailDialog(broadcast: broadcast),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          border:
              Border(bottom: BorderSide(color: AppColors.ctBorder)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (preview.isNotEmpty)
                    Text(
                      preview,
                      style: AppTextStyles.body,
                    ),
                  const SizedBox(height: 2),
                  Text(
                    dateStr,
                    style: AppTextStyles.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _StatusBadge(status: status),
                const SizedBox(height: 4),
                Text(
                  '$sent enviados · $failed fallaron',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BroadcastDetailDialog extends StatelessWidget {
  const _BroadcastDetailDialog({required this.broadcast});
  final Map<String, dynamic> broadcast;

  @override
  Widget build(BuildContext context) {
    final recipients = broadcast['recipients'];
    final List<Map<String, dynamic>> recipientList = recipients is List
        ? recipients
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()
        : [];
    final msgText = broadcast['message_text']?.toString() ?? '';

    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.ctBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.ctBorder)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Detalle del broadcast',
                      style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist'),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded,
                        size: 18, color: AppColors.ctText2),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (msgText.isNotEmpty) ...[
                      Text(
                        'Mensaje',
                        style: AppTextStyles.bodySmall.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.ctSurface2,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          msgText,
                          style: AppTextStyles.body,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (recipientList.isNotEmpty) ...[
                      Text(
                        'Destinatarios',
                        style: AppTextStyles.bodySmall.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      ...recipientList.map((r) {
                        final name = r['name']?.toString() ??
                            r['phone']?.toString() ?? '—';
                        final rStatus = r['status']?.toString() ?? 'sent';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: AppTextStyles.body,
                                ),
                              ),
                              _StatusBadge(status: rStatus),
                            ],
                          ),
                        );
                      }),
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

// ── Widgets locales ───────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.tenantName,
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.useTemplate, required this.onChanged});
  final bool useTemplate;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.ctSurface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleItem(
            label:  'Texto libre',
            active: !useTemplate,
            onTap:  () => onChanged(false),
          ),
          _ToggleItem(
            label:  'Plantilla',
            active: useTemplate,
            onTap:  () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _ToggleItem extends StatelessWidget {
  const _ToggleItem({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.ctNavy : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: active ? AppColors.ctNavy : AppColors.ctBorder,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.tenantName.copyWith(
            color: active ? AppColors.ctTeal : AppColors.ctText2,
          ),
        ),
      ),
    );
  }
}

class _BuildTextField extends StatelessWidget {
  const _BuildTextField({required this.ctrl});
  final TextEditingController ctrl;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      maxLines: 5,
      minLines: 3,
      style: AppTextStyles.body,
      decoration: InputDecoration(
        hintText:
            'Escribe el mensaje que recibirán todos los operadores...',
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
          borderSide:
              const BorderSide(color: AppColors.ctTeal, width: 1.5),
        ),
      ),
    );
  }
}

class _TemplateDropdown extends StatelessWidget {
  const _TemplateDropdown({
    required this.templates,
    required this.selectedId,
    required this.onChanged,
  });
  final List<Map<String, dynamic>> templates;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final validId = templates.any((t) => t['id']?.toString() == selectedId)
        ? selectedId
        : null;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.ctSurface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.ctBorder2),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: validId,
          isExpanded: true,
          isDense: true,
          hint: Text(
            'Selecciona una plantilla',
            style: AppTextStyles.body.copyWith(color: AppColors.ctText3),
          ),
          style: AppTextStyles.body,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 16,
            color: AppColors.ctText3,
          ),
          items: templates.map((t) {
            final id   = t['id']?.toString() ?? '';
            final name = t['name']?.toString() ?? id;
            return DropdownMenuItem<String>(value: id, child: Text(name));
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// FIX 8: chips de estado con fondo navy cuando seleccionados
class _FilterChip extends StatefulWidget {
  const _FilterChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String value;
  final bool selected;
  final ValueChanged<String> onTap;

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onTap(widget.value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.ctNavy
                : (_hovered ? AppColors.ctSurface2 : Colors.transparent),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.selected ? AppColors.ctNavy : AppColors.ctBorder,
            ),
          ),
          child: Text(
            widget.label,
            style: AppTextStyles.tenantName.copyWith(
              color: widget.selected ? Colors.white : AppColors.ctText2,
            ),
          ),
        ),
      ),
    );
  }
}

// FIX 7: botón de envío con altura 52, radius 10, ícono, colores correctos
class _SendButton extends StatefulWidget {
  const _SendButton({
    required this.enabled,
    required this.loading,
    required this.count,
    required this.onTap,
  });
  final bool enabled;
  final bool loading;
  final int count;
  final VoidCallback? onTap;

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: widget.enabled
                ? AppColors.ctNavy
                : AppColors.ctSurface2,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: widget.loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.ctNavy,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.send_rounded,
                      size: 16,
                      color: widget.enabled
                          ? AppColors.ctTeal
                          : AppColors.ctText3,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.count > 0
                          ? 'Enviar broadcast a ${widget.count} operadores'
                          : 'Enviar broadcast',
                      style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700, color: widget.enabled ? AppColors.ctTeal : AppColors.ctText3),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ConfirmBox extends StatelessWidget {
  const _ConfirmBox({
    required this.count,
    required this.onConfirm,
    required this.onCancel,
    required this.sending,
  });
  final int count;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool sending;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.ctWarnBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 16, color: AppColors.ctWarnText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '¿Enviar a $count operador${count != 1 ? 'es' : ''}?',
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.ctWarnText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _OutlineButton(label: 'Cancelar', onTap: onCancel),
              const SizedBox(width: 10),
              AppButton(
                label: 'Confirmar envío',
                variant: AppButtonVariant.teal,
                size: AppButtonSize.sm,
                isLoading: sending,
                isDisabled: sending,
                onPressed: onConfirm,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.ctWarnBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 14, color: AppColors.ctWarnText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctWarnText),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({
    required this.message,
    required this.type,
    this.errors = const [],
  });
  final String message;
  final _BroadcastResultType type;
  final List<Map<String, dynamic>> errors;

  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    final IconData iconData;

    switch (type) {
      case _BroadcastResultType.error:
        bgColor     = AppColors.ctRedBg;
        borderColor = const Color(0xFFFECACA);
        textColor   = AppColors.ctRedText;
        iconData    = Icons.error_outline_rounded;
      case _BroadcastResultType.warning:
        bgColor     = AppColors.ctWarnBg;
        borderColor = AppColors.ctWarn;
        textColor   = AppColors.ctWarnText;
        iconData    = Icons.warning_amber_rounded;
      case _BroadcastResultType.success:
        bgColor     = AppColors.ctOkBg;
        borderColor = AppColors.ctOk;
        textColor   = AppColors.ctOkText;
        iconData    = Icons.check_circle_outline_rounded;
    }

    final bannerRow = Row(
      children: [
        Icon(iconData, size: 15, color: textColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: AppTextStyles.body.copyWith(color: textColor),
          ),
        ),
      ],
    );

    if (errors.isEmpty) {
      return Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: bannerRow,
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          childrenPadding:
              const EdgeInsets.fromLTRB(14, 0, 14, 10),
          title: bannerRow,
          iconColor: textColor,
          collapsedIconColor: textColor,
          initiallyExpanded: false,
          subtitle: Text(
            'Ver detalle de errores (${errors.length})',
            style: AppTextStyles.bodySmall.copyWith(color: textColor.withValues(alpha: 0.8)),
          ),
          children: errors.map((e) {
            final phone  = e['phone']?.toString() ??
                e['to']?.toString() ?? '—';
            final errMsg = e['error']?.toString() ??
                e['message']?.toString() ??
                e['detail']?.toString() ??
                'Error desconocido';
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.circle,
                      size: 5,
                      color: textColor.withValues(alpha: 0.6)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$phone — $errMsg',
                      style: AppTextStyles.bodySmall.copyWith(color: textColor),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color textColor;
    final String label;

    switch (status) {
      case 'sent':
        bg        = AppColors.ctOkBg;
        textColor = AppColors.ctOkText;
        label     = 'Enviado';
      case 'failed':
        bg        = AppColors.ctRedBg;
        textColor = AppColors.ctRedText;
        label     = 'Fallido';
      case 'partial':
        bg        = AppColors.ctWarnBg;
        textColor = AppColors.ctWarnText;
        label     = 'Parcial';
      default:
        bg        = AppColors.ctSurface2;
        textColor = AppColors.ctText2;
        label     = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: AppTextStyles.badge.copyWith(color: textColor),
      ),
    );
  }
}

class _OutlineButton extends StatefulWidget {
  const _OutlineButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_OutlineButton> createState() => _OutlineButtonState();
}

class _OutlineButtonState extends State<_OutlineButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.ctSurface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.ctBorder2),
          ),
          child: Text(
            widget.label,
            style: AppTextStyles.btnSecondary.copyWith(color: AppColors.ctText2),
          ),
        ),
      ),
    );
  }
}

// ── Chip de variable (FIX 3) ──────────────────────────────────────────────────

class _VarChip extends StatefulWidget {
  const _VarChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_VarChip> createState() => _VarChipState();
}

class _VarChipState extends State<_VarChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.ctTeal.withValues(alpha: 0.15)
                : AppColors.ctTealLight,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.ctTeal),
          ),
          child: Text(
            '+ {${widget.label}}',
            style: AppTextStyles.badge.copyWith(color: AppColors.ctTealDark),
          ),
        ),
      ),
    );
  }
}

// ── Avatar circular con foto o inicial ────────────────────────────────────────

class _BcastAvatar extends StatelessWidget {
  const _BcastAvatar({required this.name, this.photoUrl});
  final String name;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          photoUrl!,
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorBuilder: (_, e, s) => _initials(),
        ),
      );
    }
    return _initials();
  }

  Widget _initials() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.ctSurface2,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700, color: AppColors.ctText2),
      ),
    );
  }
}

// ── Chip de flujo seleccionado (card con ×) ───────────────────────────────────

class _FlowCard extends StatelessWidget {
  const _FlowCard({
    required this.label,
    required this.value,
    required this.onRemove,
  });
  final String label;
  final String value;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.ctTealLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.ctTeal),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.smart_toy_outlined,
              size: 13, color: AppColors.ctTealDark),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTextStyles.tenantName.copyWith(color: AppColors.ctTealDark),
              ),
              Text(
                'Worker activo',
                style: AppTextStyles.caption.copyWith(color: AppColors.ctTeal),
              ),
            ],
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => onRemove(value),
            child: const Icon(Icons.close_rounded,
                size: 14, color: AppColors.ctTealDark),
          ),
        ],
      ),
    );
  }
}

// ── Chip de flujo no seleccionado (teal add) ──────────────────────────────────

class _AddFlowChip extends StatefulWidget {
  const _AddFlowChip({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String value;
  final ValueChanged<String> onTap;

  @override
  State<_AddFlowChip> createState() => _AddFlowChipState();
}

class _AddFlowChipState extends State<_AddFlowChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onTap(widget.value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.ctTealLight : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.ctTeal, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded,
                  size: 13, color: AppColors.ctTeal),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: AppTextStyles.tenantName.copyWith(color: AppColors.ctTeal),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
