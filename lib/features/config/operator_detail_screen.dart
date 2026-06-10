// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui;

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/operator_fields_api.dart';
import '../../core/api/operator_roles_api.dart';
import '../../core/api/operators_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_format.dart';
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
import '../../shared/widgets/app_multi_select.dart';
import '../../shared/widgets/app_tag_chip.dart';
import 'utils/operator_image_upload.dart';
import 'widgets/phone_field_widget.dart';
import 'widgets/phone_secondary_widget.dart';

// ── Section keys ─────────────────────────────────────────────────────────────

enum SectionKey { personal, roles, preferredChannels, secondaryPhones, customFields }

// ── Helpers ───────────────────────────────────────────────────────────────────


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
  bool _uploadingAvatar = false;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _subscribeRealtime();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    if (_realtimeChannel != null) {
      Supabase.instance.client.removeChannel(_realtimeChannel!).ignore();
    }
    super.dispose();
  }

  // ── Realtime subscription ───────────────────────────────────────────────

  void _subscribeRealtime() {
    try {
      _realtimeChannel = Supabase.instance.client
          .channel('op_detail_${widget.operatorId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'operators',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: widget.operatorId,
            ),
            callback: _handleRealtimeUpdate,
          )
          .subscribe();
    } catch (e) {
      debugPrint('[Realtime] subscribe error: $e');
      _realtimeChannel = null;
    }
  }

  void _handleRealtimeUpdate(PostgresChangePayload payload) {
    if (!mounted || _op == null) return;
    final row = payload.newRecord;
    // Shallow merge — update _op with new values from the realtime payload.
    // NOTE: If a section is currently in edit mode, we do NOT overwrite its
    // fields here because the user's unsaved edits take visual priority.
    // The next save or cancel will reconcile with fresh data via onReload.
    setState(() {
      _op = {..._op!, ...row};
    });
  }

  // ── Avatar tap action ──────────────────────────────────────────────────

  Future<void> _onAvatarTap() async {
    if (_uploadingAvatar || _op == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    if (bytes.lengthInBytes > 10 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('La imagen excede 10MB'),
          backgroundColor: AppColors.ctDanger,
        ));
      }
      return;
    }

    setState(() => _uploadingAvatar = true);
    try {
      final url = await uploadOperatorImage(
        operatorId: widget.operatorId,
        bytes: bytes,
        extension: file.extension ?? 'jpg',
      );
      await OperatorsApi.updateOperator(
        dio: ref.read(apiClientProvider).dio,
        id: widget.operatorId,
        displayName: _op!['display_name'] as String? ?? _op!['name'] as String? ?? '',
        phone: _op!['phone'] as String? ?? '',
        roleIds: (_op!['role_ids'] as List?)?.cast<String>() ?? [],
        profilePictureUrl: url,
      );
      if (!mounted) return;
      setState(() {
        _op = {..._op!, 'profile_picture_url': url};
        _uploadingAvatar = false;
      });
      ref.read(operatorListVersionProvider.notifier).state++;
    } catch (_) {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Error al subir la imagen'),
          backgroundColor: AppColors.ctDanger,
        ));
      }
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final op = await OperatorsApi.getOperator(widget.operatorId, dio: ref.read(apiClientProvider).dio);
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
      await OperatorsApi.patchStatus(dio: ref.read(apiClientProvider).dio, id: widget.operatorId, status: status);
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
          await ref.read(apiClientProvider).dio.delete('/operators/${widget.operatorId}');
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
        avatar: GestureDetector(
          onTap: canManage ? _onAvatarTap : null,
          child: MouseRegion(
            cursor: canManage ? SystemMouseCursors.click : SystemMouseCursors.basic,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (((op['profile_picture_url'] as String?) ?? '').isNotEmpty)
                  Image.network(
                    op['profile_picture_url'] as String,
                    fit: BoxFit.cover,
                    width: 40,
                    height: 40,
                  )
                else
                  const Icon(Icons.person_rounded, size: 22, color: AppColors.ctText2),
                if (_uploadingAvatar)
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
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

class _BannersSection extends ConsumerStatefulWidget {
  const _BannersSection({required this.op});
  final Map<String, dynamic> op;

  @override
  ConsumerState<_BannersSection> createState() => _BannersSectionState();
}

class _BannersSectionState extends ConsumerState<_BannersSection> {
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
        dio: ref.read(apiClientProvider).dio,
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

  // Roles
  List<Map<String, dynamic>> _availableRoles = [];

  // Telegram invite
  List<Map<String, dynamic>>? _availableTgChannels;
  String? _selectedTgChannelId;
  bool _sendingTgInvite = false;

  // ── Section-edit: Información personal ──────────────────────────────────
  bool _editingPersonal = false;
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _telegramChatIdCtrl;
  String _phoneE164 = '';
  String _phoneCountryIso = 'MX';
  String _phoneLocalNumber = '';
  String? _personalError;

  // ── Section-edit: Roles ─────────────────────────────────────────────────
  bool _editingRoles = false;
  List<String> _selectedRoleIds = [];
  String? _rolesError;

  // ── Section-edit: Canal preferido ───────────────────────────────────────
  bool _editingChannels = false;
  List<String> _editingChannelsOrder = [];
  String? _channelsError;

  // ── Section-edit: Contacto adicional ────────────────────────────────────
  bool _editingSecondaryPhones = false;
  List<Map<String, dynamic>> _editingSecondaryPhonesList = [];
  String? _secondaryPhonesError;

  // ── Section-edit: Campos personalizados ─────────────────────────────────
  bool _editingCustomFields = false;
  List<Map<String, dynamic>> _customFieldDefs = [];
  Map<String, dynamic> _editingCfValues = {};
  Map<String, TextEditingController> _cfControllers = {};
  Map<String, bool> _cfUploading = {};
  String? _customFieldsError;
  bool _cfDefsLoading = false;

  @override
  void initState() {
    super.initState();

    // Initialize personal section controllers
    final op = widget.op;
    _nameCtrl = TextEditingController(
      text: op['display_name'] as String? ?? op['name'] as String? ?? '',
    );
    _emailCtrl = TextEditingController(text: op['email'] as String? ?? '');
    final metadata = op['metadata'] as Map<String, dynamic>? ?? {};
    _telegramChatIdCtrl = TextEditingController(
      text: metadata['telegram_chat_id']?.toString() ?? '',
    );
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTypes();
      _loadRoles();
      _loadTelegramChannels();
      _loadCustomFieldDefs();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _telegramChatIdCtrl.dispose();
    for (final c in _cfControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _enterEditPersonal() {
    final op = widget.op;
    _nameCtrl.text = op['display_name'] as String? ?? op['name'] as String? ?? '';
    _emailCtrl.text = op['email'] as String? ?? '';
    final metadata = op['metadata'] as Map<String, dynamic>? ?? {};
    _telegramChatIdCtrl.text = metadata['telegram_chat_id']?.toString() ?? '';
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
    final telegramChatId = _telegramChatIdCtrl.text.trim();
    final id = widget.op['id'] as String? ?? '';

    try {
      await OperatorsApi.updateOperator(
        dio: ref.read(apiClientProvider).dio,
        id: id,
        displayName: name,
        phone: phone,
        roleIds: (widget.op['role_ids'] as List?)?.cast<String>() ?? [],
        email: email.isNotEmpty ? email : null,
        telegramChatId: telegramChatId.isNotEmpty ? telegramChatId : null,
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

  // ── Section-edit: Roles methods ─────────────────────────────────────────

  void _enterEditRoles() {
    setState(() {
      _selectedRoleIds = (widget.op['role_ids'] as List?)?.cast<String>() ?? [];
      _editingRoles = true;
      _rolesError = null;
    });
  }

  void _cancelEditRoles() {
    setState(() {
      _editingRoles = false;
      _rolesError = null;
    });
  }

  Future<void> _saveRoles() async {
    if (_selectedRoleIds.isEmpty) {
      setState(() => _rolesError = 'Selecciona al menos un rol');
      return;
    }
    final id = widget.op['id'] as String? ?? '';
    try {
      await OperatorsApi.patchRoleIds(dio: ref.read(apiClientProvider).dio, id: id, roleIds: _selectedRoleIds);
    } catch (e) {
      if (!mounted) return;
      String msg = 'Error al actualizar roles';
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
      setState(() => _rolesError = msg);
      rethrow;
    }
  }

  // ── Section-edit: Canal preferido methods ──────────────────────────────

  void _enterEditChannels() {
    setState(() {
      _editingChannelsOrder = List<String>.from(_orderedTypes);
      _editingChannels = true;
      _channelsError = null;
    });
  }

  void _cancelEditChannels() {
    setState(() {
      _editingChannels = false;
      _channelsError = null;
    });
  }

  Future<void> _saveChannels() async {
    final id = widget.op['id'] as String? ?? '';
    try {
      await OperatorsApi.patchPreferredChannelTypes(
        dio: ref.read(apiClientProvider).dio,
        id: id,
        types: _editingChannelsOrder,
      );
    } catch (e) {
      if (!mounted) return;
      String msg = 'Error al actualizar canal preferido';
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
      setState(() => _channelsError = msg);
      rethrow;
    }
  }

  // ── Section-edit: Contacto adicional methods ────────────────────────────

  void _enterEditSecondaryPhones() {
    final meta = widget.op['metadata'] as Map<String, dynamic>? ?? {};
    final existing = ((meta['phone_secondary'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    setState(() {
      _editingSecondaryPhonesList = existing;
      _editingSecondaryPhones = true;
      _secondaryPhonesError = null;
    });
  }

  void _cancelEditSecondaryPhones() {
    setState(() {
      _editingSecondaryPhones = false;
      _secondaryPhonesError = null;
    });
  }

  Future<void> _saveSecondaryPhones() async {
    final id = widget.op['id'] as String? ?? '';
    final op = widget.op;
    try {
      await OperatorsApi.updateOperator(
        dio: ref.read(apiClientProvider).dio,
        id: id,
        displayName: op['display_name'] as String? ?? op['name'] as String? ?? '',
        phone: op['phone'] as String? ?? '',
        roleIds: (op['role_ids'] as List?)?.cast<String>() ?? [],
        phoneSecondary: _editingSecondaryPhonesList,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _secondaryPhonesError = _extractErrorMsg(e));
      rethrow;
    }
  }

  // ── Section-edit: Campos personalizados methods ────────────────────────

  Future<void> _loadCustomFieldDefs() async {
    setState(() => _cfDefsLoading = true);
    try {
      final defs = await OperatorFieldsApi.getOperatorFields();
      if (mounted) setState(() { _customFieldDefs = defs; _cfDefsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _cfDefsLoading = false);
    }
  }

  void _enterEditCustomFields() {
    // Build initial values from current custom_fields list
    final initMap = <String, dynamic>{};
    final rawCf = widget.op['custom_fields'];
    if (rawCf is List) {
      for (final cf in rawCf) {
        if (cf is Map) {
          final key = cf['field_key'] as String? ?? '';
          if (key.isNotEmpty) initMap[key] = cf['value'];
        }
      }
    }

    // Create controllers for text/number/date fields
    for (final c in _cfControllers.values) { c.dispose(); }
    final controllers = <String, TextEditingController>{};
    for (final def in _customFieldDefs) {
      final key = def['field_key'] as String? ?? '';
      final type = def['field_type'] as String? ?? 'text';
      if (['text', 'number', 'date'].contains(type)) {
        String displayVal = '';
        final initVal = initMap[key];
        if (initVal != null) {
          if (type == 'date') {
            try {
              final parts = initVal.toString().split('-');
              if (parts.length == 3) {
                displayVal = '${parts[2].padLeft(2, '0')}/${parts[1].padLeft(2, '0')}/${parts[0]}';
              }
            } catch (_) {
              displayVal = initVal.toString();
            }
          } else {
            displayVal = initVal.toString();
          }
        }
        controllers[key] = TextEditingController(text: displayVal);
      }
    }

    setState(() {
      _editingCfValues = Map<String, dynamic>.from(initMap);
      _cfControllers = controllers;
      _cfUploading = {};
      _editingCustomFields = true;
      _customFieldsError = null;
    });
  }

  void _cancelEditCustomFields() {
    setState(() {
      _editingCustomFields = false;
      _customFieldsError = null;
    });
  }

  Future<void> _saveCustomFields() async {
    // Validate required fields
    for (final def in _customFieldDefs) {
      final key = def['field_key'] as String? ?? '';
      final isRequired = def['required'] as bool? ?? false;
      final type = def['field_type'] as String? ?? 'text';
      if (!isRequired || type == 'boolean') continue;
      dynamic val;
      if (['text', 'number', 'date'].contains(type)) {
        val = _cfControllers[key]?.text.trim();
      } else {
        val = _editingCfValues[key];
      }
      if (val == null || val.toString().isEmpty) {
        setState(() => _customFieldsError = '${def['label'] ?? key} es requerido');
        return;
      }
    }

    // Collect values
    final values = <String, dynamic>{};
    for (final def in _customFieldDefs) {
      final key = def['field_key'] as String? ?? '';
      final type = def['field_type'] as String? ?? 'text';
      dynamic val;
      if (type == 'date') {
        final text = _cfControllers[key]?.text.trim() ?? '';
        if (text.isNotEmpty) {
          try {
            final parts = text.split('/');
            if (parts.length == 3) {
              val = '${parts[2]}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}';
            }
          } catch (_) {}
        }
      } else if (type == 'text' || type == 'number') {
        final text = _cfControllers[key]?.text.trim() ?? '';
        if (text.isNotEmpty) val = text;
      } else {
        val = _editingCfValues[key];
      }
      if (val != null) values[key] = val;
    }

    final id = widget.op['id'] as String? ?? '';
    final op = widget.op;
    try {
      await OperatorsApi.updateOperator(
        dio: ref.read(apiClientProvider).dio,
        id: id,
        displayName: op['display_name'] as String? ?? op['name'] as String? ?? '',
        phone: op['phone'] as String? ?? '',
        roleIds: (op['role_ids'] as List?)?.cast<String>() ?? [],
        customFieldValues: values.isNotEmpty ? values : null,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _customFieldsError = _extractErrorMsg(e));
      rethrow;
    }
  }

  Future<void> _pickCfFile(String fieldKey, {required bool isPhoto}) async {
    if (_cfUploading[fieldKey] == true) return;
    final result = await FilePicker.platform.pickFiles(
      type: isPhoto ? FileType.custom : FileType.any,
      allowedExtensions: isPhoto ? ['jpg', 'jpeg', 'png'] : null,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    if (bytes.lengthInBytes > 10 * 1024 * 1024) {
      setState(() => _customFieldsError = 'El archivo excede 10MB');
      return;
    }
    setState(() { _cfUploading[fieldKey] = true; _customFieldsError = null; });
    try {
      final operatorId = widget.op['id'] as String? ?? '';
      final url = isPhoto
          ? await uploadOperatorImage(
              operatorId: operatorId, bytes: bytes,
              extension: file.extension ?? 'jpg', subfolder: 'fields/$fieldKey')
          : await uploadOperatorFile(
              operatorId: operatorId, bytes: bytes,
              extension: file.extension ?? 'bin', subfolder: 'fields/$fieldKey');
      if (mounted) setState(() { _editingCfValues[fieldKey] = url; _cfUploading[fieldKey] = false; });
    } catch (_) {
      if (mounted) setState(() { _cfUploading[fieldKey] = false; _customFieldsError = 'No se pudo subir el archivo'; });
    }
  }

  List<String> _getCfChoices(Map<String, dynamic> def) {
    final raw = def['options'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is Map) {
      final choices = raw['choices'];
      if (choices is List) return choices.map((e) => e.toString()).toList();
    }
    return [];
  }

  Widget _buildCfEditInput(Map<String, dynamic> def) {
    final key = def['field_key'] as String? ?? '';
    final label = def['label'] as String? ?? key;
    final type = def['field_type'] as String? ?? 'text';
    final isRequired = def['required'] as bool? ?? false;
    final displayLabel = '$label${isRequired ? ' *' : ''}';

    Widget input;
    switch (type) {
      case 'boolean':
        final boolVal = _editingCfValues[key] == true || _editingCfValues[key].toString() == 'true';
        input = Switch(
          value: boolVal,
          activeTrackColor: AppColors.ctTeal,
          activeThumbColor: AppColors.ctNavy,
          onChanged: (v) => setState(() => _editingCfValues[key] = v),
        );
      case 'select':
        final choices = _getCfChoices(def);
        final current = _editingCfValues[key] as String?;
        input = AppDropdown<String>(
          value: choices.contains(current) ? current : null,
          hint: 'Seleccionar',
          items: choices.map((c) => AppDropdownItem(value: c, label: c)).toList(),
          onChanged: (v) => setState(() => _editingCfValues[key] = v),
        );
      case 'date':
        final ctrl = _cfControllers[key];
        if (ctrl == null) { input = const SizedBox.shrink(); break; }
        input = GestureDetector(
          onTap: () async {
            DateTime? initial;
            try {
              final parts = ctrl.text.split('/');
              if (parts.length == 3) {
                initial = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
              }
            } catch (_) {}
            final picked = await showDatePicker(
              context: context,
              initialDate: initial ?? DateTime.now(),
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
            );
            if (picked != null && mounted) {
              setState(() {
                ctrl.text = '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
              });
            }
          },
          child: AbsorbPointer(
            child: TextField(
              controller: ctrl,
              readOnly: true,
              style: AppTextStyles.body,
              decoration: InputDecoration(
                hintText: 'dd/mm/aaaa',
                hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                filled: true, fillColor: AppColors.ctSurface2,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.ctBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.ctBorder)),
                suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.ctText2),
              ),
            ),
          ),
        );
      case 'photo':
        final url = _editingCfValues[key] as String?;
        final uploading = _cfUploading[key] ?? false;
        input = GestureDetector(
          onTap: uploading ? null : () => _pickCfFile(key, isPhoto: true),
          child: Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppColors.ctSurface2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.ctBorder),
            ),
            child: uploading
                ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : (url != null && url.isNotEmpty)
                    ? ClipRRect(borderRadius: BorderRadius.circular(7), child: Image.network(url, fit: BoxFit.cover))
                    : const Icon(Icons.add_photo_alternate_outlined, size: 28, color: AppColors.ctText3),
          ),
        );
      case 'document':
        final docUrl = _editingCfValues[key] as String?;
        final uploading = _cfUploading[key] ?? false;
        final hasDoc = docUrl != null && docUrl.isNotEmpty;
        input = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasDoc)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  const Icon(Icons.insert_drive_file_outlined, size: 14, color: AppColors.ctTeal),
                  const SizedBox(width: 6),
                  const Expanded(child: Text('Documento subido', style: AppTextStyles.navItem)),
                  GestureDetector(onTap: () => setState(() => _editingCfValues[key] = null),
                    child: const Icon(Icons.close, size: 14, color: AppColors.ctText3)),
                ]),
              ),
            if (uploading)
              const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
            else
              AppButton(
                label: hasDoc ? 'Cambiar documento' : 'Subir documento',
                onPressed: () => _pickCfFile(key, isPhoto: false),
                variant: AppButtonVariant.outline, size: AppButtonSize.sm,
                prefixIcon: const Icon(Icons.upload_file_outlined, size: 16),
              ),
          ],
        );
      default: // text, number
        final ctrl = _cfControllers[key];
        if (ctrl == null) { input = const SizedBox.shrink(); break; }
        input = TextField(
          controller: ctrl,
          style: AppTextStyles.body,
          keyboardType: type == 'number' ? TextInputType.number : null,
          decoration: InputDecoration(
            hintText: label, hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
            filled: true, fillColor: AppColors.ctSurface2,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.ctBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.ctBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.ctTeal)),
          ),
        );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(displayLabel),
          const SizedBox(height: 6),
          input,
        ],
      ),
    );
  }

  static String _extractErrorMsg(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        final detail = data['detail'];
        if (detail is Map && detail['message'] is String) return detail['message'] as String;
        if (detail is String && detail.isNotEmpty) return detail;
      }
    }
    return 'Error al guardar';
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
        case SectionKey.roles:
          _editingRoles = false;
          _rolesError = null;
        case SectionKey.preferredChannels:
          _editingChannels = false;
          _channelsError = null;
          _orderedTypes = List<String>.from(_editingChannelsOrder);
        case SectionKey.secondaryPhones:
          _editingSecondaryPhones = false;
          _secondaryPhonesError = null;
        case SectionKey.customFields:
          _editingCustomFields = false;
          _customFieldsError = null;
      }
    });
  }

  Future<void> _loadTelegramChannels() async {
    final operatorId = widget.op['id'] as String? ?? '';
    if (operatorId.isEmpty) return;
    try {
      final channels = await OperatorsApi.getAvailableTelegramChannels(operatorId, dio: ref.read(apiClientProvider).dio);
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
        dio: ref.read(apiClientProvider).dio,
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
        dio: ref.read(apiClientProvider).dio,
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
                _FieldRow(
                  label: 'Telegram Chat ID',
                  value: tgChatId?.isNotEmpty == true ? tgChatId! : '—',
                ),
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
                const SizedBox(height: 12),
                const _FieldLabel('Telegram Chat ID'),
                const SizedBox(height: 4),
                TextField(
                  controller: _telegramChatIdCtrl,
                  style: AppTextStyles.body,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.ctSurface2,
                    hintText: '123456789',
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
                            dio: ref.read(apiClientProvider).dio,
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

          // ── Sección: Contacto adicional (section-edit) ────────────
          const SizedBox(height: 24),
          AppEditableSection(
            title: 'Contacto adicional',
            isEditing: _editingSecondaryPhones,
            canEdit: canManage,
            onEdit: _enterEditSecondaryPhones,
            onCancel: _cancelEditSecondaryPhones,
            onSave: _saveSecondaryPhones,
            onSavedSuccessfully: () => _afterSectionSaved(SectionKey.secondaryPhones),
            errorText: _secondaryPhonesError,
            viewChild: phoneSecondary.isEmpty
                ? Text('Sin contactos adicionales',
                    style: AppTextStyles.body.copyWith(color: AppColors.ctText3))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: phoneSecondary.map((p) {
                      final lbl = p['label'] as String? ?? '—';
                      final ch = p['channel'] as String? ?? '';
                      final pPhone = p['phone'] as String? ?? '—';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _FieldRow(
                          label: lbl + (ch.isNotEmpty ? ' ($ch)' : ''),
                          value: pPhone,
                        ),
                      );
                    }).toList(),
                  ),
            editChild: PhoneSecondaryWidget(
              initial: _editingSecondaryPhonesList.isNotEmpty
                  ? _editingSecondaryPhonesList
                  : null,
              onChanged: (list) =>
                  setState(() => _editingSecondaryPhonesList = list),
            ),
          ),

          // ── Sección: Roles (section-edit) ──────────────────────────────
          const SizedBox(height: 24),
          AppEditableSection(
            title: 'Roles',
            isEditing: _editingRoles,
            canEdit: canManage,
            onEdit: _enterEditRoles,
            onCancel: _cancelEditRoles,
            onSave: _saveRoles,
            onSavedSuccessfully: () => _afterSectionSaved(SectionKey.roles),
            canSave: _selectedRoleIds.isNotEmpty,
            errorText: _rolesError,
            viewChild: Builder(builder: (_) {
              final roleIds = (op['role_ids'] as List?)?.cast<String>() ?? [];
              if (roleIds.isEmpty) {
                return Text('Sin roles asignados',
                    style: AppTextStyles.body.copyWith(color: AppColors.ctText3));
              }
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: roleIds.map((rid) {
                  final role = _availableRoles.firstWhere(
                    (r) => r['id'] == rid,
                    orElse: () => {'label': rid, 'color': '#59E0CC'},
                  );
                  return AppTagChip(
                    label: role['label'] as String? ?? rid,
                    colorHex: role['color'] as String?,
                  );
                }).toList(),
              );
            }),
            editChild: AppMultiSelect<String>(
              items: _availableRoles
                  .map((r) => AppMultiSelectItem(
                        value: r['id'] as String? ?? '',
                        label: r['label'] as String? ?? '—',
                      ))
                  .toList(),
              selectedValues: _selectedRoleIds,
              placeholder: 'Seleccionar roles...',
              searchable: true,
              onChanged: (vals) => setState(() {
                _selectedRoleIds = vals;
                _rolesError = null;
              }),
            ),
          ),

          // ── Sección: Canal preferido (section-edit) ────────────────────
          const SizedBox(height: 24),
          AppEditableSection(
            title: 'Canal preferido',
            isEditing: _editingChannels,
            canEdit: canManage && _orderedTypes.length > 1,
            onEdit: _enterEditChannels,
            onCancel: _cancelEditChannels,
            onSave: _saveChannels,
            onSavedSuccessfully: () => _afterSectionSaved(SectionKey.preferredChannels),
            errorText: _channelsError,
            viewChild: _loadingTypes
                ? const SizedBox(
                    height: 36,
                    child: Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.ctTeal),
                    ),
                  )
                : _orderedTypes.isEmpty
                    ? Text(
                        'Sin canales disponibles. Asigna flows al operador primero.',
                        style: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                      )
                    : _ChannelTypeOrderList(
                        types: _orderedTypes,
                        enabled: false,
                        onReorder: null,
                      ),
            editChild: _ChannelTypeOrderList(
              types: _editingChannelsOrder,
              enabled: true,
              onReorder: (newOrder) =>
                  setState(() => _editingChannelsOrder = newOrder),
            ),
          ),

          const SizedBox(height: 16),
          const _SectionTitle('Auditoría'),
          const SizedBox(height: 12),
          _FieldRow(label: 'Creado el',          value: fmtDateSlash(createdAt)),
          _FieldRow(label: 'Creado por',          value: createdBy),
          _FieldRow(label: 'Última modificación', value: fmtDateSlash(updatedAt)),
          _FieldRow(label: 'Modificado por',      value: updatedBy),

          // ── Sección: Campos personalizados (section-edit) ─────────────
          if (_customFieldDefs.isNotEmpty) ...[
            const SizedBox(height: 24),
            AppEditableSection(
              title: 'Campos personalizados',
              isEditing: _editingCustomFields,
              canEdit: canManage,
              onEdit: _enterEditCustomFields,
              onCancel: _cancelEditCustomFields,
              onSave: _saveCustomFields,
              onSavedSuccessfully: () => _afterSectionSaved(SectionKey.customFields),
              errorText: _customFieldsError,
              viewChild: Builder(builder: (_) {
                final rawCf = op['custom_fields'];
                final customFields = rawCf is List
                    ? rawCf.map((e) => Map<String, dynamic>.from(e as Map)).toList()
                    : <Map<String, dynamic>>[];
                if (customFields.isEmpty) {
                  return Text('Sin campos personalizados',
                      style: AppTextStyles.body.copyWith(color: AppColors.ctText3));
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: customFields.map((cf) => _CustomFieldReadRow(field: cf)).toList(),
                );
              }),
              editChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _customFieldDefs.map((def) => _buildCfEditInput(def)).toList(),
              ),
            ),
          ] else if (_cfDefsLoading) ...[
            const SizedBox(height: 24),
            const Center(child: SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ctTeal))),
          ],
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

class _HistorialTab extends ConsumerStatefulWidget {
  const _HistorialTab({required this.operatorId});
  final String operatorId;

  @override
  ConsumerState<_HistorialTab> createState() => _HistorialTabState();
}

class _HistorialTabState extends ConsumerState<_HistorialTab> {
  List<Map<String, dynamic>>? _sessions;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(apiClientProvider).dio
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
          subtitle: Text(fmtDateSlash(startedAt),
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

class _LinkUserDialog extends ConsumerStatefulWidget {
  const _LinkUserDialog({
    required this.operatorId,
    required this.onSuccess,
  });
  final String operatorId;
  final VoidCallback onSuccess;

  @override
  ConsumerState<_LinkUserDialog> createState() => _LinkUserDialogState();
}

class _LinkUserDialogState extends ConsumerState<_LinkUserDialog> {
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
        dio: ref.read(apiClientProvider).dio,
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
