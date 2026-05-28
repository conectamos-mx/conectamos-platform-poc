// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/operator_roles_api.dart';
import '../../core/api/operators_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/identity_config.dart';
import '../../shared/widgets/app_action_button.dart';
import '../../shared/widgets/app_badge.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_confirm_dialog.dart';
import '../../shared/widgets/app_detail_header.dart';
import 'widgets/operator_form_dialog.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────


String _fmtDate(String? iso) {
  if (iso == null) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/${dt.year} $h:$min';
  } catch (_) {
    return iso;
  }
}

({String label, Color bg, Color fg}) _statusStyle(String? status) {
  switch (status) {
    case 'active':
      return (label: 'Activo', bg: AppColors.ctOkBg, fg: AppColors.ctOkText);
    case 'incident':
      return (label: 'Incidencia', bg: AppColors.ctRedBg, fg: AppColors.ctRedText);
    case 'suspended':
      return (label: 'Suspendido', bg: AppColors.ctSurface2, fg: AppColors.ctText2);
    default:
      return (label: 'Sin inicio', bg: AppColors.ctSurface2, fg: AppColors.ctText2);
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class OperatorDetailScreen extends ConsumerStatefulWidget {
  const OperatorDetailScreen({super.key, required this.operatorId});
  final String operatorId;

  @override
  ConsumerState<OperatorDetailScreen> createState() =>
      _OperatorDetailScreenState();
}

class _OperatorDetailScreenState extends ConsumerState<OperatorDetailScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _op;
  bool _loading = true;
  String? _error;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final op = await OperatorsApi.getOperator(widget.operatorId);
      if (mounted) setState(() { _op = op; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _patchStatus(String status) async {
    final name = _op?['display_name'] as String? ?? 'este operador';
    final isSuspend = status == 'suspended';
    final label = isSuspend ? 'Suspender' : 'Reactivar';
    final consequence = isSuspend
        ? 'No podrá recibir nuevas conversaciones hasta ser reactivado.'
        : 'Volverá a recibir conversaciones nuevas.';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmDialog(
        title: '¿$label a $name?',
        body: consequence,
        confirmLabel: label,
        confirmColor: isSuspend ? AppColors.ctDanger : AppColors.ctOk,
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await OperatorsApi.patchStatus(id: widget.operatorId, status: status);
      if (mounted) setState(() => _op = {..._op!, 'status': status});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Error al cambiar el estado'),
          backgroundColor: AppColors.ctDanger,
        ));
      }
    }
  }

  Future<void> _delete() async {
    final name = _op?['display_name'] as String? ?? 'este operador';

    final step1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmDialog(
        title: '¿Eliminar a $name?',
        body: 'Esta acción no se puede deshacer.',
        confirmLabel: 'Eliminar permanentemente',
        confirmColor: AppColors.ctDanger,
      ),
    );
    if (step1 != true || !mounted) return;

    try {
      final res =
          await ApiClient.instance.delete('/operators/${widget.operatorId}');
      final data = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      final telegramLinked = data['telegram_linked'] as bool? ?? false;

      if (!mounted) return;

      if (telegramLinked) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.ctSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Text('Telegram vinculado',
                style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist', fontSize: 16)),
            content: Text(
              'Este operador tenía Telegram vinculado. Ha perdido acceso al bot.',
              style: AppTextStyles.body.copyWith(fontSize: 14, color: AppColors.ctText2),
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
      }

      if (!mounted) return;
      context.go('/operators');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Operador eliminado'),
        backgroundColor: AppColors.ctOk,
      ));
    } catch (e) {
      if (!mounted) return;
      String msg = 'Error al eliminar el operador';
      if (e is DioException) {
        final body = e.response?.data;
        if (body is Map) {
          final code = body['code'] as String?;
          final detail = body['message'] ?? body['detail'];
          if (code == 'OP_E017' && detail != null) {
            msg = detail.toString();
          } else if (detail != null) {
            msg = detail.toString();
          }
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.ctDanger));
    }
  }

  Future<void> _openEdit() async {
    final op = _op!;
    final meta = op['metadata'] as Map<String, dynamic>? ?? {};

    await showDialog(
      context: context,
      builder: (_) => OperatorFormDialog(
        operatorId: widget.operatorId,
        initialName:
            op['display_name'] as String? ?? op['name'] as String? ?? '',
        initialPhone: op['phone'] as String? ?? '',
        initialRoleIds: (op['role_ids'] as List?)?.cast<String>() ?? [],
        initialTelegramChatId: meta['telegram_chat_id'] as String?,
        initialMetadata: meta,
        initialEmail: op['email'] as String?,
        initialNationality: op['nationality'] as String?,
        initialIdentityNumber: op['identity_number'] as String?,
        initialProfilePictureUrl: op['profile_picture_url'] as String?,
        initialCustomFields: (op['custom_fields'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        onSaved: _load,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.ctBg,
        appBar: AppDetailHeader(
          title: 'Operador',
          backLabel: 'Operadores',
          onBack: () => context.go('/operators'),
          bottom: _tabBar,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _op == null) {
      return Scaffold(
        backgroundColor: AppColors.ctBg,
        appBar: AppDetailHeader(
          title: 'Operador',
          backLabel: 'Operadores',
          onBack: () => context.go('/operators'),
          bottom: _tabBar,
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: AppColors.ctDanger),
              const SizedBox(height: 12),
              Text(_error ?? 'No se encontró el operador',
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
        ),
      );
    }

    final op = _op!;
    final canManage = hasPermission(ref, 'operators', 'manage');
    final status = op['status'] as String?;

    final isLinked = op['linked_tenant_user_id'] != null;

    return Scaffold(
      backgroundColor: AppColors.ctBg,
      appBar: AppDetailHeader(
        title: op['display_name'] as String? ?? op['name'] as String? ?? 'Operador',
        backLabel: 'Operadores',
        onBack: () => context.go('/operators'),
        subtitle: op['phone'] as String?,
        avatar: ((op['profile_picture_url'] as String?) ?? '').isNotEmpty
            ? Image.network(
                op['profile_picture_url'] as String,
                fit: BoxFit.cover,
                width: 40,
                height: 40,
              )
            : const Icon(Icons.person_rounded, size: 22, color: AppColors.ctText2),
        statusLabel: _statusStyle(status).label,
        statusActive: status == 'active',
        chips: [
          AppBadge(
            label: isLinked ? 'Vinculado' : 'Sin usuario',
            variant: isLinked ? AppBadgeVariant.teal : AppBadgeVariant.neutral,
          ),
        ],
        actions: [
          if (canManage) ...[
            AppActionButton(
              variant: AppActionVariant.edit,
              onPressed: _openEdit,
            ),
            if (status == 'active' || status == 'incident')
              AppActionButton(
                variant: AppActionVariant.suspend,
                onPressed: () => _patchStatus('suspended'),
              )
            else
              AppActionButton(
                variant: AppActionVariant.reactivate,
                onPressed: () => _patchStatus('active'),
              ),
            AppActionButton(
              variant: AppActionVariant.delete,
              onPressed: _delete,
            ),
          ],
        ],
        bottom: _tabBar,
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _DatosTab(op: op, onReload: _load),
                _FlujosTab(op: op, canManage: canManage),
                const _PermisosTab(),
                _HistorialTab(operatorId: widget.operatorId),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSize get _tabBar => PreferredSize(
        preferredSize: const Size.fromHeight(44),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.ctSurface,
            border: Border(
              bottom: BorderSide(color: AppColors.ctBorder, width: 1),
            ),
          ),
          child: TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            labelColor: AppColors.ctTeal,
            unselectedLabelColor: AppColors.ctText2,
            indicatorColor: AppColors.ctTeal,
            indicatorWeight: 2,
            dividerColor: Colors.transparent,
            labelStyle: AppTextStyles.formLabel,
            unselectedLabelStyle: AppTextStyles.navItem,
            tabs: const [
              Tab(text: 'Datos'),
              Tab(text: 'Flujos'),
              Tab(text: 'Permisos'),
              Tab(text: 'Historial'),
            ],
          ),
        ),
      );
}

// ── Tab DATOS ──────────────────────────────────────────────────────────────────

class _DatosTab extends ConsumerStatefulWidget {
  const _DatosTab({required this.op, required this.onReload});
  final Map<String, dynamic> op;
  final VoidCallback onReload;

  @override
  ConsumerState<_DatosTab> createState() => _DatosTabState();
}

class _DatosTabState extends ConsumerState<_DatosTab> {
  List<String> _orderedTypes = [];
  bool _loadingTypes = false;
  bool _saving = false;

  // Rol
  String? _roleId;
  List<Map<String, dynamic>> _availableRoles = [];
  bool _savingRole = false;

  @override
  void initState() {
    super.initState();
    // Seed from persisted preferred_channel_types before API loads
    final raw = widget.op['preferred_channel_types'];
    if (raw is List) {
      _orderedTypes = raw.map((e) => e.toString()).toList();
    }
    // Seed role from operator data
    final rawRoleIds = widget.op['role_ids'];
    if (rawRoleIds is List && rawRoleIds.isNotEmpty) {
      _roleId = rawRoleIds.first?.toString();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTypes();
      _loadRoles();
    });
  }

  Future<void> _loadTypes() async {
    if (!mounted) return;
    final tenantId  = ref.read(activeTenantIdProvider);
    final operatorId = widget.op['id'] as String? ?? '';
    if (tenantId.isEmpty || operatorId.isEmpty) return;

    setState(() => _loadingTypes = true);
    try {
      final available = await OperatorsApi.getAvailableChannelTypes(
        operatorId: operatorId,
      );
      if (!mounted) return;
      setState(() {
        _orderedTypes = _mergeWithPreferred(available, _orderedTypes);
        _loadingTypes = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingTypes = false);
    }
  }

  /// Preferred types first (in saved order), then remaining available types.
  static List<String> _mergeWithPreferred(
    List<String> available,
    List<String> preferred,
  ) {
    final result = <String>[];
    for (final t in preferred) {
      if (available.contains(t)) result.add(t);
    }
    for (final t in available) {
      if (!result.contains(t)) result.add(t);
    }
    return result;
  }

  Future<void> _saveOrder(List<String> newOrder) async {
    final operatorId = widget.op['id'] as String? ?? '';
    if (operatorId.isEmpty) return;
    setState(() {
      _orderedTypes = newOrder;
      _saving = true;
    });
    try {
      await OperatorsApi.patchPreferredChannelTypes(
        id:    operatorId,
        types: newOrder,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:         Text('Canal preferido actualizado'),
        backgroundColor: AppColors.ctOk,
        duration:        Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      String msg = 'Error al actualizar el canal preferido';
      if (e is DioException) {
        final body = e.response?.data;
        if (body is Map) {
          final detail = body['detail'] ?? body['message'];
          if (detail != null) msg = detail.toString();
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:         Text(msg),
        backgroundColor: AppColors.ctDanger,
      ));
    }
  }

  Future<void> _loadRoles() async {
    if (!mounted) return;
    final tenantId = ref.read(activeTenantIdProvider);
    if (tenantId.isEmpty) return;
    try {
      final roles = await OperatorRolesApi.listRoles(tenantId: tenantId);
      if (!mounted) return;
      setState(() => _availableRoles = roles);
    } catch (_) {}
  }

  Future<void> _saveRole(String? roleId) async {
    final operatorId = widget.op['id'] as String? ?? '';
    if (operatorId.isEmpty) return;
    setState(() {
      _roleId = roleId;
      _savingRole = true;
    });
    try {
      await OperatorsApi.patchRoleIds(
        id: operatorId,
        roleIds: roleId != null ? [roleId] : [],
      );
      if (!mounted) return;
      setState(() => _savingRole = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Rol actualizado'),
        backgroundColor: AppColors.ctOk,
        duration: Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingRole = false);
      String msg = 'Error al actualizar el rol';
      if (e is DioException) {
        final body = e.response?.data;
        if (body is Map) {
          final detail = body['detail'] ?? body['message'];
          if (detail != null) msg = detail.toString();
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.ctDanger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = hasPermission(ref, 'operators', 'manage');
    final op        = widget.op;
    final meta      = op['metadata'] as Map<String, dynamic>? ?? {};

    final nationality    = op['nationality']    as String? ?? '';
    final identityNumber = op['identity_number'] as String? ?? '';
    final identityType   = op['identity_type']   as String?;
    final email          = op['email']           as String? ?? '';
    final phone          = op['phone']           as String? ?? '';
    final name = op['display_name'] as String? ?? op['name'] as String? ?? '—';
    final createdAt = op['created_at'] as String?;
    final updatedAt = op['updated_at'] as String?;
    final createdBy =
        op['created_by'] as String? ?? meta['created_by'] as String? ?? '—';
    final updatedBy =
        op['updated_by'] as String? ?? meta['updated_by'] as String? ?? '—';
    final tgChatId = meta['telegram_chat_id'] as String?;
    final phoneSecondary =
        ((meta['phone_secondary'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

    final idConfig = nationality.isNotEmpty ? getIdentityConfig(nationality) : null;
    final idLabel  = idConfig?.label ?? identityType ?? 'Identidad';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Información personal'),
          const SizedBox(height: 12),
          _FieldRow(label: 'Nombre completo', value: name),
          _FieldRow(label: 'Correo', value: email.isNotEmpty ? email : '—'),
          if (nationality.isNotEmpty)
            _FieldRow(label: 'Nacionalidad', value: nationality),
          if (identityNumber.isNotEmpty)
            _FieldRow(label: idLabel, value: identityNumber),
          _FieldRow(label: 'Teléfono WhatsApp', value: phone),
          if (tgChatId != null && tgChatId.isNotEmpty) ...[
            const _FieldLabel('Telegram Chat ID'),
            const SizedBox(height: 4),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.ctTgBubble,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.telegram,
                      size: 14, color: AppColors.ctTg),
                  const SizedBox(width: 5),
                  Text(tgChatId,
                      style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500, color: AppColors.ctTg)),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // ── Vínculo con plataforma ──────────────────────────────────
          const SizedBox(height: 16),
          const _SectionTitle('Vínculo con plataforma'),
          const SizedBox(height: 12),
          Builder(builder: (context) {
            final linkedUserId = op['linked_tenant_user_id'] as String?;
            final linkedUserName = op['linked_tenant_user_nombre'] as String?;

            if (linkedUserId != null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FieldRow(
                    label: 'Usuario vinculado',
                    value: linkedUserName ?? linkedUserId,
                  ),
                  const SizedBox(height: 10),
                  if (canManage)
                    AppButton(
                      label: 'Desvincular',
                      variant: AppButtonVariant.danger,
                      size: AppButtonSize.sm,
                      onPressed: () async {
                        final ok = await AppConfirmDialog.show(
                          context: context,
                          title: 'Desvincular operador',
                          body: 'El operador perderá acceso al panel. Puedes volver a vincularlo cuando quieras.',
                          confirmLabel: 'Sí, desvincular',
                          variant: AppConfirmDialogVariant.danger,
                        );
                        if (ok != true) return;
                        try {
                          await OperatorsApi.unlinkFromUser(
                            operatorId: op['id'] as String,
                          );
                          widget.onReload();
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Error al desvincular: $e'),
                            backgroundColor: AppColors.ctDanger,
                          ));
                        }
                      },
                    ),
                ],
              );
            }

            return AppButton(
              label: 'Vincular usuario de plataforma',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Próximamente: vincular desde aquí'),
                  backgroundColor: AppColors.ctTeal,
                ));
              },
            );
          }),

          if (phoneSecondary.isNotEmpty) ...[
            const SizedBox(height: 8),
            const _SectionTitle('Teléfonos secundarios'),
            const SizedBox(height: 12),
            ...phoneSecondary.map((p) {
              final lbl    = p['label']   as String? ?? '—';
              final ch     = p['channel'] as String? ?? '';
              final pPhone = p['phone']   as String? ?? '—';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _FieldRow(
                  label: lbl + (ch.isNotEmpty ? ' ($ch)' : ''),
                  value: pPhone,
                ),
              );
            }),
          ],

          // ── Canal preferido ─────────────────────────────────────────────
          const SizedBox(height: 16),
          Row(
            children: [
              const _SectionTitle('Canal preferido'),
              if (_saving) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width:  14,
                  height: 14,
                  child:  CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.ctTeal,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (_loadingTypes)
            const SizedBox(
              height: 36,
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.ctTeal,
                ),
              ),
            )
          else if (_orderedTypes.isEmpty)
            Text(
              'Sin canales disponibles. Asigna flows al operador primero.',
              style: AppTextStyles.body.copyWith(color: AppColors.ctText3),
            )
          else
            _ChannelTypeOrderList(
              types:      _orderedTypes,
              enabled:    canManage && !_saving,
              onReorder:  canManage ? _saveOrder : null,
            ),

          // ── Rol de operador ─────────────────────────────────────────────
          const SizedBox(height: 16),
          Row(
            children: [
              const _SectionTitle('Rol'),
              if (_savingRole) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.ctTeal),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          DropdownButton<String?>(
            value: _availableRoles.any((r) => r['id'] == _roleId)
                ? _roleId
                : null,
            isExpanded: true,
            underline: Container(height: 1, color: AppColors.ctBorder),
            style: AppTextStyles.body,
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text('Sin rol',
                    style: AppTextStyles.body.copyWith(color: AppColors.ctText3)),
              ),
              ..._availableRoles.map((role) {
                final id = role['id'] as String? ?? '';
                final label = role['label'] as String? ??
                    role['slug'] as String? ??
                    id;
                return DropdownMenuItem<String?>(
                  value: id,
                  child: Text(label, style: AppTextStyles.body),
                );
              }),
            ],
            onChanged: canManage && !_savingRole ? _saveRole : null,
          ),

          const SizedBox(height: 16),
          const _SectionTitle('Auditoría'),
          const SizedBox(height: 12),
          _FieldRow(label: 'Creado el',          value: _fmtDate(createdAt)),
          _FieldRow(label: 'Creado por',          value: createdBy),
          _FieldRow(label: 'Última modificación', value: _fmtDate(updatedAt)),
          _FieldRow(label: 'Modificado por',      value: updatedBy),

          // ── Campos personalizados ───────────────────────────────────────
          Builder(builder: (context) {
            final rawCf = op['custom_fields'];
            final customFields = rawCf is List
                ? rawCf
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList()
                : <Map<String, dynamic>>[];
            if (customFields.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                const _SectionTitle('Campos personalizados'),
                const SizedBox(height: 12),
                ...customFields.map((cf) => _CustomFieldReadRow(field: cf)),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ── Channel type order list ───────────────────────────────────────────────────

class _ChannelTypeOrderList extends StatelessWidget {
  const _ChannelTypeOrderList({
    required this.types,
    required this.enabled,
    required this.onReorder,
  });

  final List<String>            types;
  final bool                    enabled;
  final ValueChanged<List<String>>? onReorder;

  static Color _color(String t) => switch (t) {
    'whatsapp' => AppColors.ctWa,
    'telegram' => AppColors.ctTg,
    'sms'      => AppColors.ctText2,
    _          => AppColors.ctText3,
  };

  static IconData _icon(String t) => switch (t) {
    'whatsapp' => Icons.chat_bubble_outline,
    'telegram' => Icons.telegram,
    'sms'      => Icons.sms_outlined,
    _          => Icons.router_rounded,
  };

  static String _label(String t) => switch (t) {
    'whatsapp' => 'WhatsApp',
    'telegram' => 'Telegram',
    'sms'      => 'SMS',
    _          => t,
  };

  void _move(int from, int delta) {
    final to = from + delta;
    if (to < 0 || to >= types.length) return;
    final next = List<String>.from(types);
    final item = next.removeAt(from);
    next.insert(to, item);
    onReorder?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: types.asMap().entries.map((entry) {
        final i    = entry.key;
        final type = entry.value;
        final color = _color(type);

        return Container(
          key:    ValueKey(type),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color:        AppColors.ctSurface,
            border:       Border.all(color: AppColors.ctBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              // Priority badge
              Container(
                width:  22,
                height: 22,
                decoration: BoxDecoration(
                  color:        color.withValues(alpha: 0.12),
                  shape:        BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${i + 1}',
                  style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w700, color: color),
                ),
              ),
              const SizedBox(width: 10),
              // Channel icon
              Icon(_icon(type), size: 16, color: color),
              const SizedBox(width: 8),
              // Label
              Expanded(
                child: Text(
                  _label(type),
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600, color: enabled ? AppColors.ctText : AppColors.ctText3),
                ),
              ),
              // ↑ ↓ arrows
              if (enabled) ...[
                _ArrowBtn(
                  icon:      Icons.keyboard_arrow_up_rounded,
                  tooltip:   'Mover arriba',
                  onPressed: i > 0 ? () => _move(i, -1) : null,
                ),
                _ArrowBtn(
                  icon:      Icons.keyboard_arrow_down_rounded,
                  tooltip:   'Mover abajo',
                  onPressed: i < types.length - 1 ? () => _move(i, 1) : null,
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ArrowBtn extends StatelessWidget {
  const _ArrowBtn({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  final IconData     icon;
  final String       tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message:      tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap:        onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            icon,
            size:  20,
            color: onPressed != null ? AppColors.ctText2 : AppColors.ctBorder2,
          ),
        ),
      ),
    );
  }
}

// ── Tab FLUJOS ─────────────────────────────────────────────────────────────────

class _FlujosTab extends StatelessWidget {
  const _FlujosTab({required this.op, required this.canManage});
  final Map<String, dynamic> op;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final meta = op['metadata'] as Map<String, dynamic>? ?? {};
    final tgChatId = meta['telegram_chat_id'] as String?;
    final hasTgLinked = tgChatId != null && tgChatId.isNotEmpty;
    final operatorId = op['id'] as String? ?? '';

    final flows = (op['flows'] as List? ?? []).map((f) {
      if (f is Map) return Map<String, dynamic>.from(f);
      return <String, dynamic>{'id': f.toString()};
    }).toList();

    if (flows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_tree_outlined,
                size: 48, color: AppColors.ctText3),
            const SizedBox(height: 12),
            Text('Sin flujos asignados',
                style: AppTextStyles.body.copyWith(fontSize: 14, color: AppColors.ctText2)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: flows
            .map((f) => _FlowCard(
                  flow: f,
                  operatorId: operatorId,
                  hasTgLinked: hasTgLinked,
                ))
            .toList(),
      ),
    );
  }
}

class _FlowCard extends StatefulWidget {
  const _FlowCard({
    required this.flow,
    required this.operatorId,
    required this.hasTgLinked,
  });
  final Map<String, dynamic> flow;
  final String operatorId;
  final bool hasTgLinked;

  @override
  State<_FlowCard> createState() => _FlowCardState();
}

class _FlowCardState extends State<_FlowCard> {
  bool _sending = false;

  Future<void> _sendInvite() async {
    setState(() => _sending = true);
    final channelId =
        widget.flow['channel_id'] as String? ??
        widget.flow['id'] as String? ?? '';
    try {
      await OperatorsApi.sendTelegramInvite(
        operatorId: widget.operatorId,
        channelId: channelId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Invitación enviada'),
          backgroundColor: AppColors.ctOk,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Error al enviar la invitación'),
          backgroundColor: AppColors.ctDanger,
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = widget.flow;
    final name =
        flow['name'] as String? ?? flow['id'] as String? ?? '—';
    final channelTypes = flow['channel_types'];
    final isTelegram =
        channelTypes is List && channelTypes.contains('telegram');
    final isWa =
        channelTypes is List && channelTypes.contains('whatsapp');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Canal icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isTelegram
                  ? AppColors.ctTgBubble
                  : AppColors.ctOkBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isTelegram ? Icons.telegram : Icons.chat_bubble_outline,
              size: 16,
              color: isTelegram
                  ? AppColors.ctTg
                  : AppColors.ctOk,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: AppTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  isTelegram
                      ? 'Telegram'
                      : isWa
                          ? 'WhatsApp'
                          : 'Canal',
                  style: AppTextStyles.navItem,
                ),
              ],
            ),
          ),
          // Telegram link badge / invite button
          if (isTelegram && !widget.hasTgLinked) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.ctRedBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('Sin vincular',
                  style: AppTextStyles.badge.copyWith(color: AppColors.ctRedText)),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 28,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.ctTgBubble,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: _sending ? null : _sendInvite,
                child: _sending
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Enviar invitación',
                        style: AppTextStyles.badge.copyWith(
                          color: AppColors.ctTg,
                        )),
              ),
            ),
          ] else if (isTelegram && widget.hasTgLinked) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.ctOkBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, size: 12, color: AppColors.ctOk),
                  const SizedBox(width: 4),
                  Text('Vinculado',
                      style: AppTextStyles.badge.copyWith(color: AppColors.ctOkText)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Tab PERMISOS ───────────────────────────────────────────────────────────────

class _PermisosTab extends StatelessWidget {
  const _PermisosTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 56, color: AppColors.ctText3),
            const SizedBox(height: 16),
            Text(
              'La asignación de permisos individuales por operador '
              'estará disponible próximamente',
              textAlign: TextAlign.center,
              style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist', color: AppColors.ctText2),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tab HISTORIAL ──────────────────────────────────────────────────────────────

class _HistorialTab extends StatefulWidget {
  const _HistorialTab({required this.operatorId});
  final String operatorId;

  @override
  State<_HistorialTab> createState() => _HistorialTabState();
}

class _HistorialTabState extends State<_HistorialTab> {
  List<Map<String, dynamic>>? _sessions;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiClient.instance
          .get('/operators/${widget.operatorId}/sessions');
      final data = res.data;
      final List raw = data is List
          ? data
          : (data is Map
              ? (data['sessions'] ?? data['items'] ?? [])
              : []) as List;
      if (mounted) {
        setState(() {
          _sessions =
              raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _sessions = []; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final sessions = _sessions ?? [];
    if (sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history, size: 56, color: AppColors.ctText3),
            const SizedBox(height: 16),
            Text('Sin actividad registrada',
                style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist', color: AppColors.ctText2)),
            const SizedBox(height: 6),
            Text('El historial de sesiones estará disponible próximamente',
                style: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: AppColors.ctText3)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: sessions.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, color: AppColors.ctBorder),
      itemBuilder: (context, i) {
        final s = sessions[i];
        final flowName =
            s['flow_name'] as String? ?? s['flow_id'] as String? ?? '—';
        final sessionStatus = s['status'] as String? ?? '—';
        final startedAt =
            s['started_at'] as String? ?? s['created_at'] as String?;
        final isCompleted = sessionStatus == 'completed';
        return ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(flowName,
              style: AppTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text(_fmtDate(startedAt),
              style: AppTextStyles.navItem),
          trailing: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isCompleted ? AppColors.ctOkBg : AppColors.ctSurface2,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(sessionStatus,
                style: AppTextStyles.bodySmall.copyWith(
                  color: isCompleted ? AppColors.ctOkText : AppColors.ctText2,
                )),
          ),
          children: [_SessionFields(session: s)],
        );
      },
    );
  }
}

class _SessionFields extends StatelessWidget {
  const _SessionFields({required this.session});
  final Map<String, dynamic> session;

  @override
  Widget build(BuildContext context) {
    final fields = session['captured_fields'] as Map<String, dynamic>? ??
        session['fields'] as Map<String, dynamic>? ??
        {};
    if (fields.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 16),
        child: Text('Sin campos capturados',
            style: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: AppColors.ctText3)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: fields.entries
            .map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${e.key}: ',
                          style: AppTextStyles.formLabel),
                      Expanded(
                        child: Text(e.value.toString(),
                            style: AppTextStyles.navItem),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

// ── Document viewer ────────────────────────────────────────────────────────────

void _openDocumentViewer(BuildContext context, String url) {
  final isImage = RegExp(
    r'\.(jpg|jpeg|png|webp|gif)(\?|$)',
    caseSensitive: false,
  ).hasMatch(url);

  showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: AppColors.ctSurface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 620),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
              decoration: const BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: AppColors.ctBorder)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Documento',
                        style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist', fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        size: 18, color: AppColors.ctText3),
                    onPressed: () => Navigator.pop(ctx),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: isImage
                    ? InteractiveViewer(
                        child: Image.network(
                          url,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Center(
                            child: Icon(Icons.broken_image_outlined,
                                size: 48, color: AppColors.ctText3),
                          ),
                        ),
                      )
                    : _IframeView(url: url),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                border:
                    Border(top: BorderSide(color: AppColors.ctBorder)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Descargar',
                    variant: AppButtonVariant.outline,
                    size: AppButtonSize.sm,
                    prefixIcon: const Icon(Icons.download_outlined, size: 14, color: AppColors.ctInk700),
                    onPressed: () => html.window.open(url, '_blank'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _IframeView extends StatefulWidget {
  const _IframeView({required this.url});
  final String url;

  @override
  State<_IframeView> createState() => _IframeViewState();
}

class _IframeViewState extends State<_IframeView> {
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'doc-iframe-${DateTime.now().millisecondsSinceEpoch}';
    ui.platformViewRegistry.registerViewFactory(_viewId, (int id) {
      // ignore: avoid_web_libraries_in_flutter, deprecated_member_use
      return html.IFrameElement()
        ..src = widget.url
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewId);
  }
}

// ── Custom field read-only row ─────────────────────────────────────────────────

class _CustomFieldReadRow extends StatelessWidget {
  const _CustomFieldReadRow({required this.field});
  final Map<String, dynamic> field;

  @override
  Widget build(BuildContext context) {
    final label =
        field['label'] as String? ?? field['field_key'] as String? ?? '—';
    final type = field['field_type'] as String? ?? 'text';
    final value = field['value'];

    final Widget valueWidget;
    if (value == null) {
      valueWidget = Text('—',
          style: AppTextStyles.body.copyWith(fontSize: 14));
    } else if (type == 'boolean') {
      final boolVal =
          value == true || value == 'true' || value == 1;
      valueWidget = Text(boolVal ? 'Sí' : 'No',
          style: AppTextStyles.body.copyWith(fontSize: 14));
    } else if (type == 'photo') {
      final url = value.toString();
      valueWidget = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const SizedBox(
            width: 80,
            height: 80,
            child: Icon(Icons.broken_image_outlined,
                color: AppColors.ctText3, size: 32),
          ),
        ),
      );
    } else if (type == 'document') {
      final url = value.toString();
      valueWidget = GestureDetector(
        onTap: () => _openDocumentViewer(context, url),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.ctSurface2,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.ctBorder2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.insert_drive_file_outlined,
                    size: 14, color: AppColors.ctTeal),
                const SizedBox(width: 6),
                Text('Ver documento',
                    style: AppTextStyles.bodySmall.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.ctTeal)),
              ],
            ),
          ),
        ),
      );
    } else {
      valueWidget = Text(value.toString(),
          style: AppTextStyles.body.copyWith(fontSize: 14));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(label),
          const SizedBox(height: 4),
          valueWidget,
        ],
      ),
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.confirmColor,
  });
  final String title;
  final String body;
  final String confirmLabel;
  final Color confirmColor;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.ctSurface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(title,
          style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist', fontSize: 16)),
      content: Text(body,
          style: AppTextStyles.body.copyWith(fontSize: 14, color: AppColors.ctText2)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancelar',
              style: AppTextStyles.btnSecondary.copyWith(color: AppColors.ctText2)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel,
              style: AppTextStyles.btnPrimary.copyWith(color: confirmColor)),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppTextStyles.kpiLabel.copyWith(letterSpacing: 0.6),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppTextStyles.bodySmall);
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(label),
          const SizedBox(height: 2),
          Text(value,
              style: AppTextStyles.body.copyWith(fontSize: 14)),
        ],
      ),
    );
  }
}
