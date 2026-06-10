import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/flows_api.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_button.dart';
import '../../core/utils/date_format.dart';
import '../../shared/widgets/screen_header.dart';

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

String _extractFlowName(Map<String, dynamic> execution) {
  final snapshot = execution['flow_definition_snapshot'];
  if (snapshot is Map) {
    final name = snapshot['name'] as String?;
    if (name != null && name.isNotEmpty) return name;
    final slug = snapshot['slug'] as String?;
    if (slug != null && slug.isNotEmpty) return slug;
  }
  final flowName = execution['flow_name'] as String?;
  if (flowName != null && flowName.isNotEmpty) return flowName;
  return execution['flow_slug'] as String? ?? '—';
}

String _collapseValue(Map f) {
  return (f['value_text'] ??
          f['value_numeric']?.toString() ??
          f['value_media_url'] ??
          f['value_jsonb']?.toString() ??
          '')
      ?.toString() ?? '';
}

// ── Screen ────────────────────────────────────────────────────────────────────

class ExecutionsScreen extends ConsumerStatefulWidget {
  const ExecutionsScreen({super.key});

  @override
  ConsumerState<ExecutionsScreen> createState() => _ExecutionsScreenState();
}

class _ExecutionsScreenState extends ConsumerState<ExecutionsScreen> {
  List<Map<String, dynamic>> _executions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final tenantId = ref.read(activeTenantIdProvider);
    if (tenantId.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await FlowsApi.listPendingExecutions(dio: ref.read(apiClientProvider).dio);
      if (!mounted) return;
      setState(() {
        _executions = data;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('EXECUTIONS_LOAD ERROR type: ${e.runtimeType}');
      debugPrint('EXECUTIONS_LOAD STACK: $st');
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar. Verifica tu conexión.';
        _loading = false;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    ref.listen<String>(activeTenantIdProvider, (prev, next) {
      if (next.isNotEmpty && next != prev) _load();
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ScreenHeader(
          title: 'Tareas pendientes',
          subtitle: 'Ejecuciones pendientes de revisión',
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded,
                  size: 20, color: AppColors.ctText2),
              tooltip: 'Actualizar',
              onPressed: _load,
            ),
          ],
        ),

        // Body
        if (_loading)
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(color: AppColors.ctTeal),
            ),
          )
        else if (_error != null)
          Expanded(
            child: _ErrorState(message: _error!, onRetry: _load),
          )
        else if (_executions.isEmpty)
          const Expanded(child: _EmptyState())
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              itemCount: _executions.length,
              separatorBuilder: (context2, i) => const SizedBox(height: 8),
              itemBuilder: (context2, i) => _ExecutionCard(
                execution: _executions[i],
                onTap: () => context.go('/executions/${_executions[i]['id']}'),
              ),
            ),
          ),
      ],
    );
  }
}

// ── _EmptyState ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.task_alt, size: 48, color: AppColors.ctText3),
          const SizedBox(height: 12),
          Text(
            'No hay tareas pendientes',
            style: AppTextStyles.pageTitle.copyWith(fontSize: 16, color: AppColors.ctText2),
          ),
          const SizedBox(height: 6),
          Text(
            'Las ejecuciones que requieren tu atención aparecerán aquí.',
            style: AppTextStyles.body.copyWith(color: AppColors.ctText3),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── _ErrorState ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40, color: AppColors.ctDanger),
          const SizedBox(height: 12),
          Text(
            message,
            style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          AppButton(
            label: 'Reintentar',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

// ── _StatusChip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (status) {
      'pending_dashboard' => (
          AppColors.ctWarnBg,
          AppColors.ctWarnText,
          'Pendiente',
        ),
      'in_progress' => (
          AppColors.ctInfoBg,
          AppColors.ctInfoText,
          'En curso',
        ),
      _ => (AppColors.ctSurface2, AppColors.ctText2, status),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

// ── _ExecutionCard ────────────────────────────────────────────────────────────

class _ExecutionCard extends StatelessWidget {
  const _ExecutionCard({
    required this.execution,
    required this.onTap,
  });

  final Map<String, dynamic> execution;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = _extractFlowName(execution);
    final status = execution['status'] as String? ?? '';
    final createdAt = execution['created_at'] as String?;
    final fieldValues = execution['field_values'];
    final fieldCount =
        fieldValues is List ? fieldValues.length : 0;

    return Card(
      elevation: 0,
      color: AppColors.ctSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.ctBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppTextStyles.cardTitle.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fmtExecutionDate(createdAt),
                      style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _StatusChip(status: status),
                  if (fieldCount > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '$fieldCount campos',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _ExecutionDetailSheet ─────────────────────────────────────────────────────

class _ExecutionDetailSheet extends ConsumerStatefulWidget {
  const _ExecutionDetailSheet({
    required this.execution,
    required this.onSubmitted,
  });

  final Map<String, dynamic> execution;
  final VoidCallback onSubmitted;

  @override
  ConsumerState<_ExecutionDetailSheet> createState() =>
      _ExecutionDetailSheetState();
}

class _ExecutionDetailSheetState
    extends ConsumerState<_ExecutionDetailSheet> {
  Map<String, dynamic>? _detail;
  bool _loadingDetail = true;
  bool _submitting = false;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _fieldLabels = {};
  // Ordered list of capturable fields from flow_definition_snapshot
  final List<Map<String, dynamic>> _snapshotCaptureFields = [];
  final Map<String, bool> _fieldRequired = {};

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  bool get _canSubmit {
    for (final entry in _controllers.entries) {
      final required = _fieldRequired[entry.key] ?? false;
      if (required && entry.value.text.trim().isEmpty) return false;
    }
    return true;
  }

  @override
  void dispose() {
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDetail() async {
    try {
      final executionId = widget.execution['id'] as String;
      final detail = await FlowsApi.getExecution(
        dio: ref.read(apiClientProvider).dio,
        executionId: executionId,
      );
      if (!mounted) return;

      // Build field metadata from snapshot (source of truth for which fields exist)
      final snapshot = widget.execution['flow_definition_snapshot'];
      if (snapshot is Map) {
        final fields = snapshot['fields'];
        if (fields is List) {
          for (final f in fields.whereType<Map>()) {
            final key = f['key'] as String? ?? f['id'] as String?;
            final lbl = f['label'] as String?;
            final req = f['required'] as bool? ?? false;
            final source = f['source'] as String?;
            if (key == null) continue;
            if (lbl != null) _fieldLabels[key] = lbl;
            _fieldRequired[key] = req;
            // Only show fields that are not inherited
            if (source != 'inherited') {
              _snapshotCaptureFields.add(Map<String, dynamic>.from(f));
              final ctrl = TextEditingController();
              ctrl.addListener(() { if (mounted) setState(() {}); });
              _controllers[key] = ctrl;
            }
          }
        }
      }

      // Pre-populate controllers with existing field_values
      final fieldValues = detail['field_values'];
      if (fieldValues is List) {
        for (final f in fieldValues.whereType<Map>()) {
          final fieldKey = f['field_key'] as String?;
          final value = _collapseValue(f);
          if (fieldKey != null &&
              _controllers.containsKey(fieldKey) &&
              value.isNotEmpty) {
            _controllers[fieldKey]!.text = value;
          }
        }
      }

      setState(() {
        _detail = detail;
        _loadingDetail = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingDetail = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_dioError(e)),
        backgroundColor: AppColors.ctDanger,
      ));
    }
  }

  Future<void> _submit() async {
    final detail = _detail;
    if (detail == null) return;

    // Validate required fields using snapshot definition
    for (final entry in _controllers.entries) {
      final fieldKey = entry.key;
      final required = _fieldRequired[fieldKey] ?? false;
      if (required && entry.value.text.trim().isEmpty) {
        final label = _fieldLabels[fieldKey] ?? fieldKey;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('El campo "$label" es requerido'),
          backgroundColor: AppColors.ctWarn,
        ));
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      final executionId = widget.execution['id'] as String;
      final fields = Map<String, String>.fromEntries(
        _controllers.entries
            .map((e) => MapEntry(e.key, e.value.text.trim())),
      );
      await FlowsApi.submitExecution(
        dio: ref.read(apiClientProvider).dio,
        executionId: executionId,
        fields: fields,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSubmitted();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Tarea enviada'),
        backgroundColor: AppColors.ctOk,
        duration: Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_dioError(e)),
        backgroundColor: AppColors.ctDanger,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.9;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.ctBorder2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          if (_loadingDetail)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.ctTeal),
              ),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: _buildContent(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final detail = _detail;
    if (detail == null) return const SizedBox.shrink();

    final flowName = _extractFlowName(widget.execution);
    final fieldValues = detail['field_values'];
    final allFv = fieldValues is List
        ? fieldValues.whereType<Map>().toList()
        : <Map>[];
    final inheritedFields = allFv.where((f) => f['source'] == 'inherited').toList();
    final hasInherited = inheritedFields.isNotEmpty;
    // Capturable fields come from the snapshot definition, not field_values
    final captureFields = _snapshotCaptureFields;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          flowName,
          style: AppTextStyles.kpiValue.copyWith(fontSize: 18),
        ),
        const SizedBox(height: 8),

        // Inherited fields
        if (hasInherited) ...[
          Text(
            'INFORMACIÓN HEREDADA',
            style: AppTextStyles.kpiLabel.copyWith(color: AppColors.ctText3, letterSpacing: 0.8),
          ),
          const SizedBox(height: 4),
          ...inheritedFields.map((f) {
            final fieldKey = f['field_key'] as String? ?? '';
            final label = _fieldLabels[fieldKey] ?? (fieldKey.isNotEmpty ? fieldKey : '—');
            final value = _collapseValue(f).isNotEmpty ? _collapseValue(f) : '—';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Text(
                    label,
                    style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    value,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ctText),
                  ),
                ],
              ),
            );
          }),
          const Divider(color: AppColors.ctBorder),
          const SizedBox(height: 12),
        ],

        // Fields to capture
        Text(
          'CAMPOS A COMPLETAR',
          style: AppTextStyles.kpiLabel.copyWith(color: AppColors.ctText3, letterSpacing: 0.8),
        ),
        const SizedBox(height: 8),

        if (captureFields.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Sin campos adicionales',
              style: AppTextStyles.body.copyWith(color: AppColors.ctText3),
            ),
          )
        else
          ...captureFields.map((f) {
            final fieldKey = f['key'] as String? ?? f['field_key'] as String? ?? '';
            final label = _fieldLabels[fieldKey] ?? (f['label'] as String?) ?? fieldKey;
            final isRequired = _fieldRequired[fieldKey] ?? false;
            final ctrl = _controllers[fieldKey] ?? TextEditingController();
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: TextField(
                controller: ctrl,
                style: AppTextStyles.body,
                decoration: InputDecoration(
                  labelText: isRequired ? '$label *' : label,
                  labelStyle: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                  filled: true,
                  fillColor: AppColors.ctSurface2,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: AppColors.ctBorder2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: AppColors.ctBorder2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.ctTeal),
                  ),
                ),
              ),
            );
          }),

        const SizedBox(height: 24),

        // Submit button
        AppButton(
          label: 'Enviar',
          variant: AppButtonVariant.teal,
          expand: true,
          isLoading: _submitting,
          isDisabled: !_canSubmit,
          onPressed: _submit,
        ),
      ],
    );
  }
}
