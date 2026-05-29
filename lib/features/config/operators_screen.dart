import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/operator_roles_api.dart';
import '../../core/api/operators_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone_normalizer.dart';
import '../../shared/widgets/app_action_button.dart';
import '../../shared/widgets/app_badge.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_chip.dart';
import '../../shared/widgets/app_dropdown.dart';
import '../../shared/widgets/app_search_bar.dart';
import '../../shared/widgets/app_tag_chip.dart';
import '../../shared/widgets/screen_header.dart';
import 'widgets/import_operators_dialog.dart';
import 'widgets/operator_form_dialog.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

bool _isTelegramExpired(String? expiresAt) {
  if (expiresAt == null) return false;
  try {
    return DateTime.now().toUtc().isAfter(DateTime.parse(expiresAt).toUtc());
  } catch (_) {
    return false;
  }
}

String _initials(String name) {
  final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
}

String _formatLastEvent(String? iso) {
  if (iso == null) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours}h';
    if (diff.inDays == 1) return 'Ayer';
    return 'Hace ${diff.inDays} días';
  } catch (_) {
    return '—';
  }
}

({String label, AppBadgeVariant variant}) _statusBadgeInfo(String? status) {
  switch (status) {
    case 'active':
      return (label: 'Activo', variant: AppBadgeVariant.ok);
    default:
      return (label: 'Inactivo', variant: AppBadgeVariant.neutral);
  }
}

AppBadgeVariant _telegramBadgeVariant(String status) {
  switch (status) {
    case 'linked':
      return AppBadgeVariant.teal;
    case 'pending':
      return AppBadgeVariant.warn;
    default: // expired
      return AppBadgeVariant.warn;
  }
}

String _telegramBadgeLabel(String status) {
  switch (status) {
    case 'linked':
      return 'Telegram vinculado';
    case 'pending':
      return 'Vinculacion pendiente';
    default:
      return 'Invitacion expirada';
  }
}

// ── Pantalla ──────────────────────────────────────────────────────────────────

class OperatorsScreen extends ConsumerStatefulWidget {
  const OperatorsScreen({super.key});

  @override
  ConsumerState<OperatorsScreen> createState() => _OperatorsScreenState();
}

class _OperatorsScreenState extends ConsumerState<OperatorsScreen> {
  List<Map<String, dynamic>> _operators = [];
  List<Map<String, dynamic>> _roles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchOperators();
  }

  Future<void> _fetchOperators() async {
    setState(() => _loading = true);
    try {
      final tenantId = ref.read(activeTenantIdProvider);
      final results = await Future.wait([
        OperatorsApi.listOperators(),
        OperatorRolesApi.listRoles(tenantId: tenantId),
      ]);
      if (mounted) {
        setState(() {
          _operators = results[0];
          _roles = results[1];
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _updateOperatorMetadata(String operatorId, Map<String, dynamic> metadata) {
    setState(() {
      _operators = _operators.map((op) {
        if (op['id'] == operatorId) return {...op, 'metadata': metadata};
        return op;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Recarga operadores cuando cambia el tenant
    ref.listen<String>(activeTenantIdProvider, (prev, next) {
      if (prev != null && prev != next) _fetchOperators();
    });

    final canManage = hasPermission(ref, 'operators', 'manage');
    return Column(
      children: [
        _ActionBar(
          canManage: canManage,
          onAdd: () async {
            await showDialog(
              context: context,
              builder: (_) =>
                  OperatorFormDialog(onSaved: _fetchOperators),
            );
          },
          onImport: () {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => ImportOperatorsDialog(
                onSuccess: _fetchOperators,
              ),
            );
          },
        ),

        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: _OperatorsBody(
                    operators: _operators,
                    roles: _roles,
                    onRefresh: _fetchOperators,
                    canManage: canManage,
                    onOperatorMetadataUpdated: _updateOperatorMetadata,
                  ),
                ),
        ),
      ],
    );
  }
}

// ── Action bar ────────────────────────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.onAdd,
    required this.onImport,
    required this.canManage,
  });
  final VoidCallback onAdd;
  final VoidCallback onImport;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return ScreenHeader(
      title: 'Operadores',
      subtitle: 'Gestiona los operadores y sus permisos de acceso',
      actions: [
        if (canManage) ...[
          AppButton(label: 'Importar', variant: AppButtonVariant.outline, size: AppButtonSize.sm, prefixIcon: const Icon(Icons.upload_file_rounded, size: 14, color: AppColors.ctInk700), onPressed: onImport),
          const SizedBox(width: 8),
          AppButton(label: '+ Agregar operador', variant: AppButtonVariant.teal, size: AppButtonSize.sm, onPressed: onAdd),
        ],
      ],
    );
  }
}

// ── Cuerpo ────────────────────────────────────────────────────────────────────

class _OperatorsBody extends StatefulWidget {
  const _OperatorsBody({
    required this.operators,
    required this.roles,
    required this.onRefresh,
    required this.canManage,
    this.onOperatorMetadataUpdated,
  });
  final List<Map<String, dynamic>> operators;
  final List<Map<String, dynamic>> roles;
  final VoidCallback onRefresh;
  final bool canManage;
  final void Function(String id, Map<String, dynamic> metadata)?
      onOperatorMetadataUpdated;

  @override
  State<_OperatorsBody> createState() => _OperatorsBodyState();
}

class _OperatorsBodyState extends State<_OperatorsBody> {
  String _search = '';
  String _filterStatus = 'Todos';
  String _filterRole = 'Todos';

  static const _statusOptions = [
    'Todos',
    'Activo',
    'Inactivo',
  ];

  // TODO(DT): cleanup stats data source si nadie más lo consume
  // int get _kpiActivos =>
  //     widget.operators.where((o) => o['db_status'] == 'active').length;
  // int get _kpiSinInicio =>
  //     widget.operators.where((o) => o['last_inbound_at'] == null).length;
  // int get _kpiIncidencia =>
  //     widget.operators.where((o) => o['computed_status'] == 'incident').length;
  // int get _kpiTelegramPendiente =>
  //     widget.operators.where((o) => o['telegram_link_status'] == 'pending').length;

  // ── Filtrado ──

  List<Map<String, dynamic>> get _filtered {
    return widget.operators.where((op) {
      final name = op['display_name'] as String? ??
          op['name'] as String? ?? '';
      final phone = op['phone'] as String? ?? '';
      final q = _search.toLowerCase();
      final matchSearch = q.isEmpty ||
          name.toLowerCase().contains(q) ||
          phone.contains(q);

      final status = op['status'] as String?;
      final st = _statusBadgeInfo(status);
      final matchStatus =
          _filterStatus == 'Todos' || st.label == _filterStatus;

      bool matchRole = true;
      if (_filterRole != 'Todos') {
        final role = widget.roles.firstWhere(
          (r) => r['label'] == _filterRole,
          orElse: () => {},
        );
        if (role.isEmpty) {
          matchRole = false;
        } else {
          final roleId = role['id'] as String?;
          final roleIds =
              (op['role_ids'] as List?)?.cast<String>() ?? [];
          matchRole = roleIds.contains(roleId);
        }
      }

      return matchSearch && matchStatus && matchRole;
    }).toList();
  }

  static TextStyle get _headerStyle =>
      AppTextStyles.kpiLabel.copyWith(letterSpacing: 0.4);

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final rolesById = {
      for (final r in widget.roles)
        if (r['id'] is String) r['id'] as String: r,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filtros
        Row(
          children: [
            Expanded(
              child: AppSearchBar(
                hint: 'Buscar por nombre o telefono...',
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            const SizedBox(width: 12),
            ..._statusOptions.map((opt) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: AppChip(
                label: opt,
                isActive: _filterStatus == opt,
                onTap: () => setState(() => _filterStatus = opt),
              ),
            )),
            const SizedBox(width: 6),
            SizedBox(
              width: 170,
              child: AppDropdown<String>(
                value: _filterRole,
                hint: 'Rol',
                items: [
                  const AppDropdownItem(value: 'Todos', label: 'Todos los roles'),
                  ...widget.roles
                      .map((r) => r['label'] as String? ?? '')
                      .where((s) => s.isNotEmpty)
                      .map((s) => AppDropdownItem(value: s, label: s)),
                ],
                onChanged: (v) => setState(() => _filterRole = v ?? 'Todos'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Tabla
        Container(
          decoration: BoxDecoration(
            color: AppColors.ctSurface,
            border: Border.all(color: AppColors.ctBorder),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  color: AppColors.ctSurface2,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(9),
                    topRight: Radius.circular(9),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                        flex: 3,
                        child:
                            Text('OPERADOR', style: _headerStyle)),
                    Expanded(
                        flex: 2,
                        child:
                            Text('TELEFONO', style: _headerStyle)),
                    Expanded(
                        flex: 1,
                        child: Text('ESTADO', style: _headerStyle)),
                    Expanded(
                        flex: 2,
                        child: Text('ROL', style: _headerStyle)),
                    Expanded(
                        flex: 2,
                        child: Text('ULTIMO ACCESO',
                            style: _headerStyle)),
                    Expanded(
                        flex: 2,
                        child:
                            Text('ACCIONES', style: _headerStyle)),
                  ],
                ),
              ),

              // Filas
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'Sin resultados para los filtros aplicados.',
                      style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                    ),
                  ),
                )
              else
                ...rows.asMap().entries.map((entry) {
                  final isLast = entry.key == rows.length - 1;
                  return Column(
                    children: [
                      _OperatorRow(
                        op: entry.value,
                        roles: widget.roles,
                        rolesById: rolesById,
                        onRefresh: widget.onRefresh,
                        canManage: widget.canManage,
                        onOperatorMetadataUpdated:
                            widget.onOperatorMetadataUpdated,
                      ),
                      if (!isLast)
                        const Divider(
                            height: 1, color: AppColors.ctBorder),
                    ],
                  );
                }),
            ],
          ),
        ),

        // Pie de tabla
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            '${rows.length} de ${widget.operators.length} operadores',
            style: AppTextStyles.navItem,
          ),
        ),
      ],
    );
  }
}

// ── Fila de operador ──────────────────────────────────────────────────────────

class _OperatorRow extends StatefulWidget {
  const _OperatorRow({
    required this.op,
    required this.roles,
    required this.rolesById,
    required this.onRefresh,
    required this.canManage,
    this.onOperatorMetadataUpdated,
  });
  final Map<String, dynamic> op;
  final List<Map<String, dynamic>> roles;
  final Map<String, Map<String, dynamic>> rolesById;
  final VoidCallback onRefresh;
  final bool canManage;
  final void Function(String id, Map<String, dynamic> metadata)?
      onOperatorMetadataUpdated;

  @override
  State<_OperatorRow> createState() => _OperatorRowState();
}

class _OperatorRowState extends State<_OperatorRow> {
  bool _hovered = false;

  Future<void> _patchStatus(BuildContext ctx, String status) async {
    final id = widget.op['id'] as String? ?? '';
    if (id.isEmpty) return;
    final messenger = ScaffoldMessenger.of(ctx);
    try {
      await OperatorsApi.patchStatus(id: id, status: status);
      widget.onRefresh();
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Error al cambiar el estado'),
            backgroundColor: AppColors.ctDanger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final op = widget.op;
    final name = op['display_name'] as String? ??
        op['name'] as String? ?? '—';
    final phone = op['phone'] as String? ?? '—';
    final status = op['status'] as String?;
    final flows = (op['flows'] as List? ?? []).map((f) {
      if (f is Map) return Map<String, dynamic>.from(f);
      return <String, dynamic>{'id': f.toString()};
    }).toList();
    final lastEventAt = op['last_event_at'] as String?;
    final id = op['id'] as String? ?? '';
    final st = _statusBadgeInfo(status);
    final metadata = op['metadata'] as Map<String, dynamic>? ?? {};
    final profilePictureUrl = op['profile_picture_url'] as String?;
    final email = op['email'] as String?;
    final nationality = op['nationality'] as String?;
    final identityNumber = op['identity_number'] as String?;
    final tgStatus = metadata['telegram_link_status'] as String?;
    final tgExpiresAt = metadata['telegram_link_expires_at'] as String?;
    final hasTelegramFlow = flows.any((f) {
      final types = f['channel_types'];
      return types is List && types.contains('telegram');
    });
    Widget? tgBadge;
    if (hasTelegramFlow && tgStatus != null && tgStatus != 'none') {
      final expired = tgStatus == 'expired' ||
          (tgStatus == 'pending' && _isTelegramExpired(tgExpiresAt));
      final effectiveStatus = expired ? 'expired' : tgStatus;
      if (effectiveStatus == 'linked' ||
          effectiveStatus == 'pending' ||
          effectiveStatus == 'expired') {
        tgBadge = AppBadge(
          label: _telegramBadgeLabel(effectiveStatus),
          variant: _telegramBadgeVariant(effectiveStatus),
          prefixIcon: const Icon(Icons.telegram, size: 12),
        );
      }
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        color: _hovered ? AppColors.ctBg : AppColors.ctSurface,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Operador: avatar + nombre + badge telegram
            Expanded(
              flex: 3,
              child: GestureDetector(
                onTap: id.isNotEmpty ? () => context.go('/operators/$id') : null,
                child: Row(
                children: [
                  (profilePictureUrl != null && profilePictureUrl.isNotEmpty)
                      ? CircleAvatar(
                          radius: 16,
                          backgroundImage: NetworkImage(profilePictureUrl),
                          backgroundColor: AppColors.ctSurface2,
                        )
                      : Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            color: AppColors.ctTealLight,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _initials(name),
                            style: AppTextStyles.bodySmall.copyWith(
                              fontWeight: FontWeight.w700, color: AppColors.ctTealDark),
                          ),
                        ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (tgBadge != null) ...[
                          const SizedBox(height: 3),
                          tgBadge,
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              ),
            ),

            // Telefono
            Expanded(
              flex: 2,
              child: Text(
                PhoneNormalizer.formatForDisplay(op['phone'] as String?),
                style: AppTextStyles.body,
              ),
            ),

            // Estado
            Expanded(
              flex: 1,
              child: Align(
                alignment: Alignment.centerLeft,
                child: AppBadge(
                  label: st.label,
                  variant: st.variant,
                ),
              ),
            ),

            // Rol
            Expanded(
              flex: 2,
              child: _OperatorRolesCell(
                op: op,
                rolesById: widget.rolesById,
              ),
            ),

            // Ultimo acceso
            Expanded(
              flex: 2,
              child: Text(
                _formatLastEvent(lastEventAt),
                style: AppTextStyles.navItem,
              ),
            ),

            // Acciones
            Expanded(
              flex: 2,
              child: widget.canManage
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppActionButton(
                          variant: AppActionVariant.edit,
                          onPressed: () async {
                            await showDialog(
                              context: context,
                              builder: (_) => OperatorFormDialog(
                                operatorId: id,
                                initialName: name,
                                initialPhone: phone,
                                initialRoleIds: (op['role_ids'] as List?)?.cast<String>() ?? [],
                                initialTelegramChatId: metadata['telegram_chat_id'] as String?,
                                initialMetadata: metadata,
                                initialEmail: email,
                                initialNationality: nationality,
                                initialIdentityNumber: identityNumber,
                                initialProfilePictureUrl: profilePictureUrl,
                                onSaved: widget.onRefresh,
                                onOperatorMetadataUpdated:
                                    widget.onOperatorMetadataUpdated,
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 4),
                        if (status == 'active')
                          AppActionButton(
                            variant: AppActionVariant.suspend,
                            tooltipOverride: 'Desactivar',
                            onPressed: () => _patchStatus(context, 'inactive'),
                          )
                        else
                          AppActionButton(
                            variant: AppActionVariant.reactivate,
                            tooltipOverride: 'Activar',
                            onPressed: () => _patchStatus(context, 'active'),
                          ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Widgets de tabla ──────────────────────────────────────────────────────────

class _OperatorRolesCell extends StatelessWidget {
  const _OperatorRolesCell({
    required this.op,
    required this.rolesById,
  });
  final Map<String, dynamic> op;
  final Map<String, Map<String, dynamic>> rolesById;

  @override
  Widget build(BuildContext context) {
    final roleIds = (op['role_ids'] as List?)?.cast<String>() ?? [];
    final matched = roleIds
        .where((id) => rolesById.containsKey(id))
        .map((id) => rolesById[id]!)
        .toList()
      ..sort((a, b) => (a['label'] as String? ?? '')
          .toLowerCase()
          .compareTo((b['label'] as String? ?? '').toLowerCase()));

    if (matched.isEmpty) {
      return Text('—', style: AppFonts.geist(fontSize: 11, color: AppColors.ctText2));
    }

    final visible = matched.take(2).toList();
    final overflow = matched.length - 2;

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final role in visible)
          AppTagChip(
            label: role['label'] as String? ?? '—',
            colorHex: role['color'] as String?,
          ),
        if (overflow > 0)
          Tooltip(
            message: matched
                .skip(2)
                .map((r) => r['label'] as String? ?? '—')
                .join('\n'),
            decoration: BoxDecoration(
              color: AppColors.ctNavy,
              borderRadius: BorderRadius.circular(6),
            ),
            textStyle: AppTextStyles.bodySmall.copyWith(color: Colors.white),
            child: AppTagChip(label: '+$overflow'),
          ),
      ],
    );
  }
}
