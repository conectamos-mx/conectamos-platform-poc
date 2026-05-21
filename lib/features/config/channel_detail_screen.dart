import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/api/channels_api.dart';
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

// WhatsApp usa 3 tabs; Telegram renderiza contenido directo sin TabBar.
const _kWaTabs = ['Información', 'Credenciales', 'Plantillas'];

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
      final channel = await ChannelsApi.getChannel(channelId: widget.channelId);
      if (!mounted) return;
      final isWa = (channel['channel_type'] as String? ?? '') == 'whatsapp';
      _tabCtrl?.dispose();
      _tabCtrl = isWa
          ? TabController(length: _kWaTabs.length, vsync: this)
          : null;
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
          channelId: widget.channelId,
          isActive: false,
        );
        if (!mounted) return;
        setState(() { _channel = updated; _toggling = false; });
      } else {
        await ChannelsApi.activateChannel(channelId: widget.channelId);
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
                onUpdated: (updated) {
                  if (mounted) setState(() => _channel = updated);
                },
                onError: _showError,
                onSuccess: _showSuccess,
              ),
              _CredentialsTab(channel: ch),
              _TemplatesTab(
                channelId: widget.channelId,
                tenantId: _tenantId,
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
    return _TelegramInfoPanel(
      channel: ch,
      onUpdated: (updated) {
        if (mounted) setState(() => _channel = updated);
      },
      onError: _showError,
      onSuccess: _showSuccess,
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
                  AppButton(
                    label: '← Volver a canales',
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.sm,
                    expand: true,
                    onPressed: onBack,
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
    required this.onUpdated,
    required this.onError,
    required this.onSuccess,
  });
  final Map<String, dynamic> channel;
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
        ],
      ),
    );
  }
}

// ── TAB 2 — Credenciales ──────────────────────────────────────────────────────

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
    required this.onError,
    required this.onSuccess,
  });
  final String channelId;
  final String tenantId;
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
      final list = await TemplatesApi.listTemplates(channelId: widget.channelId);
      if (mounted) setState(() { _templates = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _templates = []; _loading = false; });
    }
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      await TemplatesApi.syncTemplates(channelId: widget.channelId);
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
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: const BoxDecoration(
            color: AppColors.ctSurface,
            border: Border(bottom: BorderSide(color: AppColors.ctBorder)),
          ),
          child: Row(
            children: [
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
              const SizedBox(width: 12),
              Text(
                '${_templates.length} plantillas',
                style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
              ),
              const Expanded(child: SizedBox()),
              _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : AppButton(
                      label: 'Sincronizar con Meta',
                      onPressed: _sync,
                      variant: AppButtonVariant.outline,
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
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t['name'] as String? ?? '—',
                                      style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    if ((t['body_text'] as String?) != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          t['body_text'] as String,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTextStyles.bodySmall,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: style.bg,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      style.label,
                                      style: AppTextStyles.badge.copyWith(color: style.fg),
                                    ),
                                  ),
                                  if ((t['language'] as String?) != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        t['language'] as String,
                                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
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
    required this.onUpdated,
    required this.onError,
    required this.onSuccess,
  });
  final Map<String, dynamic> channel;
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
    required this.onError,
    required this.onSuccess,
  });
  final Map<String, dynamic> channel;
  final String tenantId;
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
