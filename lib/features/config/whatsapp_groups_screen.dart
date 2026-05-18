import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_button.dart';

// ── Modelos mock ──────────────────────────────────────────────────────────────

class _MemberMock {
  const _MemberMock({required this.name, required this.role});
  final String name;
  final String role;

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, 2).toUpperCase();
  }
}

class _GroupMock {
  const _GroupMock({
    required this.name,
    required this.description,
    required this.phone,
    required this.statusLabel,
    required this.statusBg,
    required this.statusTextColor,
    required this.chips,
    required this.members,
    required this.secondActionLabel,
    required this.secondActionColor,
  });
  final String name;
  final String description;
  final String phone;
  final String statusLabel;
  final Color statusBg;
  final Color statusTextColor;
  final List<String> chips;
  final List<_MemberMock> members;
  final String secondActionLabel;
  final Color secondActionColor;
}

const _kGroups = [
  _GroupMock(
    name: 'Incidencias y Alertas',
    description: 'Recibe alertas automáticas del Flujo 3',
    phone: '+52 55 1234 5678 · ConectamOS Operaciones',
    statusLabel: 'Activo',
    statusBg: AppColors.ctOkBg,
    statusTextColor: AppColors.ctOkText,
    chips: ['Flujo 3 · Incidencias', 'Alertas inmediatas', '3 miembros'],
    members: [
      _MemberMock(name: 'Carlos Mendez', role: 'Supervisor'),
      _MemberMock(name: 'Ana Torres', role: 'Coordinación'),
      _MemberMock(name: 'Pedro Ruiz', role: 'Coordinación'),
    ],
    secondActionLabel: 'Ver en WhatsApp',
    secondActionColor: AppColors.ctText2,
  ),
  _GroupMock(
    name: 'Reporte de Turnos',
    description: 'Recibe resúmenes de inicio y cierre del Flujo 1',
    phone: '+52 55 1234 5678 · ConectamOS Operaciones',
    statusLabel: 'Activo',
    statusBg: AppColors.ctOkBg,
    statusTextColor: AppColors.ctOkText,
    chips: ['Flujo 1 · Turno', 'Resumen por turno', '2 miembros'],
    members: [
      _MemberMock(name: 'Carlos Mendez', role: 'Supervisor'),
      _MemberMock(name: 'Ana Torres', role: 'Coordinación'),
    ],
    secondActionLabel: 'Ver en WhatsApp',
    secondActionColor: AppColors.ctText2,
  ),
  _GroupMock(
    name: 'Log de Registros',
    description: 'Recibe log de eventos del Flujo 2',
    phone: '+52 55 9876 5432 · ConectamOS Soporte',
    statusLabel: 'Pausado',
    statusBg: AppColors.ctWarnBg,
    statusTextColor: AppColors.ctWarnText,
    chips: ['Flujo 2 · Registros', 'Log completo', '2 miembros'],
    members: [
      _MemberMock(name: 'Carlos Mendez', role: 'Supervisor'),
      _MemberMock(name: 'Pedro Ruiz', role: 'Coordinación'),
    ],
    secondActionLabel: 'Reactivar',
    secondActionColor: AppColors.ctOk,
  ),
];

// ── Pantalla ──────────────────────────────────────────────────────────────────

class WhatsAppGroupsScreen extends ConsumerWidget {
  const WhatsAppGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _ActionBar(
          onNew: () => showDialog(
            context: context,
            builder: (_) => const _CreateGroupDialog(),
          ),
        ),
        const Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(22),
            child: _GroupsBody(),
          ),
        ),
      ],
    );
  }
}

// ── Action bar ────────────────────────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.onNew});
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.ctSurface,
        border: Border(bottom: BorderSide(color: AppColors.ctBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Grupos WhatsApp',
                  style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist'),
                ),
                const SizedBox(height: 1),
                Text(
                  'Configura los grupos de salida para notificaciones y reportes',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
          AppButton(
            label: '+ Crear grupo',
            variant: AppButtonVariant.teal,
            size: AppButtonSize.sm,
            onPressed: onNew,
          ),
        ],
      ),
    );
  }
}

// ── Cuerpo ────────────────────────────────────────────────────────────────────

class _GroupsBody extends StatelessWidget {
  const _GroupsBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _InfoBanner(),
        const SizedBox(height: 16),
        ..._kGroups.map(
          (g) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _GroupCard(group: g),
          ),
        ),
      ],
    );
  }
}

// ── Banner informativo ────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.ctInfoBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: AppColors.ctInfoText,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Los grupos de salida reciben reportes automáticos generados por ConectamOS. Los operadores no son miembros de estos grupos.',
              style: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: AppColors.ctInfoText, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card de grupo ─────────────────────────────────────────────────────────────

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});
  final _GroupMock group;

  @override
  Widget build(BuildContext context) {
    final g = group;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ícono WhatsApp
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.ctOkBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.chat_rounded,
                    size: 20,
                    color: AppColors.ctOkText,
                  ),
                ),
                const SizedBox(width: 14),

                // Nombre + descripción + número
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.name,
                        style: AppTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        g.description,
                        style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.phone_outlined,
                            size: 11,
                            color: AppColors.ctText3,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            g.phone,
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),

                // Badge + botones
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: g.statusBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        g.statusLabel,
                        style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: g.statusTextColor),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _GhostButton(
                          label: 'Editar',
                          color: AppColors.ctInfo,
                          icon: Icons.edit_outlined,
                          onTap: () {},
                        ),
                        const SizedBox(width: 6),
                        _GhostButton(
                          label: g.secondActionLabel,
                          color: g.secondActionColor,
                          onTap: () {},
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Chips de metadata ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: g.chips.map((c) => _MetadataChip(label: c)).toList(),
            ),
          ),
          const SizedBox(height: 14),

          // ── Sección miembros ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.ctBorder)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MIEMBROS',
                  style: AppTextStyles.kpiLabel.copyWith(color: AppColors.ctText3, letterSpacing: 1.0),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: g.members
                      .map((m) => _GroupMember(member: m))
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Miembro del grupo ─────────────────────────────────────────────────────────

class _GroupMember extends StatelessWidget {
  const _GroupMember({required this.member});
  final _MemberMock member;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.ctSurface2,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.ctBorder),
          ),
          alignment: Alignment.center,
          child: Text(
            member.initials,
            style: AppTextStyles.kpiLabel,
          ),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              member.name,
              style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w500, color: AppColors.ctText),
            ),
            Text(
              member.role,
              style: AppTextStyles.caption,
            ),
          ],
        ),
      ],
    );
  }
}

// ── Modal crear grupo ─────────────────────────────────────────────────────────

class _CreateGroupDialog extends StatefulWidget {
  const _CreateGroupDialog();

  @override
  State<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<_CreateGroupDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  static const _phoneOptions = [
    '+52 55 1234 5678 · ConectamOS Operaciones',
    '+52 55 9876 5432 · ConectamOS Soporte',
  ];
  static const _flowOptions = [
    'Flujo 1 · Turno',
    'Flujo 2 · Registros',
    'Flujo 3 · Incidencias',
  ];
  static const _reportTypes = [
    'Alertas inmediatas',
    'Resumen por turno',
    'Log completo',
  ];

  String _selectedPhone = _phoneOptions[0];
  String _selectedFlow = _flowOptions[0];
  int _reportType = 0;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
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
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Título
              Text(
                'Crear grupo de WhatsApp',
                style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist'),
              ),
              const SizedBox(height: 20),

              // Nombre
              _DialogField(
                label: 'Nombre del grupo',
                controller: _nameCtrl,
                placeholder: 'Ej: Alertas de Turno',
              ),
              const SizedBox(height: 14),

              // Descripción
              _DialogField(
                label: 'Descripción',
                controller: _descCtrl,
                placeholder: 'Describe el propósito del grupo...',
              ),
              const SizedBox(height: 14),

              // Número de WhatsApp
              _DialogSelect(
                label: 'Número de WhatsApp',
                value: _selectedPhone,
                options: _phoneOptions,
                onChanged: (v) => setState(() => _selectedPhone = v),
              ),
              const SizedBox(height: 14),

              // Flujo asociado
              _DialogSelect(
                label: 'Flujo asociado',
                value: _selectedFlow,
                options: _flowOptions,
                onChanged: (v) => setState(() => _selectedFlow = v),
              ),
              const SizedBox(height: 18),

              // Tipo de reporte
              Text(
                'Tipo de reporte',
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.ctBorder),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: List.generate(_reportTypes.length, (i) {
                    final isLast = i == _reportTypes.length - 1;
                    return Column(
                      children: [
                        InkWell(
                          borderRadius: isLast
                              ? const BorderRadius.only(
                                  bottomLeft: Radius.circular(7),
                                  bottomRight: Radius.circular(7),
                                )
                              : BorderRadius.zero,
                          onTap: () => setState(() => _reportType = i),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _reportType == i
                                          ? AppColors.ctTeal
                                          : AppColors.ctBorder2,
                                      width: 1.5,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: _reportType == i
                                      ? Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: AppColors.ctTeal,
                                            shape: BoxShape.circle,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _reportTypes[i],
                                  style: AppTextStyles.body,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (!isLast)
                          const Divider(
                              height: 1, color: AppColors.ctBorder),
                      ],
                    );
                  }),
                ),
              ),
              const SizedBox(height: 24),

              // Botones
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancelar',
                    variant: AppButtonVariant.outline,
                    size: AppButtonSize.sm,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  AppButton(
                    label: 'Crear grupo',
                    variant: AppButtonVariant.teal,
                    size: AppButtonSize.sm,
                    onPressed: () => Navigator.pop(context),
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

// ── Widgets reutilizables ─────────────────────────────────────────────────────

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.ctSurface2,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodySmall,
      ),
    );
  }
}

class _GhostButton extends StatefulWidget {
  const _GhostButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.icon,
  });
  final String label;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  State<_GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<_GhostButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered
                ? widget.color.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: _hovered
                  ? widget.color.withValues(alpha: 0.4)
                  : AppColors.ctBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 12,
                  color: _hovered ? widget.color : AppColors.ctText2,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                widget.label,
                style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w500, color: _hovered ? widget.color : AppColors.ctText2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.label,
    required this.controller,
    required this.placeholder,
  });
  final String label;
  final TextEditingController controller;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: AppTextStyles.body,
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
            filled: true,
            fillColor: AppColors.ctSurface2,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
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
        ),
      ],
    );
  }
}

class _DialogSelect extends StatelessWidget {
  const _DialogSelect({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
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
              value: value,
              isExpanded: true,
              isDense: true,
              style: AppTextStyles.body,
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: AppColors.ctText3,
              ),
              items: options
                  .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}

