import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import 'auth_shared.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _loading  = false;
  bool _remember = true;
  String? _error;
  Map<String, String> _fieldErrors = {};

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text;

    final errs = <String, String>{};
    if (email.isEmpty) {
      errs['email'] = 'Ingresa tu correo electrónico';
    } else if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      errs['email'] = 'Correo electrónico inválido';
    }
    if (pass.isEmpty) errs['pass'] = 'Ingresa tu contraseña';
    setState(() { _fieldErrors = errs; _error = null; });
    if (errs.isNotEmpty) return;

    setState(() => _loading = true);
    try {
      if (kMockMode) {
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) context.go('/');
        return;
      }
      await ref.read(supabaseClientProvider).auth.signInWithPassword(
        email: email,
        password: pass,
      );
      if (mounted) context.go('/');
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Error al iniciar sesión. Intenta nuevamente.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthBackground(
        child: Column(
          children: [
            const AuthTopBar(),
            Expanded(child: _buildContent()),
            const AuthFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return LayoutBuilder(builder: (ctx, constraints) {
      final wide = constraints.maxWidth >= 800;
      if (wide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 11,
              child: _buildLeftPane(),
            ),
            Expanded(
              flex: 10,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(56, 40, 40, 40),
                child: Center(child: _buildCard()),
              ),
            ),
          ],
        );
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(child: _buildCard()),
      );
    });
  }

  Widget _buildLeftPane() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 40, 56, 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eyebrow
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF59E0CC),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF59E0CC).withValues(alpha: 0.18),
                      blurRadius: 0,
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Conectamos Platform',
                style: AppTextStyles.cardTitle.copyWith(color: AppColors.ctTeal, letterSpacing: -0.1),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Hero title — line 1 white, line 2 teal
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontFamily: 'Onest',
                fontSize: 50,
                fontWeight: FontWeight.w700,
                height: 1.02,
                letterSpacing: -2.0,
              ),
              children: [
                TextSpan(
                  text: 'Tu operación en\ntiempo real,\n',
                  style: const TextStyle(color: Colors.white),
                ),
                TextSpan(
                  text: 'en un solo lugar.',
                  style: const TextStyle(color: AppColors.ctTeal),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Subtitle
          Text(
            'Conecta las herramientas que ya usas, detecta fallas antes de que escalen y gestiona toda tu operación sin cambiar la forma en que trabaja tu equipo.',
            style: AppTextStyles.pageTitle.copyWith(
              fontFamily: 'Geist',
              fontSize: 17,
              color: Colors.white.withValues(alpha: 0.72),
              height: 1.55,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 40),

          // Notification cluster
          const _NotifCluster(),
        ],
      ),
    );
  }

  Widget _buildCard() {
    return AuthCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthCardHead(
            title: 'Bienvenido a ConectamOS',
            titleAccent: 'OS',
            subtitle: 'Inicia sesión para acceder a tu torre de control',
          ),

          // Form-level error
          if (_error != null) ...[
            AuthAlert.error(message: _error!),
            const SizedBox(height: 16),
          ],

          // Fields
          AuthField(
            key: const Key('login_email'),
            label: 'Correo electrónico',
            controller: _emailCtrl,
            placeholder: 'tu@empresa.com',
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            error: _fieldErrors['email'],
            inputAction: TextInputAction.next,
            autofocus: true,
          ),
          const SizedBox(height: 16),
          AuthField(
            key: const Key('login_password'),
            label: 'Contraseña',
            controller: _passCtrl,
            placeholder: '••••••••',
            icon: Icons.lock_outline_rounded,
            isPassword: true,
            error: _fieldErrors['pass'],
            onSubmit: _loading ? null : _signIn,
          ),
          const SizedBox(height: 16),

          // Remember + forgot
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Checkbox(
                value: _remember,
                label: 'Mantener sesión',
                onChanged: (v) => setState(() => _remember = v),
              ),
              Flexible(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => context.go('/forgot-password'),
                    child: const Text(
                      '¿Olvidaste tu contraseña?',
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
          ),
          const SizedBox(height: 16),

          AuthPrimaryButton(
            key: const Key('login_submit'),
            label: 'Iniciar sesión',
            loading: _loading,
            onTap: _loading ? null : _signIn,
            trailingIcon: Icons.arrow_forward_rounded,
          ),

          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              style: const TextStyle(
                fontFamily: 'Geist',
                fontSize: 12,
                color: Color(0xFF6E7273),
                letterSpacing: -0.1,
                height: 1.5,
              ),
              children: [
                const TextSpan(text: 'Al continuar aceptas nuestros '),
                TextSpan(
                  text: 'Términos y Condiciones',
                  style: const TextStyle(
                    color: Color(0xFF5BC0BE),
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => launchUrl(
                          Uri.parse('https://conectamos.ai/terminos-y-condiciones'),
                          mode: LaunchMode.externalApplication,
                        ),
                ),
                const TextSpan(text: ' y '),
                TextSpan(
                  text: 'Política de Privacidad',
                  style: const TextStyle(
                    color: Color(0xFF5BC0BE),
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => launchUrl(
                          Uri.parse('https://conectamos.ai/aviso-de-privacidad'),
                          mode: LaunchMode.externalApplication,
                        ),
                ),
                const TextSpan(text: '.'),
              ],
            ),
            textAlign: TextAlign.center,
          ),

          // Card foot
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.only(top: 20),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFF1F1F1))),
            ),
            child: Wrap(
              alignment: WrapAlignment.center,
              children: [
                const Text(
                  '¿Tienes una invitación? ',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    color: Color(0xFF6E7273),
                    letterSpacing: -0.1,
                  ),
                ),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => context.go('/activate'),
                    child: const Text(
                      'Activa tu cuenta',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5BC0BE),
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Checkbox ──────────────────────────────────────────────────────────────────

class _Checkbox extends StatelessWidget {
  const _Checkbox({
    required this.value,
    required this.label,
    required this.onChanged,
  });
  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 16, height: 16,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: value ? const Color(0xFF59E0CC) : const Color(0xFFC8D0DA),
                  width: 1.5,
                ),
                color: value ? const Color(0xFF59E0CC) : Colors.white,
              ),
              child: value
                  ? const Icon(Icons.check, size: 11, color: Color(0xFF0B132B))
                  : null,
            ),
            const SizedBox(width: 8),
            const Text(
              'Mantener sesión',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                color: Color(0xFF4C5D73),
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Notification cluster ──────────────────────────────────────────────────────

class _NotifCluster extends StatefulWidget {
  const _NotifCluster();

  @override
  State<_NotifCluster> createState() => _NotifClusterState();
}

class _NotifClusterState extends State<_NotifCluster>
    with TickerProviderStateMixin {
  late final AnimationController _c1;
  late final AnimationController _c2;
  late final Animation<double> _a1;
  late final Animation<double> _a2;

  @override
  void initState() {
    super.initState();
    _c1 = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _c2 = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _a1 = CurvedAnimation(parent: _c1, curve: Curves.easeOutCubic);
    _a2 = CurvedAnimation(parent: _c2, curve: Curves.easeOutCubic);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _c1.forward();
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) _c2.forward();
        });
      }
    });
  }

  @override
  void dispose() {
    _c1.dispose();
    _c2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Card 1 — "Venta registrada"
          AnimatedBuilder(
            animation: _a1,
            builder: (_, child) => Opacity(
              opacity: _a1.value,
              child: Transform.translate(
                offset: Offset(0, 14 * (1 - _a1.value)),
                child: child,
              ),
            ),
            child: const _NotifCard(
              icon: Icons.storefront_outlined,
              title: 'Venta registrada',
              desc: '\$2,840 MXN · Sucursal Roma Norte',
              meta: '',
              showCheck: true,
            ),
          ),

          // Card 2 — "Torre de control"
          Positioned(
            top: 110, left: 120,
            child: AnimatedBuilder(
              animation: _a2,
              builder: (_, child) => Opacity(
                opacity: _a2.value,
                child: Transform.translate(
                  offset: Offset(0, 14 * (1 - _a2.value)),
                  child: child,
                ),
              ),
              child: const _NotifCard(
                icon: Icons.bar_chart_rounded,
                title: 'Retraso en envío RF123733',
                desc: 'El conductor tiene más de 30 minutos de retraso en la ruta.',
                meta: 'Torre de control · Hace 5 minutos',
                showCheck: false,
                width: 320,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotifCard extends StatelessWidget {
  const _NotifCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.meta,
    this.showCheck = false,
    this.width,
  });
  final IconData icon;
  final String title, desc, meta;
  final bool showCheck;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.50),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            width: width,
            constraints: const BoxConstraints(minWidth: 220),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF3A506B).withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon badge
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF66E2D0), Color(0xFF5BC0BE)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: const Color(0xFF0B132B)),
                ),
                const SizedBox(width: 12),

                // Text
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        meta,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        title,
                        style: AppTextStyles.cardTitle.copyWith(fontSize: 14, color: Colors.white, letterSpacing: -0.1),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        desc,
                        style: AppTextStyles.bodySmall.copyWith(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.70),
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
                ),

                if (showCheck) ...[
                  const SizedBox(width: 12),
                  Container(
                    width: 22, height: 22,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF59E0CC),
                    ),
                    child: const Icon(Icons.check, size: 12, color: Color(0xFF0B132B)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
