import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

enum AppActionVariant { edit, suspend, reactivate, delete }

class AppActionButton extends StatefulWidget {
  const AppActionButton({
    super.key,
    required this.variant,
    required this.onPressed,
    this.isLoading = false,
    this.isDisabled = false,
  });

  final AppActionVariant variant;
  final VoidCallback onPressed;
  final bool isLoading;
  final bool isDisabled;

  @override
  State<AppActionButton> createState() => _AppActionButtonState();
}

class _AppActionButtonState extends State<AppActionButton> {
  bool _hovered = false;

  bool get _interactive => !widget.isLoading && !widget.isDisabled;

  String get _tooltip => switch (widget.variant) {
        AppActionVariant.edit       => 'Editar',
        AppActionVariant.suspend    => 'Suspender',
        AppActionVariant.reactivate => 'Reactivar',
        AppActionVariant.delete     => 'Eliminar',
      };

  Color get _hoverBg => switch (widget.variant) {
        AppActionVariant.edit       => AppColors.ctSurface2,
        AppActionVariant.suspend    => AppColors.ctRedBg,
        AppActionVariant.reactivate => AppColors.ctOkBg,
        AppActionVariant.delete     => AppColors.ctRedBg,
      };

  IconData get _icon => switch (widget.variant) {
        AppActionVariant.edit       => Icons.edit_outlined,
        AppActionVariant.suspend    => Icons.pause_circle_outline,
        AppActionVariant.reactivate => Icons.play_circle_outline,
        AppActionVariant.delete     => Icons.delete_outline,
      };

  Color get _iconColor => switch (widget.variant) {
        AppActionVariant.edit       => AppColors.ctText2,
        AppActionVariant.suspend    => AppColors.ctText2,
        AppActionVariant.reactivate => AppColors.ctTeal,
        AppActionVariant.delete     => AppColors.ctDanger,
      };

  @override
  Widget build(BuildContext context) {
    final child = Tooltip(
      message: _tooltip,
      decoration: BoxDecoration(
        color: AppColors.ctNavy,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: AppTextStyles.bodySmall.copyWith(color: Colors.white),
      child: MouseRegion(
        cursor: _interactive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: _interactive ? (_) => setState(() => _hovered = true) : null,
        onExit: _interactive ? (_) => setState(() => _hovered = false) : null,
        child: GestureDetector(
          onTap: _interactive ? widget.onPressed : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (_hovered && _interactive) ? _hoverBg : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: widget.isLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.ctTeal,
                    ),
                  )
                : Icon(_icon, size: 18, color: _iconColor),
          ),
        ),
      ),
    );

    return widget.isDisabled
        ? Opacity(opacity: 0.4, child: child)
        : child;
  }
}
