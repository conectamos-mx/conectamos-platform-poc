import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/iam_api.dart';
import '../../core/theme/text_styles.dart';
import '../../shared/validators/phone_validator.dart';
import 'auth_shared.dart';

class ActivateScreen extends StatefulWidget {
  const ActivateScreen({super.key, required this.token});
  final String token;

  @override
  State<ActivateScreen> createState() => _ActivateScreenState();
}

class _ActivateScreenState extends State<ActivateScreen> {
  bool _loadingToken = true;
  String? _tokenError;
  Map<String, dynamic>? _inviteData;

  final _nameCtrl    = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _submitting = false;
  String? _submitError;
  bool _success = false;

  String? _renderFallbackMsg;

  @override
  void initState() {
    super.initState();
    _validateToken();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _validateToken() async {
    try {
      final data = await IamApi.getInvitation(widget.token);
      if (!mounted) return;

      // Pre-populate name & phone from invitation data seeded by admin.
      final nombre   = data['nombre']?.toString() ?? '';
      final telefono = data['telefono']?.toString() ?? '';
      if (nombre.isNotEmpty)   _nameCtrl.text  = nombre;
      if (telefono.isNotEmpty) _phoneCtrl.text = telefono;

      setState(() { _inviteData = data; _loadingToken = false; });
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map
          ? e.response!.data['detail']?.toString()
          : e.response?.data?.toString();
      setState(() {
        _tokenError = detail ?? 'Este enlace no es válido o ha expirado';
        _loadingToken = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tokenError = 'Error al validar el enlace: $e';
        _loadingToken = false;
      });
    }
  }

  /// Extract role name defensively: backend sends role as {id, name} map,
  /// but handle string fallback just in case.
  String _roleName() {
    final role = _inviteData?['role'];
    if (role is Map) return role['name']?.toString() ?? '';
    if (role is String) return role;
    return '';
  }

  Future<void> _submit() async {
    final name    = _nameCtrl.text.trim();
    final pass    = _passCtrl.text;
    final confirm = _confirmCtrl.text;
    final phone   = _phoneCtrl.text.trim();

    if (name.isEmpty) {
      setState(() => _submitError = 'Ingresa tu nombre completo');
      return;
    }
    if (phone.isEmpty) {
      setState(() => _submitError = 'Ingresa tu número de teléfono');
      return;
    }
    final phoneErr = validatePhoneE164(phone);
    if (phoneErr != null) {
      setState(() => _submitError = phoneErr);
      return;
    }
    if (pass.length < 8) {
      setState(() => _submitError = 'La contraseña debe tener al menos 8 caracteres');
      return;
    }
    if (pass != confirm) {
      setState(() => _submitError = 'Las contraseñas no coinciden');
      return;
    }

    setState(() { _submitting = true; _submitError = null; });
    try {
      await IamApi.acceptInvitation(
        widget.token,
        password: pass,
        nombre: name,
        telefono: phone,
      );
      if (!mounted) return;
      setState(() { _submitting = false; _success = true; });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) context.go('/login');
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map
          ? e.response!.data['detail']?.toString()
          : e.response?.data?.toString();
      setState(() {
        _submitError = detail ?? 'Error al activar la cuenta. Intenta nuevamente.';
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitError = 'Error al activar la cuenta: $e';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_renderFallbackMsg != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B132B),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Error de renderizado:\n$_renderFallbackMsg',
              style: AppTextStyles.body.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    try {
      return _buildScaffold();
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _renderFallbackMsg = e.toString());
      });
      return const Scaffold(
        backgroundColor: Color(0xFF0B132B),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF59E0CC))),
      );
    }
  }

  Widget _buildScaffold() {
    return Scaffold(
      body: AuthBackground(
        child: Column(
          children: [
            const AuthTopBar(),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: AuthCard(
                    maxWidth: 460,
                    child: _buildBody(),
                  ),
                ),
              ),
            ),
            const AuthFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingToken) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthCardHead(title: 'Activa tu cuenta'),
          Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFF59E0CC)),
            ),
          ),
        ],
      );
    }
    if (_tokenError != null) return _buildTokenError();
    if (_success)            return _buildSuccess();
    return _buildForm();
  }

  Widget _buildTokenError() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthCardHead(title: 'Activa tu cuenta'),
        AuthAlert.error(message: _tokenError!),
        const SizedBox(height: 24),
        AuthPrimaryButton(
          label: 'Ir al inicio de sesión',
          loading: false,
          onTap: () => context.go('/login'),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AuthCardHead(title: 'Activa tu cuenta'),
        AuthSuccessBlock(
          title: 'Bienvenido a bordo',
          subtitle: 'Tu cuenta quedó activa. Te redirigimos al inicio de sesión...',
        ),
      ],
    );
  }

  Widget _buildForm() {
    final tenantName = _inviteData?['tenant_name']?.toString() ?? '';
    final role       = _roleName();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthCardHead(title: 'Activa tu cuenta'),

        // Invite badge
        if (tenantName.isNotEmpty || role.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDFA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFCCFBF1)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tenantName.isNotEmpty)
                  Text(
                    tenantName,
                    style: const TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                if (tenantName.isNotEmpty && role.isNotEmpty)
                  const Text(
                    ' · ',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF5BC0BE)),
                  ),
                if (role.isNotEmpty)
                  Text(
                    role,
                    style: const TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 12.5,
                      color: Color(0xFF0F766E),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        if (_submitError != null) ...[
          AuthAlert.error(message: _submitError!),
          const SizedBox(height: 16),
        ],

        AuthField(
          label: 'Nombre completo',
          controller: _nameCtrl,
          placeholder: 'Juan García',
          icon: Icons.person_outline_rounded,
          inputAction: TextInputAction.next,
          autofocus: true,
        ),
        const SizedBox(height: 16),
        AuthField(
          label: 'Teléfono',
          controller: _phoneCtrl,
          placeholder: '+52 55 1234 5678',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          inputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        AuthField(
          label: 'Contraseña',
          controller: _passCtrl,
          placeholder: '••••••••',
          icon: Icons.lock_outline_rounded,
          isPassword: true,
          inputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        AuthField(
          label: 'Confirmar contraseña',
          controller: _confirmCtrl,
          placeholder: '••••••••',
          icon: Icons.lock_outline_rounded,
          isPassword: true,
          onSubmit: _submitting ? null : _submit,
        ),
        const SizedBox(height: 16),

        AuthPrimaryButton(
          label: 'Activar cuenta',
          loading: _submitting,
          onTap: _submitting ? null : _submit,
          trailingIcon: Icons.arrow_forward_rounded,
        ),

        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.only(top: 20),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFF1F1F1))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '¿Ya tienes cuenta? ',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  color: Color(0xFF6E7273),
                ),
              ),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => context.go('/login'),
                  child: const Text(
                    'Inicia sesión',
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5BC0BE),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
