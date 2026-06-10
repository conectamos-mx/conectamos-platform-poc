import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';

/// Flexible avatar component for displaying circular images with fallback
///
/// Shows [imageUrl] when available; falls back to [fallback] widget.
/// Supports any fallback: icons, initials, logos, etc.
///
/// Usage:
/// ```dart
/// // With icon fallback (groups, entities)
/// AppAvatar(
///   imageUrl: iconUrl,
///   size: 40,
///   fallback: Icon(Icons.group, color: Colors.grey),
/// )
///
/// // With initials fallback (operators, users)
/// AppAvatar(
///   imageUrl: photoUrl,
///   size: 32,
///   fallback: Text('AB', style: TextStyle(...)),
/// )
/// ```
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.imageUrl,
    required this.fallback,
    this.size = 40,
    this.borderColor,
    this.borderWidth = 1,
    this.backgroundColor,
  });

  /// Optional image URL to display
  final String? imageUrl;

  /// Widget to show when no image (icon, text, etc.)
  final Widget fallback;

  /// Avatar diameter
  final double size;

  /// Optional border color (default: ctBorder)
  final Color? borderColor;

  /// Border width (default: 1)
  final double borderWidth;

  /// Background color (default: ctSurface2)
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor ?? AppColors.ctSurface2,
        border: Border.all(
          color: borderColor ?? AppColors.ctBorder,
          width: borderWidth,
        ),
        image: imageUrl != null && imageUrl!.isNotEmpty
            ? DecorationImage(
                image: NetworkImage(imageUrl!),
                fit: BoxFit.cover,
                onError: (error, stackTrace) {
                  // Fallback se mostrará automáticamente si la imagen falla
                },
              )
            : null,
      ),
      child: imageUrl == null || imageUrl!.isEmpty
          ? Center(child: fallback)
          : null,
    );
  }
}
