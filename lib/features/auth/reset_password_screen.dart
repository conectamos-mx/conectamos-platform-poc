import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_client.dart';
import 'auth_shared.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.token});
  final String token;

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;
  bool _success = false;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // Password strength: 0–4
  int get _strength {
    final p = _passCtrl.text;
    int s = 0;
    if (p.length >= 8) s++;
    if (p.contains(RegExp(r'[A-Z]'))) s++;
    if (p.contains(RegExp(r'[0-9]'))) s++;
    if (p.contains(RegExp(r'[^A-Za-z0-9]'))) s++;
    return s;
  }

  static const _strLabels = ['Muy débil', 'Débil', 'Aceptable', 'Buena', 'Fuerte'];
  static const _strColors = [
    Color(0xFFE5E7EB),
    Color(0xFFE24C4B),
    Color(0xFFFFB700),
    Color(0xFF5BC0BE),
    Color(0xFF0F9E82),
  ];

  Future<void> _submit() async {
    final pass    = _passCtrl.text;
    final confirm = _confirmCtrl.text;
    if (pass.length < 8) {
      setState(() => _error = 'La contraseña debe tener al menos 8 caracteres');
      return;
    }
    if (pass != confirm) {
      setState(() => _error = 'Las contraseñas no coinciden');
      return;
    }
    setState(() { _submitting = true; _error = null; });
    try {
      final otpResponse = await Supabase.instance.client.auth.verifyOTP(
        tokenHash: widget.token,
        type: OtpType.recovery,
      );
      final accessToken = otpResponse.session?.accessToken;
      if (!mounted) return;
      if (accessToken == null) {
        setState(() { _error = 'El enlace expiró o es inválido. Solicita uno nuevo.'; _submitting = false; });
        return;
      }
      await ref.read(apiClientProvider).dio.post(
        '/iam/password-reset/confirm',
        data: {'access_token': accessToken, 'password': pass},
      );
      if (!mounted) return;
      setState(() { _submitting = false; _success = true; });
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map
          ? e.response!.data['detail']?.toString()
          : null;
      setState(() {
        _error = (e.response?.statusCode == 400 || detail != null)
            ? 'El enlace expiró o es inválido. Solicita uno nuevo.'
            : 'Error al actualizar la contraseña. Intenta nuevamente.';
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'El enlace expiró o es inválido. Solicita uno nuevo.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    maxWidth: 440,
                    child: _success
                        ? _buildSuccess()
                        : widget.token.isEmpty
                            ? _buildInvalidToken()
                            : _buildForm(),
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

  Widget _buildInvalidToken() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthCardHead(title: 'Nueva contraseña'),
        const AuthAlert.error(message: 'El enlace de restablecimiento no es válido o ha expirado.'),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthCardHead(title: 'Nueva contraseña'),
        const AuthSuccessBlock(
          title: 'Todo listo',
          subtitle: 'Tu contraseña ha sido restablecida correctamente. Ya puedes iniciar sesión.',
        ),
        const SizedBox(height: 24),
        AuthPrimaryButton(
          label: 'Ir al inicio de sesión',
          loading: false,
          onTap: () => context.go('/login'),
          trailingIcon: Icons.arrow_forward_rounded,
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthCardHead(title: 'Nueva contraseña'),
        const Text(
          'Elige una contraseña segura de al menos 8 caracteres.',
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 13.5,
            color: Color(0xFF6E7273),
            letterSpacing: -0.1,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),

        if (_error != null) ...[
          AuthAlert.error(message: _error!),
          const SizedBox(height: 12),
          if (_error!.contains('expiró') || _error!.contains('inválido'))
            Center(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => context.go('/forgot-password'),
                  child: const Text(
                    'Solicitar nuevo enlace',
                    style: TextStyle(
                      fontFamily: 'Geist', fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF5BC0BE),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 4),
        ],

        AuthField(
          label: 'Nueva contraseña',
          controller: _passCtrl,
          placeholder: '••••••••',
          icon: Icons.lock_outline_rounded,
          isPassword: true,
          inputAction: TextInputAction.next,
          autofocus: true,
        ),

        // Password strength bar
        if (_passCtrl.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          _StrengthBar(strength: _strength, label: _strLabels[_strength], color: _strColors[_strength]),
        ],

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
          label: 'Actualizar contraseña',
          loading: _submitting,
          onTap: _submitting ? null : _submit,
          trailingIcon: Icons.arrow_forward_rounded,
        ),
      ],
    );
  }
}

// ── Password strength bar ──────────────────────────────────────────────────────

class _StrengthBar extends StatelessWidget {
  const _StrengthBar({required this.strength, required this.label, required this.color});
  final int strength;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Container(
              height: 4,
              color: const Color(0xFFEEF1F4),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: strength / 4,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  color: color,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 11.5,
            color: color == const Color(0xFFEEF1F4) ? const Color(0xFF9AA0A3) : color,
          ),
        ),
      ],
    );
  }
}
