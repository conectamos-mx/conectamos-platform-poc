import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/operator_fields_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_button.dart';
import 'widgets/operator_field_form_dialog.dart';

// ── Field type helpers ─────────────────────────────────────────────────────────

const _kTypeLabels = {
  'text':     'Texto',
  'number':   'Número',
  'date':     'Fecha',
  'boolean':  'Sí / No',
  'select':   'Selección',
  'photo':    'Foto',
  'document': 'Documento',
};

const _kTypeIcons = {
  'text':     Icons.text_fields,
  'number':   Icons.tag,
  'date':     Icons.calendar_today,
  'boolean':  Icons.toggle_on_outlined,
  'select':   Icons.list_alt_outlined,
  'photo':    Icons.photo_camera_outlined,
  'document': Icons.attach_file,
};

String _typeLabel(String key) => _kTypeLabels[key] ?? key;
IconData _typeIcon(String key) => _kTypeIcons[key] ?? Icons.help_outline;

// ── Standalone screen (route /settings/operator-fields) ───────────────────────

class OperatorFieldsScreen extends StatelessWidget {
  const OperatorFieldsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ctBg,
      appBar: AppBar(
        backgroundColor: AppColors.ctSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.ctText),
          onPressed: () => context.go('/settings'),
        ),
        title: Text('Campos de operador',
            style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist', fontWeight: FontWeight.w600)),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.ctBorder),
        ),
      ),
      body: const OperatorFieldsBody(),
    );
  }
}

// ── Embeddable body (used in settings panel + standalone screen) ───────────────

class OperatorFieldsBody extends ConsumerStatefulWidget {
  const OperatorFieldsBody({super.key});

  @override
  ConsumerState<OperatorFieldsBody> createState() => _OperatorFieldsBodyState();
}

class _OperatorFieldsBodyState extends ConsumerState<OperatorFieldsBody> {
  List<Map<String, dynamic>> _fields = [];         // active (is_active=true)
  List<Map<String, dynamic>> _inactiveFields = []; // disabled (is_active=false)
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      // Fetch all fields including inactive ones
      final res = await ref.read(apiClientProvider).dio.get(
        '/operator-fields',
        queryParameters: {
          'include_inactive': true,
        },
      );
      final data = res.data;
      final List raw = data is List
          ? data
          : (data is Map ? (data['fields'] ?? data['items'] ?? []) : []) as List;
      final all = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final active = all.where((f) => f['is_active'] != false).toList()
        ..sort((a, b) =>
            ((a['display_order'] as int?) ?? 0)
                .compareTo((b['display_order'] as int?) ?? 0));
      final inactive = all.where((f) => f['is_active'] == false).toList();

      if (mounted) {
        setState(() {
          _fields = active;
          _inactiveFields = inactive;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      final item = _fields.removeAt(oldIndex);
      _fields.insert(newIndex, item);
    });
    _saveReorder();
  }

  Future<void> _saveReorder() async {
    final order = _fields.asMap().entries.map((e) => {
          'id': e.value['id'] as String,
          'display_order': e.key + 1,
        }).toList();
    try {
      await OperatorFieldsApi.reorderOperatorFields(order);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Error al guardar el orden'),
          backgroundColor: AppColors.ctDanger,
        ));
        _load();
      }
    }
  }

  Future<void> _confirmDeactivate(Map<String, dynamic> field) async {
    final label = field['label'] as String? ?? 'este campo';
    final withData = field['operators_with_data'] as int? ?? 0;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.ctSurface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('¿Deshabilitar "$label"?',
            style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist', fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'El campo dejará de aparecer en el formulario de operadores.',
              style: AppTextStyles.body.copyWith(fontSize: 14, color: AppColors.ctText2),
            ),
            if (withData > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.ctWarnBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline,
                      size: 15, color: AppColors.ctWarn),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Este campo tiene datos en $withData '
                      'operador${withData == 1 ? '' : 'es'}. '
                      'Los datos no se perderán.',
                      style: AppTextStyles.body.copyWith(color: AppColors.ctWarnText),
                    ),
                  ),
                ]),
              ),
            ],
          ],
        ),
        actions: [
          AppButton(
            label: 'Cancelar',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          AppButton(
            label: 'Deshabilitar',
            variant: AppButtonVariant.danger,
            size: AppButtonSize.sm,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    final fieldId = field['id'] as String? ?? '';
    try {
      final res = await OperatorFieldsApi.deleteOperatorField(fieldId);
      final withDataResponse = res['operators_with_data'] as int? ?? 0;
      if (mounted) {
        setState(() {
          _fields.removeWhere((f) => f['id'] == fieldId);
          _inactiveFields.add({...field, 'is_active': false});
        });
        if (withDataResponse > 0) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              'Campo deshabilitado. Tenía datos en $withDataResponse '
              'operador${withDataResponse == 1 ? '' : 'es'}. '
              'Los datos no se perderán.',
            ),
            backgroundColor: AppColors.ctWarn,
            duration: const Duration(seconds: 4),
          ));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Error al deshabilitar el campo'),
          backgroundColor: AppColors.ctDanger,
        ));
      }
    }
  }

  Future<void> _rehabilitate(Map<String, dynamic> field) async {
    final fieldId = field['id'] as String? ?? '';
    final label = field['label'] as String? ?? 'este campo';
    try {
      await OperatorFieldsApi.updateOperatorField(fieldId, isActive: true);
      if (mounted) {
        setState(() {
          _inactiveFields.removeWhere((f) => f['id'] == fieldId);
          _fields.add({...field, 'is_active': true});
          _fields.sort((a, b) =>
              ((a['display_order'] as int?) ?? 0)
                  .compareTo((b['display_order'] as int?) ?? 0));
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('"$label" habilitado'),
          backgroundColor: AppColors.ctOk,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Error al rehabilitar el campo'),
          backgroundColor: AppColors.ctDanger,
        ));
      }
    }
  }

  Future<void> _confirmDeletePermanent(Map<String, dynamic> field) async {
    final label = field['label'] as String? ?? 'este campo';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.ctSurface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('¿Eliminar "$label" permanentemente?',
            style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist', fontSize: 16)),
        content: Text(
          'Esta acción no se puede deshacer.',
          style: AppTextStyles.body.copyWith(fontSize: 14, color: AppColors.ctText2),
        ),
        actions: [
          AppButton(
            label: 'Cancelar',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          AppButton(
            label: 'Eliminar',
            variant: AppButtonVariant.danger,
            size: AppButtonSize.sm,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    // Hard delete endpoint not yet available in backend
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Funcionalidad disponible próximamente'),
      duration: Duration(seconds: 3),
    ));
  }

  void _openCreate(String tenantId) {
    showDialog(
      context: context,
      builder: (_) => OperatorFieldFormDialog(
        tenantId: tenantId,
        onSaved: _load,
      ),
    );
  }

  void _openEdit(Map<String, dynamic> field) {
    showDialog(
      context: context,
      builder: (_) => OperatorFieldFormDialog(
        tenantId: '',
        field: field,
        onSaved: _load,
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final canManage = hasPermission(ref, 'settings', 'manage');
    final effectiveTenantId = ref.watch(activeTenantIdProvider);
    if (effectiveTenantId.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.ctTeal));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header bar: subtitle + action button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          color: AppColors.ctSurface,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Define campos adicionales para los perfiles de tus operadores. '
                  'Arrastra para cambiar el orden.',
                  style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                ),
              ),
              if (canManage) ...[
                const SizedBox(width: 16),
                AppButton(
                  label: 'Agregar campo',
                  variant: AppButtonVariant.teal,
                  size: AppButtonSize.sm,
                  prefixIcon: const Icon(Icons.add, size: 14, color: AppColors.ctNavy),
                  onPressed: () => _openCreate(effectiveTenantId),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.ctBorder),

        Expanded(child: _buildContent(canManage, effectiveTenantId)),
      ],
    );
  }

  Widget _buildContent(bool canManage, String tenantId) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: AppColors.ctDanger),
            const SizedBox(height: 12),
            Text(_error!,
                style: AppTextStyles.body.copyWith(color: AppColors.ctText2)),
            const SizedBox(height: 16),
            AppButton(
              label: 'Reintentar',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              onPressed: _load,
            ),
          ],
        ),
      );
    }

    if (_fields.isEmpty && _inactiveFields.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dashboard_customize_outlined,
                size: 56, color: AppColors.ctText3),
            const SizedBox(height: 16),
            Text('Sin campos definidos',
                style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist', fontSize: 16)),
            const SizedBox(height: 6),
            Text(
              'Agrega campos personalizados para enriquecer los perfiles de tus operadores',
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
            ),
            if (canManage) ...[
              const SizedBox(height: 20),
              AppButton(
                label: 'Agregar primer campo',
                variant: AppButtonVariant.teal,
                prefixIcon: const Icon(Icons.add, size: 14, color: AppColors.ctNavy),
                onPressed: () => _openCreate(tenantId),
              ),
            ],
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        // ── ACTIVOS (reorderable) ─────────────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          sliver: SliverReorderableList(
            itemCount: _fields.length,
            onReorder: canManage ? _onReorder : (oldIndex, newIndex) {},
            itemBuilder: (context, i) {
              final field = _fields[i];
              final id = field['id'] as String? ?? i.toString();
              return _FieldCard(
                key: ValueKey(id),
                field: field,
                index: i,
                canManage: canManage,
                onEdit: () => _openEdit(field),
                onDeactivate: () => _confirmDeactivate(field),
              );
            },
          ),
        ),

        // ── DESHABILITADOS ────────────────────────────────────────────────────
        if (_inactiveFields.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
              child: Text(
                'DESHABILITADOS',
                style: AppTextStyles.kpiLabel.copyWith(letterSpacing: 0.6),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final field = _inactiveFields[i];
                  final id = field['id'] as String? ?? i.toString();
                  return _InactiveFieldCard(
                    key: ValueKey('inactive_$id'),
                    field: field,
                    canManage: canManage,
                    onReactivate: () => _rehabilitate(field),
                    onDelete: () => _confirmDeletePermanent(field),
                  );
                },
                childCount: _inactiveFields.length,
              ),
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 20)),
      ],
    );
  }
}

// ── Active field card ──────────────────────────────────────────────────────────

class _FieldCard extends StatelessWidget {
  const _FieldCard({
    super.key,
    required this.field,
    required this.index,
    required this.canManage,
    required this.onEdit,
    required this.onDeactivate,
  });

  final Map<String, dynamic> field;
  final int index;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDeactivate;

  @override
  Widget build(BuildContext context) {
    final label = field['label'] as String? ?? '—';
    final fieldType = field['field_type'] as String? ?? 'text';
    final fieldKey = field['field_key'] as String? ?? '';
    final isRequired = field['required'] as bool? ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Drag handle
          if (canManage) ...[
            ReorderableDragStartListener(
              index: index,
              child: const MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Icon(Icons.drag_handle,
                    size: 20, color: AppColors.ctText3),
              ),
            ),
            const SizedBox(width: 10),
          ],

          // Type icon
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: AppColors.ctSurface2,
              shape: BoxShape.circle,
            ),
            child: Icon(_typeIcon(fieldType),
                size: 16, color: AppColors.ctText2),
          ),
          const SizedBox(width: 12),

          // Label + meta
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(children: [
                  _Chip(
                    label: _typeLabel(fieldType),
                    bg: AppColors.ctInfoBg,
                    fg: AppColors.ctInfoText,
                  ),
                  if (isRequired) ...[
                    const SizedBox(width: 6),
                    const _Chip(
                      label: 'Requerido',
                      bg: AppColors.ctWarnBg,
                      fg: AppColors.ctWarnText,
                    ),
                  ],
                  if (fieldKey.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(fieldKey,
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3)),
                  ],
                ]),
              ],
            ),
          ),

          // Actions
          if (canManage) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  size: 18, color: AppColors.ctText2),
              tooltip: 'Editar',
              onPressed: onEdit,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.toggle_off_outlined,
                  size: 20, color: AppColors.ctText2),
              tooltip: 'Deshabilitar',
              onPressed: onDeactivate,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Inactive field card ────────────────────────────────────────────────────────

class _InactiveFieldCard extends StatelessWidget {
  const _InactiveFieldCard({
    super.key,
    required this.field,
    required this.canManage,
    required this.onReactivate,
    required this.onDelete,
  });

  final Map<String, dynamic> field;
  final bool canManage;
  final VoidCallback onReactivate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final label = field['label'] as String? ?? '—';
    final fieldType = field['field_type'] as String? ?? 'text';
    final fieldKey = field['field_key'] as String? ?? '';
    final withData = field['operators_with_data'] as int? ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.ctSurface2,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Type icon (grayed)
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: AppColors.ctBg,
              shape: BoxShape.circle,
            ),
            child: Icon(_typeIcon(fieldType),
                size: 16, color: AppColors.ctText3),
          ),
          const SizedBox(width: 12),

          // Label + meta (grayed)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ctText2
                    )),
                const SizedBox(height: 4),
                Row(children: [
                  _Chip(
                    label: _typeLabel(fieldType),
                    bg: AppColors.ctSurface,
                    fg: AppColors.ctText3,
                  ),
                  if (fieldKey.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(fieldKey,
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3)),
                  ],
                ]),
              ],
            ),
          ),

          // Actions
          if (canManage) ...[
            // Rehabilitar
            IconButton(
              icon: const Icon(Icons.toggle_on_outlined,
                  size: 20, color: AppColors.ctTeal),
              tooltip: 'Rehabilitar',
              onPressed: onReactivate,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 4),
            // Eliminar
            Tooltip(
              message: withData > 0
                  ? 'Tiene datos en operadores'
                  : 'Eliminar permanentemente',
              child: IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 18,
                    color: withData > 0
                        ? AppColors.ctText3
                        : AppColors.ctDanger),
                onPressed: withData > 0 ? null : onDelete,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Shared chip ────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.bg, required this.fg});
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: fg)),
    );
  }
}
