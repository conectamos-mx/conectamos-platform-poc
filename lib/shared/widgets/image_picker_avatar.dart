import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/api/groups_api.dart';
import '../../core/theme/colors.dart';
import 'app_avatar.dart';

/// Generic avatar picker with upload functionality
///
/// Works with any upload endpoint. Shows avatar with custom fallback.
/// On tap, opens file picker and uploads image to backend.
///
/// Usage:
/// ```dart
/// // For groups/towers (icon fallback)
/// ImagePickerAvatar(
///   imageUrl: _iconUrl,
///   fallback: Icon(Icons.group, size: 40, color: Colors.grey),
///   onImageSelected: (url) => setState(() => _iconUrl = url),
/// )
///
/// // For users/operators (initials fallback)
/// ImagePickerAvatar(
///   imageUrl: _photoUrl,
///   fallback: Text('AB', style: TextStyle(fontSize: 24)),
///   onImageSelected: (url) => setState(() => _photoUrl = url),
/// )
/// ```
class ImagePickerAvatar extends StatefulWidget {
  const ImagePickerAvatar({
    super.key,
    this.imageUrl,
    required this.fallback,
    required this.onImageSelected,
    this.size = 80,
  });

  /// Current image URL (nullable)
  final String? imageUrl;

  /// Widget to show when no image (icon, initials, etc.)
  final Widget fallback;

  /// Callback when new image is uploaded
  final ValueChanged<String> onImageSelected;

  /// Avatar diameter
  final double size;

  @override
  State<ImagePickerAvatar> createState() => _ImagePickerAvatarState();
}

class _ImagePickerAvatarState extends State<ImagePickerAvatar> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    // Open file picker (images only)
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    setState(() => _uploading = true);

    try {
      // Upload to backend
      final url = await GroupsApi.uploadControlTowerIcon(
        fileBytes: file.bytes!,
        fileName: file.name,
      );

      if (!mounted) return;

      // Notify parent
      widget.onImageSelected(url);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Imagen subida exitosamente'),
          backgroundColor: AppColors.ctOk,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al subir imagen: $e'),
          backgroundColor: AppColors.ctDanger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _uploading ? null : _pickAndUpload,
      child: MouseRegion(
        cursor: _uploading ? SystemMouseCursors.wait : SystemMouseCursors.click,
        child: Stack(
          children: [
            // Avatar (uses AppAvatar internally)
            AppAvatar(
              imageUrl: widget.imageUrl,
              fallback: widget.fallback,
              size: widget.size,
              borderWidth: 2,
            ),

            // Loading indicator
            if (_uploading)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.5),
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.ctTeal,
                      strokeWidth: 3,
                    ),
                  ),
                ),
              ),

            // Camera icon overlay
            if (!_uploading)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.ctTeal,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.ctSurface, width: 2),
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
