import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/operator_roles_api.dart';
import '../../core/api/operators_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/screen_header.dart';
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

({String label, Color bg, Color fg}) _statusStyle(String? status) {
  switch (status) {
    case 'active':
      return (
        label: 'Activo',
        bg: AppColors.ctOkBg,
        fg: AppColors.ctOkText
      );
    case 'incident':
      return (
        label: 'Incidencia',
        bg: AppColors.ctRedBg,
        fg: AppColors.ctRedText
      );
    case 'suspended':
      return (
        label: 'Suspendido',
        bg: AppColors.ctSurface2,
        fg: AppColors.ctText2
      );
    default:
      return (
        label: 'Sin inicio',
        bg: AppColors.ctSurface2,
        fg: AppColors.ctText2
      );
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
  const _ActionBar({required this.onAdd, required this.canManage});
  final VoidCallback onAdd;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return ScreenHeader(
      title: 'Operadores',
      subtitle: 'Gestiona los operadores y sus permisos de acceso',
      actions: [
        if (canManage) _PrimaryButton(label: '+ Agregar operador', onTap: onAdd),
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
  String _filterFlow = 'Todos';
  String _filterRole = 'Todos';

  static const _statusOptions = [
    'Todos',
    'Activo',
    'Incidencia',
    'Sin inicio',
    'Suspendido',
  ];

  static const _flowOptions = [
    'Todos',
    'Flujo 1 · Turno',
    'Flujo 2 · Registros',
    'Flujo 3 · Incidencias',
  ];

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
      final st = _statusStyle(status);
      final matchStatus =
          _filterStatus == 'Todos' || st.label == _filterStatus;

      final flows = (op['flows'] as List? ?? [])
          .whereType<Map>()
          .toList();
      final matchFlow = _filterFlow == 'Todos' ||
          flows.any((f) => _filterFlow.startsWith(f['name'] as String? ?? ''));

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

      return matchSearch && matchStatus && matchFlow && matchRole;
    }).toList();
  }

  static const _headerStyle = TextStyle(
    fontFamily: 'Geist',
    fontSize: 10,
    fontWeight: FontWeight.w600,
    color: AppColors.ctText2,
    letterSpacing: 0.4,
  );

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filtros
        Row(
          children: [
            Expanded(
              child: _SearchField(
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            const SizedBox(width: 10),
            _FilterDropdown(
              width: 180,
              value: _filterStatus,
              options: _statusOptions,
              onChanged: (v) => setState(() => _filterStatus = v),
            ),
            const SizedBox(width: 10),
            _FilterDropdown(
              width: 200,
              value: _filterFlow,
              options: _flowOptions,
              onChanged: (v) => setState(() => _filterFlow = v),
            ),
            const SizedBox(width: 10),
            _FilterDropdown(
              width: 170,
              value: _filterRole,
              options: [
                'Todos',
                ...widget.roles
                    .map((r) => r['label'] as String? ?? '')
                    .where((s) => s.isNotEmpty),
              ],
              onChanged: (v) => setState(() => _filterRole = v),
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
                child: const Row(
                  children: [
                    Expanded(
                        flex: 3,
                        child:
                            Text('OPERADOR', style: _headerStyle)),
                    Expanded(
                        flex: 2,
                        child:
                            Text('TELÉFONO', style: _headerStyle)),
                    Expanded(
                        flex: 1,
                        child: Text('ESTADO', style: _headerStyle)),
                    Expanded(
                        flex: 2,
                        child: Text('ROL', style: _headerStyle)),
                    Expanded(
                        flex: 2,
                        child: Text('ÚLTIMO ACCESO',
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
    required this.onRefresh,
    required this.canManage,
    this.onOperatorMetadataUpdated,
  });
  final Map<String, dynamic> op;
  final List<Map<String, dynamic>> roles;
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
    final verified = op['whatsapp_verified'] as bool? ?? false;
    final flows = (op['flows'] as List? ?? []).map((f) {
      if (f is Map) return Map<String, dynamic>.from(f);
      // Backend may return plain UUID strings instead of objects
      return <String, dynamic>{'id': f.toString()};
    }).toList();
    final lastEventAt = op['last_event_at'] as String?;
    final id = op['id'] as String? ?? '';
    final st = _statusStyle(status);
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
    _TelegramBadge? tgBadge;
    if (hasTelegramFlow && tgStatus != null && tgStatus != 'none') {
      final expired = tgStatus == 'expired' ||
          (tgStatus == 'pending' && _isTelegramExpired(tgExpiresAt));
      if (tgStatus == 'linked') {
        tgBadge = const _TelegramBadge(status: 'linked');
      } else if (expired) {
        tgBadge = const _TelegramBadge(status: 'expired');
      } else if (tgStatus == 'pending') {
        tgBadge = const _TelegramBadge(status: 'pending');
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
            // Operador: avatar + nombre + verificación (clic → ficha)
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
                            style: const TextStyle(
                              fontFamily: 'Geist',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ctTealDark,
                            ),
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
                          style: const TextStyle(
                            fontFamily: 'Geist',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ctText,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        if (verified)
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                size: 11,
                                color: AppColors.ctOk,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'WhatsApp verificado',
                                style: AppTextStyles.bodySmall,
                              ),
                            ],
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFEDD5),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Pendiente verificación',
                              style: TextStyle(
                                fontFamily: 'Geist',
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF9A3412),
                              ),
                            ),
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

            // Teléfono
            Expanded(
              flex: 2,
              child: Text(
                phone,
                style: AppTextStyles.body,
              ),
            ),

            // Estado
            Expanded(
              flex: 1,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _StatusBadge(
                  label: st.label,
                  bg: st.bg,
                  textColor: st.fg,
                ),
              ),
            ),

            // Rol
            Expanded(
              flex: 2,
              child: () {
                final roleIds =
                    (op['role_ids'] as List?)?.cast<String>() ?? [];
                if (roleIds.isEmpty) return const SizedBox.shrink();
                final matched = widget.roles.where(
                    (r) => r['id'] == roleIds.first).toList();
                if (matched.isNotEmpty) {
                  return _RoleBadge(role: matched.first);
                }
                return Text(
                  roleIds.first.length > 8
                      ? roleIds.first.substring(0, 8)
                      : roleIds.first,
                  style: AppFonts.geist(
                      fontSize: 11, color: AppColors.ctText2),
                );
              }(),
            ),

            // Último acceso
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
                        _ActionButton(
                          label: 'Editar',
                          color: AppColors.ctInfo,
                          onTap: () async {
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
                        const SizedBox(width: 6),
                        if (status == 'active' || status == 'incident')
                          _ActionButton(
                            label: 'Suspender',
                            color: AppColors.ctDanger,
                            onTap: () => _patchStatus(context, 'suspended'),
                          )
                        else
                          _ActionButton(
                            label: 'Reactivar',
                            color: AppColors.ctOk,
                            onTap: () => _patchStatus(context, 'active'),
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

// ── Widgets reutilizables (tabla) ─────────────────────────────────────────────
// OperatorFormDialog → widgets/operator_form_dialog.dart


class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      style: const TextStyle(
        fontFamily: 'Geist',
        fontSize: 13,
        color: AppColors.ctText,
      ),
      decoration: InputDecoration(
        hintText: 'Buscar por nombre o teléfono...',
        hintStyle: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 13,
          color: AppColors.ctText3,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 17,
          color: AppColors.ctText3,
        ),
        filled: true,
        fillColor: AppColors.ctSurface,
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

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.width,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final double width;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 40,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.ctSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.ctBorder2),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isDense: true,
            isExpanded: true,
            style: AppTextStyles.body,
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: AppColors.ctText3,
            ),
            items: options
                .map((o) =>
                    DropdownMenuItem(value: o, child: Text(o)))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.bg,
    required this.textColor,
  });
  final String label;
  final Color bg;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

class _TelegramBadge extends StatelessWidget {
  const _TelegramBadge({required this.status});
  // status: 'linked' | 'pending' | 'expired'
  final String status;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final String label;
    switch (status) {
      case 'linked':
        bg = AppColors.ctTealLight;
        fg = AppColors.ctTealDark;
        label = '✓ Telegram vinculado';
      case 'pending':
        bg = AppColors.ctWarnBg;
        fg = AppColors.ctWarnText;
        label = '⏳ Vinculación pendiente';
      default: // expired
        bg = AppColors.ctWarnBg;
        fg = AppColors.ctWarnText;
        label = '⚠ Invitación expirada';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Geist',
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

Color _parseColor(String hex) {
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  } catch (_) {
    return const Color(0xFF59E0CC);
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final Map<String, dynamic> role;

  @override
  Widget build(BuildContext context) {
    final label = role['label'] as String? ?? '—';
    final color = _parseColor(role['color'] as String? ?? '#59E0CC');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: AppFonts.geist(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.color,
    required this.onTap,
  });
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
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
          duration: const Duration(milliseconds: 100),
          padding:
              const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: _hovered
                ? widget.color.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _hovered
                  ? widget.color.withValues(alpha: 0.4)
                  : AppColors.ctBorder,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  const _PrimaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
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
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.ctTealDark
                : AppColors.ctTeal,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.label,
            style: AppTextStyles.tenantName.copyWith(color: AppColors.ctNavy),
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatefulWidget {
  const _GhostButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<_GhostButton> {
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
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.ctSurface2
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.ctBorder2),
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.ctText2,
            ),
          ),
        ),
      ),
    );
  }
}
