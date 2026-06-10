import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/api/operator_fields_api.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_button.dart';

// ── Field type config ──────────────────────────────────────────────────────────

const _kFieldTypes = [
  (key: 'text',     label: 'Texto',      icon: Icons.text_fields),
  (key: 'number',   label: 'Número',     icon: Icons.tag),
  (key: 'date',     label: 'Fecha',      icon: Icons.calendar_today),
  (key: 'boolean',  label: 'Sí / No',    icon: Icons.toggle_on_outlined),
  (key: 'select',   label: 'Selección',  icon: Icons.list_alt_outlined),
  (key: 'photo',    label: 'Foto',       icon: Icons.photo_camera_outlined),
  (key: 'document', label: 'Documento',  icon: Icons.attach_file),
];

String _typeLabel(String key) =>
    _kFieldTypes.firstWhere((t) => t.key == key, orElse: () => _kFieldTypes.first).label;

IconData _typeIcon(String key) =>
    _kFieldTypes.firstWhere((t) => t.key == key, orElse: () => _kFieldTypes.first).icon;

// ── Dialog ─────────────────────────────────────────────────────────────────────

class OperatorFieldFormDialog extends StatefulWidget {
  const OperatorFieldFormDialog({
    super.key,
    required this.tenantId,
    required this.dio,
    this.field,
    required this.onSaved,
  });

  final String tenantId;
  final Dio dio;
  final Map<String, dynamic>? field; // null = create mode
  final VoidCallback onSaved;

  bool get isEdit => field != null;

  @override
  State<OperatorFieldFormDialog> createState() =>
      _OperatorFieldFormDialogState();
}

class _OperatorFieldFormDialogState extends State<OperatorFieldFormDialog> {
  late TextEditingController _labelCtrl;
  late String _selectedType;
  late bool _isRequired;
  late List<String> _options;
  final TextEditingController _optionCtrl = TextEditingController();

  bool _saving = false;
  String? _labelError;
  String? _optionsError;
  String? _bannerError;

  @override
  void initState() {
    super.initState();
    final f = widget.field;
    _labelCtrl = TextEditingController(text: f?['label'] as String? ?? '');
    _selectedType = f?['field_type'] as String? ?? 'text';
    _isRequired = f?['required'] as bool? ?? false;
    final rawOpts = f?['options'];
    _options = rawOpts is List
        ? List<String>.from(rawOpts.map((e) => e.toString()))
        : [];
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _optionCtrl.dispose();
    super.dispose();
  }

  bool get _isSelect => _selectedType == 'select';

  void _addOption() {
    final v = _optionCtrl.text.trim();
    if (v.isEmpty) return;
    setState(() {
      _options.add(v);
      _optionCtrl.clear();
      _optionsError = null;
    });
  }

  void _removeOption(int i) {
    setState(() => _options.removeAt(i));
  }

  Future<void> _save() async {
    final label = _labelCtrl.text.trim();

    // Validate
    setState(() {
      _labelError = label.isEmpty ? 'El nombre es obligatorio' : null;
      _optionsError = (_isSelect && _options.length < 2)
          ? 'Agrega al menos 2 opciones'
          : null;
      _bannerError = null;
    });

    if (_labelError != null || _optionsError != null) return;

    setState(() => _saving = true);

    try {
      if (widget.isEdit) {
        await OperatorFieldsApi.updateOperatorField(
          widget.field!['id'] as String,
          dio: widget.dio,
          label: label,
          isRequired: _isRequired,
          options: _isSelect ? _options : null,
        );
      } else {
        await OperatorFieldsApi.createOperatorField(
          dio: widget.dio,
          label: label,
          fieldType: _selectedType,
          isRequired: _isRequired,
          options: _isSelect ? _options : null,
        );
      }
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
      }
    } catch (e) {
      if (!mounted) return;
      String? fieldErr;
      String? bannerErr;

      if (e is DioException) {
        final body = e.response?.data;
        if (body is Map) {
          final code = body['code'] as String?;
          final msg = body['message'] as String? ??
              body['detail']?.toString() ??
              'Error inesperado';
          if (code == 'OF_E001' || code == 'OF_E003') {
            fieldErr = msg;
          } else {
            bannerErr = msg;
          }
        } else {
          bannerErr = 'Error al guardar el campo';
        }
      } else {
        bannerErr = e.toString();
      }

      setState(() {
        _labelError = fieldErr;
        _bannerError = bannerErr;
        _saving = false;
      });
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final title = widget.isEdit ? 'Editar campo' : 'Nuevo campo';

    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.ctBorder)),
              ),
              child: Row(
                children: [
                  Text(title,
                      style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist', fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18,
                        color: AppColors.ctText2),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Banner error
                    if (_bannerError != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.ctRedBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(children: [
                          const Icon(Icons.error_outline,
                              size: 16, color: AppColors.ctDanger),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_bannerError!,
                                style: AppTextStyles.body.copyWith(color: AppColors.ctRedText)),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Label
                    const _FieldLabel('Nombre del campo *'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _labelCtrl,
                      maxLength: 50,
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'Ej: Número de empleado',
                        errorText: _labelError,
                        filled: true,
                        fillColor: AppColors.ctBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: AppColors.ctBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: AppColors.ctBorder),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      style: AppTextStyles.body.copyWith(fontSize: 14),
                      onChanged: (_) {
                        if (_labelError != null) {
                          setState(() => _labelError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Field type
                    const _FieldLabel('Tipo de campo'),
                    const SizedBox(height: 6),
                    if (widget.isEdit) ...[
                      // Read-only chip in edit mode
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.ctSurface2,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.ctBorder),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_typeIcon(_selectedType),
                                  size: 15,
                                  color: AppColors.ctText2),
                              const SizedBox(width: 6),
                              Text(_typeLabel(_selectedType),
                                  style: AppTextStyles.body.copyWith(color: AppColors.ctText2)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('El tipo no se puede cambiar',
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3)),
                      ]),
                      const SizedBox(height: 8),
                      // field_key read-only
                      if ((widget.field?['field_key'] as String?)?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 4),
                        Row(children: [
                          const _FieldLabel('Clave: '),
                          Text(
                            widget.field!['field_key'] as String,
                            style: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: AppColors.ctText3),
                          ),
                          const SizedBox(width: 6),
                          Text('(no se puede cambiar)',
                              style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3)),
                        ]),
                      ],
                    ] else ...[
                      // Dropdown in create mode
                      DropdownButtonFormField<String>(
                        initialValue: _selectedType,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppColors.ctBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: AppColors.ctBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: AppColors.ctBorder),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        dropdownColor: AppColors.ctSurface,
                        style: AppTextStyles.body.copyWith(fontSize: 14),
                        items: _kFieldTypes
                            .map((t) => DropdownMenuItem(
                                  value: t.key,
                                  child: Row(children: [
                                    Icon(t.icon,
                                        size: 16, color: AppColors.ctText2),
                                    const SizedBox(width: 8),
                                    Text(t.label),
                                  ]),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _selectedType = v);
                        },
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Required switch
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Requerido',
                                  style: AppTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.w500)),
                              Text(
                                'El operador debe completar este campo',
                                style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _isRequired,
                          activeThumbColor: AppColors.ctTeal,
                          onChanged: (v) => setState(() => _isRequired = v),
                        ),
                      ],
                    ),

                    // Options (select type only)
                    if (_isSelect) ...[
                      const SizedBox(height: 16),
                      const Divider(color: AppColors.ctBorder),
                      const SizedBox(height: 12),
                      Row(children: [
                        Text('Opciones',
                            style: AppTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 6),
                        Text('(mínimo 2)',
                            style: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: AppColors.ctText3)),
                      ]),
                      const SizedBox(height: 8),
                      if (_options.isNotEmpty) ...[
                        ..._options.asMap().entries.map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: AppColors.ctBg,
                                      border:
                                          Border.all(color: AppColors.ctBorder),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(e.value,
                                        style: AppTextStyles.body),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  icon: const Icon(Icons.close,
                                      size: 16, color: AppColors.ctText2),
                                  onPressed: () => _removeOption(e.key),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ]),
                            )),
                        const SizedBox(height: 4),
                      ],
                      // Add option field
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _optionCtrl,
                            decoration: InputDecoration(
                              hintText: 'Nueva opción...',
                              filled: true,
                              fillColor: AppColors.ctBg,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    const BorderSide(color: AppColors.ctBorder),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    const BorderSide(color: AppColors.ctBorder),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              errorText: _optionsError,
                            ),
                            style: AppTextStyles.body,
                            onSubmitted: (_) => _addOption(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        AppButton(
                          label: 'Agregar',
                          onPressed: _addOption,
                          variant: AppButtonVariant.ghost,
                          size: AppButtonSize.sm,
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.ctBorder)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancelar',
                    onPressed: () => Navigator.pop(context),
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.sm,
                    isDisabled: _saving,
                  ),
                  const SizedBox(width: 10),
                  AppButton(
                    label: widget.isEdit ? 'Guardar cambios' : 'Crear campo',
                    onPressed: _save,
                    variant: AppButtonVariant.teal,
                    size: AppButtonSize.sm,
                    isLoading: _saving,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.ctText2,
        ));
  }
}
