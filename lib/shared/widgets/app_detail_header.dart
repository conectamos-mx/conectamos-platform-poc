import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

/// Cabecera canónica de pantalla de detalle (DS §2.10).
///
/// PreferredSizeWidget — úsalo como appBar en Scaffold.
/// Layout: fila de navegación (← back + acciones) / fila de identidad
/// (avatar + título + subtítulo) / fila de chips opcionales / divider /
/// bottom opcional (TabBar).
class AppDetailHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppDetailHeader({
    super.key,
    required this.title,
    required this.backLabel,
    required this.onBack,
    this.subtitle,
    this.avatar,
    this.chips,
    this.actions = const [],
    this.bottom,
  });

  final String title;
  final String backLabel;
  final VoidCallback onBack;
  final String? subtitle;
  final Widget? avatar;
  final List<Widget>? chips;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;

  bool get _hasChips => chips != null && chips!.isNotEmpty;

  @override
  Size get preferredSize {
    double height = 52 + 56 + 1; // row1 + row2 + divider
    if (_hasChips) height += 36;
    if (bottom != null) height += bottom!.preferredSize.height;
    return Size.fromHeight(height);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Fila 1: navegación ─────────────────────────────────────────────
        Container(
          height: 52,
          color: AppColors.ctSurface,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              TextButton(
                onPressed: onBack,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  '← $backLabel',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.ctText2,
                  ),
                ),
              ),
              const Spacer(),
              for (int i = 0; i < actions.length; i++) ...[
                actions[i],
                if (i < actions.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        // ── Fila 2: identidad ──────────────────────────────────────────────
        Container(
          height: 56,
          color: AppColors.ctSurface,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (avatar != null) ...[
                SizedBox(
                  width: 40,
                  height: 40,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: avatar,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.pageTitle),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.ctText2,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        // ── Fila 3: chips (opcional) ───────────────────────────────────────
        if (_hasChips)
          Container(
            height: 36,
            color: AppColors.ctSurface,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (int i = 0; i < chips!.length; i++) ...[
                  chips![i],
                  if (i < chips!.length - 1) const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        // ── Divider ────────────────────────────────────────────────────────
        const Divider(height: 1, thickness: 1, color: AppColors.ctBorder),
        // ── Bottom (TabBar opcional) ───────────────────────────────────────
        ?bottom,
      ],
    );
  }
}
