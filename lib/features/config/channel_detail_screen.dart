import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/api/ai_workers_api.dart';
import '../../core/api/channels_api.dart';
import '../../core/api/operators_api.dart';
import '../../core/api/templates_api.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_badge.dart';
import '../../shared/widgets/app_button.dart';
import 'template_create_dialog.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _kColorPalette = [
  '#59E0CC', '#818CF8', '#FB923C', '#F472B6', '#34D399', '#60A5FA',
];

const _kChannelTypeConfig = {
  'whatsapp': (label: 'WhatsApp', bg: Color(0xFFDBEAFE), fg: Color(0xFF1E40AF)),
  'telegram': (label: 'Telegram', bg: Color(0xFFEDE9FE), fg: Color(0xFF6D28D9)),
  'sms':      (label: 'SMS',      bg: Color(0xFFFFEDD5), fg: Color(0xFFC2410C)),
};

const _kTemplateTabs = ['Información', 'Credenciales', 'Plantillas', 'Bienvenida'];
const _kInfoOnlyTabs = ['Información'];

// ── Helpers ───────────────────────────────────────────────────────────────────

Color _hexColor(String? hex) {
  try {
    final h = (hex ?? '#9CA3AF').replaceAll('#', '');
    if (h.length != 6) return const Color(0xFF9CA3AF);
    return Color(int.parse('FF$h', radix: 16));
  } catch (_) {
    return const Color(0xFF9CA3AF);
  }
}

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
  List<Map<String, dynamic>> _workers   = [];
  List<Map<String, dynamic>> _operators = [];
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
      final tenantId = ref.read(activeTenantIdProvider);
      _tenantId = tenantId;
      final results = await Future.wait([
        ChannelsApi.getChannel(channelId: widget.channelId),
        AiWorkersApi.listWorkers(),
        OperatorsApi.listOperators(),
      ]);
      if (!mounted) return;
      final channel = results[0] as Map<String, dynamic>;
      final isWa = (channel['channel_type'] as String? ?? '') == 'whatsapp';
      final tabs = isWa ? _kTemplateTabs : _kInfoOnlyTabs;
      _tabCtrl?.dispose();
      _tabCtrl = TabController(length: tabs.length, vsync: this);
      setState(() {
        _channel   = channel;
        _workers   = List<Map<String, dynamic>>.from(results[1] as List);
        _operators = List<Map<String, dynamic>>.from(results[2] as List);
        _loading   = false;
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
      await ChannelsApi.deleteChannel(
        tenantWorkerId: _channel!['tenant_worker_id'] as String,
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
    final tabs = _isWhatsApp ? _kTemplateTabs : _kInfoOnlyTabs;

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
        // ── Zona derecha — tabs ──
        Expanded(
          child: Column(
            children: [
              Container(
                color: AppColors.ctSurface,
                child: Column(
                  children: [
                    const Divider(height: 1, color: AppColors.ctBorder),
                    TabBar(
                      controller: _tabCtrl,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelStyle: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                      unselectedLabelStyle: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
                      labelColor: AppColors.ctTeal,
                      unselectedLabelColor: AppColors.ctText2,
                      indicatorColor: AppColors.ctTeal,
                      indicatorWeight: 2,
                      tabs: [for (final t in tabs) Tab(text: t)],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _InfoTab(
                      channel: _channel!,
                      workers: _workers,
                      operators: _operators,
                      onUpdated: (updated) {
                        if (mounted) setState(() => _channel = updated);
                      },
                      onError: _showError,
                      onSuccess: _showSuccess,
                    ),
                    if (_isWhatsApp) ...[
                      _CredentialsTab(
                        channel: _channel!,
                        tenantId: _tenantId,
                        onUpdated: (updated) {
                          if (mounted) setState(() => _channel = updated);
                        },
                        onError: _showError,
                        onSuccess: _showSuccess,
                      ),
                      _TemplatesTab(
                        channelId: widget.channelId,
                        tenantId: _tenantId,
                        onError: _showError,
                        onSuccess: _showSuccess,
                      ),
                      _WelcomeTab(
                        channel: _channel!,
                        tenantId: _tenantId,
                        onError: _showError,
                        onSuccess: _showSuccess,
                      ),
                    ],
                  ],
                ),
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
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppButton(
            label: '← Volver a canales',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
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
                variant:
                    isActive ? AppBadgeVariant.ok : AppBadgeVariant.neutral,
              ),
              const Spacer(),
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
                      activeColor: AppColors.ctTeal,
                      activeTrackColor: AppColors.ctTealLight,
                    ),
            ],
          ),
          const SizedBox(height: 16),

          if (identifier.isNotEmpty) ...[
            Text('IDENTIFICADOR', style: AppTextStyles.kpiLabel),
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.ctSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.ctBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child:
                        Text(identifier, style: AppTextStyles.bodySmall),
                  ),
                  if (inviteUrl.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: inviteUrl));
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

          const Spacer(),

          AppButton(
            label: deleting ? 'Eliminando...' : 'Eliminar canal',
            variant: AppButtonVariant.danger,
            size: AppButtonSize.sm,
            expand: true,
            isDisabled: deleting,
            onPressed: onDelete,
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
    required this.workers,
    required this.operators,
    required this.onUpdated,
    required this.onError,
    required this.onSuccess,
  });
  final Map<String, dynamic> channel;
  final List<Map<String, dynamic>> workers;
  final List<Map<String, dynamic>> operators;
  final ValueChanged<Map<String, dynamic>> onUpdated;
  final ValueChanged<String> onError;
  final ValueChanged<String> onSuccess;

  @override
  State<_InfoTab> createState() => _InfoTabState();
}

class _InfoTabState extends State<_InfoTab> {
  late final TextEditingController _nameCtrl;
  late String _selectedColor;
  late String? _selectedWorkerId;
  bool _saving = false;

  List<Map<String, dynamic>> get _assignedOps {
    final opIds = (widget.channel['operator_ids'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toSet();
    if (opIds.isEmpty) return [];
    return widget.operators.where((o) => opIds.contains(o['id'])).toList();
  }


  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
        text: widget.channel['display_name'] as String? ?? '');
    _selectedColor = widget.channel['color'] as String? ?? _kColorPalette[0];
    _selectedWorkerId = widget.channel['tenant_worker_id'] as String?;
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
        color: _selectedColor,
        tenantWorkerId: _selectedWorkerId,
      );
      widget.onUpdated(updated);
      widget.onSuccess('Cambios guardados');
    } catch (e) {
      widget.onError(_dioError(e));
    } finally {
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
                _FieldLabel('Nombre del canal'),
                const SizedBox(height: 6),
                _StyledTextField(controller: _nameCtrl, hint: 'Mi canal'),
                const SizedBox(height: 16),
                _FieldLabel('Worker IA asignado'),
                const SizedBox(height: 6),
                _WorkerDropdown(
                  workers: widget.workers,
                  value: _selectedWorkerId,
                  onChanged: (v) => setState(() => _selectedWorkerId = v),
                ),
                const SizedBox(height: 16),
                _FieldLabel('Color del canal'),
                const SizedBox(height: 8),
                _ColorPicker(
                  selected: _selectedColor,
                  onChanged: (c) => setState(() => _selectedColor = c),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: AppButton(
                    label: 'Guardar cambios',
                    onPressed: _save,
                    variant: AppButtonVariant.teal,
                    size: AppButtonSize.sm,
                    isLoading: _saving,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionCard(
            title: 'Operadores asignados',
            child: _assignedOps.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Sin operadores asignados.',
                      style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                    ),
                  )
                : Column(
                    children: [
                      for (final op in _assignedOps)
                        _OperatorRow(op: op),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── TAB 2 — Credenciales ──────────────────────────────────────────────────────

class _CredentialsTab extends StatefulWidget {
  const _CredentialsTab({
    required this.channel,
    required this.tenantId,
    required this.onUpdated,
    required this.onError,
    required this.onSuccess,
  });
  final Map<String, dynamic> channel;
  final String tenantId;
  final ValueChanged<Map<String, dynamic>> onUpdated;
  final ValueChanged<String> onError;
  final ValueChanged<String> onSuccess;

  @override
  State<_CredentialsTab> createState() => _CredentialsTabState();
}

class _CredentialsTabState extends State<_CredentialsTab> {
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _wabaCtrl;
  late final TextEditingController _tokenCtrl;
  late final TextEditingController _pinCtrl;
  late final TextEditingController _pinConfirmCtrl;
  bool    _saving             = false;
  bool    _verifying          = false;
  String? _verifyError;
  bool    _showToken          = false;
  bool    _showPin            = false;
  bool    _showPinConfirm     = false;
  bool    _credentialsLocked  = false;

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
    final creds = _credentials;
    _phoneCtrl = TextEditingController(
        text: widget.channel['phone_number_id'] as String?
            ?? creds['phone_number_id'] as String? ?? '');
    _wabaCtrl = TextEditingController(
        text: widget.channel['waba_id'] as String?
            ?? creds['waba_id'] as String? ?? '');
    _tokenCtrl = TextEditingController(
        text: widget.channel['wa_token'] as String?
            ?? creds['access_token'] as String? ?? '');
    _pinCtrl        = TextEditingController();
    _pinConfirmCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _wabaCtrl.dispose();
    _tokenCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfirmCtrl.dispose();
    super.dispose();
  }

  bool get _isPinValid {
    final pin = _pinCtrl.text.trim();
    return pin.length == 6 && RegExp(r'^\d{6}$').hasMatch(pin) && pin == _pinConfirmCtrl.text.trim();
  }

  Future<void> _saveCredentials() async {
    final phone = _phoneCtrl.text.trim();
    final waba  = _wabaCtrl.text.trim();
    final token = _tokenCtrl.text.trim();
    if (phone.isEmpty || waba.isEmpty || token.isEmpty) {
      widget.onError('Completa todos los campos de credenciales');
      return;
    }
    if (!_isPinValid) {
      widget.onError('El PIN debe tener exactamente 6 dígitos numéricos y coincidir en ambos campos');
      return;
    }
    // Step 1: verify credentials against Meta
    setState(() { _verifying = true; _verifyError = null; });
    try {
      await ChannelsApi.verifyCredentials(phoneNumberId: phone, accessToken: token);
    } catch (e) {
      if (mounted) setState(() { _verifying = false; _verifyError = _dioError(e); });
      return;
    }
    if (!mounted) return;
    // Step 2: activate WhatsApp channel on Meta
    try {
      await ChannelsApi.activateWhatsapp(
        phoneNumberId: phone,
        wabaId:        waba,
        accessToken:   token,
        pin:           _pinCtrl.text.trim(),
      );
    } catch (e) {
      if (mounted) setState(() { _verifying = false; _verifyError = _dioError(e); });
      return;
    }
    if (!mounted) return;
    setState(() { _verifying = false; _saving = true; });
    // Step 3: persist credentials
    try {
      final updated = await ChannelsApi.updateChannel(
        channelId: widget.channel['id'] as String,
        phoneNumberId: phone,
        wabaId: waba,
        waToken: token,
      );
      widget.onUpdated(updated);
      TemplatesApi.syncTemplates(
        channelId: widget.channel['id'] as String,
      ).catchError((_) {});
      widget.onSuccess('Credenciales guardadas');
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 409) {
        final data = e.response?.data;
        final errorCode = data is Map ? data['error'] as String? : null;
        if (errorCode == 'channel_has_history') {
          final msg = data is Map
              ? (data['message'] as String? ?? 'Este canal tiene historial.')
              : 'Este canal tiene historial.';
          if (mounted) setState(() => _credentialsLocked = true);
          widget.onError(msg);
          return;
        }
      }
      widget.onError(_dioError(e));
    } finally {
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
          // ── Embedded Signup (disabled) ──
          _SectionCard(
            title: 'Conexión rápida',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.ctTealLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Requiere certificación Tech Provider',
                    style: AppTextStyles.kpiLabel.copyWith(color: AppColors.ctTealDark),
                  ),
                ),
                const SizedBox(height: 8),
                Tooltip(
                  message:
                      'Disponible cuando Conectamos obtenga certificación Meta Tech Provider',
                  child: Opacity(
                    opacity: 0.5,
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1877F2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                              color: Color(0xFF1565C0),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(8),
                                bottomLeft: Radius.circular(8),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'f',
                              style: AppTextStyles.body.copyWith(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Conectar con WhatsApp Business',
                            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                          const SizedBox(width: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Manual credentials ──
          _SectionCard(
            title: 'Credenciales manuales',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_credentialsLocked) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.ctWarnBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.ctWarnText.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.ctWarnText),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Este canal tiene historial. Para cambiar el número o WABA, desactiva este canal y crea uno nuevo.',
                            style: AppTextStyles.body.copyWith(fontSize: 12.5, color: AppColors.ctWarnText, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                _FieldLabel('Phone Number ID'),
                const SizedBox(height: 6),
                _StyledTextField(
                    controller: _phoneCtrl,
                    hint: '123456789012345',
                    enabled: !_credentialsLocked),
                const SizedBox(height: 16),
                _FieldLabel('WABA ID'),
                const SizedBox(height: 6),
                _StyledTextField(
                    controller: _wabaCtrl,
                    hint: '987654321098765',
                    enabled: !_credentialsLocked),
                const SizedBox(height: 16),
                _FieldLabel('Access Token'),
                const SizedBox(height: 6),
                _StyledTextField(
                  controller: _tokenCtrl,
                  hint: 'EAAxxxx...',
                  obscure: !_showToken,
                  enabled: !_credentialsLocked,
                  suffix: IconButton(
                    icon: Icon(
                      _showToken ? Icons.visibility_off : Icons.visibility,
                      size: 18,
                      color: AppColors.ctText2,
                    ),
                    onPressed: () =>
                        setState(() => _showToken = !_showToken),
                  ),
                ),
                if (!_credentialsLocked) ...[
                  const SizedBox(height: 16),
                  _FieldLabel('PIN de verificación (6 dígitos)'),
                  const SizedBox(height: 6),
                  _StyledTextField(
                    controller: _pinCtrl,
                    hint: '6 dígitos numéricos',
                    obscure: !_showPin,
                    suffix: IconButton(
                      icon: Icon(_showPin ? Icons.visibility_off : Icons.visibility, size: 18, color: AppColors.ctText2),
                      onPressed: () => setState(() => _showPin = !_showPin),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _FieldLabel('Confirmar PIN'),
                  const SizedBox(height: 6),
                  _StyledTextField(
                    controller: _pinConfirmCtrl,
                    hint: 'Repite los 6 dígitos',
                    obscure: !_showPinConfirm,
                    suffix: IconButton(
                      icon: Icon(_showPinConfirm ? Icons.visibility_off : Icons.visibility, size: 18, color: AppColors.ctText2),
                      onPressed: () => setState(() => _showPinConfirm = !_showPinConfirm),
                    ),
                  ),
                ],
                if (!_credentialsLocked) ...[
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _verifying
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(color: AppColors.ctTeal, borderRadius: BorderRadius.circular(8)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ctNavy)),
                                const SizedBox(width: 8),
                                Text('Verificando...', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.ctNavy)),
                              ],
                            ),
                          )
                        : AppButton(
                            label: 'Guardar credenciales',
                            onPressed: _saveCredentials,
                            variant: AppButtonVariant.teal,
                            size: AppButtonSize.sm,
                            isLoading: _saving,
                          ),
                  ),
                  if (_verifyError != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: AppColors.ctRedBg, borderRadius: BorderRadius.circular(8)),
                      child: Text(_verifyError!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctRedText)),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
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
              const Spacer(),
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

// ── TAB 4 — Bienvenida ────────────────────────────────────────────────────────

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
    this.obscure = false,
    this.suffix,
    this.enabled = true,
  });
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final Widget? suffix;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      enabled: enabled,
      style: AppTextStyles.body.copyWith(color: enabled ? AppColors.ctText : AppColors.ctText3),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: enabled ? AppColors.ctSurface : AppColors.ctSurface2,
        suffixIcon: suffix,
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

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final hex in _kColorPalette) ...[
          GestureDetector(
            onTap: () => onChanged(hex),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _hexColor(hex),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected == hex
                      ? AppColors.ctText
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: selected == hex
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _WorkerDropdown extends StatelessWidget {
  const _WorkerDropdown({
    required this.workers,
    required this.value,
    required this.onChanged,
  });
  final List<Map<String, dynamic>> workers;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(8),
        color: AppColors.ctSurface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: workers.any((w) => w['id'].toString() == value) ? value : null,
          isExpanded: true,
          hint: Text(
            'Sin worker asignado',
            style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
          ),
          items: [
            for (final w in workers)
              DropdownMenuItem(
                value: w['id'].toString(),
                child: Text(
                  w['display_name'] as String? ?? w['id'].toString(),
                  style: AppTextStyles.body,
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _OperatorRow extends StatelessWidget {
  const _OperatorRow({required this.op});
  final Map<String, dynamic> op;

  @override
  Widget build(BuildContext context) {
    final name = op['nombre'] as String?
        ?? op['display_name'] as String?
        ?? op['phone'] as String?
        ?? '?';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.ctTealLight,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w700, color: AppColors.ctTealDark),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: AppTextStyles.body,
            ),
          ),
        ],
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
