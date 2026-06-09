import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';

/// Small circular icon button for showing information/help dialogs
///
/// Usage:
/// ```dart
/// Row(
///   children: [
///     Expanded(child: TextField(...)),
///     const SizedBox(width: 8),
///     InfoIconButton(onTap: () => showDialog(...)),
///   ],
/// )
/// ```
class InfoIconButton extends StatelessWidget {
  const InfoIconButton({
    super.key,
    required this.onTap,
    this.icon = Icons.info_outline,
    this.color = AppColors.ctTeal,
  });

  /// Callback when button is tapped
  final VoidCallback onTap;

  /// Icon to display (default: Icons.info_outline)
  final IconData icon;

  /// Icon and background tint color (default: ctTeal)
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 18,
            color: color,
          ),
        ),
      ),
    );
  }
}
