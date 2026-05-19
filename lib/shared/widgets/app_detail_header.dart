import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

// ── Status pill interno ────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final bg = active ? AppColors.ctOkBg : AppColors.ctSurface2;
    final fg = active ? AppColors.ctOkText : AppColors.ctText2;
    final dot = active ? AppColors.ctOk : AppColors.ctText3;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.formLabel.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

// ── AppDetailHeader ────────────────────────────────────────────────────────────

/// Cabecera canónica de pantalla de detalle (DS §2.10).
///
/// PreferredSizeWidget — úsalo como appBar en Scaffold.
/// Layout: fila horizontal única con back-button, identidad (avatar +
/// título + subtítulo + chips opcionales) y status pill / acciones + bottom slot.
class AppDetailHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppDetailHeader({
    super.key,
    required this.title,
    required this.backLabel,
    required this.onBack,
    this.subtitle,
    this.avatar,
    this.chips,
    this.statusLabel,
    this.statusActive,
    this.actions = const [],
    this.bottom,
  });

  final String title;
  final String backLabel;
  final VoidCallback onBack;
  final String? subtitle;
  final Widget? avatar;
  final List<Widget>? chips;
  final String? statusLabel;
  final bool? statusActive;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;

  bool get _hasChips => chips != null && chips!.isNotEmpty;

  @override
  Size get preferredSize {
    double h = 80;
    if (_hasChips) h += 28;
    if (bottom != null) h += bottom!.preferredSize.height;
    return Size.fromHeight(h);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Fila principal ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          decoration: const BoxDecoration(
            color: AppColors.ctSurface,
            border: Border(
              bottom: BorderSide(color: AppColors.ctBorder, width: 1),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Back button
              GestureDetector(
                onTap: onBack,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.ctSurface2,
                    border: Border.all(color: AppColors.ctBorder, width: 1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '← $backLabel',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.ctText2,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Identidad — Expanded
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (avatar != null) ...[
                      Container(
                        width: 40,
                        height: 40,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.ctTeal.withValues(alpha: 0.25),
                            width: 2,
                          ),
                        ),
                        child: avatar,
                      ),
                      const SizedBox(width: 12),
                    ],
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: AppTextStyles.cardTitle.copyWith(
                            fontFamily: 'Onest',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ctText,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 1),
                          Text(
                            subtitle!,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.ctText3,
                            ),
                          ),
                        ],
                        if (_hasChips) ...[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (int i = 0; i < chips!.length; i++) ...[
                                chips![i],
                                if (i < chips!.length - 1)
                                  const SizedBox(width: 6),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Derecha: actions y/o status pill
              if (actions.isNotEmpty || statusLabel != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < actions.length; i++) ...[
                      actions[i],
                      const SizedBox(width: 8),
                    ],
                    if (statusLabel != null)
                      _StatusPill(
                        label: statusLabel!,
                        active: statusActive ?? false,
                      ),
                  ],
                ),
            ],
          ),
        ),
        // ── Bottom (TabBar opcional) ─────────────────────────────────────
        ?bottom,
      ],
    );
  }
}
