import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import 'auth_shared.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _sent = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Ingresa un correo electrónico válido');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(apiClientProvider).dio.post(
        '/iam/password-reset',
        data: {'email': email},
      );
      if (!mounted) return;
      setState(() { _loading = false; _sent = true; });
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map
          ? e.response!.data['detail']?.toString()
          : e.response?.data?.toString();
      setState(() {
        _error = detail ?? 'Error al enviar el enlace. Intenta nuevamente.';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Error al enviar el enlace. Intenta nuevamente.';
        _loading = false;
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
                    child: _sent ? _buildSuccess() : _buildForm(),
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

  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthCardHead(title: 'Recuperar contraseña'),
        const Text(
          'Ingresa tu correo y te enviaremos un enlace seguro para restablecer tu contraseña.',
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
          const SizedBox(height: 16),
        ],

        AuthField(
          label: 'Correo electrónico',
          controller: _emailCtrl,
          placeholder: 'tu@empresa.com',
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          onSubmit: _loading ? null : _submit,
          autofocus: true,
        ),
        const SizedBox(height: 16),

        AuthPrimaryButton(
          label: 'Enviar enlace',
          loading: _loading,
          onTap: _loading ? null : _submit,
          trailingIcon: Icons.arrow_forward_rounded,
        ),

        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.only(top: 20),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFF1F1F1))),
          ),
          child: Center(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => context.go('/login'),
                child: const Text(
                  '← Volver al inicio de sesión',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF5BC0BE),
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthCardHead(title: 'Recuperar contraseña'),
        AuthSuccessBlock(
          icon: Icons.mark_email_read_outlined,
          title: 'Revisa tu correo',
          subtitle:
              'Enviamos un enlace a ${_emailCtrl.text.trim()}. Revisa también tu carpeta de spam.',
        ),
        const SizedBox(height: 24),
        Center(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => context.go('/login'),
              child: const Text(
                'Volver al inicio de sesión',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF5BC0BE),
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
