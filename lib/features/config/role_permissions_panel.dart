import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/permissions_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_button.dart';

// ── Grupos de permisos para la UI ─────────────────────────────────────────────

const _kPermGroups = [
  (label: 'Conversaciones', keys: ['conversations.view', 'conversations.send', 'conversations.export']),
  (label: 'Broadcasts',     keys: ['broadcasts.send']),
  (label: 'Flujos',         keys: ['flows.view', 'flows.manage']),
  (label: 'Operadores',     keys: ['operators.view', 'operators.manage']),
  (label: 'Reportes',       keys: ['reports.view']),
  (label: 'Configuración',  keys: ['settings.view', 'settings.manage']),
  (label: 'Usuarios',       keys: ['users.view', 'users.manage']),
  (label: 'Escalaciones',   keys: ['escalations.view', 'escalations.manage']),
  (label: 'Catálogos',     keys: ['catalogs.view', 'catalogs.manage']),
  (label: 'Asignaciones',  keys: ['assignments.view', 'assignments.manage']),
  (label: 'Roles de operadores', keys: ['operator_roles.view', 'operator_roles.manage']),
  (label: 'Dashboards',     keys: ['dashboards.view', 'dashboards.manage']),
  (label: 'Ejecuciones',    keys: ['flow_executions.view_all', 'flow_executions.execute_dashboard']),
  (label: 'Integraciones',  keys: ['flow_integrations.view', 'flow_integrations.manage']),
  (label: 'Webhooks',       keys: ['webhook_secrets.view']),
  (label: 'Conectores',     keys: ['integrations.view', 'integrations.manage']),
];

// ── Panel principal ───────────────────────────────────────────────────────────

class RolePermissionsPanel extends ConsumerStatefulWidget {
  const RolePermissionsPanel({
    super.key,
    required this.roleId,
    required this.roleName,
  });

  final String roleId;
  final String roleName;

  @override
  ConsumerState<RolePermissionsPanel> createState() => _RolePermissionsPanelState();
}

class _RolePermissionsPanelState extends ConsumerState<RolePermissionsPanel> {
  bool _saving = false;

  bool get _isAdmin => widget.roleName.toLowerCase() == 'admin';

  Future<void> _save() async {
    setState(() => _saving = true);
    final err = await ref.read(rolePermissionsEditProvider(widget.roleId).notifier).save();
    if (!mounted) return;
    setState(() => _saving = false);
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Permisos actualizados correctamente.'),
        backgroundColor: AppColors.ctOk,
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err),
        backgroundColor: AppColors.ctDanger,
      ));
    }
  }

  void _toggle(String module, String action) {
    final cascades = ref
        .read(rolePermissionsEditProvider(widget.roleId).notifier)
        .toggle(module, action);
    if (!mounted) return;
    if (cascades.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(cascades.join('\n'), key: const Key('perm_cascade_msg')),
        backgroundColor: AppColors.ctTeal,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(roleName: widget.roleName),
          const Divider(height: 1, color: AppColors.ctBorder),
          if (_isAdmin)
            _AdminBody()
          else
            _EditableBody(
              roleId:   widget.roleId,
              onToggle: _toggle,
            ),
          const Divider(height: 1, color: AppColors.ctBorder),
          if (!_isAdmin) _SaveFooter(roleId: widget.roleId, saving: _saving, onSave: _save),
        ],
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.roleName});
  final String roleName;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (roleName.toLowerCase()) {
      'admin'      => (const Color(0xFFCCFBF1), AppColors.ctTealDark),
      'supervisor' => (const Color(0xFFEDE9FE), const Color(0xFF6D28D9)),
      _            => (AppColors.ctSurface2,    AppColors.ctText2),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.ctSurface2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
            child: Text(
              roleName,
              style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w700, color: fg),
            ),
          ),
          if (roleName.toLowerCase() == 'admin') ...[
            const SizedBox(width: 8),
            Tooltip(
              message: 'El rol admin siempre tiene todos los permisos',
              child: const Icon(Icons.lock_outline, size: 14, color: AppColors.ctText3),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Cuerpo admin (estático, todo deshabilitado) ───────────────────────────────

class _AdminBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: _kPermGroups.map((group) {
          return _PermGroup(
            label: group.label,
            child: Column(
              children: group.keys.map((key) {
                return _PermRow(
                  label:    kPermLabels[key] ?? key,
                  checked:  true,
                  disabled: true,
                  onChanged: null,
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Cuerpo editable ───────────────────────────────────────────────────────────

class _EditableBody extends ConsumerWidget {
  const _EditableBody({required this.roleId, required this.onToggle});
  final String roleId;
  final void Function(String module, String action) onToggle;
  String _permKey(String perm) => 'perm_${roleId}_$perm';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rolePermissionsEditProvider(roleId));

    if (state.loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(color: AppColors.ctTeal, strokeWidth: 2)),
      );
    }

    if (state.error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(state.error!, style: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: AppColors.ctDanger)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: _kPermGroups.map((group) {
          return _PermGroup(
            label: group.label,
            child: Column(
              children: group.keys.map((key) {
                final parts = key.split('.');
                final module = parts[0];
                final action = parts[1];
                return _PermRow(
                  key: Key(_permKey(key)),
                  label:    kPermLabels[key] ?? key,
                  checked:  state.grants[key] ?? false,
                  disabled: false,
                  onChanged: (v) { if (v != null) onToggle(module, action); },
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Grupo de permisos con encabezado ──────────────────────────────────────────

class _PermGroup extends StatelessWidget {
  const _PermGroup({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
            label.toUpperCase(),
            style: AppTextStyles.navSectionLabel.copyWith(color: AppColors.ctText3, letterSpacing: 0.6),
          ),
        ),
        child,
      ],
    );
  }
}

// ── Fila de permiso ───────────────────────────────────────────────────────────

class _PermRow extends StatelessWidget {
  const _PermRow({
    super.key,
    required this.label,
    required this.checked,
    required this.disabled,
    required this.onChanged,
  });
  final String     label;
  final bool       checked;
  final bool       disabled;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value:            checked,
      onChanged:        disabled ? null : onChanged,
      activeColor:      AppColors.ctTeal,
      dense:            true,
      controlAffinity:  ListTileControlAffinity.leading,
      contentPadding:   const EdgeInsets.symmetric(horizontal: 12),
      visualDensity:    VisualDensity.compact,
      title: Text(
        label,
        style: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: disabled ? AppColors.ctText3 : AppColors.ctText),
      ),
    );
  }
}

// ── Footer con botón guardar ──────────────────────────────────────────────────

class _SaveFooter extends ConsumerWidget {
  const _SaveFooter({required this.roleId, required this.saving, required this.onSave});
  final String       roleId;
  final bool         saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPending = ref.watch(
      rolePermissionsEditProvider(roleId).select((s) => s.hasPendingChanges),
    );

    final canSave = hasPending && !saving;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: AppButton(
        key: Key('perm_save_$roleId'),
        label: 'Guardar cambios',
        onPressed: onSave,
        isDisabled: !canSave,
        isLoading: saving,
        variant: AppButtonVariant.teal,
        size: AppButtonSize.sm,
        expand: true,
      ),
    );
  }
}
