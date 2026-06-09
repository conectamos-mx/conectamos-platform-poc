import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import 'app_dropdown.dart';
import 'app_switch.dart';
import 'app_text_field.dart';

class CatalogItemForm extends StatefulWidget {
  const CatalogItemForm({
    super.key,
    required this.fieldsSchema,
    required this.primaryKeyField,
    this.initialData,
    this.enabled = true,
  });

  final List<Map<String, dynamic>> fieldsSchema;
  final String primaryKeyField;
  final Map<String, dynamic>? initialData;
  final bool enabled;

  @override
  State<CatalogItemForm> createState() => CatalogItemFormState();
}

class CatalogItemFormState extends State<CatalogItemForm> {
  final Map<String, TextEditingController> _textCtrls = {};
  final Map<String, bool> _boolValues = {};
  final Map<String, String?> _selectValues = {};
  final Map<String, String?> _fieldErrors = {};

  bool get _isEditMode => widget.initialData != null;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  @override
  void dispose() {
    for (final ctrl in _textCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _initControllers() {
    for (final field in widget.fieldsSchema) {
      final key = field['key'] as String? ?? '';
      if (key.isEmpty) continue;

      final type = field['type'] as String? ?? 'text';
      final options = _getOptions(field);
      final initial = widget.initialData?[key];

      if (type == 'boolean') {
        _boolValues[key] = _parseBool(initial);
      } else if (options.isNotEmpty) {
        _selectValues[key] = initial?.toString();
      } else {
        _textCtrls[key] = TextEditingController(
          text: initial?.toString() ?? '',
        );
      }
    }
  }

  bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    if (value is num) return value != 0;
    return false;
  }

  List<String> _getOptions(Map<String, dynamic> field) {
    final raw = field['options'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => e.toString()).toList();
    }
    return [];
  }

  bool validate() {
    bool valid = true;
    setState(() {
      _fieldErrors.clear();
      for (final field in widget.fieldsSchema) {
        final key = field['key'] as String? ?? '';
        if (key.isEmpty) continue;
        final type = field['type'] as String? ?? 'text';

        if (key == widget.primaryKeyField) {
          final val = _textCtrls[key]?.text.trim() ?? '';
          if (val.isEmpty) {
            _fieldErrors[key] = 'Campo obligatorio';
            valid = false;
          }
        }

        if (type == 'number') {
          final text = _textCtrls[key]?.text.trim() ?? '';
          if (text.isNotEmpty && num.tryParse(text) == null) {
            _fieldErrors[key] = 'Debe ser un numero valido';
            valid = false;
          }
        }
      }
    });
    return valid;
  }

  Map<String, dynamic> getValue() {
    final result = <String, dynamic>{};
    for (final field in widget.fieldsSchema) {
      final key = field['key'] as String? ?? '';
      if (key.isEmpty) continue;
      final type = field['type'] as String? ?? 'text';
      final options = _getOptions(field);

      if (type == 'boolean') {
        result[key] = _boolValues[key] ?? false;
      } else if (options.isNotEmpty) {
        final val = _selectValues[key];
        if (val != null) result[key] = val;
      } else if (type == 'number') {
        final text = _textCtrls[key]?.text.trim() ?? '';
        if (text.isEmpty) continue;
        final parsed = num.tryParse(text);
        if (parsed != null) result[key] = parsed;
      } else {
        result[key] = _textCtrls[key]?.text.trim() ?? '';
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final field in widget.fieldsSchema)
          _buildField(field),
      ],
    );
  }

  Widget _buildField(Map<String, dynamic> field) {
    final key = field['key'] as String? ?? '';
    if (key.isEmpty) return const SizedBox.shrink();

    final label = field['label'] as String? ?? key;
    final type = field['type'] as String? ?? 'text';
    final options = _getOptions(field);
    final isPk = key == widget.primaryKeyField;
    final fieldEnabled = widget.enabled && !(_isEditMode && isPk);
    final error = _fieldErrors[key];

    Widget child;

    if (type == 'boolean') {
      child = AppSwitch(
        label: label,
        value: _boolValues[key] ?? false,
        enabled: fieldEnabled,
        onChanged: (v) => setState(() => _boolValues[key] = v),
      );
    } else if (options.isNotEmpty) {
      child = AppDropdown<String>(
        label: label,
        items: options
            .map((o) => AppDropdownItem<String>(value: o, label: o))
            .toList(),
        value: _selectValues[key],
        enabled: fieldEnabled,
        errorText: error,
        onChanged: (v) => setState(() {
          _selectValues[key] = v;
          _fieldErrors.remove(key);
        }),
      );
    } else if (type == 'number') {
      child = AppTextField(
        key: ValueKey('item_field_$key'),
        controller: _textCtrls[key]!,
        label: label,
        hint: isPk ? '$label (clave primaria)' : label,
        enabled: fieldEnabled,
        errorText: error,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[\d.\-]')),
        ],
        onChanged: (_) {
          if (_fieldErrors.containsKey(key)) {
            setState(() => _fieldErrors.remove(key));
          }
        },
      );
    } else {
      child = AppTextField(
        key: ValueKey('item_field_$key'),
        controller: _textCtrls[key]!,
        label: label,
        hint: isPk ? '$label (clave primaria)' : label,
        enabled: fieldEnabled,
        errorText: error,
        onChanged: (_) {
          if (_fieldErrors.containsKey(key)) {
            setState(() => _fieldErrors.remove(key));
          }
        },
      );
    }

    if (_isEditMode && isPk) {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          const SizedBox(height: 2),
          Text(
            'La clave primaria no se puede modificar',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: child,
    );
  }
}
