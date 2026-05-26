import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/operators_api.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_dropdown.dart';

class ImportOperatorsDialog extends StatefulWidget {
  const ImportOperatorsDialog({super.key, required this.onSuccess});
  final VoidCallback onSuccess;

  @override
  State<ImportOperatorsDialog> createState() => _ImportOperatorsDialogState();
}

class _ImportOperatorsDialogState extends State<ImportOperatorsDialog> {
  // Step 1 state
  String _strategy = 'all_or_nothing';
  String? _fileName;
  Uint8List? _fileBytes;
  bool _uploading = false;

  // Step 2 state
  Map<String, dynamic>? _result;
  String? _error;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
      withData: true,
    );
    if (result != null && result.files.single.bytes != null) {
      setState(() {
        _fileBytes = result.files.single.bytes;
        _fileName = result.files.single.name;
      });
    }
  }

  Future<void> _downloadTemplate() async {
    final url = OperatorsApi.templateUrl();
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _import() async {
    if (_fileBytes == null || _fileName == null) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final result = await OperatorsApi.importOperators(
        fileBytes: _fileBytes!,
        fileName: _fileName!,
        strategy: _strategy,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _uploading = false;
      });
      final created = result['created'] as int? ?? 0;
      if (created > 0) widget.onSuccess();
    } on DioException catch (e) {
      if (!mounted) return;
      final data = e.response?.data;
      if (data is Map && data['errors'] != null) {
        setState(() {
          _result = Map<String, dynamic>.from(data);
          _uploading = false;
        });
        return;
      }
      final detail = data is Map ? data['detail'] as String? : null;
      setState(() {
        _error = detail ?? 'Error ${e.response?.statusCode ?? ''} al importar';
        _uploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _uploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: _result != null || _error != null
            ? _buildResultStep()
            : _buildConfigStep(),
      ),
    );
  }

  Widget _buildConfigStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Importar operadores',
                        style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w700, fontSize: 17)),
                    const SizedBox(height: 4),
                    Text('Sube un archivo .xlsx o .csv con los datos de operadores',
                        style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.ctText2)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: AppColors.ctText2),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1, color: AppColors.ctBorder),
        // Body
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Template download
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.ctInfoBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.ctInfo.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: AppColors.ctInfoText),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Descarga la plantilla para asegurar el formato correcto.',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctInfoText),
                        ),
                      ),
                      const SizedBox(width: 10),
                      AppButton(
                        label: 'Descargar plantilla',
                        variant: AppButtonVariant.ghost,
                        size: AppButtonSize.sm,
                        onPressed: _downloadTemplate,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Strategy
                AppDropdown<String>(
                  label: 'Estrategia de importaci\u00F3n',
                  value: _strategy,
                  hint: 'Seleccionar',
                  items: const [
                    AppDropdownItem(
                      value: 'all_or_nothing',
                      label: 'Todo o nada',
                      subtitle: 'Cancela la importaci\u00F3n completa si hay errores',
                    ),
                    AppDropdownItem(
                      value: 'skip_errors',
                      label: 'Saltar errores',
                      subtitle: 'Importa las filas v\u00E1lidas y omite las que fallan',
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _strategy = v);
                  },
                ),
                const SizedBox(height: 20),

                // File picker
                Text('Archivo',
                    style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _uploading ? null : _pickFile,
                  child: MouseRegion(
                    cursor: _uploading
                        ? SystemMouseCursors.basic
                        : SystemMouseCursors.click,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      decoration: BoxDecoration(
                        color: AppColors.ctSurface2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _fileName != null
                              ? AppColors.ctTeal
                              : AppColors.ctBorder,
                          style: _fileName != null
                              ? BorderStyle.solid
                              : BorderStyle.solid,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            _fileName != null
                                ? Icons.check_circle_rounded
                                : Icons.upload_file_rounded,
                            size: 28,
                            color: _fileName != null
                                ? AppColors.ctTeal
                                : AppColors.ctText3,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _fileName ?? 'Haz clic para seleccionar archivo (.xlsx, .csv)',
                            style: AppTextStyles.body.copyWith(
                              color: _fileName != null
                                  ? AppColors.ctText
                                  : AppColors.ctText3,
                              fontWeight: _fileName != null
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        // Footer
        const Divider(height: 1, color: AppColors.ctBorder),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                label: 'Cancelar',
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.sm,
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              AppButton(
                label: 'Importar',
                variant: AppButtonVariant.teal,
                size: AppButtonSize.sm,
                isLoading: _uploading,
                isDisabled: _fileBytes == null,
                onPressed: _import,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultStep() {
    final created = _result?['created'] as int? ?? 0;
    final skipped = _result?['skipped'] as int? ?? 0;
    final errors = (_result?['errors'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text('Resultado de importaci\u00F3n',
                    style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w700, fontSize: 17)),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: AppColors.ctText2),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1, color: AppColors.ctBorder),
        // Body
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.ctRedBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.ctDanger.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, size: 16, color: AppColors.ctDanger),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_error!,
                              style: AppTextStyles.body.copyWith(color: AppColors.ctRedText)),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Summary badges
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      if (created > 0)
                        AppBadge(
                          label: '$created operador${created == 1 ? '' : 'es'} creado${created == 1 ? '' : 's'}',
                          variant: AppBadgeVariant.ok,
                        ),
                      if (skipped > 0)
                        AppBadge(
                          label: '$skipped omitido${skipped == 1 ? '' : 's'}',
                          variant: AppBadgeVariant.warn,
                        ),
                      if (errors.isNotEmpty)
                        AppBadge(
                          label: '${errors.length} error${errors.length == 1 ? '' : 'es'}',
                          variant: AppBadgeVariant.danger,
                        ),
                      if (created == 0 && skipped == 0 && errors.isEmpty)
                        AppBadge(
                          label: 'Sin cambios',
                          variant: AppBadgeVariant.neutral,
                        ),
                    ],
                  ),
                  // Errors list
                  if (errors.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Errores por fila',
                        style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    ...errors.map((err) {
                      final row = err['row'] as int? ?? 0;
                      final field = err['field'] as String? ?? '';
                      final message = err['message'] as String? ?? err['code'] as String? ?? '';
                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.ctSurface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.ctBorder),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.ctRedBg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('Fila $row',
                                  style: AppTextStyles.caption.copyWith(
                                      fontWeight: FontWeight.w700, color: AppColors.ctDanger)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (field.isNotEmpty)
                                    Text(field,
                                        style: AppTextStyles.bodySmall.copyWith(
                                            fontWeight: FontWeight.w600, color: AppColors.ctText)),
                                  Text(message,
                                      style: AppTextStyles.bodySmall.copyWith(
                                          color: AppColors.ctText2)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        // Footer
        const Divider(height: 1, color: AppColors.ctBorder),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                label: 'Cerrar',
                variant: AppButtonVariant.primary,
                size: AppButtonSize.sm,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
