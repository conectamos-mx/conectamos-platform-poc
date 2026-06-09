import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import 'app_button.dart';

enum AppConfirmDialogVariant { normal, danger }

class AppConfirmDialog extends StatelessWidget {
  const AppConfirmDialog._({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.variant,
    this.icon,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final String cancelLabel;
  final AppConfirmDialogVariant variant;
  final Widget? icon;

  static Future<bool?> show({
    required BuildContext context,
    required String title,
    required String body,
    String confirmLabel = 'Confirmar',
    String cancelLabel = 'Cancelar',
    AppConfirmDialogVariant variant = AppConfirmDialogVariant.normal,
    Widget? icon,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AppConfirmDialog._(
        title: title,
        body: body,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        variant: variant,
        icon: icon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                icon!,
                const SizedBox(height: 12),
              ],
              Text(title, style: AppTextStyles.cardTitle),
              const SizedBox(height: 8),
              Text(
                body,
                style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    key: const Key('confirm_dialog_cancel'),
                    label: cancelLabel,
                    variant: AppButtonVariant.ghost,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    key: const Key('confirm_dialog_ok'),
                    label: confirmLabel,
                    variant: variant == AppConfirmDialogVariant.danger
                        ? AppButtonVariant.danger
                        : AppButtonVariant.primary,
                    onPressed: () => Navigator.of(context).pop(true),
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
