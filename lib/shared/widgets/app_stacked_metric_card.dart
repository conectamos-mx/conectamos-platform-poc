import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

class AppStackedMetricCard extends StatelessWidget {
  const AppStackedMetricCard({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.accentBgColor,
    this.onTap,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color accentColor;
  final Color accentBgColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Stack(
      clipBehavior: Clip.none,
      children: [
        // Card de fondo — asoma por arriba, coloreado
        Positioned(
          top: 0,
          left: 8,
          right: 8,
          child: Container(
            height: 18,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(10)),
              border: Border.all(
                  color: accentColor.withValues(alpha: 0.25), width: 1),
            ),
          ),
        ),
        // Card principal
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.ctSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: accentColor.withValues(alpha: 0.35), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accentBgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: accentColor),
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: AppTextStyles.pageTitle.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: accentColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: AppTextStyles.navItem
                    .copyWith(color: AppColors.ctText2),
              ),
            ],
          ),
        ),
      ],
    );

    if (onTap != null) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: onTap, child: card),
      );
    }
    return card;
  }
}
