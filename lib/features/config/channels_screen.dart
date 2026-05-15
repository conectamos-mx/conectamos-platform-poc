// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:js_interop';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/ai_workers_api.dart';
import '../../core/api/channels_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/page_header.dart';

/// JS bridge injected by [_CreateChannelStepperState._initFbSdk].
/// Calls FB.login() and forwards the OAuth code (or cancellation) to Dart.
@JS('_fbLaunchSignup')
external void _fbLaunchSignup(JSFunction onCode, JSFunction onCancel);

// ── Constants ─────────────────────────────────────────────────────────────────

const _kChannelTypeConfig = {
  'whatsapp': (label: 'WhatsApp', bg: Color(0xFFDBEAFE), fg: Color(0xFF1E40AF)),
  'telegram': (label: 'Telegram', bg: Color(0xFFEDE9FE), fg: Color(0xFF6D28D9)),
  'sms':      (label: 'SMS',      bg: Color(0xFFFFEDD5), fg: Color(0xFFC2410C)),
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
  const ChannelsScreen({super.key});

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
      setState(() {
        _channels  = results[0];
        _workers   = results[1];
        _loading   = false;
      });
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
      builder: (_) => _CreateChannelStepper(
        workers: _workers,
        tenantId: ref.read(activeTenantIdProvider),
      ),
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
      context.go('/channels/$result');
    }
  }

  void _openEdit(Map<String, dynamic> channel) {
    final id = channel['id'] as String? ?? '';
    if (id.isNotEmpty) context.go('/channels/$id');
  }


  @override
  Widget build(BuildContext context) {
    ref.listen<String>(activeTenantIdProvider, (prev, next) {
      if (prev != next) _fetchAll();
    });
    return Column(
      children: [
        PageHeader(
          eyebrow: 'Canales',
          title: 'Canales de comunicación',
          description: 'Conecta números de WhatsApp con AI Workers y operadores',
          actions: [
            if (hasPermission(ref, 'settings', 'manage'))
              _PrimaryBtn(label: '+ Nuevo canal', onTap: _openCreate, disabled: _loading),
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
                          Text(_error!, style: const TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctDanger), textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          _GhostBtn(label: 'Reintentar', onTap: _fetchAll),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(22),
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

  static const _headerStyle = TextStyle(fontFamily: 'Geist', fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.ctText2, letterSpacing: 0.4);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.ctSurface, border: Border.all(color: AppColors.ctBorder), borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(color: AppColors.ctSurface2, borderRadius: BorderRadius.only(topLeft: Radius.circular(9), topRight: Radius.circular(9))),
            child: const Row(
              children: [
                Expanded(flex: 4, child: Text('CANAL',    style: _headerStyle)),
                Expanded(flex: 3, child: Text('WORKER',   style: _headerStyle)),
                Expanded(flex: 1, child: Text('ESTADO',   style: _headerStyle)),
                Expanded(flex: 2, child: Text('ACCIONES', style: _headerStyle)),
              ],
            ),
          ),
          if (channels.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text('No hay canales configurados aún.', style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText2))),
            )
          else
            ...channels.asMap().entries.map((entry) {
              final isLast = entry.key == channels.length - 1;
              return Column(children: [
                _ChannelRow(
                  channel: entry.value,
                  onEdit: () => onEdit(entry.value),
                  onToggleActive: () => onToggleActive(entry.value),
                  canManage: canManage,
                ),
                if (!isLast) const Divider(height: 1, color: AppColors.ctBorder),
              ]);
            }),
        ],
      ),
    );
  }
}

// ── Channel row ───────────────────────────────────────────────────────────────

class _ChannelRow extends StatefulWidget {
  const _ChannelRow({required this.channel, required this.onEdit, required this.onToggleActive, required this.canManage});
  final Map<String, dynamic> channel;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final bool canManage;

  @override
  State<_ChannelRow> createState() => _ChannelRowState();
}

class _ChannelRowState extends State<_ChannelRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ch          = widget.channel;
    final name        = ch['display_name'] as String? ?? ch['name'] as String? ?? '—';
    final colorHex    = ch['color'] as String? ?? '#59E0CC';
    final channelType = ch['channel_type'] as String? ?? 'whatsapp';
    final isActive    = ch['is_active'] as bool? ?? false;
    final workerName  = ch['worker_name']  as String? ?? '';
    final workerColor = ch['worker_color'] as String? ?? '#9CA3AF';
    final typeEntry   = _kChannelTypeConfig[channelType] ?? _kChannelTypeConfig['whatsapp']!;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        color: _hovered ? AppColors.ctBg : AppColors.ctSurface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Opacity(
          opacity: isActive ? 1.0 : 0.45,
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 4,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(width: 12, height: 12, decoration: BoxDecoration(color: _hexColor(colorHex), shape: BoxShape.circle)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(name, style: const TextStyle(fontFamily: 'Geist', fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ctText), overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: typeEntry.bg, borderRadius: BorderRadius.circular(20)),
                          child: Text(typeEntry.label, style: TextStyle(fontFamily: 'Geist', fontSize: 10, fontWeight: FontWeight.w600, color: typeEntry.fg)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: workerName.isEmpty
                  ? const Text('Sin worker', style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: AppColors.ctText3))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 10, height: 10, decoration: BoxDecoration(color: _hexColor(workerColor), shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Flexible(child: Text(workerName, style: const TextStyle(fontFamily: 'Geist', fontSize: 12, color: AppColors.ctText), overflow: TextOverflow.ellipsis)),
                      ],
                    ),
            ),
            Expanded(
              flex: 1,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: isActive ? AppColors.ctOkBg : AppColors.ctSurface2, borderRadius: BorderRadius.circular(20)),
                  child: Text(isActive ? 'Activo' : 'Inactivo', style: TextStyle(fontFamily: 'Geist', fontSize: 11, fontWeight: FontWeight.w600, color: isActive ? AppColors.ctOkText : AppColors.ctText2)),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: widget.canManage
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ActionBtn(label: 'Editar', color: AppColors.ctInfo, onTap: widget.onEdit),
                        const SizedBox(width: 4),
                        _ActionBtn(label: isActive ? 'Desactivar' : 'Activar', color: isActive ? AppColors.ctDanger : AppColors.ctOk, onTap: widget.onToggleActive),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

// ── Operator avatars ──────────────────────────────────────────────────────────


// ── Create channel stepper ────────────────────────────────────────────────────

class _CreateChannelStepper extends StatefulWidget {
  const _CreateChannelStepper({required this.workers, required this.tenantId});
  final List<Map<String, dynamic>> workers;
  final String tenantId;

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

        // ── Event listener para WA_EMBEDDED_SIGNUP ──
        window.addEventListener('message', function(event) {
          if (!event.origin.endsWith('facebook.com')) return;
          try {
            var data = JSON.parse(event.data);
            console.log('WA_EMBEDDED_SIGNUP event:', JSON.stringify(data));
            if (data.type === 'WA_EMBEDDED_SIGNUP') {
              // Aquí llegan waba_id, phone_number_id, etc.
              window._waSignupData = data;
            }
          } catch(e) {
            console.log('message event raw:', event.data);
          }
        });

        window._fbLaunchSignup = function(onCode, onCancel) {
          if (typeof FB === 'undefined') { onCancel('not_ready'); return; }
          FB.login(function(r) {
            console.log('FB.login response:', JSON.stringify(r));
            if (r && r.authResponse && r.authResponse.code) {
              console.log('CODE:', r.authResponse.code);
              onCode(r.authResponse.code);
            } else {
              onCancel('cancelled');
            }
          }, {
            scope: 'whatsapp_business_management,whatsapp_business_messaging',
            config_id: '2145617199565998',
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
    if (widget.workers.isNotEmpty) {
      _workerId = widget.workers.first['id'] as String?;
    }
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
    if (_step == 0) return _workerId != null && widget.workers.isNotEmpty;
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
        // onCode: JS calls this with the OAuth code string
        ((JSString jsCode) {
          _callEmbeddedSignup(jsCode.toDart);
        }).toJS,
        // onCancel: user dismissed popup or SDK not ready
        ((JSString reason) {
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

  Future<void> _callEmbeddedSignup(String code) async {
    if (_embeddedSignupInProgress) return;
    _embeddedSignupInProgress = true;
    try {
      final result = await ChannelsApi.embeddedSignup(code: code);
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
    hintStyle: const TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText3),
    filled: true, fillColor: AppColors.ctSurface2,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.ctBorder2)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.ctBorder2)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.ctTeal, width: 1.5)),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(fontFamily: 'Geist', fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.ctText)),
  );

  Widget _dropdownBox(Widget child) => Container(
    height: 40, padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: AppColors.ctSurface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.ctBorder2)),
    child: child,
  );

  // ── Sidebar ──────────────────────────────────────────────────────────────

  Widget _buildSidebar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Text('Nuevo canal', style: TextStyle(fontFamily: 'Geist', fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ctText)),
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
                : Text('$number', style: TextStyle(fontFamily: 'Geist', fontSize: 11, fontWeight: FontWeight.w700, color: isActive ? AppColors.ctNavy : AppColors.ctText2)),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(label, style: TextStyle(fontFamily: 'Geist', fontSize: 12, fontWeight: isActive ? FontWeight.w600 : FontWeight.w400, color: isActive ? AppColors.ctText : AppColors.ctText2)),
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
        const Text('Elige el tipo de canal', style: TextStyle(fontFamily: 'Geist', fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ctText)),
        const SizedBox(height: 4),
        const Text('Selecciona la plataforma de mensajería para este canal.', style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText2)),
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
        const SizedBox(height: 24),
        _label('AI Worker asignado'),
        if (widget.workers.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.ctWarnBg, borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.ctWarnText, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'No tienes Workers contratados. Ve a Mis Workers para contratar uno.',
                    style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: AppColors.ctWarnText),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop('_workers'),
                  child: const Text('Ir a Workers', style: TextStyle(fontFamily: 'Geist', fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ctWarnText, decoration: TextDecoration.underline)),
                ),
              ],
            ),
          )
        else
          _dropdownBox(
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _workerId,
                isExpanded: true,
                style: const TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.ctText3),
                items: widget.workers.map((w) {
                  final id    = w['id']           as String? ?? '';
                  final name  = w['display_name'] as String? ?? w['catalog_name'] as String? ?? '—';
                  final color = w['catalog_color'] as String? ?? '#9CA3AF';
                  return DropdownMenuItem<String>(
                    value: id,
                    child: Row(children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: _hexColor(color), shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text(name),
                    ]),
                  );
                }).toList(),
                onChanged: (v) { if (v != null) setState(() => _workerId = v); },
              ),
            ),
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
        const Text('Configura tu canal de WhatsApp', style: TextStyle(fontFamily: 'Geist', fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ctText)),
        const SizedBox(height: 24),

        // ── Embedded Signup ──────────────────────────────────────────────
        const Text('Conexión automática', style: TextStyle(fontFamily: 'Geist', fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ctText)),
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
                const Text('Conectar con WhatsApp Business', style: TextStyle(fontFamily: 'Geist', fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
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
        const Text('Configura tu canal de Telegram', style: TextStyle(fontFamily: 'Geist', fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ctText)),
        const SizedBox(height: 24),

        _label('Nombre del canal *'),
        TextField(controller: _nameCtrl, style: const TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText), decoration: _fieldDec('Ej: Soporte Telegram')),
        const SizedBox(height: 14),

        _label('Bot Token *'),
        TextField(
          controller: _tokenCtrl,
          obscureText: !_tokenVisible,
          style: const TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText),
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
          title: const Text('¿Cómo obtengo mi Bot Token?', style: TextStyle(fontFamily: 'Geist', fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.ctTeal)),
          iconColor: AppColors.ctTeal,
          collapsedIconColor: AppColors.ctTeal,
          children: const [
            ListTile(
              dense: true,
              leading: CircleAvatar(radius: 10, backgroundColor: AppColors.ctTeal, child: Text('1', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.ctNavy))),
              title: Text('Abre Telegram y busca @BotFather', style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: AppColors.ctText2)),
            ),
            ListTile(
              dense: true,
              leading: CircleAvatar(radius: 10, backgroundColor: AppColors.ctTeal, child: Text('2', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.ctNavy))),
              title: Text('Envía /newbot y sigue las instrucciones', style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: AppColors.ctText2)),
            ),
            ListTile(
              dense: true,
              leading: CircleAvatar(radius: 10, backgroundColor: AppColors.ctTeal, child: Text('3', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.ctNavy))),
              title: Text('Al finalizar, BotFather te dará un token como 123456:ABC-DEF...', style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: AppColors.ctText2)),
            ),
            ListTile(
              dense: true,
              leading: CircleAvatar(radius: 10, backgroundColor: AppColors.ctTeal, child: Text('4', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.ctNavy))),
              title: Text('Copia ese token en el campo de arriba', style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: AppColors.ctText2)),
            ),
          ],
        ),
        const SizedBox(height: 14),

      ],
    );
  }

  // ── Step 3 ───────────────────────────────────────────────────────────────

  Widget _buildStep3() {
    final worker = widget.workers.firstWhere(
      (w) => (w['id'] as String?) == _workerId,
      orElse: () => {},
    );
    final workerName = worker['display_name'] as String? ?? worker['catalog_name'] as String? ?? '—';

    final errorBox = _createError != null
        ? Column(children: [
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: AppColors.ctRedBg, borderRadius: BorderRadius.circular(8)),
              child: Text(_createError!, style: const TextStyle(fontFamily: 'Geist', fontSize: 12, color: AppColors.ctRedText)),
            ),
          ])
        : const SizedBox.shrink();

    if (_channelType == 'telegram') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Revisa antes de crear', style: TextStyle(fontFamily: 'Geist', fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ctText)),
          const SizedBox(height: 4),
          const Text('Verifica que la información sea correcta.', style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText2)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.ctSurface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.ctBorder)),
            child: Column(
              children: [
                _reviewRow('Tipo de canal', _buildTypeChip()),
                const Divider(height: 20, color: AppColors.ctBorder),
                _reviewRow('Nombre', Text(_nameCtrl.text.trim(), style: const TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText))),
                const Divider(height: 20, color: AppColors.ctBorder),
                _reviewRow('Username', Text('@${_botUsername ?? '—'}', style: const TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText))),
                const Divider(height: 20, color: AppColors.ctBorder),
                _reviewRow('Worker', Text(workerName, style: const TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText))),
                const Divider(height: 20, color: AppColors.ctBorder),
                _reviewRow('Token', const Text('••••••••', style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText2))),
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
        const Text('Revisa antes de crear', style: TextStyle(fontFamily: 'Geist', fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ctText)),
        const SizedBox(height: 4),
        const Text('Verifica que la información sea correcta.', style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText2)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.ctSurface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.ctBorder)),
          child: Column(
            children: [
              _reviewRow('Tipo de canal', _buildTypeChip()),
              const Divider(height: 20, color: AppColors.ctBorder),
              _reviewRow('Nombre', Text(_nameCtrl.text.trim(), style: const TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText))),
              const Divider(height: 20, color: AppColors.ctBorder),
              _reviewRow('Worker', Text(workerName, style: const TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText))),
              const Divider(height: 20, color: AppColors.ctBorder),
              _reviewRow('Phone Number ID', Text(maskedPhone, style: const TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText))),
              const Divider(height: 20, color: AppColors.ctBorder),
              _reviewRow('WABA ID', Text(_wabaCtrl.text.trim(), style: const TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText))),
              const Divider(height: 20, color: AppColors.ctBorder),
              _reviewRow('Token', const Text('••••••••', style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText2))),
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
        Text(label, style: const TextStyle(fontFamily: 'Geist', fontSize: 12, color: AppColors.ctText2)),
        value,
      ],
    );
  }

  Widget _buildTypeChip() {
    if (_channelType == 'telegram') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: const Color(0xFFEDE9FE), borderRadius: BorderRadius.circular(20)),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 8, height: 8, child: DecoratedBox(decoration: BoxDecoration(color: Color(0xFF229ED9), shape: BoxShape.circle))),
            SizedBox(width: 5),
            Text('Telegram', style: TextStyle(fontFamily: 'Geist', fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6D28D9))),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(20)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 8, height: 8, child: DecoratedBox(decoration: BoxDecoration(color: Color(0xFF25D366), shape: BoxShape.circle))),
          SizedBox(width: 5),
          Text('WhatsApp', style: TextStyle(fontFamily: 'Geist', fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF16A34A))),
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
            ? _GhostBtn(label: '← Atrás', onTap: () => setState(() { _step--; _createError = null; _verifyError = null; if (_step == 1) _botUsername = null; }))
            : _GhostBtn(label: 'Cancelar', onTap: () => Navigator.pop(context)),
        if (_step == 0)
          _PrimaryBtn(label: 'Siguiente →', onTap: _canNext ? () => setState(() => _step++) : (() {}), disabled: !_canNext)
        else if (_step == 1 && _verifying)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(color: AppColors.ctTeal, borderRadius: BorderRadius.circular(8)),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ctNavy)),
                SizedBox(width: 8),
                Text('Verificando...', style: TextStyle(fontFamily: 'Geist', fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ctNavy)),
              ],
            ),
          )
        else if (_step == 1)
          _PrimaryBtn(label: 'Siguiente →', onTap: _canNext ? _verifyAndNext : (() {}), disabled: !_canNext)
        else if (_creating)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(color: AppColors.ctTeal, borderRadius: BorderRadius.circular(8)),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ctNavy)),
                SizedBox(width: 8),
                Text('Creando...', style: TextStyle(fontFamily: 'Geist', fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ctNavy)),
              ],
            ),
          )
        else
          _PrimaryBtn(label: 'Crear canal', onTap: _create),
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
                                  style: const TextStyle(
                                    fontFamily: 'Geist',
                                    fontSize: 12,
                                    color: AppColors.ctRedText,
                                  ),
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

  static const _icons    = {'whatsapp': Icons.chat_rounded, 'telegram': Icons.send_rounded, 'sms': Icons.sms_rounded};
  static const _colors   = {'whatsapp': Color(0xFF25D366), 'telegram': Color(0xFF229ED9), 'sms': Color(0xFF6B7280)};
  static const _labels   = {'whatsapp': 'WhatsApp Business API', 'telegram': 'Telegram Bot API', 'sms': 'SMS via Twilio / Vonage'};

  @override
  Widget build(BuildContext context) {
    final channelColor = _colors[widget.type] ?? AppColors.ctTeal;
    final icon         = _icons[widget.type]  ?? Icons.chat_rounded;
    final label        = _labels[widget.type] ?? widget.type;

    return MouseRegion(
      onEnter: (_) => !widget.disabled ? setState(() => _hovered = true)  : null,
      onExit:  (_) => !widget.disabled ? setState(() => _hovered = false) : null,
      cursor: widget.disabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.disabled ? null : widget.onTap,
        child: Opacity(
          opacity: widget.disabled ? 0.45 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 90,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: widget.selected
                  ? channelColor.withValues(alpha: 0.07)
                  : _hovered
                      ? AppColors.ctSurface2
                      : AppColors.ctSurface,
              border: Border.all(
                color: widget.selected ? channelColor : AppColors.ctBorder2,
                width: widget.selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: channelColor, borderRadius: BorderRadius.circular(8)),
                  alignment: Alignment.center,
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(label, style: const TextStyle(fontFamily: 'Geist', fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ctText)),
                      if (widget.disabled) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.ctSurface2, borderRadius: BorderRadius.circular(20)),
                          child: const Text('Próximamente', style: TextStyle(fontFamily: 'Geist', fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.ctText3)),
                        ),
                      ],
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

class _EmptyTypeCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.ctBorder, width: 1.5, style: BorderStyle.solid),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_circle_outline_rounded, size: 22, color: AppColors.ctText3),
          const SizedBox(height: 6),
          const Text('Más próximamente', style: TextStyle(fontFamily: 'Geist', fontSize: 11, color: AppColors.ctText3)),
        ],
      ),
    );
  }
}


// ── Button helpers ────────────────────────────────────────────────────────────

class _PrimaryBtn extends StatefulWidget {
  const _PrimaryBtn({required this.label, required this.onTap, this.disabled = false});
  final String label;
  final VoidCallback onTap;
  final bool disabled;

  @override
  State<_PrimaryBtn> createState() => _PrimaryBtnState();
}

class _PrimaryBtnState extends State<_PrimaryBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: widget.disabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.disabled ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: widget.disabled ? AppColors.ctBorder2 : _hovered ? AppColors.ctTealDark : AppColors.ctTeal,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(widget.label, style: TextStyle(fontFamily: 'Geist', fontSize: 13, fontWeight: FontWeight.w600, color: widget.disabled ? AppColors.ctText3 : AppColors.ctNavy)),
        ),
      ),
    );
  }
}

class _GhostBtn extends StatefulWidget {
  const _GhostBtn({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_GhostBtn> createState() => _GhostBtnState();
}

class _GhostBtnState extends State<_GhostBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.ctSurface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.ctBorder),
          ),
          child: Text(widget.label, style: const TextStyle(fontFamily: 'Geist', fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.ctText2)),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatefulWidget {
  const _ActionBtn({required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_ActionBtn> createState() => _ActionBtnState();
}

class _ActionBtnState extends State<_ActionBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: _hovered ? widget.color.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(widget.label, style: TextStyle(fontFamily: 'Geist', fontSize: 12, fontWeight: FontWeight.w500, color: widget.color)),
        ),
      ),
    );
  }
}
