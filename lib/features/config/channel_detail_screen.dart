import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/api/api_client.dart';
import '../../core/api/channels_api.dart';
import '../../core/api/groups_api.dart';
import '../../core/api/iam_api.dart';
import '../../core/api/templates_api.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_badge.dart';
import '../../shared/widgets/app_button.dart';
import 'template_create_dialog.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _kChannelTypeConfig = {
  'whatsapp': (label: 'WhatsApp', bg: AppColors.ctOkBg,    fg: AppColors.ctWa),
  'telegram': (label: 'Telegram', bg: AppColors.ctInfoBg,  fg: AppColors.ctTg),
  'sms':      (label: 'SMS',      bg: AppColors.ctSurface2, fg: AppColors.ctText2),
};

const _kWaTabs = ['Información', 'Plantillas', 'Grupos'];
const _kTgTabs = ['Información', 'Grupos'];

// ── Helpers ───────────────────────────────────────────────────────────────────

String _dioError(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      final d = data['detail'];
      if (d != null) return 'Error: $d';
    }
    final s = e.response?.statusCode;
    if (s != null) return 'Error $s';
  }
  return e.toString();
}

String _formatDate(String iso) {
  const months = [
    '', 'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.day} de ${months[dt.month]} de ${dt.year}';
  } catch (_) {
    return '—';
  }
}

// ── Panel ─────────────────────────────────────────────────────────────────────

class ChannelDetailPanel extends ConsumerStatefulWidget {
  const ChannelDetailPanel({
    super.key,
    required this.channelId,
    required this.onBack,
  });
  final String channelId;
  final VoidCallback onBack;

  @override
  ConsumerState<ChannelDetailPanel> createState() =>
      _ChannelDetailPanelState();
}

class _ChannelDetailPanelState extends ConsumerState<ChannelDetailPanel>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _channel;
  bool    _loading  = true;
  String? _error;
  bool    _toggling = false;
  bool    _deleting = false;
  String  _tenantId = '';

  TabController? _tabCtrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(ChannelDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channelId != widget.channelId) _load();
  }

  @override
  void dispose() {
    _tabCtrl?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      _tenantId = ref.read(activeTenantIdProvider);
      final channel = await ChannelsApi.getChannel(dio: ref.read(apiClientProvider).dio, channelId: widget.channelId);
      if (!mounted) return;
      final isWa = (channel['channel_type'] as String? ?? '') == 'whatsapp';
      _tabCtrl?.dispose();
      _tabCtrl = TabController(
        length: isWa ? _kWaTabs.length : _kTgTabs.length,
        vsync: this,
      );
      setState(() {
        _channel = channel;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = _dioError(e); _loading = false; });
    }
  }

  bool get _isWhatsApp =>
      (_channel?['channel_type'] as String? ?? '') == 'whatsapp';

  Future<void> _toggleActive() async {
    final ch = _channel;
    if (ch == null) return;
    final current = ch['is_active'] as bool? ?? false;
    setState(() => _toggling = true);
    try {
      if (current) {
        final updated = await ChannelsApi.updateChannel(
          dio: ref.read(apiClientProvider).dio,
          channelId: widget.channelId,
          isActive: false,
        );
        if (!mounted) return;
        setState(() { _channel = updated; _toggling = false; });
      } else {
        await ChannelsApi.activateChannel(dio: ref.read(apiClientProvider).dio, channelId: widget.channelId);
        if (!mounted) return;
        await _load();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _toggling = false);
      _showError(_dioError(e));
    }
  }

  Future<void> _deleteChannel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteChannelDialog(
        channelName: _channel!['display_name'] as String? ?? '',
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      final tenantWorkerId =
          (_channel!['worker_id'] ?? _channel!['tenant_worker_id']) as String? ?? '';
      if (tenantWorkerId.isEmpty) {
        setState(() => _deleting = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo identificar el worker del canal'),
          backgroundColor: AppColors.ctDanger,
        ));
        return;
      }
      await ChannelsApi.deleteChannel(
        dio: ref.read(apiClientProvider).dio,
        tenantWorkerId: tenantWorkerId,
        channelId: widget.channelId,
      );
      if (!mounted) return;
      widget.onBack();
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_dioError(e)),
        backgroundColor: AppColors.ctDanger,
      ));
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: AppTextStyles.body),
        backgroundColor: AppColors.ctDanger,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: AppTextStyles.body),
        backgroundColor: AppColors.ctOk,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.ctTeal),
      );
    }
    if (_error != null) {
      return Center(
        child: Text(
          'Error: $_error',
          style: AppTextStyles.body.copyWith(color: AppColors.ctDanger),
        ),
      );
    }

    final ch = _channel!;
    final isActive = ch['is_active'] as bool? ?? true;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Zona izquierda — side panel fijo ──
        _ChannelSidePanel(
          channel: ch,
          isActive: isActive,
          toggling: _toggling,
          deleting: _deleting,
          onBack: widget.onBack,
          onToggle: _toggleActive,
          onDelete: _deleteChannel,
        ),
        // ── Divisor vertical ──
        Container(width: 1, color: AppColors.ctBorder),
        // ── Zona derecha — condicional por tipo ──
        Expanded(
          child: _isWhatsApp ? _buildWaContent(ch) : _buildTgContent(ch),
        ),
      ],
    );
  }

  Widget _buildWaContent(Map<String, dynamic> ch) {
    return Column(
      children: [
        Container(
          color: AppColors.ctSurface,
          child: Column(
            children: [
              const Divider(height: 1, color: AppColors.ctBorder),
              TabBar(
                controller: _tabCtrl!,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Colors.transparent,
                labelStyle:
                    AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                unselectedLabelStyle:
                    AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
                labelColor: AppColors.ctTeal,
                unselectedLabelColor: AppColors.ctText2,
                indicatorColor: AppColors.ctTeal,
                indicatorWeight: 2,
                tabs: [for (final t in _kWaTabs) Tab(text: t)],
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl!,
            children: [
              _InfoTab(
                channel: ch,
                dio: ref.read(apiClientProvider).dio,
                onUpdated: (updated) {
                  if (mounted) setState(() => _channel = updated);
                },
                onError: _showError,
                onSuccess: _showSuccess,
              ),
              _TemplatesTab(
                channelId: widget.channelId,
                tenantId: _tenantId,
                dio: ref.read(apiClientProvider).dio,
                onError: _showError,
                onSuccess: _showSuccess,
              ),
              _GroupsTab(
                channel: ch,
                onError: _showError,
                onSuccess: _showSuccess,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTgContent(Map<String, dynamic> ch) {
    return Column(
      children: [
        Container(
          color: AppColors.ctSurface,
          child: Column(
            children: [
              const Divider(height: 1, color: AppColors.ctBorder),
              TabBar(
                controller: _tabCtrl!,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Colors.transparent,
                labelStyle:
                    AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                unselectedLabelStyle:
                    AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
                labelColor: AppColors.ctTeal,
                unselectedLabelColor: AppColors.ctText2,
                indicatorColor: AppColors.ctTeal,
                indicatorWeight: 2,
                tabs: [for (final t in _kTgTabs) Tab(text: t)],
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl!,
            children: [
              _TelegramInfoPanel(
                channel: ch,
                dio: ref.read(apiClientProvider).dio,
                onUpdated: (updated) {
                  if (mounted) setState(() => _channel = updated);
                },
                onError: _showError,
                onSuccess: _showSuccess,
              ),
              _GroupsTab(
                channel: ch,
                onError: _showError,
                onSuccess: _showSuccess,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Channel logo ──────────────────────────────────────────────────────────────

class _ChannelLogo extends StatelessWidget {
  const _ChannelLogo({required this.channelType, this.size = 40});
  final String channelType;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (channelType == 'whatsapp') {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.ctWa,
          borderRadius: BorderRadius.circular(size * 0.35),
        ),
        padding: EdgeInsets.all(size * 0.15),
        child: SvgPicture.asset(
          'assets/logos/whatsapp.svg',
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.ctTg,
        borderRadius: BorderRadius.circular(size * 0.35),
      ),
      padding: EdgeInsets.all(size * 0.15),
      child: Image.asset('assets/logos/telegram.png'),
    );
  }
}

// ── Side panel ────────────────────────────────────────────────────────────────

class _ChannelSidePanel extends StatelessWidget {
  const _ChannelSidePanel({
    required this.channel,
    required this.isActive,
    required this.toggling,
    required this.deleting,
    required this.onBack,
    required this.onToggle,
    required this.onDelete,
  });
  final Map<String, dynamic> channel;
  final bool isActive;
  final bool toggling;
  final bool deleting;
  final VoidCallback onBack;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final channelType = channel['channel_type'] as String? ?? 'whatsapp';
    final name = channel['display_name'] as String? ?? '';
    final credentials =
        (channel['channel_config'] as Map<String, dynamic>?)?['credentials']
            as Map<String, dynamic>? ??
        {};
    final rawPhone = credentials['display_phone_number'] as String? ??
        credentials['phone_number_id'] as String? ??
        '';
    final rawHandle = credentials['bot_username'] as String? ?? '';
    final identifier = channelType == 'whatsapp'
        ? rawPhone
        : (rawHandle.isNotEmpty ? '@$rawHandle' : '');
    final inviteUrl = channelType == 'whatsapp' && rawPhone.isNotEmpty
        ? 'https://wa.me/${rawPhone.replaceAll('+', '').replaceAll(' ', '').replaceAll('-', '')}'
        : (rawHandle.isNotEmpty
            ? 'https://t.me/${rawHandle.replaceAll('@', '')}'
            : '');

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
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: onBack,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.ctNavy,
                          border: Border.all(
                              color: AppColors.ctNavy, width: 1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '← Volver a canales',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Center(child: _ChannelLogo(channelType: channelType, size: 64)),
                  const SizedBox(height: 12),

                  Center(
                    child: Text(
                      name,
                      style: AppTextStyles.cardTitle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 6),

                  Center(child: _TypeChip(channelType)),
                  const SizedBox(height: 20),

                  const Divider(color: AppColors.ctBorder, height: 1),
                  const SizedBox(height: 16),

                  Text('ESTADO', style: AppTextStyles.kpiLabel),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      AppBadge(
                        label: isActive ? 'Activo' : 'Inactivo',
                        variant: isActive
                            ? AppBadgeVariant.ok
                            : AppBadgeVariant.neutral,
                      ),
                      const Expanded(child: SizedBox()),
                      toggling
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.ctTeal),
                            )
                          : Switch(
                              value: isActive,
                              onChanged: (_) => onToggle(),
                              activeThumbColor: AppColors.ctTeal,
                              activeTrackColor: AppColors.ctTealLight,
                            ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (identifier.isNotEmpty) ...[
                    Text('IDENTIFICADOR', style: AppTextStyles.kpiLabel),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.ctSurface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.ctBorder),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(identifier,
                                style: AppTextStyles.bodySmall),
                          ),
                          if (inviteUrl.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                Clipboard.setData(
                                    ClipboardData(text: inviteUrl));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('URL copiada'),
                                    duration: Duration(seconds: 2),
                                    backgroundColor: AppColors.ctOk,
                                  ),
                                );
                              },
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: Icon(
                                  Icons.link_rounded,
                                  size: 14,
                                  color: AppColors.ctText3,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          // Botón Eliminar — fuera del scroll, pegado al fondo
          Padding(
            padding: const EdgeInsets.all(16),
            child: AppButton(
              label: deleting ? 'Eliminando...' : 'Eliminar canal',
              variant: AppButtonVariant.danger,
              size: AppButtonSize.sm,
              expand: true,
              isDisabled: deleting,
              onPressed: onDelete,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Delete dialog ─────────────────────────────────────────────────────────────

class _DeleteChannelDialog extends StatefulWidget {
  const _DeleteChannelDialog({required this.channelName});
  final String channelName;

  @override
  State<_DeleteChannelDialog> createState() => _DeleteChannelDialogState();
}

class _DeleteChannelDialogState extends State<_DeleteChannelDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = _ctrl.text.trim() == widget.channelName;
    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Eliminar canal', style: AppTextStyles.cardTitle),
              const SizedBox(height: 8),
              Text(
                'Esta acción es irreversible. Escribe el nombre del canal para confirmar:',
                style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _ctrl,
                autofocus: true,
                style: AppTextStyles.body,
                decoration: InputDecoration(
                  hintText: widget.channelName,
                  hintStyle:
                      AppTextStyles.body.copyWith(color: AppColors.ctText3),
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
                    borderSide:
                        const BorderSide(color: AppColors.ctTeal),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancelar',
                    variant: AppButtonVariant.outline,
                    size: AppButtonSize.sm,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    label: 'Eliminar',
                    variant: AppButtonVariant.danger,
                    size: AppButtonSize.sm,
                    isDisabled: !canConfirm,
                    onPressed: () => Navigator.of(context).pop(true),
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

// ── TAB 1 — Información ───────────────────────────────────────────────────────

class _InfoTab extends StatefulWidget {
  const _InfoTab({
    required this.channel,
    required this.dio,
    required this.onUpdated,
    required this.onError,
    required this.onSuccess,
  });
  final Map<String, dynamic> channel;
  final Dio dio;
  final ValueChanged<Map<String, dynamic>> onUpdated;
  final ValueChanged<String> onError;
  final ValueChanged<String> onSuccess;

  @override
  State<_InfoTab> createState() => _InfoTabState();
}

class _InfoTabState extends State<_InfoTab> {
  late final TextEditingController _nameCtrl;
  bool _editing = false;
  bool _saving  = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
        text: widget.channel['display_name'] as String? ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      final updated = await ChannelsApi.updateChannel(
        dio: widget.dio,
        channelId: widget.channel['id'] as String,
        displayName: name,
      );
      widget.onUpdated(updated);
      widget.onSuccess('Cambios guardados');
      if (mounted) setState(() { _editing = false; _saving = false; });
    } catch (e) {
      widget.onError(_dioError(e));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionCard(
            title: 'Información del canal',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _FieldLabel('Nombre del canal'),
                    const Expanded(child: SizedBox()),
                    if (!_editing)
                      AppButton(
                        label: 'Editar',
                        variant: AppButtonVariant.ghost,
                        size: AppButtonSize.sm,
                        onPressed: () => setState(() => _editing = true),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_editing) ...[
                  _StyledTextField(controller: _nameCtrl, hint: 'Mi canal'),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AppButton(
                        label: 'Cancelar',
                        variant: AppButtonVariant.ghost,
                        size: AppButtonSize.sm,
                        onPressed: () => setState(() {
                          _nameCtrl.text =
                              widget.channel['display_name'] as String? ?? '';
                          _editing = false;
                        }),
                      ),
                      const SizedBox(width: 8),
                      AppButton(
                        label: 'Guardar',
                        variant: AppButtonVariant.teal,
                        size: AppButtonSize.sm,
                        isLoading: _saving,
                        onPressed: _save,
                      ),
                    ],
                  ),
                ] else
                  Text(
                    widget.channel['display_name'] as String? ?? '—',
                    style: AppTextStyles.body,
                  ),
                const SizedBox(height: 16),
                _FieldLabel('Creado el'),
                const SizedBox(height: 4),
                Text(
                  _formatDate(widget.channel['created_at'] as String? ?? ''),
                  style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionCard(
            title: 'Credenciales del canal',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ReadOnlyCredentialRow(
                  label: 'Phone Number ID',
                  value: widget.channel['phone_number_id'] as String?
                      ?? (widget.channel['channel_config']
                              ?['credentials']?['phone_number_id']
                          as String?)
                      ?? '—',
                ),
                const SizedBox(height: 16),
                _ReadOnlyCredentialRow(
                  label: 'WABA ID',
                  value: widget.channel['waba_id'] as String?
                      ?? (widget.channel['channel_config']
                              ?['credentials']?['waba_id']
                          as String?)
                      ?? '—',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── TAB 2 — Credenciales (DEPRECATED) ─────────────────────────────────────────

// DEPRECATED — sesión 2026-05-20. Contenido movido a _InfoTab.
// Eliminar cuando se confirme que ninguna referencia externa persiste.
// ignore: unused_element
class _CredentialsTab extends StatelessWidget {
  const _CredentialsTab({required this.channel});
  final Map<String, dynamic> channel;

  Map<String, dynamic> get _credentials {
    final cfg = channel['channel_config'];
    if (cfg is Map) {
      final creds = cfg['credentials'];
      if (creds is Map) return Map<String, dynamic>.from(creds);
    }
    return {};
  }

  @override
  Widget build(BuildContext context) {
    final creds = _credentials;
    final phoneId = channel['phone_number_id'] as String?
        ?? creds['phone_number_id'] as String? ?? '—';
    final wabaId = channel['waba_id'] as String?
        ?? creds['waba_id'] as String? ?? '—';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: _SectionCard(
        title: 'Credenciales del canal',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ReadOnlyCredentialRow(label: 'Phone Number ID', value: phoneId),
            const SizedBox(height: 12),
            _ReadOnlyCredentialRow(label: 'WABA ID', value: wabaId),
          ],
        ),
      ),
    );
  }
}

// ── TAB 3 — Plantillas ────────────────────────────────────────────────────────

class _TemplatesTab extends StatefulWidget {
  const _TemplatesTab({
    required this.channelId,
    required this.tenantId,
    required this.dio,
    required this.onError,
    required this.onSuccess,
  });
  final String channelId;
  final String tenantId;
  final Dio dio;
  final ValueChanged<String> onError;
  final ValueChanged<String> onSuccess;

  @override
  State<_TemplatesTab> createState() => _TemplatesTabState();
}

class _TemplatesTabState extends State<_TemplatesTab> {
  List<Map<String, dynamic>> _templates = [];
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _fetchTemplates();
  }

  Future<void> _fetchTemplates() async {
    setState(() => _loading = true);
    try {
      final list = await TemplatesApi.listTemplates(dio: widget.dio, channelId: widget.channelId);
      if (mounted) setState(() { _templates = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _templates = []; _loading = false; });
    }
  }

  Future<void> _deleteTemplate(Map<String, dynamic> template) async {
    final name = template['name'] as String? ?? 'esta plantilla';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.ctSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Eliminar plantilla', style: AppTextStyles.cardTitle),
        content: Text(
          '¿Eliminar "$name"? Esta acción no se puede deshacer.',
          style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
        ),
        actions: [
          AppButton(
            label: 'Cancelar',
            variant: AppButtonVariant.outline,
            size: AppButtonSize.sm,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          const SizedBox(width: 8),
          AppButton(
            label: 'Eliminar',
            variant: AppButtonVariant.danger,
            size: AppButtonSize.sm,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
        actionsAlignment: MainAxisAlignment.end,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await TemplatesApi.deleteTemplate(
        dio: widget.dio,
        templateId: template['id'] as String,
        channelId: widget.channelId,
      );
      widget.onSuccess('Plantilla eliminada');
      await _fetchTemplates();
    } catch (e) {
      widget.onError(_dioError(e));
    }
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      await TemplatesApi.syncTemplates(dio: widget.dio, channelId: widget.channelId);
      widget.onSuccess('Plantillas sincronizadas');
      await _fetchTemplates();
    } catch (e) {
      widget.onError(_dioError(e));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  ({String label, Color bg, Color fg}) _statusStyle(String? status) {
    switch ((status ?? '').toUpperCase()) {
      case 'APPROVED':
        return (label: 'Aprobada', bg: AppColors.ctOkBg, fg: AppColors.ctOkText);
      case 'PENDING':
      case 'PENDING_DELETION':
        return (label: 'Pendiente', bg: AppColors.ctWarnBg, fg: AppColors.ctWarnText);
      case 'REJECTED':
      case 'PAUSED':
      case 'DISABLED':
        return (label: 'Rechazada', bg: AppColors.ctRedBg, fg: AppColors.ctRedText);
      default:
        return (label: status ?? '—', bg: AppColors.ctSurface2, fg: AppColors.ctText2);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          decoration: const BoxDecoration(
            color: AppColors.ctSurface,
            border: Border(bottom: BorderSide(color: AppColors.ctBorder)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Plantillas de WhatsApp',
                    style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_templates.length} plantillas sincronizadas',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2),
                  ),
                ],
              ),
              const Expanded(child: SizedBox()),
              _syncing
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ctTeal),
                    )
                  : AppButton(
                      label: 'Sincronizar con Meta',
                      onPressed: _sync,
                      variant: AppButtonVariant.outline,
                      size: AppButtonSize.sm,
                    ),
              const SizedBox(width: 8),
              AppButton(
                label: '+ Nueva plantilla',
                onPressed: () async {
                  final created = await showDialog<bool>(
                    context: context,
                    barrierDismissible: true,
                    builder: (_) => TemplateCreateDialog(
                      channelId: widget.channelId,
                      tenantId: widget.tenantId,
                    ),
                  );
                  if (created == true) _fetchTemplates();
                },
                variant: AppButtonVariant.teal,
                size: AppButtonSize.sm,
              ),
            ],
          ),
        ),

        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _templates.isEmpty
                  ? Center(
                      child: Text(
                        'Sin plantillas. Sincroniza para obtenerlas.',
                        style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(24),
                      itemCount: _templates.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final t = _templates[i];
                        final style = _statusStyle(t['status'] as String?);
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.ctSurface,
                            border: Border.all(color: AppColors.ctBorder),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          t['name'] as String? ?? '—',
                                          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if ((t['language'] as String?) != null) ...[
                                          const SizedBox(width: 6),
                                          Text(
                                            t['language'] as String,
                                            style: AppTextStyles.caption.copyWith(color: AppColors.ctText3),
                                          ),
                                        ],
                                        const Expanded(child: SizedBox()),
                                        const SizedBox(width: 8),
                                        MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: GestureDetector(
                                            onTap: () => _deleteTemplate(t),
                                            child: Tooltip(
                                              message: 'Eliminar plantilla',
                                              child: Icon(
                                                Icons.delete_outline_rounded,
                                                size: 16,
                                                color: AppColors.ctDanger,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if ((t['body_text'] as String?) != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        t['body_text'] as String,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if ((t['category'] as String?) != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.ctSurface2,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: AppColors.ctBorder),
                                      ),
                                      child: Text(
                                        (t['category'] as String).toUpperCase(),
                                        style: AppTextStyles.caption.copyWith(
                                          color: AppColors.ctText2,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: style.bg,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      style.label,
                                      style: AppTextStyles.badge.copyWith(color: style.fg),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// ── Telegram info panel ───────────────────────────────────────────────────────

class _TelegramInfoPanel extends StatefulWidget {
  const _TelegramInfoPanel({
    required this.channel,
    required this.dio,
    required this.onUpdated,
    required this.onError,
    required this.onSuccess,
  });
  final Map<String, dynamic> channel;
  final Dio dio;
  final ValueChanged<Map<String, dynamic>> onUpdated;
  final ValueChanged<String> onError;
  final ValueChanged<String> onSuccess;

  @override
  State<_TelegramInfoPanel> createState() => _TelegramInfoPanelState();
}

class _TelegramInfoPanelState extends State<_TelegramInfoPanel> {
  late final TextEditingController _nameCtrl;
  bool _editing = false;
  bool _saving  = false;

  Map<String, dynamic> get _credentials {
    final cfg = widget.channel['channel_config'];
    if (cfg is Map) {
      final creds = cfg['credentials'];
      if (creds is Map) return Map<String, dynamic>.from(creds);
    }
    return {};
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
        text: widget.channel['display_name'] as String? ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      final updated = await ChannelsApi.updateChannel(
        dio: widget.dio,
        channelId: widget.channel['id'] as String,
        displayName: name,
      );
      widget.onUpdated(updated);
      widget.onSuccess('Cambios guardados');
      if (mounted) setState(() { _editing = false; _saving = false; });
    } catch (e) {
      widget.onError(_dioError(e));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final creds = _credentials;
    final handle = creds['bot_username'] as String? ?? '';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionCard(
            title: 'Información del canal',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _FieldLabel('Nombre del canal'),
                    const Expanded(child: SizedBox()),
                    if (!_editing)
                      AppButton(
                        label: 'Editar',
                        variant: AppButtonVariant.ghost,
                        size: AppButtonSize.sm,
                        onPressed: () => setState(() => _editing = true),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_editing) ...[
                  _StyledTextField(controller: _nameCtrl, hint: 'Mi bot'),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AppButton(
                        label: 'Cancelar',
                        variant: AppButtonVariant.ghost,
                        size: AppButtonSize.sm,
                        onPressed: () => setState(() {
                          _nameCtrl.text =
                              widget.channel['display_name'] as String? ?? '';
                          _editing = false;
                        }),
                      ),
                      const SizedBox(width: 8),
                      AppButton(
                        label: 'Guardar',
                        variant: AppButtonVariant.teal,
                        size: AppButtonSize.sm,
                        isLoading: _saving,
                        onPressed: _save,
                      ),
                    ],
                  ),
                ] else
                  Text(
                    widget.channel['display_name'] as String? ?? '—',
                    style: AppTextStyles.body,
                  ),
                const SizedBox(height: 16),
                _FieldLabel('Identificador'),
                const SizedBox(height: 4),
                Text(
                  handle.isNotEmpty ? '@$handle' : '—',
                  style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                ),
                const SizedBox(height: 16),
                _FieldLabel('Bot Token'),
                const SizedBox(height: 4),
                Text(
                  '••••••••',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.ctText2,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 16),
                _FieldLabel('Creado el'),
                const SizedBox(height: 4),
                Text(
                  _formatDate(widget.channel['created_at'] as String? ?? ''),
                  style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── TAB 4 — Bienvenida (DEPRECATED) ──────────────────────────────────────────

// DEPRECATED — ADR-253 sesión 2026-05-20. Tab Bienvenida desactivada.
// welcome_template_id permanece en BD pero no se expone en UI.
// Eliminar esta clase cuando se confirme que ningún tenant depende del flujo.
// ignore: unused_element
class _WelcomeTab extends StatefulWidget {
  const _WelcomeTab({
    required this.channel,
    required this.tenantId,
    required this.dio,
    required this.onError,
    required this.onSuccess,
  });
  final Map<String, dynamic> channel;
  final String tenantId;
  final Dio dio;
  final ValueChanged<String> onError;
  final ValueChanged<String> onSuccess;

  @override
  State<_WelcomeTab> createState() => _WelcomeTabState();
}

class _WelcomeTabState extends State<_WelcomeTab> {
  List<Map<String, dynamic>> _approved = [];
  String? _selectedId;
  bool _loading = true;
  bool _saving  = false;

  @override
  void initState() {
    super.initState();
    _loadApproved();
  }

  Future<void> _loadApproved() async {
    try {
      final all = await TemplatesApi.listTemplates(
          dio: widget.dio,
          channelId: widget.channel['id'] as String);
      final approved = all
          .where((t) =>
              (t['status'] as String? ?? '').toUpperCase() == 'APPROVED')
          .toList();
      if (!mounted) return;
      final currentId =
          widget.channel['welcome_template_id'] as String?;
      setState(() {
        _approved = approved;
        _selectedId = currentId;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_selectedId == null) return;
    setState(() => _saving = true);
    try {
      await ChannelsApi.updateWelcomeTemplate(
        dio: widget.dio,
        channelId: widget.channel['id'] as String,
        templateId: _selectedId!,
      );
      widget.onSuccess('Plantilla de bienvenida actualizada');
    } catch (e) {
      widget.onError(_dioError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic>? get _preview =>
      _approved.where((t) => t['id'] == _selectedId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: _SectionCard(
        title: 'Plantilla de bienvenida',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Se envía automáticamente cuando un usuario escribe por primera vez.',
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: 16),
            if (_selectedId == null && _approved.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: Color(0xFF92400E)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No hay plantilla de bienvenida configurada.',
                        style: AppTextStyles.bodySmall.copyWith(color: const Color(0xFF92400E)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            _FieldLabel('Seleccionar plantilla aprobada'),
            const SizedBox(height: 8),
            if (_approved.isEmpty)
              Text(
                'No hay plantillas aprobadas. Sincroniza en la pestaña Plantillas.',
                style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
              )
            else
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.ctBorder),
                  borderRadius: BorderRadius.circular(8),
                  color: AppColors.ctSurface,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedId,
                    isExpanded: true,
                    hint: Text(
                      'Selecciona una plantilla',
                      style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                    ),
                    items: [
                      for (final t in _approved)
                        DropdownMenuItem(
                          value: t['id'] as String?,
                          child: Text(
                            t['name'] as String? ?? t['id'].toString(),
                            style: AppTextStyles.body,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _selectedId = v),
                  ),
                ),
              ),

            // Preview
            if (_preview != null) ...[
              const SizedBox(height: 16),
              _FieldLabel('Vista previa'),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  border: Border.all(color: const Color(0xFF6EE7B7)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _preview!['body_text'] as String? ?? '(sin texto de cuerpo)',
                  style: AppTextStyles.body,
                ),
              ),
            ],

            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                label: 'Guardar',
                onPressed: _save,
                variant: AppButtonVariant.teal,
                size: AppButtonSize.sm,
                isLoading: _saving,
                isDisabled: _selectedId == null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── TAB — Grupos ─────────────────────────────────────────────────────────────

class _GroupsTab extends ConsumerStatefulWidget {
  const _GroupsTab({
    required this.channel,
    required this.onError,
    required this.onSuccess,
  });
  final Map<String, dynamic> channel;
  final ValueChanged<String> onError;
  final ValueChanged<String> onSuccess;

  @override
  ConsumerState<_GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends ConsumerState<_GroupsTab> {
  List<Map<String, dynamic>> _groups = [];
  bool _loading = true;
  Timer? _pendingTimer;

  String get _channelId => widget.channel['id'] as String? ?? '';
  String get _channelType => widget.channel['channel_type'] as String? ?? '';
  bool get _isWhatsApp => _channelType == 'whatsapp';

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  @override
  void dispose() {
    _pendingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final list = await GroupsApi.listGroups(dio: ref.read(apiClientProvider).dio, channelId: _channelId);
      if (!mounted) return;
      setState(() {
        _groups = list;
        _loading = false;
      });
      _checkPending();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _groups = [];
        _loading = false;
      });
    }
  }

  void _checkPending() {
    _pendingTimer?.cancel();
    final hasPending = _groups.any((g) => g['status'] == 'pending');
    if (hasPending) {
      _pendingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _loadGroups();
      });
    }
  }

  Future<void> _openCreateDialog() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _CreateGroupDialog(
        channelId: _channelId,
        dio: ref.read(apiClientProvider).dio,
        onError: widget.onError,
      ),
    );
    if (created == true) {
      widget.onSuccess('Grupo creado');
      _loadGroups();
    }
  }

  Future<void> _openGroupDetail(Map<String, dynamic> group) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _GroupDetailDialog(
        group: group,
        onError: widget.onError,
        onSuccess: widget.onSuccess,
      ),
    );
    if (changed == true) _loadGroups();
  }

  Future<void> _deleteGroup(Map<String, dynamic> group) async {
    final groupId = group['id'] as String? ?? '';
    final displayName = group['display_name'] as String? ?? 'este grupo';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.ctSurface,
        title: Text(
          'Eliminar grupo',
          style: AppTextStyles.cardTitle.copyWith(fontSize: 15),
        ),
        content: Text(
          '¿Seguro que deseas eliminar "$displayName"? '
          'El grupo se desactivará y dejará de recibir mensajes.',
          style: AppTextStyles.pageSubtitle,
        ),
        actions: [
          AppButton(
            label: 'Cancelar',
            onPressed: () => Navigator.pop(ctx, false),
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
          ),
          AppButton(
            label: 'Eliminar',
            onPressed: () => Navigator.pop(ctx, true),
            variant: AppButtonVariant.danger,
            size: AppButtonSize.sm,
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await GroupsApi.deleteGroup(dio: ref.read(apiClientProvider).dio, groupId: groupId);
      widget.onSuccess('Grupo eliminado');
      _loadGroups();
    } catch (e) {
      widget.onError(_dioError(e));
    }
  }

  ({String label, AppBadgeVariant variant}) _statusBadge(String? status) {
    switch (status) {
      case 'active':
        return (label: 'Activo', variant: AppBadgeVariant.ok);
      case 'pending':
        return (label: 'Creando...', variant: AppBadgeVariant.warn);
      case 'inactive':
        return (label: 'Inactivo', variant: AppBadgeVariant.neutral);
      default:
        return (label: status ?? '—', variant: AppBadgeVariant.neutral);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          decoration: const BoxDecoration(
            color: AppColors.ctSurface,
            border: Border(bottom: BorderSide(color: AppColors.ctBorder)),
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Grupos',
                    style: AppTextStyles.body
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_groups.length} grupo${_groups.length == 1 ? '' : 's'}',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.ctText2),
                  ),
                ],
              ),
              const Expanded(child: SizedBox()),
              if (_isWhatsApp)
                AppButton(
                  label: '+ Crear grupo',
                  onPressed: _openCreateDialog,
                  variant: AppButtonVariant.teal,
                  size: AppButtonSize.sm,
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.ctTeal))
              : _groups.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.groups_outlined,
                              size: 48, color: AppColors.ctText3),
                          const SizedBox(height: 12),
                          Text(
                            _isWhatsApp
                                ? 'Sin grupos. Crea uno para comenzar.'
                                : 'Sin grupos. Los grupos se registran automáticamente cuando el bot recibe un mensaje.',
                            style: AppTextStyles.body
                                .copyWith(color: AppColors.ctText2),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(24),
                      itemCount: _groups.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final g = _groups[i];
                        final displayName =
                            g['display_name'] as String? ?? '—';
                        final externalName =
                            g['external_name'] as String?;
                        final status = g['status'] as String?;
                        final badge = _statusBadge(status);
                        final meta =
                            g['metadata'] as Map<String, dynamic>? ?? {};
                        final participantCount =
                            meta['participant_count'] as int?;
                        final visCount =
                            g['visibility_count'] as int? ?? 0;

                        return MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => _openGroupDetail(g),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.ctSurface,
                                border:
                                    Border.all(color: AppColors.ctBorder),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: AppColors.ctNavy
                                          .withValues(alpha: 0.1),
                                      borderRadius:
                                          BorderRadius.circular(18),
                                    ),
                                    child: Icon(Icons.groups,
                                        size: 18,
                                        color: AppColors.ctNavy),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(displayName,
                                            style: AppTextStyles.body
                                                .copyWith(
                                                    fontWeight:
                                                        FontWeight
                                                            .w600)),
                                        if (externalName != null &&
                                            externalName !=
                                                displayName) ...[
                                          const SizedBox(height: 2),
                                          Text(externalName,
                                              style: AppTextStyles
                                                  .bodySmall
                                                  .copyWith(
                                                      color: AppColors
                                                          .ctText3)),
                                        ],
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            if (participantCount !=
                                                null) ...[
                                              Icon(Icons.people_outline,
                                                  size: 12,
                                                  color: AppColors
                                                      .ctText3),
                                              const SizedBox(width: 4),
                                              Text(
                                                  '$participantCount participantes',
                                                  style: AppTextStyles
                                                      .caption
                                                      .copyWith(
                                                          color: AppColors
                                                              .ctText3)),
                                              const SizedBox(width: 12),
                                            ],
                                            Icon(
                                                Icons
                                                    .visibility_outlined,
                                                size: 12,
                                                color:
                                                    AppColors.ctText3),
                                            const SizedBox(width: 4),
                                            Text(
                                                '$visCount usuario${visCount == 1 ? '' : 's'}',
                                                style: AppTextStyles
                                                    .caption
                                                    .copyWith(
                                                        color: AppColors
                                                            .ctText3)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  AppBadge(
                                    label: badge.label,
                                    variant: badge.variant,
                                  ),
                                  const SizedBox(width: 8),
                                  MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: GestureDetector(
                                      onTap: () => _deleteGroup(g),
                                      child: Icon(Icons.delete_outline,
                                          size: 18,
                                          color: AppColors.ctDanger),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.chevron_right,
                                      size: 18,
                                      color: AppColors.ctText3),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// ── Create group dialog ──────────────────────────────────────────────────────

class _CreateGroupDialog extends StatefulWidget {
  const _CreateGroupDialog({
    required this.channelId,
    required this.dio,
    required this.onError,
  });
  final String channelId;
  final Dio dio;
  final ValueChanged<String> onError;

  @override
  State<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<_CreateGroupDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await GroupsApi.createGroup(
        dio: widget.dio,
        channelId: widget.channelId,
        subject: name,
        description:
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        widget.onError(_dioError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Crear grupo de WhatsApp',
                  style: AppTextStyles.cardTitle),
              const SizedBox(height: 16),
              _FieldLabel('Nombre del grupo'),
              const SizedBox(height: 6),
              _StyledTextField(controller: _nameCtrl, hint: 'Mi grupo'),
              const SizedBox(height: 4),
              Text('Máximo 25 caracteres',
                  style:
                      AppTextStyles.caption.copyWith(color: AppColors.ctText3)),
              const SizedBox(height: 16),
              _FieldLabel('Descripción (opcional)'),
              const SizedBox(height: 6),
              TextField(
                controller: _descCtrl,
                maxLines: 3,
                maxLength: 512,
                style: AppTextStyles.body.copyWith(color: AppColors.ctText),
                decoration: InputDecoration(
                  hintText: 'Descripción del grupo',
                  hintStyle:
                      AppTextStyles.body.copyWith(color: AppColors.ctText3),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: AppColors.ctSurface,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.ctBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: AppColors.ctTeal, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancelar',
                    variant: AppButtonVariant.outline,
                    size: AppButtonSize.sm,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    label: 'Crear',
                    variant: AppButtonVariant.teal,
                    size: AppButtonSize.sm,
                    isLoading: _saving,
                    onPressed: _create,
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

// ── Group detail dialog ──────────────────────────────────────────────────────

class _GroupDetailDialog extends ConsumerStatefulWidget {
  const _GroupDetailDialog({
    required this.group,
    required this.onError,
    required this.onSuccess,
  });
  final Map<String, dynamic> group;
  final ValueChanged<String> onError;
  final ValueChanged<String> onSuccess;

  @override
  ConsumerState<_GroupDetailDialog> createState() => _GroupDetailDialogState();
}

class _GroupDetailDialogState extends ConsumerState<_GroupDetailDialog> {
  late final TextEditingController _nameCtrl;
  bool _savingName = false;
  bool _changed = false;

  List<Map<String, dynamic>> _visibility = [];
  bool _loadingVis = true;

  String get _groupId => widget.group['id'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
        text: widget.group['display_name'] as String? ?? '');
    _loadVisibility();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadVisibility() async {
    try {
      final vis = await GroupsApi.getVisibility(dio: ref.read(apiClientProvider).dio, groupId: _groupId);
      if (mounted) setState(() { _visibility = vis; _loadingVis = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingVis = false);
    }
  }

  Future<void> _saveName() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _savingName = true);
    try {
      await GroupsApi.updateGroup(dio: ref.read(apiClientProvider).dio, groupId: _groupId, displayName: name);
      widget.onSuccess('Nombre actualizado');
      _changed = true;
      if (mounted) setState(() => _savingName = false);
    } catch (e) {
      widget.onError(_dioError(e));
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _removeVisibility(String tenantUserId) async {
    try {
      await GroupsApi.removeVisibility(
        dio: ref.read(apiClientProvider).dio,
          groupId: _groupId, tenantUserId: tenantUserId);
      _changed = true;
      _loadVisibility();
    } catch (e) {
      widget.onError(_dioError(e));
    }
  }

  Future<void> _addUsers() async {
    // Fetch all tenant users
    List<Map<String, dynamic>> allUsers = [];
    try {
      allUsers = await IamApi.getUsers(dio: ref.read(apiClientProvider).dio);
    } catch (e) {
      widget.onError(_dioError(e));
      return;
    }

    // Filter out users already with visibility
    final existingIds =
        _visibility.map((v) => v['tenant_user_id'] as String).toSet();
    final available =
        allUsers.where((u) => !existingIds.contains(u['id'] as String?)).toList();

    if (!mounted) return;

    final selected = await showDialog<List<String>>(
      context: context,
      builder: (_) => _UserPickerDialog(users: available),
    );

    if (selected != null && selected.isNotEmpty) {
      try {
        await GroupsApi.addVisibility(
          dio: ref.read(apiClientProvider).dio,
            groupId: _groupId, tenantUserIds: selected);
        _changed = true;
        _loadVisibility();
        widget.onSuccess('Usuarios agregados');
      } catch (e) {
        widget.onError(_dioError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final externalName = widget.group['external_name'] as String?;
    final inviteLink = widget.group['invite_link'] as String?;

    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Detalle del grupo',
                        style: AppTextStyles.cardTitle),
                    const Expanded(child: SizedBox()),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(_changed),
                        child: Icon(Icons.close, size: 18,
                            color: AppColors.ctText2),
                      ),
                    ),
                  ],
                ),
                const Divider(color: AppColors.ctBorder, height: 24),

                // Display name
                _FieldLabel('Nombre visible'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _StyledTextField(
                          controller: _nameCtrl, hint: 'Nombre del grupo'),
                    ),
                    const SizedBox(width: 8),
                    AppButton(
                      label: 'Guardar',
                      variant: AppButtonVariant.teal,
                      size: AppButtonSize.sm,
                      isLoading: _savingName,
                      onPressed: _saveName,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // External name
                if (externalName != null) ...[
                  _FieldLabel('Nombre en el canal'),
                  const SizedBox(height: 4),
                  Text(externalName,
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.ctText2)),
                  const SizedBox(height: 16),
                ],

                // Invite link
                _FieldLabel('Link de invitación'),
                const SizedBox(height: 4),
                if (inviteLink != null && inviteLink.isNotEmpty)
                  Row(
                    children: [
                      Expanded(
                        child: Text(inviteLink,
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.ctText2),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            Clipboard.setData(
                                ClipboardData(text: inviteLink));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Link copiado'),
                                duration: Duration(seconds: 2),
                                backgroundColor: AppColors.ctOk,
                              ),
                            );
                          },
                          child: Icon(Icons.copy_rounded,
                              size: 14, color: AppColors.ctText3),
                        ),
                      ),
                    ],
                  )
                else
                  Text('No disponible aún',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.ctText3)),
                const SizedBox(height: 20),

                // Visibility section
                const Divider(color: AppColors.ctBorder, height: 1),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _FieldLabel('Visibilidad'),
                    const Expanded(child: SizedBox()),
                    AppButton(
                      label: '+ Agregar usuario',
                      variant: AppButtonVariant.outline,
                      size: AppButtonSize.sm,
                      onPressed: _addUsers,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_loadingVis)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.ctTeal),
                      ),
                    ),
                  )
                else if (_visibility.isEmpty)
                  Text(
                    'Sin usuarios asignados. Los administradores siempre tienen acceso completo.',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.ctText3),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final v in _visibility)
                        Chip(
                          label: Text(
                            v['nombre'] as String? ??
                                v['tenant_user_id'] as String? ??
                                '—',
                            style: AppTextStyles.bodySmall,
                          ),
                          deleteIcon: Icon(Icons.close,
                              size: 14, color: AppColors.ctText2),
                          onDeleted: () => _removeVisibility(
                              v['tenant_user_id'] as String),
                          backgroundColor: AppColors.ctSurface2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: const BorderSide(
                                color: AppColors.ctBorder),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                Text(
                  'Los administradores siempre tienen acceso completo a todos los grupos.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.ctText3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── User picker dialog ───────────────────────────────────────────────────────

class _UserPickerDialog extends StatefulWidget {
  const _UserPickerDialog({required this.users});
  final List<Map<String, dynamic>> users;

  @override
  State<_UserPickerDialog> createState() => _UserPickerDialogState();
}

class _UserPickerDialogState extends State<_UserPickerDialog> {
  final _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Seleccionar usuarios', style: AppTextStyles.cardTitle),
              const SizedBox(height: 16),
              if (widget.users.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('Todos los usuarios ya tienen acceso.',
                        style: AppTextStyles.body
                            .copyWith(color: AppColors.ctText2)),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.users.length,
                    itemBuilder: (_, i) {
                      final u = widget.users[i];
                      final id = u['id'] as String? ?? '';
                      final name = u['nombre'] as String? ?? u['email'] as String? ?? id;
                      final roleName =
                          (u['roles'] as Map?)?.cast<String, dynamic>()['name']
                              as String? ??
                          '';
                      final isSelected = _selected.contains(id);
                      return CheckboxListTile(
                        value: isSelected,
                        activeColor: AppColors.ctTeal,
                        title: Text(name, style: AppTextStyles.body),
                        subtitle: roleName.isNotEmpty
                            ? Text(roleName,
                                style: AppTextStyles.caption
                                    .copyWith(color: AppColors.ctText3))
                            : null,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selected.add(id);
                            } else {
                              _selected.remove(id);
                            }
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancelar',
                    variant: AppButtonVariant.outline,
                    size: AppButtonSize.sm,
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    label: 'Agregar (${_selected.length})',
                    variant: AppButtonVariant.teal,
                    size: AppButtonSize.sm,
                    isDisabled: _selected.isEmpty,
                    onPressed: () =>
                        Navigator.of(context).pop(_selected.toList()),
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

// ── Shared Widgets ────────────────────────────────────────────────────────────

class _ReadOnlyCredentialRow extends StatelessWidget {
  const _ReadOnlyCredentialRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(label,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.ctText2)),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.bodySmall
                .copyWith(fontWeight: FontWeight.w500),
          ),
        ),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Copiado'),
              duration: Duration(seconds: 2),
              backgroundColor: AppColors.ctOk,
            ));
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Icon(Icons.copy_rounded,
                size: 14, color: AppColors.ctText3),
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
  });
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Text(
                  title,
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const Divider(color: AppColors.ctBorder, height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextStyles.formLabel.copyWith(color: AppColors.ctText2),
    );
  }
}

class _StyledTextField extends StatelessWidget {
  const _StyledTextField({
    required this.controller,
    required this.hint,
  });
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: AppTextStyles.body.copyWith(color: AppColors.ctText),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: AppColors.ctSurface,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.ctBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.ctTeal, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.ctBorder),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip(this.type);
  final String type;

  @override
  Widget build(BuildContext context) {
    final cfg = _kChannelTypeConfig[type] ??
        (label: type, bg: AppColors.ctSurface2, fg: AppColors.ctText2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cfg.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        cfg.label,
        style: AppTextStyles.badge.copyWith(color: cfg.fg),
      ),
    );
  }
}
