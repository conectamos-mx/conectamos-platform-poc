import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import 'app_loading_state.dart';

// ── Widget ──────────────────────────────────────────────────────────────────

class AppDropZone extends StatefulWidget {
  const AppDropZone({
    super.key,
    required this.allowedExtensions,
    required this.onFilePicked,
    this.label,
    this.sublabel,
    this.isLoading = false,
  });

  final List<String> allowedExtensions;
  final void Function(Uint8List bytes, String filename) onFilePicked;
  final String? label;
  final String? sublabel;
  final bool isLoading;

  @override
  State<AppDropZone> createState() => _AppDropZoneState();
}

class _AppDropZoneState extends State<AppDropZone> {
  bool _hovering = false;
  String? _selectedFilename;

  Future<void> _pickFile() async {
    if (widget.isLoading) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: widget.allowedExtensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    if (!_isExtensionAllowed(file.name)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Extensión no permitida. Usa: ${widget.allowedExtensions.join(', ')}',
            ),
          ),
        );
      }
      return;
    }

    setState(() => _selectedFilename = file.name);
    widget.onFilePicked(file.bytes!, file.name);
  }

  bool _isExtensionAllowed(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return widget.allowedExtensions
        .map((e) => e.toLowerCase())
        .contains(ext);
  }

  void _clear() {
    setState(() => _selectedFilename = null);
  }

  @override
  Widget build(BuildContext context) {
    final borderColor =
        _hovering ? AppColors.ctTeal : AppColors.ctBorder2;
    final bgColor =
        _hovering ? AppColors.ctTeal.withValues(alpha: 0.06) : AppColors.ctSurface;

    return GestureDetector(
      onTap: _selectedFilename == null ? _pickFile : null,
      child: MouseRegion(
        cursor: widget.isLoading
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Stack(
          children: [
            CustomPaint(
              painter: _DashedBorderPainter(color: borderColor),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 140),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 28,
                  horizontal: 24,
                ),
                child: _selectedFilename != null
                    ? _SelectedFileRow(
                        filename: _selectedFilename!,
                        onClear: _clear,
                      )
                    : _EmptyState(
                        label: widget.label,
                        sublabel: widget.sublabel,
                        extensions: widget.allowedExtensions,
                      ),
              ),
            ),
            if (widget.isLoading)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.ctSurface.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const AppLoadingState.inline(
                    message: 'Procesando archivo...',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.label,
    required this.sublabel,
    required this.extensions,
  });

  final String? label;
  final String? sublabel;
  final List<String> extensions;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_upload_outlined,
            size: 32, color: AppColors.ctText3),
        const SizedBox(height: 10),
        Text(
          label ?? 'Arrastra tu archivo aqui o',
          style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
        ),
        const SizedBox(height: 4),
        Text(
          'Seleccionar archivo',
          style: AppTextStyles.formLabel.copyWith(color: AppColors.ctTeal),
        ),
        const SizedBox(height: 8),
        Text(
          sublabel ?? 'Formatos: ${extensions.map((e) => '.${e.toUpperCase()}').join(', ')}',
          style: AppTextStyles.caption,
        ),
      ],
    );
  }
}

// ── Selected file row ───────────────────────────────────────────────────────

class _SelectedFileRow extends StatelessWidget {
  const _SelectedFileRow({
    required this.filename,
    required this.onClear,
  });

  final String filename;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, size: 20, color: AppColors.ctTeal),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            filename,
            style: AppTextStyles.body.copyWith(color: AppColors.ctText),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onClear,
            child:
                const Icon(Icons.close, size: 18, color: AppColors.ctText3),
          ),
        ),
      ],
    );
  }
}

// ── Dashed border painter ───────────────────────────────────────────────────

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});
  final Color color;

  static const double _strokeWidth = 1.5;
  static const double _dashLength = 5.0;
  static const double _gapLength = 4.0;
  static const double _radius = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(_strokeWidth / 2, _strokeWidth / 2,
            size.width - _strokeWidth, size.height - _strokeWidth),
        const Radius.circular(_radius),
      ));

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + _dashLength),
          paint,
        );
        distance += _dashLength + _gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}
