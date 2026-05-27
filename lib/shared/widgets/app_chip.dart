import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

class AppChip extends StatefulWidget {
  const AppChip({
    super.key,
    required this.label,
    this.isActive = false,
    this.onTap,
    this.prefixIcon,
  });

  final String label;
  final bool isActive;
  final VoidCallback? onTap;
  final Widget? prefixIcon;

  @override
  State<AppChip> createState() => _AppChipState();
}

class _AppChipState extends State<AppChip> {
  bool _hovered = false;

  static const _textStyle = AppTextStyles.chipLabel;

  Color get _bgColor {
    if (widget.isActive) return AppColors.ctNavy;
    if (_hovered && widget.onTap != null) return AppColors.ctSurface2;
    return Colors.transparent;
  }

  Color get _textColor =>
      widget.isActive ? AppColors.ctTeal : AppColors.ctText2;

  Color get _borderColor =>
      widget.isActive ? AppColors.ctNavy : AppColors.ctBorder;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    if (widget.prefixIcon != null) {
      children.add(widget.prefixIcon!);
      children.add(const SizedBox(width: 6));
    }

    children.add(Text(
      widget.label,
      style: _textStyle.copyWith(color: _textColor),
    ));

    Widget chip = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: children,
      ),
    );

    if (widget.onTap != null) {
      chip = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: chip,
        ),
      );
    }

    return chip;
  }
}
