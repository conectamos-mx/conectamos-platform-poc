import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

class AppTagChip extends StatelessWidget {
  const AppTagChip({
    super.key,
    required this.label,
    this.colorHex,
  });

  final String label;
  final String? colorHex;

  static Color _parseHex(String? hex) {
    if (hex == null || hex.isEmpty) return AppColors.ctTeal;
    try {
      final clean = hex.startsWith('#') ? hex.substring(1) : hex;
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return AppColors.ctTeal;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _parseHex(colorHex);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: AppTextStyles.badge.copyWith(color: color),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
