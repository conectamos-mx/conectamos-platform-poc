import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/api/channels_api.dart';
import '../../core/api/iam_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/validators/phone_validator.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/page_header.dart';
import 'role_permissions_panel.dart';
import '../settings/operator_fields_screen.dart';
import 'operator_roles_screen.dart';

// ── Enum de secciones ─────────────────────────────────────────────────────────

enum _Section { general, billing, users, communication, permissions, roles, operatorFields }

// ── Pantalla principal ────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  _Section _active = _Section.general;

  @override
  Widget build(BuildContext context) {
    final canManageSettings = hasPermission(ref, 'settings', 'manage');
    final canViewRoles      = hasPermission(ref, 'operator_roles', 'view');

    final items = [
      (section: _Section.general,       label: 'Información general', icon: Icons.business_outlined),
      (section: _Section.billing,       label: 'Facturación',         icon: Icons.receipt_long_outlined),
      (section: _Section.users,         label: 'Usuarios',            icon: Icons.group_outlined),
      (section: _Section.communication, label: 'Comunicación',        icon: Icons.chat_bubble_outline_rounded),
      if (canManageSettings)
        (section: _Section.permissions,    label: 'Permisos',            icon: Icons.security_outlined),
      if (canViewRoles)
        (section: _Section.roles,          label: 'Roles',               icon: Icons.badge_outlined),
      if (canManageSettings)
        (section: _Section.operatorFields, label: 'Operador',            icon: Icons.dashboard_customize),
    ];

    // Reset to general if active tab was removed (e.g., permissions lost)
    final validSection = items.any((i) => i.section == _active) ||
        (_active == _Section.operatorFields && canManageSettings);
    if (!validSection) {
      _active = _Section.general;
    }

    return Row(
      children: [
        // ── Panel izquierdo ──────────────────────────────────────────
        Container(
          width: 220,
          decoration: const BoxDecoration(
            color: AppColors.ctSurface,
            border: Border(
              right: BorderSide(color: AppColors.ctBorder),
            ),
          ),
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...items.map((item) => _NavItem(
                    label: item.label,
                    icon: item.icon,
                    active: _active == item.section,
                    onTap: () => setState(() => _active = item.section),
                  )),
            ],
          ),
        ),
        // ── Panel derecho ────────────────────────────────────────────
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeader(
                eyebrow: 'Configuración',
                title: 'Ajustes',
                description: 'Configuración general del tenant',
              ),
              Expanded(child: _SectionPanel(active: _active)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Nav item ──────────────────────────────────────────────────────────────────

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color textColor;
    final FontWeight weight;

    if (widget.active) {
      bg        = AppColors.ctTealLight;
      textColor = AppColors.ctTeal;
      weight    = FontWeight.w700;
    } else if (_hovered) {
      bg        = AppColors.ctBg;
      textColor = AppColors.ctText2;
      weight    = FontWeight.w500;
    } else {
      bg        = Colors.transparent;
      textColor = AppColors.ctText2;
      weight    = FontWeight.w500;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              left: BorderSide(
                color: widget.active ? AppColors.ctTeal : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(widget.icon, size: 16, color: textColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: AppTextStyles.body.copyWith(fontWeight: weight, color: textColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Panel derecho — despacha la sección activa ────────────────────────────────

class _SectionPanel extends StatelessWidget {
  const _SectionPanel({required this.active});
  final _Section active;

  @override
  Widget build(BuildContext context) {
    if (active == _Section.permissions) {
      return const _PermissionsSection();
    }
    if (active == _Section.roles) {
      return const OperatorRolesScreen();
    }
    if (active == _Section.operatorFields) {
      return const OperatorFieldsBody();
    }

    final Widget content;
    switch (active) {
      case _Section.general:
        content = const _GeneralInfoCard();
      case _Section.billing:
        content = const _BillingCard();
      case _Section.users:
        content = const _UsersCard();
      case _Section.communication:
        content = const _CommunicationSection();
      case _Section.permissions:
        content = const SizedBox.shrink(); // handled above
      case _Section.roles:
        content = const SizedBox.shrink(); // handled above
      case _Section.operatorFields:
        content = const SizedBox.shrink(); // handled above
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [content],
      ),
    );
  }
}

// ── Sección Permisos ──────────────────────────────────────────────────────────

class _PermissionsSection extends ConsumerWidget {
  const _PermissionsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rolesAsync = ref.watch(roleListProvider);

    return rolesAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.ctTeal, strokeWidth: 2),
      ),
      error: (e, _) => Center(
        child: Text(
          'Error al cargar roles: $e',
          style: AppTextStyles.body.copyWith(color: AppColors.ctDanger),
        ),
      ),
      data: (roles) {
        // Ensure order: admin → supervisor → viewer
        final ordered = ['admin', 'supervisor', 'viewer'];
        final sorted = [
          for (final name in ordered)
            ...roles.where((r) => r.name == name),
          // any extra roles not in ordered list
          ...roles.where((r) => !ordered.contains(r.name)),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gestión de permisos por rol',
                    style: AppTextStyles.pageTitle.copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Define qué puede hacer cada rol en tu organización. Los cambios del rol admin no pueden modificarse.',
                    style: AppTextStyles.navItem,
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            // Columnas
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = 0; i < sorted.length; i++) ...[
                          SizedBox(
                            width: 300,
                            child: RolePermissionsPanel(
                              roleId:   sorted[i].id,
                              roleName: sorted[i].name,
                            ),
                          ),
                          if (i < sorted.length - 1) const SizedBox(width: 16),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Sección 1 — Información general (incluye dirección) ──────────────────────

class _GeneralInfoCard extends ConsumerStatefulWidget {
  const _GeneralInfoCard();

  @override
  ConsumerState<_GeneralInfoCard> createState() => _GeneralInfoCardState();
}

class _GeneralInfoCardState extends ConsumerState<_GeneralInfoCard> {
  final _displayNameCtrl = TextEditingController();
  final _legalNameCtrl   = TextEditingController();
  final _rfcCtrl         = TextEditingController();
  final _emailCtrl       = TextEditingController();
  final _telefonoCtrl    = TextEditingController();
  final _calleCtrl       = TextEditingController();
  final _numExtCtrl      = TextEditingController();
  final _numIntCtrl      = TextEditingController();
  final _coloniaCtrl     = TextEditingController();
  final _ciudadCtrl      = TextEditingController();
  final _estadoCtrl      = TextEditingController();
  final _cpCtrl          = TextEditingController();

  bool _loading = true;
  bool _saving  = false;
  String _currentTenantId = '';
  String? _error;
  String? _success;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tenantId = ref.read(activeTenantIdProvider);
    if (tenantId.isNotEmpty && tenantId != _currentTenantId) {
      _currentTenantId = tenantId;
      _load();
    }
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _legalNameCtrl.dispose();
    _rfcCtrl.dispose();
    _emailCtrl.dispose();
    _telefonoCtrl.dispose();
    _calleCtrl.dispose();
    _numExtCtrl.dispose();
    _numIntCtrl.dispose();
    _coloniaCtrl.dispose();
    _ciudadCtrl.dispose();
    _estadoCtrl.dispose();
    _cpCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiClient.instance.get('/tenants/$_currentTenantId');
      final d = Map<String, dynamic>.from(res.data as Map);
      if (!mounted) return;
      _displayNameCtrl.text = d['display_name']?.toString() ?? d['name']?.toString() ?? '';
      _legalNameCtrl.text   = d['legal_name']?.toString() ?? '';
      _rfcCtrl.text         = d['rfc']?.toString() ?? '';
      _emailCtrl.text       = d['email_contacto']?.toString() ?? '';
      _telefonoCtrl.text    = d['telefono']?.toString() ?? '';
      _calleCtrl.text       = d['calle']?.toString() ?? '';
      _numExtCtrl.text      = d['numero_exterior']?.toString() ?? '';
      _numIntCtrl.text      = d['numero_interior']?.toString() ?? '';
      _coloniaCtrl.text     = d['colonia']?.toString() ?? '';
      _ciudadCtrl.text      = d['ciudad']?.toString() ?? '';
      _estadoCtrl.text      = d['estado_cliente']?.toString() ?? '';
      _cpCtrl.text          = d['codigo_postal']?.toString() ?? '';
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(_errorSnack('Error al cargar: $e'));
    }
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; _success = null; });
    try {
      await ApiClient.instance.put('/tenants/$_currentTenantId', data: {
        'display_name':    _displayNameCtrl.text.trim(),
        'legal_name':      _legalNameCtrl.text.trim(),
        'rfc':             _rfcCtrl.text.trim(),
        'email_contacto':  _emailCtrl.text.trim(),
        'telefono':        _telefonoCtrl.text.trim(),
        'calle':           _calleCtrl.text.trim(),
        'numero_exterior': _numExtCtrl.text.trim(),
        'numero_interior': _numIntCtrl.text.trim(),
        'colonia':         _coloniaCtrl.text.trim(),
        'ciudad':          _ciudadCtrl.text.trim(),
        'estado_cliente':  _estadoCtrl.text.trim(),
        'codigo_postal':   _cpCtrl.text.trim(),
      });
      if (!mounted) return;
      setState(() { _saving = false; _success = 'Información guardada'; });
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = e.response?.data is Map
          ? e.response!.data['detail']?.toString()
          : e.response?.data?.toString();
      setState(() { _saving = false; _error = msg ?? 'Error al guardar'; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _saving = false; _error = 'Error: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Información general',
      loading: _loading,
      error: _error,
      success: _success,
      onSave: (_saving || !hasPermission(ref, 'settings', 'manage')) ? null : _save,
      saving: _saving,
      child: Column(
        children: [
          _Row2(
            left: _Field(label: 'Nombre comercial', ctrl: _displayNameCtrl, placeholder: 'Ej: Mi Empresa'),
            right: _Field(label: 'Razón social', ctrl: _legalNameCtrl, placeholder: 'Nombre legal completo'),
          ),
          const SizedBox(height: 14),
          _Row2(
            left: _Field(label: 'RFC', ctrl: _rfcCtrl, placeholder: 'XAXX010101000'),
            right: _Field(label: 'Teléfono', ctrl: _telefonoCtrl, placeholder: '+52 55 1234 5678'),
          ),
          const SizedBox(height: 14),
          _Field(label: 'Email de contacto', ctrl: _emailCtrl, placeholder: 'contacto@empresa.com'),
          const SizedBox(height: 20),
          const Divider(color: AppColors.ctBorder),
          const SizedBox(height: 16),
          _Row2(
            left: _Field(label: 'Calle', ctrl: _calleCtrl, placeholder: 'Nombre de la calle'),
            right: _Row2(
              left: _Field(label: 'Núm. exterior', ctrl: _numExtCtrl, placeholder: '123'),
              right: _Field(label: 'Núm. interior', ctrl: _numIntCtrl, placeholder: 'Opcional'),
            ),
          ),
          const SizedBox(height: 14),
          _Row2(
            left: _Field(label: 'Colonia', ctrl: _coloniaCtrl, placeholder: 'Col. Centro'),
            right: _Field(label: 'Ciudad', ctrl: _ciudadCtrl, placeholder: 'Ciudad de México'),
          ),
          const SizedBox(height: 14),
          _Row2(
            left: _Field(label: 'Estado', ctrl: _estadoCtrl, placeholder: 'CDMX'),
            right: _Field(label: 'Código postal', ctrl: _cpCtrl, placeholder: '06600'),
          ),
        ],
      ),
    );
  }
}

// ── Sección 2 — Facturación ───────────────────────────────────────────────────

class _BillingCard extends ConsumerStatefulWidget {
  const _BillingCard();

  @override
  ConsumerState<_BillingCard> createState() => _BillingCardState();
}

class _BillingCardState extends ConsumerState<_BillingCard> {
  final _regimenCtrl = TextEditingController();
  final _usoCfdiCtrl = TextEditingController();

  bool _loading = true;
  bool _saving  = false;
  bool _requiereCfdi = false;
  String _currentTenantId = '';
  String? _error;
  String? _success;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tenantId = ref.read(activeTenantIdProvider);
    if (tenantId.isNotEmpty && tenantId != _currentTenantId) {
      _currentTenantId = tenantId;
      _load();
    }
  }

  @override
  void dispose() {
    _regimenCtrl.dispose();
    _usoCfdiCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiClient.instance.get('/tenants/$_currentTenantId');
      final d = Map<String, dynamic>.from(res.data as Map);
      if (!mounted) return;
      _requiereCfdi     = d['requiere_cfdi'] == true;
      _regimenCtrl.text = d['regimen_fiscal']?.toString() ?? '';
      _usoCfdiCtrl.text = d['uso_cfdi']?.toString() ?? '';
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(_errorSnack('Error al cargar: $e'));
    }
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; _success = null; });
    try {
      await ApiClient.instance.put('/tenants/$_currentTenantId', data: {
        'requiere_cfdi':  _requiereCfdi,
        'regimen_fiscal': _regimenCtrl.text.trim(),
        'uso_cfdi':       _usoCfdiCtrl.text.trim(),
      });
      if (!mounted) return;
      setState(() { _saving = false; _success = 'Facturación guardada'; });
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = e.response?.data is Map
          ? e.response!.data['detail']?.toString()
          : e.response?.data?.toString();
      setState(() { _saving = false; _error = msg ?? 'Error al guardar'; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _saving = false; _error = 'Error: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Facturación',
      loading: _loading,
      error: _error,
      success: _success,
      onSave: (_saving || !hasPermission(ref, 'settings', 'manage')) ? null : _save,
      saving: _saving,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '¿Requiere CFDI?',
                      style: AppTextStyles.formLabel,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _requiereCfdi ? 'Sí, requiere factura' : 'No requiere factura',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
              ),
              Switch(
                value: _requiereCfdi,
                onChanged: (v) => setState(() => _requiereCfdi = v),
                activeThumbColor: AppColors.ctTeal,
              ),
            ],
          ),
          if (_requiereCfdi) ...[
            const SizedBox(height: 16),
            _Row2(
              left: _Field(
                label: 'Régimen fiscal',
                ctrl: _regimenCtrl,
                placeholder: 'Ej: 601 - General de Ley',
              ),
              right: _Field(
                label: 'Uso de CFDI',
                ctrl: _usoCfdiCtrl,
                placeholder: 'Ej: G03 - Gastos en general',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Validadores IAM ──────────────────────────────────────────────────────────

/// Email: formato básico + normalización.
String? _validateEmail(String? value) {
  if (value == null || value.trim().isEmpty) return 'Ingresa un email';
  final email = value.trim().toLowerCase();
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
    return 'Formato de email inválido';
  }
  return null;
}

/// Parsea error_code estructurado del backend (ADR-369).
/// Retorna mensaje amigable o null si no reconocido.
String? _friendlyError409(DioException e) {
  final status = e.response?.statusCode;
  final data = e.response?.data;
  if (data is! Map) return null;
  final detail = data['detail'];
  final String? code;
  if (detail is Map) {
    code = detail['code']?.toString() ?? detail['error_code']?.toString();
  } else {
    code = data['error_code']?.toString();
  }
  if (code == null) return null;

  switch (code) {
    case 'EMAIL_ALREADY_EXISTS':
      return 'Ya existe un usuario con ese email en este tenant';
    case 'PHONE_BELONGS_TO_USER':
      return 'Ese teléfono ya está asignado a otro usuario';
    case 'OPERATOR_PHONE_IN_USE':
      return 'Ese teléfono ya pertenece a un operador vinculado';
    case 'USER_NOT_FOUND_BY_PHONE':
      return 'No encontramos un usuario con ese teléfono';
    case 'TENANT_USER_ALREADY_LINKED':
      return 'Este usuario ya está vinculado a otro operador';
    case 'OPERATOR_ALREADY_LINKED':
      return 'Este operador ya está vinculado a otro usuario';
    case 'USER_HAS_ACTIVE_SESSIONS':
      return 'No se puede eliminar: el usuario tiene sesiones activas';
    default:
      if (status == 409) return 'Conflicto: ${detail is Map ? detail['message'] ?? code : code}';
      return null;
  }
}

// ── FutureProviders para usuarios y roles ─────────────────────────────────────

final _usersListProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, tenantId) async {
    if (tenantId.isEmpty) return [];
    return IamApi.getUsers();
  },
);

final _rolesMapProvider =
    FutureProvider.autoDispose.family<Map<String, String>, String>(
  (ref, tenantId) async {
    if (tenantId.isEmpty) return {};
    final roles = await IamApi.getRoles();
    final map = <String, String>{};
    for (final e in roles) {
      final id   = e['id']?.toString() ?? '';
      final name = e['name']?.toString() ?? '';
      if (id.isNotEmpty) map[id] = name;
    }
    return map;
  },
);

// ── Sección 4 — Usuarios ──────────────────────────────────────────────────────

class _UsersCard extends ConsumerWidget {
  const _UsersCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantId   = ref.watch(activeTenantIdProvider);
    final usersAsync = ref.watch(_usersListProvider(tenantId));
    final roleMap    = ref.watch(_rolesMapProvider(tenantId)).valueOrNull ?? {};

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Usuarios',
                  style: AppTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              AppButton(
                label: '+ Invitar usuario',
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => _InviteUserDialog(
                    tenantId: tenantId,
                    onInvited: () =>
                        ref.invalidate(_usersListProvider(tenantId)),
                  ),
                ),
                variant: AppButtonVariant.teal,
                size: AppButtonSize.sm,
              ),
            ],
          ),
          const SizedBox(height: 16),
          usersAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(color: AppColors.ctTeal),
              ),
            ),
            error: (e, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FeedbackBanner(
                  message: 'Error al cargar usuarios: $e',
                  isError: true,
                ),
                const SizedBox(height: 8),
                AppButton(
                  label: 'Reintentar',
                  onPressed: () =>
                      ref.invalidate(_usersListProvider(tenantId)),
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                ),
              ],
            ),
            data: (users) => users.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No hay usuarios registrados en este tenant.',
                      style: AppTextStyles.pageSubtitle,
                    ),
                  )
                : _UsersTable(
                    users: users,
                    tenantId: tenantId,
                    roleMap: roleMap,
                    onRefresh: () =>
                        ref.invalidate(_usersListProvider(tenantId)),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Tabla de usuarios ─────────────────────────────────────────────────────────

class _UsersTable extends StatelessWidget {
  const _UsersTable({
    required this.users,
    required this.tenantId,
    required this.roleMap,
    required this.onRefresh,
  });
  final List<Map<String, dynamic>> users;
  final String tenantId;
  final Map<String, String> roleMap;
  final VoidCallback onRefresh;

  static TextStyle get _h => AppTextStyles.kpiLabel.copyWith(letterSpacing: 0.4);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.ctSurface2,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
            ),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text('USUARIO', style: _h)),
                Expanded(flex: 2, child: Text('TELÉFONO', style: _h)),
                Expanded(flex: 2, child: Text('ROL', style: _h)),
                Expanded(flex: 2, child: Text('STATUS', style: _h)),
                const SizedBox(width: 36),
              ],
            ),
          ),
          // Rows
          ...users.asMap().entries.map((entry) {
            final i = entry.key;
            final u = entry.value;
            return Column(
              children: [
                if (i > 0) const Divider(height: 1, color: AppColors.ctBorder),
                _UserRow(
                  user: u,
                  tenantId: tenantId,
                  roleMap: roleMap,
                  isLast: i == users.length - 1,
                  onRefresh: onRefresh,
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ── Fila de usuario ───────────────────────────────────────────────────────────

class _UserRow extends ConsumerStatefulWidget {
  const _UserRow({
    required this.user,
    required this.tenantId,
    required this.roleMap,
    required this.isLast,
    required this.onRefresh,
  });
  final Map<String, dynamic> user;
  final String tenantId;
  final Map<String, String> roleMap;
  final bool isLast;
  final VoidCallback onRefresh;

  @override
  ConsumerState<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends ConsumerState<_UserRow> {
  bool _hovered = false;
  bool _acting  = false;

  String get _id => widget.user['id']?.toString() ?? '';
  String get _name =>
      widget.user['name']?.toString() ??
      widget.user['nombre']?.toString() ??
      widget.user['display_name']?.toString() ?? '';
  String get _email =>
      widget.user['email']?.toString() ??
      widget.user['user_email']?.toString() ?? '';
  String get _phone =>
      widget.user['phone']?.toString() ??
      widget.user['telefono']?.toString() ??
      widget.user['phone_number']?.toString() ?? '';
  String get _roleId =>
      widget.user['role_id']?.toString() ?? '';
  String get _role {
    final nested = widget.user['roles'];
    if (nested is Map) {
      final name = nested['name']?.toString();
      if (name != null && name.isNotEmpty) return name;
    }
    if (_roleId.isNotEmpty) return widget.roleMap[_roleId] ?? _roleId;
    return widget.user['role']?.toString() ??
           widget.user['role_name']?.toString() ?? '';
  }

  String get _status => widget.user['status']?.toString() ?? 'active';

  String get _tenantUserId =>
      widget.user['tenant_user_id']?.toString() ??
      widget.user['id']?.toString() ?? '';

  void _showManageChannelsDialog() {
    showDialog(
      context: context,
      builder: (_) => _ManageChannelsDialog(
        tenantUserId: _tenantUserId,
        tenantId: widget.tenantId,
        userName: _name.isNotEmpty ? _name : _email,
      ),
    );
  }

  Future<void> _patch(Map<String, dynamic> body) async {
    if (_id.isEmpty) return;
    setState(() => _acting = true);
    try {
      await IamApi.updateUser(_id, body);
      widget.onRefresh();
    } catch (_) {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _resendInvitation() async {
    if (_id.isEmpty) return;
    setState(() => _acting = true);
    try {
      await IamApi.resendInvite(_id);
      if (mounted) setState(() => _acting = false);
    } catch (_) {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _email;
    if (email.isEmpty) return;
    try {
      await IamApi.resetPassword(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Enlace enviado a $email', style: AppTextStyles.body),
          backgroundColor: AppColors.ctNavy,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(_errorSnack('Error al enviar el enlace: $e'));
      }
    }
  }

  void _showPasswordResetConfirm() {
    final email = _email;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Enviar reset de contraseña',
          style: AppTextStyles.body.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '¿Enviar enlace de recuperación de contraseña a $email?',
          style: AppTextStyles.pageSubtitle,
        ),
        actions: [
          AppButton(
            label: 'Cancelar',
            onPressed: () => Navigator.of(ctx).pop(false),
            variant: AppButtonVariant.outline,
            size: AppButtonSize.sm,
          ),
          AppButton(
            label: 'Enviar',
            onPressed: () => Navigator.of(ctx).pop(true),
            variant: AppButtonVariant.teal,
            size: AppButtonSize.sm,
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) _sendPasswordReset();
    });
  }

  void _showChangeRoleDialog() {
    showDialog(
      context: context,
      builder: (_) => _ChangeRoleDialog(
        userId: _id,
        tenantId: widget.tenantId,
        onChanged: widget.onRefresh,
      ),
    );
  }

  void _showEditDialog() {
    showDialog(
      context: context,
      builder: (_) => _EditUserDialog(
        userId: _id,
        initialNombre: _name,
        initialTelefono: _phone,
        onSaved: widget.onRefresh,
      ),
    );
  }

  String? get _operatorId =>
      widget.user['operator_id']?.toString();

  void _showDeleteConfirm() {
    final hasOperator = _operatorId != null && _operatorId!.isNotEmpty;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Eliminar usuario',
          style: AppTextStyles.body.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Eliminar a ${_name.isNotEmpty ? _name : _email}?',
              style: AppTextStyles.pageSubtitle,
            ),
            if (hasOperator) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.ctWarnBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.ctWarnText),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Este usuario está vinculado a un operador. Al eliminarlo, el operador quedará sin usuario asociado.',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctWarnText),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          AppButton(
            label: 'Cancelar',
            onPressed: () => Navigator.of(ctx).pop(false),
            variant: AppButtonVariant.outline,
            size: AppButtonSize.sm,
          ),
          AppButton(
            label: 'Eliminar',
            onPressed: () => Navigator.of(ctx).pop(true),
            variant: AppButtonVariant.danger,
            size: AppButtonSize.sm,
          ),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed != true || _id.isEmpty) return;
      setState(() => _acting = true);
      try {
        await IamApi.deleteUser(_id);
        widget.onRefresh();
      } on DioException catch (e) {
        if (!mounted) return;
        setState(() => _acting = false);
        final friendly = _friendlyError409(e);
        ScaffoldMessenger.of(context).showSnackBar(
          _errorSnack(friendly ?? 'Error al eliminar usuario'),
        );
      } catch (_) {
        if (mounted) setState(() => _acting = false);
      }
    });
  }

  void _showRevokeConfirm() {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Revocar invitación',
          style: AppTextStyles.body.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '¿Revocar la invitación enviada a ${_email.isNotEmpty ? _email : _name}? La invitación dejará de ser válida.',
          style: AppTextStyles.pageSubtitle,
        ),
        actions: [
          AppButton(
            label: 'Cancelar',
            onPressed: () => Navigator.of(ctx).pop(false),
            variant: AppButtonVariant.outline,
            size: AppButtonSize.sm,
          ),
          AppButton(
            label: 'Revocar',
            onPressed: () => Navigator.of(ctx).pop(true),
            variant: AppButtonVariant.danger,
            size: AppButtonSize.sm,
          ),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed != true || _id.isEmpty) return;
      setState(() => _acting = true);
      try {
        await IamApi.revokeInvitation(_id);
        widget.onRefresh();
      } on DioException catch (e) {
        if (!mounted) return;
        setState(() => _acting = false);
        final friendly = _friendlyError409(e);
        ScaffoldMessenger.of(context).showSnackBar(
          _errorSnack(friendly ?? 'Error al revocar la invitación'),
        );
      } catch (_) {
        if (mounted) setState(() => _acting = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final canManageUsers = hasPermission(ref, 'users', 'manage');
    final borderRadius = widget.isLast
        ? const BorderRadius.only(
            bottomLeft: Radius.circular(7),
            bottomRight: Radius.circular(7),
          )
        : BorderRadius.zero;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          color: _hovered ? AppColors.ctBg : AppColors.ctSurface,
          borderRadius: borderRadius,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Usuario
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_name.isNotEmpty)
                    Text(
                      _name,
                      style: AppTextStyles.btnSecondary,
                    ),
                  Text(
                    _email,
                    style: AppTextStyles.body.copyWith(
                      fontSize: _name.isNotEmpty ? 11 : 13,
                      color: _name.isNotEmpty ? AppColors.ctText2 : AppColors.ctText,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Teléfono
            Expanded(
              flex: 2,
              child: Text(
                _phone.isNotEmpty ? _phone : '—',
                style: AppTextStyles.navItem,
              ),
            ),

            // Rol
            Expanded(
              flex: 2,
              child: _RoleBadge(role: _role),
            ),

            // Status
            Expanded(
              flex: 2,
              child: _StatusBadge(status: _status),
            ),

            // Acciones
            SizedBox(
              width: 36,
              child: _acting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.ctTeal,
                      ),
                    )
                  : PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        size: 18,
                        color: AppColors.ctText3,
                      ),
                      color: AppColors.ctSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: AppColors.ctBorder),
                      ),
                      itemBuilder: (_) {
                        final items = <PopupMenuEntry<String>>[];
                        if (_status == 'active') {
                          items.add(const PopupMenuItem(
                            value: 'edit',
                            child: Text('Editar',
                                style: AppTextStyles.body),
                          ));
                          if (canManageUsers) {
                            items.add(const PopupMenuItem(
                              value: 'role',
                              child: Text('Cambiar rol',
                                  style: AppTextStyles.body),
                            ));
                            items.add(const PopupMenuItem(
                              value: 'password_reset',
                              child: Text('Enviar reset de contraseña',
                                  style: AppTextStyles.body),
                            ));
                            items.add(const PopupMenuItem(
                              value: 'suspend',
                              child: Text('Suspender',
                                  style: AppTextStyles.body),
                            ));
                          }
                        } else if (_status == 'suspended') {
                          items.add(const PopupMenuItem(
                            value: 'edit',
                            child: Text('Editar',
                                style: AppTextStyles.body),
                          ));
                          if (canManageUsers) {
                            items.add(const PopupMenuItem(
                              value: 'role',
                              child: Text('Cambiar rol',
                                  style: AppTextStyles.body),
                            ));
                            items.add(const PopupMenuItem(
                              value: 'reactivate',
                              child: Text('Reactivar',
                                  style: AppTextStyles.body),
                            ));
                          }
                        } else if (_status == 'invited') {
                          if (canManageUsers) {
                            items.add(const PopupMenuItem(
                              value: 'resend',
                              child: Text('Reenviar invitación',
                                  style: AppTextStyles.body),
                            ));
                            items.add(PopupMenuItem(
                              value: 'revoke',
                              child: Text('Revocar invitación',
                                  style: AppTextStyles.body.copyWith(color: AppColors.ctDanger)),
                            ));
                          }
                        }
                        if (_role.toLowerCase() != 'admin') {
                          items.add(const PopupMenuItem(
                            value: 'channels',
                            child: Text('Gestionar canales',
                                style: AppTextStyles.body),
                          ));
                        }
                        if (canManageUsers && _status != 'invited') {
                          items.add(const PopupMenuDivider(height: 8));
                          items.add(PopupMenuItem(
                            value: 'delete',
                            child: Text('Eliminar',
                                style: AppTextStyles.body.copyWith(color: AppColors.ctDanger)),
                          ));
                        }
                        return items;
                      },
                      onSelected: (v) {
                        if (v == 'edit') {
                          _showEditDialog();
                        } else if (v == 'role') {
                          _showChangeRoleDialog();
                        } else if (v == 'password_reset') {
                          _showPasswordResetConfirm();
                        } else if (v == 'suspend') {
                          _patch({'status': 'suspended'});
                        } else if (v == 'reactivate') {
                          _patch({'status': 'active'});
                        } else if (v == 'resend') {
                          _resendInvitation();
                        } else if (v == 'channels') {
                          _showManageChannelsDialog();
                        } else if (v == 'delete') {
                          _showDeleteConfirm();
                        } else if (v == 'revoke') {
                          _showRevokeConfirm();
                        }
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Badges ────────────────────────────────────────────────────────────────────

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    if (role.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.ctSurface2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: Text(
        role,
        style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color textColor;
    final String label;

    if (status == 'invited') {
      bg        = AppColors.ctWarnBg;
      textColor = AppColors.ctWarnText;
      label     = 'Invitado';
    } else if (status == 'suspended') {
      bg        = AppColors.ctRedBg;
      textColor = AppColors.ctRedText;
      label     = 'Suspendido';
    } else {
      bg        = AppColors.ctOkBg;
      textColor = AppColors.ctOkText;
      label     = 'Activo';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: textColor),
      ),
    );
  }
}

// ── Dialog: Editar usuario ────────────────────────────────────────────────────

class _EditUserDialog extends StatefulWidget {
  const _EditUserDialog({
    required this.userId,
    required this.initialNombre,
    required this.initialTelefono,
    required this.onSaved,
  });
  final String userId;
  final String initialNombre;
  final String initialTelefono;
  final VoidCallback onSaved;

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _telefonoCtrl;
  bool _saving = false;
  String? _error;
  String? _phoneError;

  @override
  void initState() {
    super.initState();
    _nombreCtrl   = TextEditingController(text: widget.initialNombre);
    _telefonoCtrl = TextEditingController(text: widget.initialTelefono);
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nombre   = _nombreCtrl.text.trim();
    final phoneErr = validatePhoneE164(_telefonoCtrl.text);
    if (nombre.isEmpty) {
      setState(() => _error = 'Ingresa el nombre completo');
      return;
    }
    if (phoneErr != null) {
      setState(() => _phoneError = phoneErr);
      return;
    }
    setState(() { _saving = true; _error = null; _phoneError = null; });
    try {
      final phoneRaw = _telefonoCtrl.text.trim();
      await IamApi.updateUser(widget.userId, {
        'nombre':   nombre,
        'telefono': phoneRaw.isNotEmpty
            ? phoneRaw.replaceAll(RegExp(r'[\s\-\(\)]'), '')
            : '',
      });
      if (!mounted) return;
      widget.onSaved();
      Navigator.pop(context);
    } on DioException catch (e) {
      if (!mounted) return;
      final friendly = _friendlyError409(e);
      if (friendly != null) {
        setState(() { _saving = false; _error = friendly; });
        return;
      }
      final detail = e.response?.data is Map
          ? e.response!.data['detail']?.toString()
          : e.response?.data?.toString();
      setState(() { _saving = false; _error = detail ?? 'Error al guardar'; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _saving = false; _error = 'Error: $e'; });
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
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Editar usuario',
                style: AppTextStyles.body.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              _Field(
                label: 'Nombre completo',
                ctrl: _nombreCtrl,
                placeholder: 'Juan García',
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Teléfono (opcional)', style: AppTextStyles.formLabel),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _telefonoCtrl,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d\+\s\-\(\)]')),
                    ],
                    onChanged: (_) {
                      if (_phoneError != null) setState(() => _phoneError = null);
                    },
                    style: AppTextStyles.body,
                    decoration: InputDecoration(
                      hintText: '+52 55 1234 5678',
                      hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                      errorText: _phoneError,
                      errorStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.ctDanger),
                      filled: true,
                      fillColor: AppColors.ctSurface2,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.ctBorder2),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: _phoneError != null ? AppColors.ctDanger : AppColors.ctBorder2,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: _phoneError != null ? AppColors.ctDanger : AppColors.ctTeal,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _FeedbackBanner(message: _error!, isError: true),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancelar',
                    onPressed: () => Navigator.pop(context),
                    variant: AppButtonVariant.outline,
                    size: AppButtonSize.sm,
                  ),
                  const SizedBox(width: 10),
                  AppButton(
                    label: 'Guardar',
                    onPressed: _save,
                    variant: AppButtonVariant.teal,
                    size: AppButtonSize.sm,
                    isLoading: _saving,
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

// ── Dialog: Cambiar rol ───────────────────────────────────────────────────────

class _ChangeRoleDialog extends ConsumerStatefulWidget {
  const _ChangeRoleDialog({
    required this.userId,
    required this.tenantId,
    required this.onChanged,
  });
  final String userId;
  final String tenantId;
  final VoidCallback onChanged;

  @override
  ConsumerState<_ChangeRoleDialog> createState() => _ChangeRoleDialogState();
}

class _ChangeRoleDialogState extends ConsumerState<_ChangeRoleDialog> {
  List<Map<String, dynamic>> _roles = [];
  String? _roleId;
  bool _rolesLoading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRoles();
  }

  Future<void> _loadRoles() async {
    try {
      final roles = await IamApi.getRoles();
      if (!mounted) return;
      setState(() {
        _roles        = roles;
        _roleId       = roles.isNotEmpty ? roles.first['id']?.toString() : null;
        _rolesLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _rolesLoading = false);
    }
  }

  Future<void> _save() async {
    if (_roleId == null || _roleId!.isEmpty) return;
    setState(() { _saving = true; _error = null; });
    try {
      await IamApi.updateUserRole(widget.userId, _roleId!);
      if (!mounted) return;
      widget.onChanged();
      Navigator.pop(context);
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map
          ? e.response!.data['detail']?.toString()
          : e.response?.data?.toString();
      setState(() { _saving = false; _error = detail ?? 'Error al cambiar rol'; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _saving = false; _error = 'Error: $e'; });
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
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cambiar rol',
                style: AppTextStyles.body.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              if (_rolesLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: CircularProgressIndicator(color: AppColors.ctTeal),
                  ),
                )
              else
                Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.ctSurface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.ctBorder2),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _roles.any(
                              (r) => r['id']?.toString() == _roleId)
                          ? _roleId
                          : null,
                      isExpanded: true,
                      isDense: true,
                      style: AppTextStyles.body,
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: AppColors.ctText3,
                      ),
                      items: _roles.map((r) {
                        final id   = r['id']?.toString() ?? '';
                        final name = r['name']?.toString() ?? id;
                        return DropdownMenuItem<String>(
                          value: id,
                          child: Text(name),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _roleId = v);
                      },
                    ),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _FeedbackBanner(message: _error!, isError: true),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancelar',
                    onPressed: () => Navigator.pop(context),
                    variant: AppButtonVariant.outline,
                    size: AppButtonSize.sm,
                  ),
                  const SizedBox(width: 10),
                  AppButton(
                    label: 'Guardar',
                    onPressed: _save,
                    variant: AppButtonVariant.teal,
                    size: AppButtonSize.sm,
                    isLoading: _saving,
                    isDisabled: _rolesLoading,
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

// ── Modal invitar usuario ─────────────────────────────────────────────────────

class _InviteUserDialog extends ConsumerStatefulWidget {
  const _InviteUserDialog({required this.tenantId, required this.onInvited});
  final String tenantId;
  final VoidCallback onInvited;

  @override
  ConsumerState<_InviteUserDialog> createState() => _InviteUserDialogState();
}

class _InviteUserDialogState extends ConsumerState<_InviteUserDialog> {
  final _nombreCtrl   = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _emailCtrl    = TextEditingController();
  List<Map<String, dynamic>> _availableRoles = [];
  String? _roleId;
  bool _rolesLoading = true;
  bool _sending = false;
  String? _error;
  String? _phoneError;
  String? _emailError;

  @override
  void initState() {
    super.initState();
    _loadRoles();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRoles() async {
    try {
      final roles = await IamApi.getRoles();
      if (!mounted) return;
      setState(() {
        _availableRoles = roles;
        _roleId         = roles.isNotEmpty ? roles.first['id']?.toString() : null;
        _rolesLoading   = false;
      });
    } catch (_) {
      if (mounted) setState(() => _rolesLoading = false);
    }
  }

  Future<void> _send() async {
    final nombre     = _nombreCtrl.text.trim();
    final emailErr   = _validateEmail(_emailCtrl.text);
    final phoneErr   = validatePhoneE164(_telefonoCtrl.text);

    if (nombre.isEmpty) {
      setState(() => _error = 'Ingresa el nombre completo');
      return;
    }
    if (emailErr != null) {
      setState(() => _emailError = emailErr);
      return;
    }
    if (phoneErr != null) {
      setState(() => _phoneError = phoneErr);
      return;
    }
    if (_roleId == null || _roleId!.isEmpty) {
      setState(() => _error = 'Selecciona un rol');
      return;
    }
    setState(() { _sending = true; _error = null; _phoneError = null; _emailError = null; });
    try {
      final email    = _emailCtrl.text.trim().toLowerCase();
      final phoneRaw = _telefonoCtrl.text.trim();
      final payload = <String, dynamic>{
        'nombre':  nombre,
        'email':   email,
        'role_id': _roleId,
      };
      if (phoneRaw.isNotEmpty) {
        payload['telefono'] = phoneRaw.replaceAll(RegExp(r'[\s\-\(\)]'), '');
      }
      await IamApi.inviteUser(payload);
      if (!mounted) return;
      widget.onInvited();
      Navigator.pop(context);
    } on DioException catch (e) {
      if (!mounted) return;
      final friendly = _friendlyError409(e);
      if (friendly != null) {
        setState(() { _sending = false; _error = friendly; });
        return;
      }
      final detail = e.response?.data is Map
          ? e.response!.data['detail']?.toString()
          : e.response?.data?.toString();
      setState(() {
        _sending = false;
        _error = detail ?? 'Error al enviar la invitación';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _sending = false; _error = 'Error: $e'; });
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
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Invitar usuario',
                style: AppTextStyles.body.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              _Field(
                label: 'Nombre completo',
                ctrl: _nombreCtrl,
                placeholder: 'Juan García',
              ),
              const SizedBox(height: 12),
              _Row2(
                left: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Email', style: AppTextStyles.formLabel),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) {
                        if (_emailError != null) setState(() => _emailError = null);
                      },
                      style: AppTextStyles.body,
                      decoration: InputDecoration(
                        hintText: 'usuario@empresa.com',
                        hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                        errorText: _emailError,
                        errorStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.ctDanger),
                        filled: true,
                        fillColor: AppColors.ctSurface2,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppColors.ctBorder2),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: _emailError != null ? AppColors.ctDanger : AppColors.ctBorder2,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: _emailError != null ? AppColors.ctDanger : AppColors.ctTeal,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                right: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Teléfono (opcional)',
                      style: AppTextStyles.formLabel,
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _telefonoCtrl,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[\d\+\s\-\(\)]'),
                        ),
                      ],
                      onChanged: (_) {
                        if (_phoneError != null) {
                          setState(() => _phoneError = null);
                        }
                      },
                      style: AppTextStyles.body,
                      decoration: InputDecoration(
                        hintText: '+52 55 1234 5678',
                        hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                        errorText: _phoneError,
                        errorStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.ctDanger),
                        filled: true,
                        fillColor: AppColors.ctSurface2,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: AppColors.ctBorder2),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: _phoneError != null
                                ? AppColors.ctDanger
                                : AppColors.ctBorder2,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: _phoneError != null
                                ? AppColors.ctDanger
                                : AppColors.ctTeal,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Rol',
                style: AppTextStyles.formLabel,
              ),
              const SizedBox(height: 6),
              _rolesLoading
                  ? const SizedBox(
                      height: 40,
                      child: Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.ctTeal,
                          ),
                        ),
                      ),
                    )
                  : Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.ctSurface2,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.ctBorder2),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _availableRoles.any(
                                  (r) => r['id']?.toString() == _roleId)
                              ? _roleId
                              : null,
                          isExpanded: true,
                          isDense: true,
                          style: AppTextStyles.body,
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: AppColors.ctText3,
                          ),
                          items: _availableRoles.map((r) {
                            final id   = r['id']?.toString() ?? '';
                            final name = r['name']?.toString() ?? id;
                            return DropdownMenuItem<String>(
                              value: id,
                              child: Text(name),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _roleId = v);
                          },
                        ),
                      ),
                    ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                _FeedbackBanner(message: _error!, isError: true),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancelar',
                    onPressed: () => Navigator.pop(context),
                    variant: AppButtonVariant.outline,
                    size: AppButtonSize.sm,
                  ),
                  const SizedBox(width: 10),
                  AppButton(
                    label: 'Enviar invitación',
                    onPressed: _send,
                    variant: AppButtonVariant.teal,
                    size: AppButtonSize.sm,
                    isLoading: _sending,
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

// ── Dialog: Gestionar canales ─────────────────────────────────────────────────

class _ManageChannelsDialog extends StatefulWidget {
  const _ManageChannelsDialog({
    required this.tenantUserId,
    required this.tenantId,
    required this.userName,
  });
  final String tenantUserId;
  final String tenantId;
  final String userName;

  @override
  State<_ManageChannelsDialog> createState() => _ManageChannelsDialogState();
}

class _ManageChannelsDialogState extends State<_ManageChannelsDialog> {
  List<Map<String, dynamic>> _channels = [];
  Set<String> _assigned = {};
  bool _loading = true;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ChannelsApi.listChannels(),
        IamApi.getUserChannels(tenantUserId: widget.tenantUserId),
      ]);
      if (!mounted) return;
      final channels   = results[0];
      final accessList = results[1];
      final assigned = <String>{};
      for (final a in accessList) {
        final cid = a['channel_id']?.toString() ?? '';
        if (cid.isNotEmpty) assigned.add(cid);
      }
      setState(() {
        _channels = channels;
        _assigned = assigned;
        _loading  = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String channelId, bool checked) async {
    if (_busy.contains(channelId)) return;
    setState(() {
      _busy.add(channelId);
      if (checked) {
        _assigned.add(channelId);
      } else {
        _assigned.remove(channelId);
      }
    });
    try {
      if (checked) {
        await IamApi.assignChannel(
          tenantUserId: widget.tenantUserId,
          channelId: channelId,
        );
      } else {
        await IamApi.removeChannel(
          tenantUserId: widget.tenantUserId,
          channelId: channelId,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (checked) {
          _assigned.remove(channelId);
        } else {
          _assigned.add(channelId);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e', style: AppTextStyles.body),
          backgroundColor: AppColors.ctNavy,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(channelId));
    }
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return AppColors.ctTeal;
    final clean = hex.replaceFirst('#', '');
    final value = int.tryParse(
      clean.length == 6 ? 'FF$clean' : clean,
      radix: 16,
    );
    return value != null ? Color(value) : AppColors.ctTeal;
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
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Canales de ${widget.userName}',
                style: AppTextStyles.body.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Este usuario solo verá los canales seleccionados',
                style: AppTextStyles.navItem,
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(color: AppColors.ctTeal),
                  ),
                )
              else if (_channels.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No hay canales activos en este tenant.',
                    style: AppTextStyles.pageSubtitle,
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _channels.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1, color: AppColors.ctBorder),
                    itemBuilder: (_, i) {
                      final ch    = _channels[i];
                      final cid   = (ch['id'] ?? ch['channel_id'])?.toString() ?? '';
                      final name  = ch['display_name']?.toString() ?? cid;
                      final color = _parseColor(ch['color']?.toString());
                      final isChecked = _assigned.contains(cid);
                      final isBusy    = _busy.contains(cid);
                      return CheckboxListTile(
                        value: isChecked,
                        onChanged: isBusy || cid.isEmpty
                            ? null
                            : (v) => _toggle(cid, v ?? false),
                        activeColor: AppColors.ctTeal,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        secondary: isBusy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.ctTeal,
                                ),
                              )
                            : Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                        title: Text(
                          name,
                          style: AppTextStyles.body,
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.ctSurface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.ctBorder),
                ),
                child: const Text(
                  'El usuario verá solo los operadores y conversaciones de los canales asignados',
                  style: AppTextStyles.bodySmall,
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: AppButton(
                  label: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                  variant: AppButtonVariant.outline,
                  size: AppButtonSize.sm,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sección 5 — Comunicación ──────────────────────────────────────────────────

class _CommunicationSection extends ConsumerStatefulWidget {
  const _CommunicationSection();

  @override
  ConsumerState<_CommunicationSection> createState() =>
      _CommunicationSectionState();
}

class _CommunicationSectionState
    extends ConsumerState<_CommunicationSection> {
  bool _loading = true;
  bool _showSupervisorName = false;
  String _currentTenantId = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tenantId = ref.read(activeTenantIdProvider);
    if (tenantId.isNotEmpty && tenantId != _currentTenantId) {
      _currentTenantId = tenantId;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.get('/tenants/$_currentTenantId');
      final d = Map<String, dynamic>.from(res.data as Map);
      if (!mounted) return;
      setState(() {
        _showSupervisorName = d['show_supervisor_name'] == true;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(bool value) async {
    setState(() => _showSupervisorName = value);
    try {
      await ApiClient.instance.put(
        '/tenants/$_currentTenantId',
        data: {'show_supervisor_name': value},
      );
    } catch (_) {
      // Revert on error
      if (mounted) setState(() => _showSupervisorName = !value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Configuración de mensajes',
            style: AppTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(color: AppColors.ctTeal),
              ),
            )
          else ...[
            // Toggle row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mostrar nombre del usuario en mensajes salientes',
                        style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _showSupervisorName
                            ? 'El nombre del supervisor aparecerá antes del mensaje'
                            : 'Los mensajes se envían sin identificar al supervisor',
                        style: AppTextStyles.bodySmall,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _showSupervisorName,
                  onChanged: _toggle,
                  activeThumbColor: AppColors.ctTeal,
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Preview bubble
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.ctSurface2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.ctBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vista previa',
                    style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.3),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 300),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9FDD3),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(2),
                          bottomLeft: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                      ),
                      child: Text(
                        _showSupervisorName
                            ? 'Pedro: Buenos días, ¿cómo van con la ruta?'
                            : 'Buenos días, ¿cómo van con la ruta?',
                        style: AppTextStyles.body,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Así verán tus operadores los mensajes enviados desde la plataforma',
                    style: AppTextStyles.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Shared: SectionCard ───────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    required this.loading,
    required this.saving,
    required this.onSave,
    this.error,
    this.success,
  });
  final String title;
  final Widget child;
  final bool loading;
  final bool saving;
  final VoidCallback? onSave;
  final String? error;
  final String? success;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(color: AppColors.ctTeal),
              ),
            )
          else ...[
            child,
            const SizedBox(height: 20),
            if (error != null) ...[
              _FeedbackBanner(message: error!, isError: true),
              const SizedBox(height: 12),
            ],
            if (success != null) ...[
              _FeedbackBanner(message: success!, isError: false),
              const SizedBox(height: 12),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                label: 'Guardar',
                onPressed: onSave ?? () {},
                variant: AppButtonVariant.teal,
                size: AppButtonSize.sm,
                isLoading: saving,
                isDisabled: onSave == null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Shared: _Row2 ─────────────────────────────────────────────────────────────

class _Row2 extends StatelessWidget {
  const _Row2({required this.left, required this.right});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 14),
        Expanded(child: right),
      ],
    );
  }
}

// ── Shared: widgets reutilizables ─────────────────────────────────────────────

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.ctrl,
    required this.placeholder,
  });
  final String label;
  final TextEditingController ctrl;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.formLabel,
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          style: AppTextStyles.body,
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
            filled: true,
            fillColor: AppColors.ctSurface2,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.ctBorder2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.ctBorder2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.ctTeal, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.message, required this.isError});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final bg        = isError ? AppColors.ctRedBg  : AppColors.ctOkBg;
    final border    = isError ? const Color(0xFFFECACA) : AppColors.ctOk;
    final textColor = isError ? AppColors.ctRedText : AppColors.ctOkText;
    final icon      = isError
        ? Icons.error_outline_rounded
        : Icons.check_circle_outline_rounded;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: textColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.body.copyWith(color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}


// ── Helper global ─────────────────────────────────────────────────────────────

SnackBar _errorSnack(String msg) => SnackBar(
      content: Text(msg, style: AppTextStyles.body),
      backgroundColor: AppColors.ctNavy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      margin: const EdgeInsets.all(16),
    );
