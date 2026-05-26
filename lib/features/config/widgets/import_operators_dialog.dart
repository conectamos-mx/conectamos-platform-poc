import 'dart:html' as html;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/api/operators_api.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_drop_zone.dart';

import '../../../shared/widgets/app_import_preview_table.dart';
import '../../../shared/widgets/app_loading_state.dart';
import '../../../shared/widgets/app_template_download.dart';

class ImportOperatorsDialog extends StatefulWidget {
  const ImportOperatorsDialog({super.key, required this.onSuccess});
  final VoidCallback onSuccess;

  @override
  State<ImportOperatorsDialog> createState() => _ImportOperatorsDialogState();
}

class _ImportOperatorsDialogState extends State<ImportOperatorsDialog> {
  // ── Navigation ────────────────────────────────────────────────────────────
  int _step = 0; // 0=config, 1=preview, 2=result

  // ── Step 1 state ──────────────────────────────────────────────────────────
  Uint8List? _fileBytes;
  String? _fileName;
  bool _validating = false;

  // ── Step 2 state (dry_run response) ───────────────────────────────────────
  List<Map<String, dynamic>> _dryValid = [];
  List<Map<String, dynamic>> _dryErrors = [];

  // ── Step 3 state (commit response) ────────────────────────────────────────
  bool _importing = false;
  Map<String, dynamic>? _commitResult;
  String? _commitError;

  // ── Helpers ───────────────────────────────────────────────────────────────

  int get _validCount => _dryValid.length;
  int get _errorCount => _dryErrors.length;

  bool get _canImport => _validCount > 0;

  String get _importLabel => _validCount == 1
      ? 'Importar 1 operador'
      : 'Importar $_validCount operadores';

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _validate() async {
    if (_fileBytes == null || _fileName == null) return;
    setState(() => _validating = true);
    try {
      final result = await OperatorsApi.importDryRun(
        fileBytes: _fileBytes!,
        fileName: _fileName!,
        strategy: 'skip_errors',
      );
      if (!mounted) return;
      setState(() {
        _dryValid = List<Map<String, dynamic>>.from(result['valid'] ?? []);
        _dryErrors = List<Map<String, dynamic>>.from(result['errors'] ?? []);
        _validating = false;
        _step = 1;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      final data = e.response?.data;
      final detail = data is Map ? data['detail'] as String? : null;
      setState(() => _validating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(detail ?? 'Error al validar el archivo'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _validating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _import() async {
    if (_fileBytes == null || _fileName == null) return;
    setState(() {
      _importing = true;
      _commitError = null;
      _step = 2;
    });
    try {
      final result = await OperatorsApi.importOperators(
        fileBytes: _fileBytes!,
        fileName: _fileName!,
        strategy: 'skip_errors',
      );
      if (!mounted) return;
      setState(() {
        _commitResult = result;
        _importing = false;
      });
      final created = result['created'] as int? ?? 0;
      if (created > 0) widget.onSuccess();
    } on DioException catch (e) {
      if (!mounted) return;
      final data = e.response?.data;
      if (data is Map && data['errors'] != null) {
        setState(() {
          _commitResult = Map<String, dynamic>.from(data);
          _importing = false;
        });
        return;
      }
      final detail = data is Map ? data['detail'] as String? : null;
      setState(() {
        _commitError = detail ?? 'Error ${e.response?.statusCode ?? ''} al importar';
        _importing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _commitError = e.toString();
        _importing = false;
      });
    }
  }

  void _normalizePhone(Map<String, dynamic> data) {
    final phone = data['phone'];
    if (phone is String && phone.isNotEmpty && !phone.startsWith('+')) {
      data['phone'] = '+$phone';
    }
  }

  void _downloadErrors() {
    final lines = <String>['nombre,telefono,email,error'];
    for (final err in _dryErrors) {
      final name = _csvEscape(err['name'] ?? '');
      final phone = _csvEscape(err['phone'] ?? '');
      final email = _csvEscape(err['email'] ?? '');
      final message = _csvEscape(err['message'] ?? err['code'] ?? '');
      lines.add('$name,$phone,$email,$message');
    }
    final csv = lines.join('\n');
    final bytes = Uint8List.fromList(csv.codeUnits);
    final blob = html.Blob([bytes], 'text/csv');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', 'errores_importacion.csv')
      ..style.display = 'none';
    html.document.body!.append(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }

  String _csvEscape(dynamic value) {
    final s = (value ?? '').toString().replaceAll('"', '""');
    return s.contains(',') || s.contains('"') || s.contains('\n')
        ? '"$s"'
        : s;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            const Divider(height: 1, color: AppColors.ctBorder),
            Flexible(
              child: switch (_step) {
                0 => _buildConfigStep(),
                1 => _buildPreviewStep(),
                _ => _buildResultStep(),
              },
            ),
            const Divider(height: 1, color: AppColors.ctBorder),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final titles = ['Configurar', 'Preview', 'Resultado'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Importar operadores',
                  style: AppTextStyles.cardTitle.copyWith(fontSize: 17),
                ),
                const SizedBox(height: 4),
                Text(
                  'Paso ${_step + 1} de 3 \u2014 ${titles[_step]}',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: AppColors.ctText2),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  // ── Step 1: Config ────────────────────────────────────────────────────────

  Widget _buildConfigStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Template download info box
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
                const AppTemplateDownload(
                  endpoint: '/operators/export/template',
                  filename: 'plantilla_operadores.xlsx',
                  queryParams: {'nationality': 'MX'},
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // File drop zone
          Text('Archivo', style: AppTextStyles.formLabel),
          const SizedBox(height: 8),
          AppDropZone(
            allowedExtensions: const ['xlsx', 'csv'],
            isLoading: _validating,
            onFilePicked: (bytes, name) {
              setState(() {
                _fileBytes = bytes;
                _fileName = name;
              });
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Step 2: Preview ───────────────────────────────────────────────────────

  Widget _buildPreviewStep() {
    final columns = const [
      ImportColumn(header: 'Fila', key: 'row'),
      ImportColumn(header: 'Nombre', key: 'name'),
      ImportColumn(header: 'Tel\u00E9fono', key: 'phone'),
      ImportColumn(header: 'Email', key: 'email'),
    ];

    final rows = <ImportRow>[
      ..._dryValid.map((v) {
        final data = Map<String, dynamic>.from(v['data'] ?? v);
        _normalizePhone(data);
        final row = v['row'] as int? ?? 0;
        return ImportRow(row: row, data: data);
      }),
      ..._dryErrors.map((e) {
        final row = e['row'] as int? ?? 0;
        final field = e['field'] as String? ?? '';
        final message = e['message'] as String? ?? e['code'] as String? ?? '';
        return ImportRow(
          row: row,
          data: {'row': row},
          errors: [ImportRowError(field: field, message: message)],
        );
      }),
    ]..sort((a, b) => a.row.compareTo(b.row));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppImportPreviewTable(columns: columns, rows: rows),
          if (_errorCount > 0) ...[
            const SizedBox(height: 12),
            AppButton(
              label: 'Descargar errores',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              prefixIcon: const Icon(Icons.download_outlined,
                  size: 16, color: AppColors.ctInk700),
              onPressed: _downloadErrors,
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Step 3: Result ────────────────────────────────────────────────────────

  Widget _buildResultStep() {
    if (_importing) {
      return const Center(
        child: AppLoadingState.inline(message: 'Importando operadores...'),
      );
    }

    if (_commitError != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        child: Container(
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
                child: Text(
                  _commitError!,
                  style: AppTextStyles.body.copyWith(color: AppColors.ctRedText),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final created = _commitResult?['created'] as int? ?? 0;
    final skipped = _commitResult?['skipped'] as int? ?? 0;
    final errors = (_commitResult?['errors'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                const AppBadge(
                  label: 'Sin cambios',
                  variant: AppBadgeVariant.neutral,
                ),
            ],
          ),
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Errores por fila',
                style: AppTextStyles.formLabel),
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
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: switch (_step) {
          0 => [
              AppButton(
                label: 'Cancelar',
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.sm,
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              AppButton(
                label: 'Validar archivo',
                variant: AppButtonVariant.teal,
                size: AppButtonSize.sm,
                isLoading: _validating,
                isDisabled: _fileBytes == null,
                onPressed: _validate,
              ),
            ],
          1 => [
              AppButton(
                label: 'Volver',
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.sm,
                onPressed: () => setState(() => _step = 0),
              ),
              const SizedBox(width: 8),
              AppButton(
                label: _importLabel,
                variant: AppButtonVariant.teal,
                size: AppButtonSize.sm,
                isDisabled: !_canImport,
                onPressed: _import,
              ),
            ],
          _ => [
              AppButton(
                label: 'Cerrar',
                variant: AppButtonVariant.primary,
                size: AppButtonSize.sm,
                onPressed: () {
                  widget.onSuccess();
                  Navigator.pop(context);
                },
              ),
            ],
        },
      ),
    );
  }
}
