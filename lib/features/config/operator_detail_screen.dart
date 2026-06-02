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
import '../../core/utils/phone_normalizer.dart';
import '../../shared/widgets/app_action_button.dart';
import '../../shared/widgets/app_badge.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_confirm_dialog.dart';
import '../../shared/widgets/app_alert_banner.dart';
import '../../shared/widgets/app_detail_header.dart';
import '../../shared/widgets/app_dropdown.dart';
import '../../shared/widgets/app_editable_section.dart';
import 'widgets/phone_field_widget.dart';

// ── Section keys ─────────────────────────────────────────────────────────────

enum SectionKey { personal }

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
    _tabCtrl = TabController(length: 3, vsync: this);
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

    final ok = await AppConfirmDialog.show(
      context: context,
      title: '¿$label a $name?',
      body: consequence,
      confirmLabel: label,
      variant: isSuspend
          ? AppConfirmDialogVariant.danger
          : AppConfirmDialogVariant.normal,
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

    final step1 = await AppConfirmDialog.show(
      context: context,
      title: '¿Eliminar a $name?',
      body: 'Esta acción no se puede deshacer.',
      confirmLabel: 'Eliminar permanentemente',
      variant: AppConfirmDialogVariant.danger,
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
      ref.read(operatorListVersionProvider.notifier).state++;
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
          // ── Banners contextuales ──
          _BannersSection(op: op),

          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _DatosTab(op: op, onReload: _load),
                _FlujosTab(op: op, canManage: canManage),
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
              Tab(text: 'Historial'),
            ],
          ),
        ),
      );
}

// ── Banners contextuales ────────────────────────────────────────────────────

class _BannersSection extends StatefulWidget {
  const _BannersSection({required this.op});
  final Map<String, dynamic> op;

  @override
  State<_BannersSection> createState() => _BannersSectionState();
}

class _BannersSectionState extends State<_BannersSection> {
  bool _resending = false;

  String _fmtExpiry(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/${dt.year} $h:$min';
  }

  String? _firstTelegramChannelId() {
    // Check top-level channels first
    final channels = widget.op['channels'] as List?;
    if (channels != null) {
      for (final ch in channels) {
        if (ch is Map && ch['channel_type'] == 'telegram') {
          return ch['channel_id'] as String? ?? ch['id'] as String?;
        }
      }
    }
    // Fallback: check flow.channels (new shape)
    final flows = widget.op['flows'] as List?;
    if (flows == null) return null;
    for (final f in flows) {
      if (f is Map) {
        final flowChannels = f['channels'] as List?;
        if (flowChannels != null) {
          for (final ch in flowChannels) {
            if (ch is Map && ch['channel_type'] == 'telegram') {
              return ch['channel_id'] as String?;
            }
          }
        }
      }
    }
    return null;
  }

  Future<void> _resendTelegramInvite() async {
    final channelId = _firstTelegramChannelId();
    if (channelId == null) return;
    final operatorId = widget.op['id'] as String? ?? '';
    if (operatorId.isEmpty) return;

    setState(() => _resending = true);
    try {
      await OperatorsApi.sendTelegramInvite(
        operatorId: operatorId,
        channelId: channelId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Invitacion reenviada'),
          backgroundColor: AppColors.ctOk,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Error al reenviar la invitacion'),
          backgroundColor: AppColors.ctDanger,
        ));
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final banners = <Widget>[];

    // Banner incidencia
    final computedStatus = widget.op['computed_status'] as String?;
    if (computedStatus == 'incident') {
      banners.add(AppAlertBanner(
        variant: AppAlertBannerVariant.danger,
        title: 'Incidencia activa',
        message: 'Este operador tiene una escalacion abierta.',
        actions: [
          AppButton(
            label: 'Abrir torre de control',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: () => context.go('/escalaciones'),
          ),
        ],
      ));
    }

    // Banner Telegram
    final tgLinkStatus = widget.op['telegram_link_status'] as String?;
    if (tgLinkStatus == 'pending') {
      final meta = widget.op['metadata'] as Map<String, dynamic>? ?? {};
      final expiresAtRaw = meta['telegram_link_expires_at'] as String?;
      final expiresAt = expiresAtRaw != null
          ? DateTime.tryParse(expiresAtRaw)
          : null;
      final isExpired = expiresAt != null && expiresAt.isBefore(DateTime.now());

      final hasTgChannel = _firstTelegramChannelId() != null;

      if (!isExpired && expiresAt != null) {
        // Pending vigente
        banners.add(AppAlertBanner(
          variant: AppAlertBannerVariant.info,
          title: 'Invitacion de Telegram enviada',
          message:
              'El operador aun no completa la vinculacion. Expira el ${_fmtExpiry(expiresAt.toLocal())}.',
          actions: [
            hasTgChannel
                ? AppButton(
                    label: 'Reenviar invitacion',
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.sm,
                    isLoading: _resending,
                    onPressed: _resending ? () {} : _resendTelegramInvite,
                  )
                : Tooltip(
                    message: 'Sin canal Telegram configurado',
                    child: AppButton(
                      label: 'Reenviar invitacion',
                      variant: AppButtonVariant.ghost,
                      size: AppButtonSize.sm,
                      isDisabled: true,
                      onPressed: () {},
                    ),
                  ),
          ],
        ));
      } else {
        // Pending expirada o sin expires_at
        banners.add(AppAlertBanner(
          variant: AppAlertBannerVariant.warning,
          title: 'Invitacion de Telegram expirada',
          message:
              'El operador no podra recibir mensajes por Telegram hasta que reenvies el link.',
          actions: [
            hasTgChannel
                ? AppButton(
                    label: 'Reenviar invitacion',
                    variant: AppButtonVariant.teal,
                    size: AppButtonSize.sm,
                    prefixIcon: const Icon(Icons.send, size: 14),
                    isLoading: _resending,
                    onPressed: _resending ? () {} : _resendTelegramInvite,
                  )
                : Tooltip(
                    message: 'Sin canal Telegram configurado',
                    child: AppButton(
                      label: 'Reenviar invitacion',
                      variant: AppButtonVariant.teal,
                      size: AppButtonSize.sm,
                      isDisabled: true,
                      onPressed: () {},
                    ),
                  ),
          ],
        ));
      }
    }

    if (banners.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        children: [
          for (int i = 0; i < banners.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            banners[i],
          ],
        ],
      ),
    );
  }
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

  // Telegram invite
  List<Map<String, dynamic>>? _availableTgChannels;
  String? _selectedTgChannelId;
  bool _sendingTgInvite = false;

  // ── Section-edit: Información personal ──────────────────────────────────
  bool _editingPersonal = false;
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  String _phoneE164 = '';
  String _phoneCountryIso = 'MX';
  String _phoneLocalNumber = '';
  String? _personalError;

  @override
  void initState() {
    super.initState();

    // Initialize personal section controllers
    final op = widget.op;
    _nameCtrl = TextEditingController(
      text: op['display_name'] as String? ?? op['name'] as String? ?? '',
    );
    _emailCtrl = TextEditingController(text: op['email'] as String? ?? '');
    final rawPhone = op['phone'] as String? ?? '';
    if (rawPhone.isNotEmpty) {
      final (iso, local) = PhoneNormalizer.parsePhone(rawPhone);
      _phoneCountryIso = iso;
      _phoneLocalNumber = local;
      _phoneE164 = PhoneNormalizer.formatToE164(local, iso);
    }

    // Seed from persisted preferred_channel_types before API loads
    final raw = op['preferred_channel_types'];
    if (raw is List) {
      _orderedTypes = raw.map((e) => e.toString()).toList();
    }
    // Seed role from operator data
    final rawRoleIds = op['role_ids'];
    if (rawRoleIds is List && rawRoleIds.isNotEmpty) {
      _roleId = rawRoleIds.first?.toString();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTypes();
      _loadRoles();
      _loadTelegramChannels();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  void _enterEditPersonal() {
    final op = widget.op;
    _nameCtrl.text = op['display_name'] as String? ?? op['name'] as String? ?? '';
    _emailCtrl.text = op['email'] as String? ?? '';
    final rawPhone = op['phone'] as String? ?? '';
    if (rawPhone.isNotEmpty) {
      final (iso, local) = PhoneNormalizer.parsePhone(rawPhone);
      _phoneCountryIso = iso;
      _phoneLocalNumber = local;
      _phoneE164 = PhoneNormalizer.formatToE164(local, iso);
    }
    setState(() {
      _editingPersonal = true;
      _personalError = null;
    });
  }

  void _cancelEditPersonal() {
    setState(() {
      _editingPersonal = false;
      _personalError = null;
    });
  }

  Future<void> _savePersonal() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _personalError = 'Nombre obligatorio');
      return;
    }
    final phone = _phoneE164;
    if (phone.isEmpty) {
      setState(() => _personalError = 'Teléfono obligatorio');
      return;
    }
    final email = _emailCtrl.text.trim();
    final id = widget.op['id'] as String? ?? '';

    try {
      await OperatorsApi.updateOperator(
        id: id,
        displayName: name,
        phone: phone,
        roleIds: (widget.op['role_ids'] as List?)?.cast<String>() ?? [],
        email: email.isNotEmpty ? email : null,
      );
    } catch (e) {
      if (!mounted) return;
      String msg = 'Error al guardar';
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map) {
          final detail = data['detail'];
          if (detail is Map && detail['message'] is String) {
            msg = detail['message'] as String;
          } else if (detail is String && detail.isNotEmpty) {
            msg = detail;
          }
        }
      }
      setState(() => _personalError = msg);
      rethrow;
    }
  }

  // ── Shared post-save housekeeping ─────────────────────────────────────────

  void _afterSectionSaved(SectionKey key) {
    if (!mounted) return;
    widget.onReload();
    ref.read(operatorListVersionProvider.notifier).state++;
    setState(() {
      switch (key) {
        case SectionKey.personal:
          _editingPersonal = false;
          _personalError = null;
      }
    });
  }

  Future<void> _loadTelegramChannels() async {
    final operatorId = widget.op['id'] as String? ?? '';
    if (operatorId.isEmpty) return;
    try {
      final channels = await OperatorsApi.getAvailableTelegramChannels(operatorId);
      if (mounted) setState(() => _availableTgChannels = channels);
    } catch (_) {
      if (mounted) setState(() => _availableTgChannels = []);
    }
  }

  Future<void> _sendTelegramInvite(String channelId) async {
    final operatorId = widget.op['id'] as String? ?? '';
    if (operatorId.isEmpty) return;
    setState(() => _sendingTgInvite = true);
    try {
      await OperatorsApi.sendTelegramInvite(
        operatorId: operatorId,
        channelId: channelId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Invitacion enviada'),
          backgroundColor: AppColors.ctOk,
        ));
        widget.onReload();
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final status = e.response?.statusCode;
      final msg = status == 409
          ? 'Este operador ya tiene Telegram vinculado.'
          : 'Error al enviar la invitacion';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.ctDanger,
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Error al enviar la invitacion'),
        backgroundColor: AppColors.ctDanger,
      ));
    } finally {
      if (mounted) setState(() => _sendingTgInvite = false);
    }
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
          // ── Sección: Información personal (section-edit) ──────────
          AppEditableSection(
            title: 'Información personal',
            isEditing: _editingPersonal,
            canEdit: canManage,
            onEdit: _enterEditPersonal,
            onCancel: _cancelEditPersonal,
            onSave: _savePersonal,
            onSavedSuccessfully: () => _afterSectionSaved(SectionKey.personal),
            canSave: _nameCtrl.text.trim().isNotEmpty && _phoneE164.isNotEmpty,
            errorText: _personalError,
            viewChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FieldRow(label: 'Nombre completo', value: name),
                _FieldRow(label: 'Teléfono WhatsApp', value: phone),
                _FieldRow(label: 'Correo', value: email.isNotEmpty ? email : '—'),
              ],
            ),
            editChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FieldLabel('Nombre completo *'),
                const SizedBox(height: 4),
                TextField(
                  controller: _nameCtrl,
                  style: AppTextStyles.body,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.ctSurface2,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                      borderSide: const BorderSide(color: AppColors.ctTeal),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                PhoneFieldWidget(
                  label: 'Teléfono WhatsApp *',
                  initialCountryIso: _phoneCountryIso,
                  initialLocalNumber: _phoneLocalNumber,
                  onChanged: (e164) => setState(() => _phoneE164 = e164),
                ),
                const SizedBox(height: 12),
                const _FieldLabel('Correo electrónico'),
                const SizedBox(height: 4),
                TextField(
                  controller: _emailCtrl,
                  style: AppTextStyles.body,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.ctSurface2,
                    hintText: 'correo@ejemplo.com',
                    hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                      borderSide: const BorderSide(color: AppColors.ctTeal),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Sección: Identidad (read-only, ADR-367) ────────────────
          if (nationality.isNotEmpty || identityNumber.isNotEmpty) ...[
            const SizedBox(height: 24),
            AppEditableSection(
              title: 'Identidad',
              isEditing: false,
              canEdit: false,
              onSave: () async {},
              onCancel: () {},
              viewChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (nationality.isNotEmpty)
                    _FieldRow(label: 'Nacionalidad', value: nationality),
                  if (identityNumber.isNotEmpty)
                    _FieldRow(label: idLabel, value: identityNumber),
                ],
              ),
              editChild: const SizedBox.shrink(),
            ),
          ],

          const SizedBox(height: 24),
          // ── Telegram ──────────────────────────────────────────────
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
          // Telegram invite — only when status is 'none' (not linked, not pending)
          Builder(builder: (context) {
            final tgLinkStatus = op['telegram_link_status'] as String? ??
                (meta['telegram_link_status'] as String? ?? 'none');
            // linked → pill shown above; pending → banner shown above body
            if (tgLinkStatus != 'none') return const SizedBox.shrink();

            if (_availableTgChannels == null) {
              return const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  height: 24,
                  child: Center(
                    child: SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ctTeal),
                    ),
                  ),
                ),
              );
            }

            final channels = _availableTgChannels!;
            if (channels.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Sin canal Telegram disponible. Conecta uno desde Mis Workers.',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
                ),
              );
            }

            if (channels.length == 1) {
              final chId = channels[0]['channel_id'] as String? ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppButton(
                  label: 'Enviar invitacion Telegram',
                  variant: AppButtonVariant.teal,
                  size: AppButtonSize.sm,
                  prefixIcon: const Icon(Icons.send, size: 14),
                  isLoading: _sendingTgInvite,
                  onPressed: _sendingTgInvite ? () {} : () => _sendTelegramInvite(chId),
                ),
              );
            }

            // Multiple channels — dropdown + button
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 280,
                    child: AppDropdown<String>(
                      value: _selectedTgChannelId,
                      hint: 'Seleccionar canal Telegram',
                      items: channels.map((ch) {
                        final id = ch['channel_id'] as String? ?? '';
                        final bot = ch['bot_username'] as String? ?? '';
                        final worker = ch['worker_name'] as String? ?? '';
                        final label = worker.isNotEmpty
                            ? '$bot ($worker)'
                            : bot.isNotEmpty ? bot : id;
                        return AppDropdownItem(value: id, label: label);
                      }).toList(),
                      onChanged: (v) => setState(() => _selectedTgChannelId = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AppButton(
                    label: 'Enviar invitacion',
                    variant: AppButtonVariant.teal,
                    size: AppButtonSize.sm,
                    prefixIcon: const Icon(Icons.send, size: 14),
                    isLoading: _sendingTgInvite,
                    isDisabled: _selectedTgChannelId == null,
                    onPressed: _selectedTgChannelId != null && !_sendingTgInvite
                        ? () => _sendTelegramInvite(_selectedTgChannelId!)
                        : () {},
                  ),
                ],
              ),
            );
          }),
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
                showDialog(
                  context: context,
                  builder: (_) => _LinkUserDialog(
                    operatorId: op['id'] as String,
                    onSuccess: widget.onReload,
                  ),
                );
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
            .map((f) => _FlowCard(flow: f))
            .toList(),
      ),
    );
  }
}

class _FlowCard extends StatelessWidget {
  const _FlowCard({required this.flow});
  final Map<String, dynamic> flow;

  static ({IconData icon, Color color, String label}) _channelVisual(String type) {
    return switch (type) {
      'telegram' => (icon: Icons.telegram, color: AppColors.ctTg, label: 'Telegram'),
      'whatsapp' => (icon: Icons.chat_bubble_outline, color: AppColors.ctWa, label: 'WhatsApp'),
      'sms' => (icon: Icons.sms_outlined, color: AppColors.ctText2, label: 'SMS'),
      _ => (icon: Icons.router_rounded, color: AppColors.ctText3, label: type),
    };
  }

  @override
  Widget build(BuildContext context) {
    final name = flow['name'] as String? ?? flow['id'] as String? ?? '—';
    final workerName = flow['worker_name'] as String?;

    // Extract channel types from flow['channels'] (new shape)
    final flowChannels = (flow['channels'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final channelTypes = flowChannels
        .map((ch) => ch['channel_type'] as String? ?? '')
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();

    // Primary channel for icon (first one)
    final primary = channelTypes.isNotEmpty
        ? _channelVisual(channelTypes.first)
        : _channelVisual('');

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
          // Primary channel icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: primary.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(primary.icon, size: 16, color: primary.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: AppTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (workerName != null && workerName.isNotEmpty) ...[
                      Text(workerName, style: AppTextStyles.navItem),
                      if (channelTypes.isNotEmpty) ...[
                        Text(' · ', style: AppTextStyles.navItem),
                      ],
                    ],
                    // Channel type labels
                    ...channelTypes.map((t) {
                      final v = _channelVisual(t);
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(v.icon, size: 12, color: v.color),
                            const SizedBox(width: 3),
                            Text(v.label, style: AppTextStyles.navItem),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
        ],
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

// ── _LinkUserDialog ─────────────────────────────────────────────────────────

class _LinkUserDialog extends StatefulWidget {
  const _LinkUserDialog({
    required this.operatorId,
    required this.onSuccess,
  });
  final String operatorId;
  final VoidCallback onSuccess;

  @override
  State<_LinkUserDialog> createState() => _LinkUserDialogState();
}

class _LinkUserDialogState extends State<_LinkUserDialog> {
  final _phoneCtrl = TextEditingController();
  bool _loading = false;
  String? _fieldError;

  bool get _isValid {
    final cleaned = _phoneCtrl.text.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (!cleaned.startsWith('+')) return false;
    final digits = cleaned.substring(1);
    return digits.length >= 10 &&
        digits.length <= 15 &&
        RegExp(r'^\d+$').hasMatch(digits);
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isValid || _loading) return;
    setState(() {
      _loading = true;
      _fieldError = null;
    });

    final cleaned = _phoneCtrl.text.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    try {
      await OperatorsApi.linkToUser(
        operatorId: widget.operatorId,
        phone: cleaned,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSuccess();
    } on DioException catch (e) {
      if (!mounted) return;
      final status = e.response?.statusCode;
      final data = e.response?.data;
      final detail = data is Map ? data['detail'] : null;
      final code = detail is Map ? detail['code'] as String? : null;

      String? inline;
      if (status == 404 || code == 'USER_NOT_FOUND_BY_PHONE') {
        inline = 'No encontramos un usuario con ese teléfono';
      } else if (code == 'TENANT_USER_ALREADY_LINKED') {
        inline = 'Este usuario ya está vinculado a otro operador';
      } else if (code == 'OPERATOR_ALREADY_LINKED') {
        inline = 'Este operador ya está vinculado a otro usuario';
      }

      if (inline != null) {
        setState(() {
          _loading = false;
          _fieldError = inline;
        });
      } else {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Error al vincular. Intenta de nuevo.'),
          backgroundColor: AppColors.ctDanger,
        ));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Error al vincular. Intenta de nuevo.'),
        backgroundColor: AppColors.ctDanger,
      ));
    }
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
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vincular usuario de plataforma',
                style: AppTextStyles.body
                    .copyWith(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Ingresa el teléfono con el que el usuario inició sesión',
                style:
                    AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _phoneCtrl,
                autofocus: true,
                keyboardType: TextInputType.phone,
                style: AppTextStyles.body,
                onChanged: (_) => setState(() => _fieldError = null),
                decoration: InputDecoration(
                  labelText: 'Teléfono',
                  labelStyle: AppTextStyles.formLabel,
                  hintText: '+52 55 1234 5678',
                  hintStyle:
                      AppTextStyles.body.copyWith(color: AppColors.ctText3),
                  errorText: _fieldError,
                  errorStyle: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.ctDanger),
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
                    borderSide: BorderSide(
                      color: _fieldError != null
                          ? AppColors.ctDanger
                          : AppColors.ctBorder2,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: _fieldError != null
                          ? AppColors.ctDanger
                          : AppColors.ctTeal,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancelar',
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.sm,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  AppButton(
                    label: _loading ? 'Vinculando...' : 'Vincular',
                    variant: AppButtonVariant.teal,
                    size: AppButtonSize.sm,
                    isDisabled: !_isValid || _loading,
                    isLoading: _loading,
                    onPressed: _isValid ? _submit : () {},
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
