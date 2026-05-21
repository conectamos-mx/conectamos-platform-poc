import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:js_interop';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/ai_workers_api.dart';
import '../../core/api/channels_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/page_header.dart';

/// JS bridge injected by [_CreateChannelStepperState._initFbSdk].
/// Calls FB.login() and forwards the OAuth code + signup data (or cancellation) to Dart.
@JS('_fbLaunchSignup')
external void _fbLaunchSignup(JSFunction onFlush, JSFunction onCancel);

// ── Constants ─────────────────────────────────────────────────────────────────

const _kChannelTypeConfig = {
  'whatsapp': (label: 'WhatsApp', bg: AppColors.ctOkBg, fg: AppColors.ctWa),
  'telegram': (label: 'Telegram', bg: AppColors.ctInfoBg, fg: AppColors.ctTg),
  'sms':      (label: 'SMS',      bg: AppColors.ctSurface2, fg: AppColors.ctText2),
};

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
    if (s != null) return 'Error $s al procesar la solicitud';
  }
  return e.toString();
}


// ── Screen ────────────────────────────────────────────────────────────────────

class ChannelsScreen extends ConsumerStatefulWidget {
  const ChannelsScreen({
    super.key,
    this.tenantWorkerId,
    this.onChannelSelected,
    this.onActiveCountChanged,
  });
  final String? tenantWorkerId;
  final ValueChanged<String>? onChannelSelected;
  final ValueChanged<int>? onActiveCountChanged;

  @override
  ConsumerState<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends ConsumerState<ChannelsScreen> {
  List<Map<String, dynamic>> _channels  = [];
  List<Map<String, dynamic>> _workers   = [];
  bool    _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchAll());
  }

  Future<void> _fetchAll() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        ChannelsApi.listChannels(),
        AiWorkersApi.listWorkers(),
      ]);
      if (!mounted) return;
      final allChannels = results[0];
      final filtered = widget.tenantWorkerId != null
          ? allChannels
              .where((c) =>
                  (c['tenant_worker_id'] as String?) ==
                  widget.tenantWorkerId)
              .toList()
          : allChannels;
      final activeCount =
          filtered.where((c) => c['is_active'] as bool? ?? false).length;
      setState(() {
        _channels = filtered;
        _workers  = results[1];
        _loading  = false;
      });
      widget.onActiveCountChanged?.call(activeCount);
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = _dioError(e); });
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> channel) async {
    final id       = channel['id'] as String? ?? '';
    final isActive = channel['is_active'] as bool? ?? false;
    try {
      if (isActive) {
        await ChannelsApi.updateChannel(channelId: id, isActive: false);
      } else {
        await ChannelsApi.activateChannel(channelId: id);
      }
      ref.read(channelStateVersionProvider.notifier).state++;
      await _fetchAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_dioError(e)),
        backgroundColor: AppColors.ctDanger,
      ));
    }
  }

  void _openCreate() async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        final currentWorker = widget.tenantWorkerId != null
            ? _workers.firstWhere(
                (w) => (w['id'] as String?) == widget.tenantWorkerId,
                orElse: () => <String, dynamic>{},
              )
            : <String, dynamic>{};
        return _CreateChannelStepper(
          tenantWorkerId: widget.tenantWorkerId ?? '',
          workerData: currentWorker.isNotEmpty ? currentWorker : null,
        );
      },
    );
    if (!mounted) return;
    if (result == '_workers') {
      context.go('/workers');
      return;
    }
    if (result == 'embedded_ok') {
      _fetchAll();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Canal conectado correctamente'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
      return;
    }
    if (result != null && result.isNotEmpty) {
      _fetchAll();
      if (widget.onChannelSelected != null) {
        widget.onChannelSelected!(result);
      } else {
        context.go('/channels/$result');
      }
    }
  }

  void _openEdit(Map<String, dynamic> channel) {
    final id = channel['id'] as String? ?? '';
    if (id.isEmpty) return;
    if (widget.onChannelSelected != null) {
      widget.onChannelSelected!(id);
    } else {
      context.go('/channels/$id');
    }
  }


  @override
  Widget build(BuildContext context) {
    ref.listen<String>(activeTenantIdProvider, (prev, next) {
      if (prev != next) _fetchAll();
    });
    return Column(
      children: [
        widget.tenantWorkerId != null
          ? Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Canales de comunicación', style: AppTextStyles.pageTitle),
                        const SizedBox(height: 2),
                        Text(
                          'Conecta números de WhatsApp y bots de Telegram al worker',
                          style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                        ),
                      ],
                    ),
                  ),
                  if (hasPermission(ref, 'settings', 'manage'))
                    AppButton(label: '+ Nuevo canal', variant: AppButtonVariant.teal, size: AppButtonSize.sm, isDisabled: _loading, onPressed: _openCreate),
                ],
              ),
            )
          : PageHeader(
              eyebrow: 'Canales',
              title: 'Canales de comunicación',
              description: 'Conecta números de WhatsApp con AI Workers y operadores',
              actions: [
                if (hasPermission(ref, 'settings', 'manage'))
                  AppButton(label: '+ Nuevo canal', variant: AppButtonVariant.teal, size: AppButtonSize.sm, isDisabled: _loading, onPressed: _openCreate),
              ],
            ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.ctTeal, strokeWidth: 2))
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, style: AppTextStyles.body.copyWith(color: AppColors.ctDanger), textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          AppButton(label: 'Reintentar', variant: AppButtonVariant.outline, size: AppButtonSize.sm, onPressed: _fetchAll),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: _ChannelsBody(
                        channels: _channels,
                        onEdit: _openEdit,
                        onToggleActive: _toggleActive,
                        canManage: hasPermission(ref, 'settings', 'manage'),
                      ),
                    ),
        ),
      ],
    );
  }
}

// ── Channels body ─────────────────────────────────────────────────────────────

class _ChannelsBody extends StatelessWidget {
  const _ChannelsBody({
    required this.channels,
    required this.onEdit,
    required this.onToggleActive,
    required this.canManage,
  });
  final List<Map<String, dynamic>> channels;
  final void Function(Map<String, dynamic>) onEdit;
  final void Function(Map<String, dynamic>) onToggleActive;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Text('No hay canales configurados aún.')),
      );
    }
    return Column(
      children: channels.map((ch) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.ctSurface,
          border: Border.all(color: AppColors.ctBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        child: _ChannelCard(
          channel: ch,
          onEdit: () => onEdit(ch),
          onToggleActive: () => onToggleActive(ch),
          canManage: canManage,
        ),
      )).toList(),
    );
  }
}

// ── Channel card ──────────────────────────────────────────────────────────────

class _ChannelCard extends StatefulWidget {
  const _ChannelCard({
    required this.channel,
    required this.onEdit,
    required this.onToggleActive,
    required this.canManage,
  });
  final Map<String, dynamic> channel;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final bool canManage;

  @override
  State<_ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<_ChannelCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ch          = widget.channel;
    final name        = ch['display_name'] as String? ?? ch['name'] as String? ?? '—';
    final channelType = ch['channel_type'] as String? ?? 'whatsapp';
    final isActive    = ch['is_active'] as bool? ?? false;
    final typeEntry   = _kChannelTypeConfig[channelType] ?? _kChannelTypeConfig['whatsapp']!;

    final credentials = (ch['channel_config'] as Map<String, dynamic>?)?['credentials'] as Map<String, dynamic>? ?? {};
    final rawPhone  = credentials['display_phone_number'] as String? ?? credentials['phone_number_id'] as String? ?? '';
    final rawHandle = credentials['bot_username'] as String? ?? '';
    final identifier = channelType == 'whatsapp'
        ? rawPhone
        : (rawHandle.isNotEmpty ? '@$rawHandle' : '');

    final inviteUrl = channelType == 'whatsapp' && rawPhone.isNotEmpty
        ? 'https://wa.me/${rawPhone.replaceAll('+', '').replaceAll(' ', '').replaceAll('-', '')}'
        : (rawHandle.isNotEmpty
            ? 'https://t.me/${rawHandle.replaceAll('@', '')}'
            : '');

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        color: _hovered ? AppColors.ctBg : AppColors.ctSurface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Opacity(
          opacity: isActive ? 1.0 : 0.5,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ChannelLogo(channelType: channelType),
              const SizedBox(width: 14),
              // Nombre + badge tipo + identifier + icono copiar
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name,
                        style: AppTextStyles.body
                            .copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                              color: typeEntry.bg,
                              borderRadius: BorderRadius.circular(20)),
                          child: Text(typeEntry.label,
                              style: AppTextStyles.caption.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: typeEntry.fg)),
                        ),
                        if (identifier.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(identifier,
                              style: AppTextStyles.navItem
                                  .copyWith(color: AppColors.ctText2)),
                          if (inviteUrl.isNotEmpty) ...[
                            const SizedBox(width: 6),
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
                                child: Tooltip(
                                  message: 'Copiar URL de invitación',
                                  child: const Icon(Icons.link_rounded,
                                      size: 14, color: AppColors.ctText3),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Status pill
              Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: isActive ? AppColors.ctOkBg : AppColors.ctSurface2,
                    borderRadius: BorderRadius.circular(20)),
                child: Text(
                  isActive ? 'Activo' : 'Inactivo',
                  style: AppTextStyles.badge.copyWith(
                      color: isActive ? AppColors.ctOkText : AppColors.ctText2),
                ),
              ),
              // Ver detalle
              GestureDetector(
                onTap: widget.onEdit,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Text('Ver detalle →',
                      style: AppTextStyles.navItem
                          .copyWith(color: AppColors.ctTeal)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Channel logo ──────────────────────────────────────────────────────────────

class _ChannelLogo extends StatelessWidget {
  const _ChannelLogo({required this.channelType});
  final String channelType;

  @override
  Widget build(BuildContext context) {
    if (channelType == 'whatsapp') {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.ctWa,
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(6),
        child: SvgPicture.asset(
          'assets/logos/whatsapp.svg',
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
      );
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.ctTg,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(6),
      child: Image.asset('assets/logos/telegram.png'),
    );
  }
}

// ── Operator avatars ──────────────────────────────────────────────────────────


// ── Create channel stepper ────────────────────────────────────────────────────

class _CreateChannelStepper extends StatefulWidget {
  const _CreateChannelStepper({
    required this.tenantWorkerId,
    this.workerData,
  });
  final String tenantWorkerId;
  final Map<String, dynamic>? workerData;

  @override
  State<_CreateChannelStepper> createState() => _CreateChannelStepperState();
}

class _CreateChannelStepperState extends State<_CreateChannelStepper> {
  // ── FB SDK (WhatsApp Embedded Signup) ──────────────────────────────────────
  static bool _fbSdkInitialized = false;

  static void _initFbSdk() {
    if (_fbSdkInitialized) return;
    _fbSdkInitialized = true;

    // Inject a JS helper that wraps FB.init + FB.login so Dart never needs
    // to touch dart:js directly — only dart:js_interop is used at call site.
    //
    // Double-listener pattern: the OAuth code (from FB.login callback) and the
    // signup data (from WA_EMBEDDED_SIGNUP message event) arrive asynchronously.
    // _waFlush() fires when both are present; _waRetryFlush() gives 3×500ms
    // retries if the code arrives before the signup data.
    final helper = html.ScriptElement()
      ..text = '''
        window.fbAsyncInit = function() {
          FB.init({
            appId            : '4149613485350757',
            autoLogAppEvents : true,
            xfbml            : true,
            version          : 'v25.0'
          });
        };

        // ── State reset per signup attempt ──
        window._waSignupData  = null;
        window._waSignupCode  = null;
        window._waDartFlush   = null;
        window._waDartCancel  = null;

        // ── Flush: merge code + signup data and call Dart ──
        window._waFlush = function() {
          var code = window._waSignupCode;
          var sd   = window._waSignupData;
          var fn   = window._waDartFlush;
          if (!code || !fn) return;
          var payload = { code: code, has_signup_data: !!sd };
          if (sd && sd.data) {
            payload.phone_number_id = sd.data.phone_number_id || null;
            payload.waba_id         = sd.data.waba_id         || null;
            payload.business_id     = sd.data.data ? sd.data.data.business_id || null : null;
          }
          console.log('_waFlush payload:', JSON.stringify(payload));
          fn(JSON.stringify(payload));
        };

        // ── Retry flush: if code arrives first, wait for signup data ──
        window._waRetryFlush = function(attempt) {
          if (window._waSignupData) { window._waFlush(); return; }
          if (attempt >= 3) {
            console.warn('_waRetryFlush: signup data not received after 3 retries, flushing code only');
            window._waFlush();
            return;
          }
          setTimeout(function() { window._waRetryFlush(attempt + 1); }, 500);
        };

        // ── Message listener: WA_EMBEDDED_SIGNUP events ──
        window.addEventListener('message', function(event) {
          if (!event.origin.endsWith('facebook.com')) return;
          try {
            var data = JSON.parse(event.data);
            if (data.type !== 'WA_EMBEDDED_SIGNUP') return;
            console.log('WA_EMBEDDED_SIGNUP event:', JSON.stringify(data));

            if (data.event === 'FINISH') {
              window._waSignupData = data;
              if (window._waSignupCode) window._waFlush();
            } else if (data.event === 'CANCEL') {
              var cancelFn = window._waDartCancel;
              if (!cancelFn) return;
              if (data.data && data.data.error_code) {
                cancelFn(JSON.stringify({
                  event_type:    'signup_error',
                  error_message: data.data.error_message || '',
                  error_code:    String(data.data.error_code),
                  session_id:    data.data.session_id || '',
                  timestamp:     new Date().toISOString()
                }));
              } else {
                cancelFn(JSON.stringify({
                  event_type:   'signup_cancelled',
                  current_step: (data.data && data.data.current_step) || ''
                }));
              }
            }
          } catch(e) {
            // non-JSON message from Facebook iframe — ignore
          }
        });

        // ── Launch signup: reset state, open FB.login, wire callbacks ──
        window._fbLaunchSignup = function(onFlush, onCancel) {
          if (typeof FB === 'undefined') {
            onCancel(JSON.stringify({ event_type: 'sdk_not_ready' }));
            return;
          }
          // Reset per-attempt state
          window._waSignupData = null;
          window._waSignupCode = null;
          window._waDartFlush  = onFlush;
          window._waDartCancel = onCancel;

          FB.login(function(r) {
            console.log('FB.login response:', JSON.stringify(r));
            if (r && r.authResponse && r.authResponse.code) {
              window._waSignupCode = r.authResponse.code;
              if (window._waSignupData) {
                window._waFlush();
              } else {
                window._waRetryFlush(0);
              }
            } else {
              onCancel(JSON.stringify({ event_type: 'fb_login_cancelled' }));
            }
          }, {
            scope: 'whatsapp_business_management,whatsapp_business_messaging',
            config_id: '980871654909798',
            response_type: 'code',
            override_default_response_type: true,
            extras: {
              setup: {},
              featureType: 'whatsapp_business_app_onboarding',
              sessionInfoVersion: '3'
            }
          });
        };
      ''';
    html.document.head!.append(helper);

    // Inject FB SDK script once
    if (html.document.getElementById('facebook-jssdk') == null) {
      final script = html.ScriptElement()
        ..id    = 'facebook-jssdk'
        ..async = true
        ..src   = 'https://connect.facebook.net/en_US/sdk.js';
      html.document.body!.append(script);
    }
  }

  // ── Stepper state ──────────────────────────────────────────────────────────
  int _step = 0;

  // Step 1
  String  _channelType = 'whatsapp';
  String? _workerId;
  String? _botUsername;

  // Step 2
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _wabaCtrl;
  late final TextEditingController _tokenCtrl;
  late final TextEditingController _pinCtrl;
  late final TextEditingController _pinConfirmCtrl;
  String _color             = '#59E0CC';
  bool   _tokenVisible      = false;
  // ignore: prefer_final_fields, unused_field
  bool   _pinVisible        = false;
  // ignore: prefer_final_fields, unused_field
  bool   _pinConfirmVisible = false;

  // Step 2 verify
  bool    _verifying  = false;
  String? _verifyError;

  // Step 3
  bool    _creating                = false;
  bool    _embeddedSignupInProgress = false;
  String? _createError;

  @override
  void initState() {
    super.initState();
    _initFbSdk(); // pre-load FB SDK so it's ready when user reaches step 2
    _workerId = widget.tenantWorkerId;
    _nameCtrl       = TextEditingController()..addListener(_rebuild);
    _phoneCtrl      = TextEditingController()..addListener(_rebuild);
    _wabaCtrl       = TextEditingController()..addListener(_rebuild);
    _tokenCtrl      = TextEditingController()..addListener(_rebuild);
    _pinCtrl        = TextEditingController()..addListener(_rebuild);
    _pinConfirmCtrl = TextEditingController()..addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose(); _wabaCtrl.dispose(); _tokenCtrl.dispose();
    _pinCtrl.dispose(); _pinConfirmCtrl.dispose();
    super.dispose();
  }

  // ignore: unused_element
  bool get _isPinValid {
    final pin = _pinCtrl.text.trim();
    return pin.length == 6 && RegExp(r'^\d{6}$').hasMatch(pin) && pin == _pinConfirmCtrl.text.trim();
  }

  bool get _canNext {
    if (_step == 0) return true; // worker siempre implícito del workspace
    if (_step == 1) {
      if (_channelType == 'telegram') {
        return _nameCtrl.text.trim().isNotEmpty && _tokenCtrl.text.trim().isNotEmpty;
      }
      // Configuración manual deshabilitada — solo embedded signup disponible para WhatsApp.
      // TODO: restaurar validación manual cuando se re-habiliten los campos.
      return false;
    }
    return true;
  }

  Future<void> _create() async {
    if (_creating) return;
    setState(() { _creating = true; _createError = null; });
    try {
      final Map<String, dynamic> result;
      if (_channelType == 'telegram') {
        result = await ChannelsApi.createChannel(
          tenantWorkerId: _workerId!,
          displayName:    _nameCtrl.text.trim(),
          color:          _color,
          channelType:    'telegram',
          channelConfig:  {'credentials': {'bot_token': _tokenCtrl.text.trim()}},
        );
      } else {
        result = await ChannelsApi.createChannel(
          tenantWorkerId: _workerId!,
          displayName:    _nameCtrl.text.trim(),
          color:          _color,
          channelType:    _channelType,
          phoneNumberId:  _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          wabaId:         _wabaCtrl.text.trim().isEmpty  ? null : _wabaCtrl.text.trim(),
          waToken:        _tokenCtrl.text.trim().isEmpty ? null : _tokenCtrl.text.trim(),
        );
        final id = result['id'] as String? ?? result['channel_id'] as String? ?? '';
        if (id.isNotEmpty) {
          ChannelsApi.syncTemplates(channelId: id)
              .catchError((e) => <String, dynamic>{});
        }
      }
      if (!mounted) return;
      final newId = result['id'] as String? ?? result['channel_id'] as String? ?? '';
      Navigator.of(context).pop(newId);
    } catch (e) {
      if (!mounted) return;
      setState(() { _creating = false; _createError = _dioError(e); });
    }
  }

  // ── Embedded Signup ──────────────────────────────────────────────────────

  /// Called directly from onTap — must NOT have any async gap before FB.login().
  void _launchEmbeddedSignup() {
    setState(() { _creating = true; _createError = null; });
    try {
      _fbLaunchSignup(
        // onFlush: JS calls this with JSON {code, phone_number_id, waba_id, business_id, has_signup_data}
        ((JSString jsPayload) {
          _handleEmbeddedSignupFlush(jsPayload.toDart);
        }).toJS,
        // onCancel: user dismissed popup, Meta error, or SDK not ready
        ((JSString jsPayload) {
          _handleSignupEvent(jsPayload.toDart);
          if (mounted) setState(() => _creating = false);
        }).toJS,
      );
    } catch (_) {
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Facebook SDK aún cargando, intenta en un momento.')),
      );
    }
  }

  void _handleEmbeddedSignupFlush(String jsonPayload) {
    try {
      final data = jsonDecode(jsonPayload) as Map<String, dynamic>;
      final code          = data['code'] as String? ?? '';
      final phoneNumberId = data['phone_number_id'] as String?;
      final wabaId        = data['waba_id'] as String?;
      final businessId    = data['business_id'] as String?;
      final hasSignupData = data['has_signup_data'] as bool? ?? false;
      if (code.isEmpty) return;
      _callEmbeddedSignup(
        code,
        phoneNumberId: phoneNumberId,
        wabaId: wabaId,
        businessId: businessId,
        hasSignupData: hasSignupData,
      );
    } catch (_) {
      // Malformed JSON from JS — should not happen
    }
  }

  void _handleSignupEvent(String jsonPayload) {
    try {
      final data = jsonDecode(jsonPayload) as Map<String, dynamic>;
      final eventType = data['event_type'] as String? ?? '';
      // Fire-and-forget telemetry for actionable events
      if (eventType == 'signup_cancelled' || eventType == 'signup_error') {
        ChannelsApi.postSignupEvent(data).ignore();
      }
      // 'fb_login_cancelled' and 'sdk_not_ready' are expected — no POST needed
    } catch (_) {
      // Malformed JSON — ignore
    }
  }

  Future<void> _callEmbeddedSignup(
    String code, {
    String? phoneNumberId,
    String? wabaId,
    String? businessId,
    bool hasSignupData = false,
  }) async {
    if (_embeddedSignupInProgress) return;
    _embeddedSignupInProgress = true;
    try {
      if (!hasSignupData) {
        ChannelsApi.postSignupEvent({'event_type': 'missing_signup_data'}).ignore();
      }
      final result = await ChannelsApi.embeddedSignup(
        code: code,
        phoneNumberId: phoneNumberId,
        wabaId: wabaId,
        businessId: businessId,
      );
      if (!mounted) return;
      setState(() => _creating = false);
      final newId = result['id'] as String? ?? result['channel_id'] as String? ?? '';
      Navigator.of(context).pop(newId.isNotEmpty ? newId : 'embedded_ok');
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      final statusCode = e.response?.statusCode;
      final String msg;
      if (statusCode == 409) {
        msg = 'Este número ya está registrado como canal';
      } else if (statusCode == 400) {
        msg = 'El código de Meta expiró. Intenta de nuevo';
      } else {
        msg = _dioError(e);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: const Color(0xFFEF4444)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: const Color(0xFFEF4444)),
      );
    } finally {
      _embeddedSignupInProgress = false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _verifyAndNext() async {
    if (_verifying) return;
    setState(() { _verifying = true; _verifyError = null; });
    try {
      if (_channelType == 'telegram') {
        final result = await ChannelsApi.verifyTelegramToken(_tokenCtrl.text.trim());
        if (!mounted) return;
        setState(() { _verifying = false; _botUsername = result['username'] as String?; _step++; });
      } else {
        await ChannelsApi.verifyCredentials(
          phoneNumberId: _phoneCtrl.text.trim(),
          accessToken:   _tokenCtrl.text.trim(),
        );
        if (!mounted) return;
        await ChannelsApi.activateWhatsapp(
          phoneNumberId: _phoneCtrl.text.trim(),
          wabaId:        _wabaCtrl.text.trim(),
          accessToken:   _tokenCtrl.text.trim(),
          pin:           _pinCtrl.text.trim(),
        );
        if (!mounted) return;
        setState(() { _verifying = false; _step++; });
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : _dioError(e);
      setState(() { _verifying = false; _verifyError = msg; });
    }
  }

  InputDecoration _fieldDec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
    filled: true, fillColor: AppColors.ctSurface2,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.ctBorder2)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.ctBorder2)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.ctTeal, width: 1.5)),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500)),
  );

  // ── Sidebar ──────────────────────────────────────────────────────────────

  Widget _buildSidebar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Text('Nuevo canal', style: AppTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
        const Divider(height: 1, color: AppColors.ctBorder),
        const SizedBox(height: 12),
        _sideStep(1, 'Tipo de canal', 0),
        _sideStep(2, 'Configuración', 1),
        _sideStep(3, 'Verificar y crear', 2),
      ],
    );
  }

  Widget _sideStep(int number, String label, int idx) {
    final isActive    = _step == idx;
    final isCompleted = _step > idx;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: isCompleted ? AppColors.ctOk : isActive ? AppColors.ctTeal : AppColors.ctBorder2,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: isCompleted
                ? const Icon(Icons.check, size: 12, color: Colors.white)
                : Text('$number', style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w700, color: isActive ? AppColors.ctNavy : AppColors.ctText2)),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(label, style: AppTextStyles.bodySmall.copyWith(fontSize: 12, fontWeight: isActive ? FontWeight.w600 : FontWeight.w400, color: isActive ? AppColors.ctText : AppColors.ctText2)),
          ),
        ],
      ),
    );
  }

  // ── Step 1 ───────────────────────────────────────────────────────────────

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Elige el tipo de canal', style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist', fontSize: 16)),
        const SizedBox(height: 4),
        Text('Selecciona la plataforma de mensajería para este canal.', style: AppTextStyles.body.copyWith(color: AppColors.ctText2)),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: _TypeCard(type: 'whatsapp', selected: _channelType == 'whatsapp', onTap: () => setState(() { _channelType = 'whatsapp'; _color = '#25D366'; }))),
            const SizedBox(width: 12),
            Expanded(child: _TypeCard(type: 'telegram', selected: _channelType == 'telegram', onTap: () => setState(() { _channelType = 'telegram'; _color = '#229ED9'; }))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(child: _TypeCard(type: 'sms', disabled: true)),
            const SizedBox(width: 12),
            Expanded(child: _EmptyTypeCard()),
          ],
        ),
      ],
    );
  }

  // ── Step 2 ───────────────────────────────────────────────────────────────

  Widget _buildStep2() {
    if (_channelType == 'telegram') return _buildStep2Telegram();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Configura tu canal de WhatsApp', style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist', fontSize: 16)),
        const SizedBox(height: 24),

        // ── Embedded Signup ──────────────────────────────────────────────
        Text('Conexión automática', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _creating ? null : _launchEmbeddedSignup,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _creating ? const Color(0xFF1877F2).withValues(alpha: 0.7) : const Color(0xFF1877F2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 20, height: 20,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: _creating
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1877F2)))
                      : const Text('f', style: TextStyle(fontFamily: 'Geist', fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF1877F2))),
                ),
                const SizedBox(width: 12),
                Text('Conectar con WhatsApp Business', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600, color: Colors.white)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // TODO: re-habilitar configuración manual cuando el backend soporte PIN sin embedded signup
        // ── Separator ────────────────────────────────────────────────────
        // Row(children: [
        //   const Expanded(child: Divider(color: AppColors.ctBorder)),
        //   Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('o configura manualmente', style: const TextStyle(fontFamily: 'Geist', fontSize: 12, color: AppColors.ctText3))),
        //   const Expanded(child: Divider(color: AppColors.ctBorder)),
        // ]),
        // const SizedBox(height: 20),

        // ── Manual fields ─────────────────────────────────────────────────
        // _label('Nombre del canal *'),
        // TextField(controller: _nameCtrl, ...),
        // _label('Phone Number ID *'),
        // TextField(controller: _phoneCtrl, ...),
        // _label('WABA ID *'),
        // TextField(controller: _wabaCtrl, ...),
        // _label('Token de acceso *'),
        // TextField(controller: _tokenCtrl, ...),
        // _label('Crea un PIN de 6 dígitos para este canal *'),
        // TextField(controller: _pinCtrl, ...),
        // _label('Confirmar PIN *'),
        // TextField(controller: _pinConfirmCtrl, ...),

      ],
    );
  }

  // ── Step 2 Telegram ──────────────────────────────────────────────────────

  Widget _buildStep2Telegram() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Configura tu canal de Telegram', style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist', fontSize: 16)),
        const SizedBox(height: 24),

        _label('Nombre del canal *'),
        TextField(controller: _nameCtrl, style: AppTextStyles.body, decoration: _fieldDec('Ej: Soporte Telegram')),
        const SizedBox(height: 14),

        _label('Bot Token *'),
        TextField(
          controller: _tokenCtrl,
          obscureText: !_tokenVisible,
          style: AppTextStyles.body,
          decoration: _fieldDec('Ej: 123456:ABC-DEF...').copyWith(
            suffixIcon: IconButton(
              icon: Icon(_tokenVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: AppColors.ctText3),
              onPressed: () => setState(() => _tokenVisible = !_tokenVisible),
            ),
          ),
        ),
        const SizedBox(height: 14),

        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('¿Cómo obtengo mi Bot Token?', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500, color: AppColors.ctTeal)),
          iconColor: AppColors.ctTeal,
          collapsedIconColor: AppColors.ctTeal,
          children: [
            ListTile(
              dense: true,
              leading: CircleAvatar(radius: 10, backgroundColor: AppColors.ctTeal, child: Text('1', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ctNavy))),
              title: Text('Abre Telegram y busca @BotFather', style: AppTextStyles.bodySmall.copyWith(fontSize: 12)),
            ),
            ListTile(
              dense: true,
              leading: CircleAvatar(radius: 10, backgroundColor: AppColors.ctTeal, child: Text('2', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ctNavy))),
              title: Text('Envía /newbot y sigue las instrucciones', style: AppTextStyles.bodySmall.copyWith(fontSize: 12)),
            ),
            ListTile(
              dense: true,
              leading: CircleAvatar(radius: 10, backgroundColor: AppColors.ctTeal, child: Text('3', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ctNavy))),
              title: Text('Al finalizar, BotFather te dará un token como 123456:ABC-DEF...', style: AppTextStyles.bodySmall.copyWith(fontSize: 12)),
            ),
            ListTile(
              dense: true,
              leading: CircleAvatar(radius: 10, backgroundColor: AppColors.ctTeal, child: Text('4', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ctNavy))),
              title: Text('Copia ese token en el campo de arriba', style: AppTextStyles.bodySmall.copyWith(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 14),

      ],
    );
  }

  // ── Step 3 ───────────────────────────────────────────────────────────────

  Widget _buildWorkerChip() {
    final workerData = widget.workerData;
    if (workerData == null || workerData.isEmpty) {
      return Text('—', style: AppTextStyles.body.copyWith(color: AppColors.ctText2));
    }
    final name      = workerData['display_name'] as String?
        ?? workerData['catalog_name'] as String? ?? '—';
    final avatarUrl = workerData['catalog_avatar_url'] as String?
        ?? workerData['avatar_url'] as String?;
    final colorHex  = workerData['catalog_color'] as String?
        ?? workerData['color'] as String?;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (avatarUrl != null && avatarUrl.isNotEmpty)
          Container(
            width: 24, height: 24,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.ctBorder, width: 1),
            ),
            child: Image.network(
              avatarUrl,
              fit: BoxFit.cover,
              errorBuilder: (context2, err, stack) => Container(
                color: _hexColor(colorHex),
                alignment: Alignment.center,
                child: Text(
                  name[0].toUpperCase(),
                  style: AppTextStyles.caption.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          )
        else
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: _hexColor(colorHex),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              name[0].toUpperCase(),
              style: AppTextStyles.caption.copyWith(
                color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        const SizedBox(width: 8),
        Text(name, style: AppTextStyles.body),
      ],
    );
  }

  Widget _buildStep3() {

    final errorBox = _createError != null
        ? Column(children: [
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: AppColors.ctRedBg, borderRadius: BorderRadius.circular(8)),
              child: Text(_createError!, style: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: AppColors.ctRedText)),
            ),
          ])
        : const SizedBox.shrink();

    if (_channelType == 'telegram') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Revisa antes de crear', style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist', fontSize: 16)),
          const SizedBox(height: 4),
          Text('Verifica que la información sea correcta.', style: AppTextStyles.body.copyWith(color: AppColors.ctText2)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.ctSurface2, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.ctBorder)),
            child: Column(
              children: [
                _reviewRow('Tipo de canal', _buildTypeChip()),
                const Divider(height: 20, color: AppColors.ctBorder),
                _reviewRow('Nombre', Text(_nameCtrl.text.trim(), style: AppTextStyles.body)),
                const Divider(height: 20, color: AppColors.ctBorder),
                _reviewRow('Username', Text('@${_botUsername ?? '—'}', style: AppTextStyles.body)),
                const Divider(height: 20, color: AppColors.ctBorder),
                _reviewRow('Worker', _buildWorkerChip()),
                const Divider(height: 20, color: AppColors.ctBorder),
                _reviewRow('Token', Text('••••••••', style: AppTextStyles.body.copyWith(color: AppColors.ctText2))),
              ],
            ),
          ),
          errorBox,
        ],
      );
    }

    final phone      = _phoneCtrl.text.trim();
    final maskedPhone = phone.length > 4 ? '${'*' * (phone.length - 4)}${phone.substring(phone.length - 4)}' : phone;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Revisa antes de crear', style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist', fontSize: 16)),
        const SizedBox(height: 4),
        Text('Verifica que la información sea correcta.', style: AppTextStyles.body.copyWith(color: AppColors.ctText2)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.ctSurface2, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.ctBorder)),
          child: Column(
            children: [
              _reviewRow('Tipo de canal', _buildTypeChip()),
              const Divider(height: 20, color: AppColors.ctBorder),
              _reviewRow('Nombre', Text(_nameCtrl.text.trim(), style: AppTextStyles.body)),
              const Divider(height: 20, color: AppColors.ctBorder),
              _reviewRow('Worker', _buildWorkerChip()),
              const Divider(height: 20, color: AppColors.ctBorder),
              _reviewRow('Phone Number ID', Text(maskedPhone, style: AppTextStyles.body)),
              const Divider(height: 20, color: AppColors.ctBorder),
              _reviewRow('WABA ID', Text(_wabaCtrl.text.trim(), style: AppTextStyles.body)),
              const Divider(height: 20, color: AppColors.ctBorder),
              _reviewRow('Token', Text('••••••••', style: AppTextStyles.body.copyWith(color: AppColors.ctText2))),
            ],
          ),
        ),
        errorBox,
      ],
    );
  }

  Widget _reviewRow(String label, Widget value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.bodySmall.copyWith(fontSize: 12)),
        value,
      ],
    );
  }

  Widget _buildTypeChip() {
    if (_channelType == 'telegram') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: AppColors.ctInfoBg, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 8, height: 8, child: DecoratedBox(decoration: BoxDecoration(color: AppColors.ctTg, shape: BoxShape.circle))),
            const SizedBox(width: 5),
            Text('Telegram', style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: AppColors.ctTg)),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppColors.ctOkBg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 8, height: 8, child: DecoratedBox(decoration: BoxDecoration(color: AppColors.ctWa, shape: BoxShape.circle))),
          const SizedBox(width: 5),
          Text('WhatsApp', style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: AppColors.ctWa)),
        ],
      ),
    );
  }

  // ── Nav buttons ───────────────────────────────────────────────────────────

  Widget _buildNavButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _step > 0
            ? AppButton(label: '← Atrás', variant: AppButtonVariant.outline, size: AppButtonSize.sm, onPressed: () => setState(() { _step--; _createError = null; _verifyError = null; if (_step == 1) _botUsername = null; }))
            : AppButton(label: 'Cancelar', variant: AppButtonVariant.outline, size: AppButtonSize.sm, onPressed: () => Navigator.pop(context)),
        if (_step == 0)
          AppButton(label: 'Siguiente →', variant: AppButtonVariant.teal, size: AppButtonSize.sm, isDisabled: !_canNext, onPressed: () => setState(() => _step++))
        else if (_step == 1 && _verifying)
          Container(
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
        else if (_step == 1)
          AppButton(label: 'Siguiente →', variant: AppButtonVariant.teal, size: AppButtonSize.sm, isDisabled: !_canNext, onPressed: _verifyAndNext)
        else if (_creating)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(color: AppColors.ctTeal, borderRadius: BorderRadius.circular(8)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ctNavy)),
                const SizedBox(width: 8),
                Text('Creando...', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.ctNavy)),
              ],
            ),
          )
        else
          AppButton(label: 'Crear canal', variant: AppButtonVariant.teal, size: AppButtonSize.sm, onPressed: _create),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.ctBorder)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Sidebar
                Container(width: 200, color: AppColors.ctSurface2, child: _buildSidebar()),
                // Divider
                Container(width: 1, color: AppColors.ctBorder),
                // Content
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(28),
                          child: [_buildStep1(), _buildStep2(), _buildStep3()][_step],
                        ),
                      ),
                      if (_step == 1 && _verifyError != null)
                        Container(
                          margin: const EdgeInsets.fromLTRB(28, 12, 28, 0),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.ctRedBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, size: 14, color: AppColors.ctDanger),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _verifyError!,
                                  style: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: AppColors.ctRedText),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Divider(height: 1, color: AppColors.ctBorder),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16), child: _buildNavButtons()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Type card ─────────────────────────────────────────────────────────────────

// ── Channel type card logo ────────────────────────────────────────────────────

class _TypeCardLogo extends StatelessWidget {
  const _TypeCardLogo({required this.type, this.size = 36});
  final String type;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (type == 'whatsapp') {
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: AppColors.ctWa,
          borderRadius: BorderRadius.circular(size * 0.22),
        ),
        padding: EdgeInsets.all(size * 0.17),
        child: SvgPicture.asset(
          'assets/logos/whatsapp.svg',
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
      );
    }
    if (type == 'telegram') {
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: AppColors.ctTg,
          borderRadius: BorderRadius.circular(size * 0.22),
        ),
        padding: EdgeInsets.all(size * 0.17),
        child: Image.asset('assets/logos/telegram.png'),
      );
    }
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: AppColors.ctSurface2,
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(color: AppColors.ctBorder),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.sms_rounded, size: size * 0.5, color: AppColors.ctText3),
    );
  }
}

class _TypeCard extends StatefulWidget {
  const _TypeCard({required this.type, this.selected = false, this.disabled = false, this.onTap});
  final String        type;
  final bool          selected;
  final bool          disabled;
  final VoidCallback? onTap;

  @override
  State<_TypeCard> createState() => _TypeCardState();
}

class _TypeCardState extends State<_TypeCard> {
  bool _hovered = false;

  static const _colors = {'whatsapp': Color(0xFF25D366), 'telegram': Color(0xFF229ED9), 'sms': Color(0xFF6B7280)};
  static const _labels = {'whatsapp': 'WhatsApp Business API', 'telegram': 'Telegram Bot API', 'sms': 'SMS via Twilio / Vonage'};

  Widget _buildCardContent(Color channelColor, String label) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: 90,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.selected
            ? channelColor.withValues(alpha: 0.07)
            : _hovered
                ? AppColors.ctSurface2
                : AppColors.ctSurface,
        border: widget.disabled
            ? Border.all(color: Colors.transparent, width: 1)
            : Border.all(
                color: widget.selected ? channelColor : AppColors.ctBorder2,
                width: widget.selected ? 2 : 1,
              ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _TypeCardLogo(type: widget.type, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: AppTextStyles.bodySmall.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ctText)),
                if (widget.disabled) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.ctSurface2, borderRadius: BorderRadius.circular(20)),
                    child: Text('Próximamente', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w500, color: AppColors.ctText3)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final channelColor = _colors[widget.type] ?? AppColors.ctTeal;
    final label        = _labels[widget.type] ?? widget.type;

    return MouseRegion(
      onEnter: (_) => !widget.disabled ? setState(() => _hovered = true)  : null,
      onExit:  (_) => !widget.disabled ? setState(() => _hovered = false) : null,
      cursor: widget.disabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.disabled ? null : widget.onTap,
        child: Opacity(
          opacity: widget.disabled ? 0.55 : 1.0,
          child: widget.disabled
              ? CustomPaint(
                  painter: const _DashedBorderPainter(color: AppColors.ctBorder2),
                  child: _buildCardContent(channelColor, label),
                )
              : _buildCardContent(channelColor, label),
        ),
      ),
    );
  }
}

class _EmptyTypeCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _DashedBorderPainter(color: AppColors.ctBorder2),
      child: Container(
        height: 90,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline_rounded, size: 22, color: AppColors.ctText3),
            const SizedBox(height: 6),
            Text('Más próximamente', style: AppTextStyles.bodySmall),
          ],
        ),
      ),
    );
  }
}

// ── Dashed border painter ──────────────────────────────────────────────────────

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});
  final Color color;

  static const double _strokeWidth = 1.5;
  static const double _dashLength  = 5.0;
  static const double _gapLength   = 4.0;
  static const double _radius      = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = color
      ..strokeWidth = _strokeWidth
      ..style       = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(_strokeWidth / 2, _strokeWidth / 2,
            size.width - _strokeWidth, size.height - _strokeWidth),
        const Radius.circular(_radius),
      ));

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + _dashLength),
          paint,
        );
        distance += _dashLength + _gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}


