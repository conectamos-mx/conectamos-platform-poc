import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/api/operator_roles_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/screen_header.dart';

// ── Pantalla principal ────────────────────────────────────────────────────────

class OperatorRolesScreen extends ConsumerStatefulWidget {
  const OperatorRolesScreen({super.key});

  @override
  ConsumerState<OperatorRolesScreen> createState() => _OperatorRolesScreenState();
}

class _OperatorRolesScreenState extends ConsumerState<OperatorRolesScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _roles = [];
  Map<String, dynamic>? _editingRole;
  bool _drawerOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
    });
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final tenantId = ref.read(activeTenantIdProvider);
      final data = await OperatorRolesApi.listRoles(dio: ref.read(apiClientProvider).dio, tenantId: tenantId);
      if (mounted) setState(() { _roles = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _openCreate() => setState(() { _editingRole = null; _drawerOpen = true; });
  void _openEdit(Map<String, dynamic> role) => setState(() { _editingRole = role; _drawerOpen = true; });
  void _closeDrawer() => setState(() { _drawerOpen = false; _editingRole = null; });

  Future<void> _confirmDelete(Map<String, dynamic> role, BuildContext ctx) async {
    final messenger = ScaffoldMessenger.of(ctx);
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dlg) => AlertDialog(
        backgroundColor: AppColors.ctSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          '¿Eliminar rol?',
          style: AppFonts.onest(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ctText),
        ),
        content: Text(
          'Se eliminará el rol "${role['label'] ?? ''}" permanentemente.',
          style: AppFonts.geist(fontSize: 13, color: AppColors.ctText2),
        ),
        actions: [
          AppButton(
            label: 'Cancelar',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: () => Navigator.of(dlg).pop(false),
          ),
          AppButton(
            label: 'Eliminar',
            variant: AppButtonVariant.danger,
            size: AppButtonSize.sm,
            onPressed: () => Navigator.of(dlg).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final id = role['id'] as String? ?? '';
    if (id.isEmpty) return;

    try {
      await OperatorRolesApi.deleteRole(dio: ref.read(apiClientProvider).dio, roleId: id);
      if (mounted) _load();
    } catch (e) {
      String msg = e.toString();
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map) {
          msg = data['detail']?.toString() ??
              data['message']?.toString() ??
              msg;
        }
      }
      messenger.showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.ctDanger,
        duration: const Duration(milliseconds: 3500),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(activeTenantIdProvider, (prev, next) {
      if (next.isNotEmpty && prev != next) _load();
    });

    final canManage = hasPermission(ref, 'operator_roles', 'manage');
    final tenantId  = ref.read(activeTenantIdProvider);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Lista principal ──────────────────────────────────────────────────
        Expanded(
          child: Column(
            children: [
              ScreenHeader(
                title: 'Roles de operadores',
                subtitle: 'Roles en campo — no confundir con roles IAM del dashboard.',
                actions: [
                  if (canManage)
                    AppButton(
                      label: '+ Nuevo rol',
                      variant: AppButtonVariant.primary,
                      size: AppButtonSize.sm,
                      onPressed: _openCreate,
                    ),
                ],
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.ctTeal))
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!,
                                    style: AppFonts.geist(
                                        fontSize: 14, color: AppColors.ctDanger)),
                                const SizedBox(height: 12),
                                AppButton(
                                  label: 'Reintentar',
                                  variant: AppButtonVariant.ghost,
                                  size: AppButtonSize.sm,
                                  onPressed: _load,
                                ),
                              ],
                            ),
                          )
                        : _roles.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.badge_outlined,
                                        size: 48, color: AppColors.ctText2),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Sin roles',
                                      style: AppFonts.onest(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.ctText2),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Crea el primer rol de operador con el botón de arriba.',
                                      style: AppFonts.geist(
                                          fontSize: 12, color: AppColors.ctText3),
                                    ),
                                  ],
                                ),
                              )
                            : SingleChildScrollView(
                                padding: const EdgeInsets.all(22),
                                child: Column(
                                  children: _roles
                                      .map((role) => Padding(
                                            padding: const EdgeInsets.only(bottom: 8),
                                            child: _RoleCard(
                                              role: role,
                                              canManage: canManage,
                                              onEdit: () => _openEdit(role),
                                              onDelete: () =>
                                                  _confirmDelete(role, context),
                                            ),
                                          ))
                                      .toList(),
                                ),
                              ),
              ),
            ],
          ),
        ),

        // ── Drawer lateral ───────────────────────────────────────────────────
        if (_drawerOpen)
          _RoleEditorDrawer(
            key: ValueKey(_editingRole?['id'] ?? 'new'),
            tenantId: tenantId,
            dio: ref.read(apiClientProvider).dio,
            role: _editingRole,
            canManage: canManage,
            onSaved: () { _closeDrawer(); _load(); },
            onClose: _closeDrawer,
          ),
      ],
    );
  }
}

// ── Role card ─────────────────────────────────────────────────────────────────

class _RoleCard extends StatefulWidget {
  const _RoleCard({
    required this.role,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });
  final Map<String, dynamic> role;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final role  = widget.role;
    final label = role['label'] as String? ?? '—';
    final slug  = role['slug']  as String? ?? '';
    final hex   = role['color'] as String? ?? '#59E0CC';
    final operatorsCount = role['operators_count'] as int? ?? 0;

    Color roleColor;
    try {
      roleColor = Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      roleColor = const Color(0xFF59E0CC);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          color:   _hovered ? AppColors.ctBg : AppColors.ctSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.ctBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Color circle
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: roleColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.group, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 14),
              // Label + slug
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: AppFonts.onest(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ctText),
                    ),
                    if (slug.isNotEmpty)
                      Text(slug,
                          style: AppFonts.geist(
                              fontSize: 11, color: AppColors.ctText3)),
                  ],
                ),
              ),
              // Operators count
              Text(
                '$operatorsCount operadores',
                style: AppFonts.geist(fontSize: 12, color: AppColors.ctText2),
              ),
              if (widget.canManage) ...[
                const SizedBox(width: 4),
                IconButton(
                  onPressed: widget.onEdit,
                  tooltip: 'Editar',
                  icon: const Icon(Icons.edit_outlined,
                      size: 16, color: AppColors.ctText2),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                ),
                IconButton(
                  onPressed: widget.onDelete,
                  tooltip: 'Eliminar',
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 16, color: AppColors.ctDanger),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Editor drawer ─────────────────────────────────────────────────────────────

class _RoleEditorDrawer extends StatefulWidget {
  const _RoleEditorDrawer({
    super.key,
    required this.tenantId,
    required this.dio,
    required this.role,
    required this.canManage,
    required this.onSaved,
    required this.onClose,
  });
  final String tenantId;
  final Dio dio;
  final Map<String, dynamic>? role;
  final bool canManage;
  final VoidCallback onSaved;
  final VoidCallback onClose;

  @override
  State<_RoleEditorDrawer> createState() => _RoleEditorDrawerState();
}

class _RoleEditorDrawerState extends State<_RoleEditorDrawer> {
  late TextEditingController _labelCtrl;
  late TextEditingController _slugCtrl;
  late TextEditingController _descCtrl;
  bool _slugManuallyEdited = false;
  String _selectedColor = '#59E0CC';
  bool _saving = false;
  String? _error;

  static const _kPresetColors = [
    '#59E0CC', '#3B82F6', '#8B5CF6', '#F97316',
    '#EF4444', '#22C55E', '#EC4899', '#6B7280',
  ];

  @override
  void initState() {
    super.initState();
    final r = widget.role;
    _labelCtrl = TextEditingController(text: r?['label'] as String? ?? '');
    _slugCtrl  = TextEditingController(text: r?['slug']  as String? ?? '');
    _descCtrl  = TextEditingController(text: r?['description'] as String? ?? '');
    _selectedColor = r?['color'] as String? ?? '#59E0CC';
    if (r == null) {
      _labelCtrl.addListener(_autoSlug);
    } else {
      _slugManuallyEdited = true;
    }
  }

  void _autoSlug() {
    if (_slugManuallyEdited) return;
    final slug = _labelCtrl.text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    _slugCtrl.text = slug;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _slugCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final label = _labelCtrl.text.trim();
    final slug  = _slugCtrl.text.trim();
    if (label.isEmpty || slug.isEmpty) {
      setState(() => _error = 'Nombre y slug son requeridos.');
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() { _saving = true; _error = null; });

    final body = {
      'label': label,
      'slug': slug,
      if (_descCtrl.text.trim().isNotEmpty) 'description': _descCtrl.text.trim(),
      'color': _selectedColor,
    };

    try {
      final existing = widget.role;
      if (existing == null) {
        await OperatorRolesApi.createRole(
            dio: widget.dio, tenantId: widget.tenantId, body: body);
        if (mounted) {
          messenger.showSnackBar(const SnackBar(
              content: Text('Rol creado correctamente.')));
          widget.onSaved();
        }
      } else {
        final id = existing['id'] as String? ?? '';
        await OperatorRolesApi.updateRole(
            dio: widget.dio, tenantId: widget.tenantId, roleId: id, body: body);
        if (mounted) {
          messenger.showSnackBar(const SnackBar(
              content: Text('Rol actualizado correctamente.')));
          widget.onSaved();
        }
      }
    } catch (e) {
      String msg = e.toString();
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map) {
          msg = data['detail']?.toString() ??
              data['message']?.toString() ??
              msg;
        }
      }
      if (mounted) setState(() { _saving = false; _error = msg; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCreate = widget.role == null;

    return Container(
      width: 360,
      decoration: const BoxDecoration(
        color: AppColors.ctSurface,
        border: Border(left: BorderSide(color: AppColors.ctBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: AppColors.ctSurface2,
              border: Border(bottom: BorderSide(color: AppColors.ctBorder)),
            ),
            child: Row(
              children: [
                Text(
                  isCreate ? 'Nuevo rol' : 'Editar rol',
                  style: AppFonts.onest(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ctText),
                ),
                const Spacer(),
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded,
                      size: 16, color: AppColors.ctText2),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          // ── Form ──────────────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.ctRedBg,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(_error!,
                          style: AppFonts.geist(
                              fontSize: 12, color: AppColors.ctDanger)),
                    ),
                    const SizedBox(height: 12),
                  ],

                  _DrawerLabel('Nombre *'),
                  const SizedBox(height: 6),
                  _DrawerField(
                    controller: _labelCtrl,
                    hint: 'Ej. Supervisor de campo',
                  ),
                  const SizedBox(height: 12),

                  _DrawerLabel('Slug *'),
                  const SizedBox(height: 6),
                  _DrawerField(
                    controller: _slugCtrl,
                    hint: 'supervisor_campo',
                    onChanged: (_) =>
                        setState(() => _slugManuallyEdited = true),
                  ),
                  const SizedBox(height: 12),

                  _DrawerLabel('Descripción'),
                  const SizedBox(height: 6),
                  _DrawerField(
                    controller: _descCtrl,
                    hint: 'Descripción opcional...',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),

                  _DrawerLabel('Color'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _kPresetColors.map((hex) {
                      final color = Color(
                          int.parse(hex.replaceFirst('#', '0xFF')));
                      final isSelected = _selectedColor == hex;
                      return MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _selectedColor = hex),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 100),
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.ctText
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: isSelected
                                ? const Icon(Icons.check_rounded,
                                    size: 14, color: Colors.white)
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),

          // ── Footer ────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.ctBorder)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Cancelar',
                    variant: AppButtonVariant.outline,
                    expand: true,
                    onPressed: widget.onClose,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    label: 'Guardar',
                    variant: AppButtonVariant.teal,
                    expand: true,
                    isLoading: _saving,
                    isDisabled: !widget.canManage,
                    onPressed: _save,
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

// ── Widgets auxiliares del drawer ─────────────────────────────────────────────

class _DrawerLabel extends StatelessWidget {
  const _DrawerLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppFonts.geist(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.ctText2),
      );
}

class _DrawerField extends StatelessWidget {
  const _DrawerField({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.onChanged,
  });
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      style: AppFonts.geist(fontSize: 13, color: AppColors.ctText),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppFonts.geist(fontSize: 13, color: AppColors.ctText3),
        filled: true,
        fillColor: AppColors.ctBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          borderSide:
              const BorderSide(color: AppColors.ctTeal, width: 1.5),
        ),
      ),
    );
  }
}

