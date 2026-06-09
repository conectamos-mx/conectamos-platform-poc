import 'dart:html' as html;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/colors.dart';
import 'app_button.dart';

// ── Widget ──────────────────────────────────────────────────────────────────

class AppTemplateDownload extends ConsumerStatefulWidget {
  const AppTemplateDownload({
    super.key,
    required this.endpoint,
    required this.filename,
    this.queryParams,
    this.label,
  });

  final String endpoint;
  final String filename;
  final Map<String, String>? queryParams;
  final String? label;

  @override
  ConsumerState<AppTemplateDownload> createState() =>
      _AppTemplateDownloadState();
}

class _AppTemplateDownloadState extends ConsumerState<AppTemplateDownload> {
  bool _downloading = false;

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);

    try {
      final response = await ref.read(apiClientProvider).dio.get<List<int>>(
        widget.endpoint,
        queryParameters: widget.queryParams,
        options: Options(responseType: ResponseType.bytes),
      );

      final bytes = response.data!;
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', widget.filename)
        ..style.display = 'none';
      html.document.body!.append(anchor);
      anchor.click();
      anchor.remove();
      html.Url.revokeObjectUrl(url);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al descargar la plantilla'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: widget.label ?? 'Descargar plantilla',
      onPressed: _download,
      variant: AppButtonVariant.ghost,
      size: AppButtonSize.sm,
      isLoading: _downloading,
      prefixIcon: const Icon(
        Icons.download_outlined,
        size: 16,
        color: AppColors.ctInk700,
      ),
    );
  }
}
