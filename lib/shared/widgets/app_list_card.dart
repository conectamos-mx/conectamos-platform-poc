import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

/// Metadata row for AppListCard - icon + text pair
class AppListCardMetadata {
  const AppListCardMetadata({
    required this.icon,
    required this.text,
    this.iconColor,
    this.textStyle,
  });

  final IconData icon;
  final String text;
  final Color? iconColor;
  final TextStyle? textStyle;
}

/// Action icon button for AppListCard
class AppListCardAction {
  const AppListCardAction({
    required this.icon,
    required this.onPressed,
    this.color,
    this.tooltip,
    this.isDisabled = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;
  final String? tooltip;
  final bool isDisabled;
}

/// Banner for warnings/info messages in AppListCard
class AppListCardBanner {
  const AppListCardBanner({
    required this.message,
    this.icon = Icons.info_outline,
    this.backgroundColor,
    this.borderColor,
    this.textColor,
    this.iconColor,
  });

  final String message;
  final IconData icon;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? textColor;
  final Color? iconColor;

  /// Warning banner preset
  factory AppListCardBanner.warning(String message) {
    return AppListCardBanner(
      message: message,
      icon: Icons.warning_amber,
      backgroundColor: AppColors.ctWarnBg,
      borderColor: AppColors.ctWarn.withValues(alpha: 0.3),
      textColor: AppColors.ctWarnText,
      iconColor: AppColors.ctWarn,
    );
  }

  /// Info banner preset
  factory AppListCardBanner.info(String message) {
    return AppListCardBanner(
      message: message,
      icon: Icons.info_outline,
      backgroundColor: AppColors.ctSurface2,
      borderColor: AppColors.ctBorder2,
      textColor: AppColors.ctText2,
      iconColor: AppColors.ctText3,
    );
  }
}

/// Reusable list card component for displaying items with icon actions
///
/// Supports:
/// - Title with optional trailing widget (badge, icon, etc.)
/// - Optional subtitle/description
/// - Icon action buttons in header (edit, delete, etc.)
/// - Metadata rows (icon + text pairs) below divider
/// - Optional banner messages
/// - Custom content area for complex layouts
///
/// Usage:
/// ```dart
/// AppListCard(
///   title: 'Torre Central',
///   trailing: AppBadge(label: 'Activo', variant: AppBadgeVariant.ok),
///   subtitle: 'Notificaciones de urgencia',
///   metadataRows: [
///     AppListCardMetadata(icon: Icons.chat, text: 'WHATSAPP'),
///     AppListCardMetadata(icon: Icons.tag, text: 'ext-123'),
///   ],
///   actions: [
///     AppListCardAction(
///       icon: Icons.edit,
///       color: AppColors.ctTeal,
///       tooltip: 'Editar',
///       onPressed: () {},
///     ),
///     AppListCardAction(
///       icon: Icons.delete_outline,
///       color: AppColors.ctDanger,
///       tooltip: 'Eliminar',
///       onPressed: () {},
///     ),
///   ],
/// )
/// ```
class AppListCard extends StatelessWidget {
  const AppListCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leadingIcon,
    this.metadataRows = const [],
    this.actions = const [],
    this.banner,
    this.customContent,
    this.onTap,
  });

  /// Card title (required)
  final String title;

  /// Optional subtitle/description shown below title
  final String? subtitle;

  /// Optional widget shown on the right side of title (typically a badge)
  final Widget? trailing;

  /// Optional leading icon (shown on the left, useful for entity type icons)
  final Widget? leadingIcon;

  /// Metadata rows shown below divider (icon + text pairs)
  final List<AppListCardMetadata> metadataRows;

  /// Icon action buttons shown in header (edit, delete, etc.)
  final List<AppListCardAction> actions;

  /// Optional banner message (warning, info, etc.)
  final AppListCardBanner? banner;

  /// Custom content widget inserted between metadata and actions
  /// Use this for complex layouts that don't fit the standard pattern
  final Widget? customContent;

  /// Optional tap handler for the entire card
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.ctSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.ctBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Title + Badge + Metadata + Actions
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (leadingIcon != null) ...[
                  leadingIcon!,
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: AppTextStyles.body.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          if (trailing != null) ...[
                            const SizedBox(width: 8),
                            trailing!,
                          ],
                        ],
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 13,
                            color: AppColors.ctText2,
                          ),
                        ),
                      ],
                      // Metadata rows
                      if (metadataRows.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          children: metadataRows.map((meta) {
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  meta.icon,
                                  size: 14,
                                  color: meta.iconColor ?? AppColors.ctText3,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  meta.text,
                                  style: meta.textStyle ??
                                      AppTextStyles.caption.copyWith(
                                        color: AppColors.ctText3,
                                      ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                // Icon action buttons
                if (actions.isNotEmpty)
                  ...actions.map((action) => IconButton(
                    icon: Icon(action.icon, size: 18),
                    color: action.color ?? AppColors.ctText2,
                    onPressed: action.isDisabled ? null : action.onPressed,
                    tooltip: action.tooltip,
                  )),
              ],
            ),

            // Custom content area
            if (customContent != null) ...[
              const SizedBox(height: 12),
              customContent!,
            ],

            // Banner (warning, info, etc.)
            if (banner != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: banner!.backgroundColor ?? AppColors.ctSurface2,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: banner!.borderColor ?? AppColors.ctBorder2,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      banner!.icon,
                      size: 14,
                      color: banner!.iconColor ?? AppColors.ctText3,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        banner!.message,
                        style: AppTextStyles.caption.copyWith(
                          color: banner!.textColor ?? AppColors.ctText2,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
