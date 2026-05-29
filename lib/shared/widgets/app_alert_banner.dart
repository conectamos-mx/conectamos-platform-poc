import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

enum AppAlertBannerVariant { danger, warning, info }

class AppAlertBanner extends StatelessWidget {
  const AppAlertBanner({
    super.key,
    required this.variant,
    required this.title,
    this.message,
    this.actions,
    this.prefixIcon,
  });

  final AppAlertBannerVariant variant;
  final String title;
  final String? message;
  final List<Widget>? actions;
  final Widget? prefixIcon;

  Color get _bgColor => switch (variant) {
        AppAlertBannerVariant.danger  => AppColors.ctRedBg,
        AppAlertBannerVariant.warning => AppColors.ctWarnBg,
        AppAlertBannerVariant.info    => AppColors.ctInfoBg,
      };

  Color get _textColor => switch (variant) {
        AppAlertBannerVariant.danger  => AppColors.ctRedText,
        AppAlertBannerVariant.warning => AppColors.ctWarnText,
        AppAlertBannerVariant.info    => AppColors.ctInfoText,
      };

  IconData get _defaultIcon => switch (variant) {
        AppAlertBannerVariant.danger  => Icons.error_outline,
        AppAlertBannerVariant.warning => Icons.warning_amber_rounded,
        AppAlertBannerVariant.info    => Icons.info_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _textColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: prefixIcon ??
                Icon(_defaultIcon, size: 22, color: _textColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTextStyles.body
                      .copyWith(fontWeight: FontWeight.w600, color: _textColor),
                ),
                if (message != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    message!,
                    style: AppTextStyles.bodySmall.copyWith(color: _textColor),
                  ),
                ],
              ],
            ),
          ),
          if (actions != null && actions!.isNotEmpty) ...[
            const SizedBox(width: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < actions!.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  actions![i],
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
