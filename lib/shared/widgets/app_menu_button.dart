import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';

class AppMenuButtonItem {
  const AppMenuButtonItem({
    required this.label,
    required this.onTap,
    this.icon,
  });
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
}

class AppMenuButton extends StatelessWidget {
  const AppMenuButton({
    super.key,
    required this.label,
    required this.items,
    this.icon,
  });

  final String label;
  final List<AppMenuButtonItem> items;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      offset: const Offset(0, 36),
      tooltip: '',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: AppColors.ctSurface,
      elevation: 4,
      onSelected: (i) => items[i].onTap(),
      itemBuilder: (_) => [
        for (int i = 0; i < items.length; i++)
          PopupMenuItem<int>(
            value: i,
            height: 40,
            child: Row(
              children: [
                if (items[i].icon != null) ...[
                  Icon(items[i].icon, size: 16, color: AppColors.ctInk700),
                  const SizedBox(width: 10),
                ],
                Text(
                  items[i].label,
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    color: AppColors.ctText,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: IgnorePointer(
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.ctBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: AppColors.ctInk700),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ctInk700,
                  letterSpacing: -0.01,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 14, color: AppColors.ctInk700),
            ],
          ),
        ),
      ),
    );
  }
}
