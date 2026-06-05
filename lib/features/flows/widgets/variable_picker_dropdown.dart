import 'package:flutter/material.dart';
import '../../../shared/widgets/app_dropdown.dart';

/// Metadata variable definition used to build the dropdown items.
class _MetaVar {
  const _MetaVar(this.key, this.label, this.template);

  /// Internal tracking key, e.g. `__meta.operator.name`.
  final String key;

  /// Human-readable label shown in the dropdown.
  final String label;

  /// Template string written to the value controller, e.g. `{{operator.name}}`.
  final String template;
}

/// Grouped list of platform metadata variables available for Google Sheets
/// column mapping. Organised by category.
const _kMetaSections = <(String header, IconData icon, List<_MetaVar>)>[
  (
    'OPERADOR',
    Icons.person_outline,
    [
      _MetaVar('__meta.operator.name', 'Nombre del operador', '{{operator.name}}'),
      _MetaVar('__meta.operator.phone', 'Teléfono del operador', '{{operator.phone}}'),
      _MetaVar('__meta.operator.email', 'Email del operador', '{{operator.email}}'),
      _MetaVar('__meta.operator.id', 'ID del operador', '{{operator.id}}'),
    ],
  ),
  (
    'EJECUCIÓN',
    Icons.play_circle_outline,
    [
      _MetaVar('__meta.execution.execution_id', 'ID de ejecución', '{{execution.execution_id}}'),
      _MetaVar('__meta.execution.date', 'Fecha (YYYY-MM-DD)', '{{execution.date}}'),
      _MetaVar('__meta.execution.time', 'Hora (HH:MM:SS)', '{{execution.time}}'),
      _MetaVar('__meta.execution.completed_at', 'Fecha de completado', '{{execution.completed_at}}'),
      _MetaVar('__meta.execution.created_at', 'Fecha de creación', '{{execution.created_at}}'),
    ],
  ),
  (
    'FLUJO / CANAL',
    Icons.description_outlined,
    [
      _MetaVar('__meta.execution.flow_name', 'Nombre del flujo', '{{execution.flow_name}}'),
      _MetaVar('__meta.execution.flow_definition_id', 'ID del flujo', '{{execution.flow_definition_id}}'),
      _MetaVar('__meta.execution.worker_name', 'Nombre del worker', '{{execution.worker_name}}'),
      _MetaVar('__meta.execution.channel_name', 'Nombre del canal', '{{execution.channel_name}}'),
    ],
  ),
];

/// All known metadata keys for validation purposes.
final Set<String> kAllMetaKeys = {
  for (final section in _kMetaSections)
    for (final v in section.$3) v.key,
};

/// A searchable dropdown that shows both flow fields and platform metadata
/// variables, grouped by category.
///
/// Used in Google Sheets append_row and update_row column mapping to let the
/// user choose what value goes into each column.
class VariablePickerDropdown extends StatelessWidget {
  const VariablePickerDropdown({
    super.key,
    required this.flowFields,
    required this.catalogSchemas,
    required this.onSelected,
    this.selectedKey,
    this.loadingCatalogSchemas = false,
    this.hint = 'Campo o variable\u2026',
  });

  /// Flow field definitions from the flow being edited.
  final List<Map<String, dynamic>> flowFields;

  /// Loaded catalog schemas for asset_ref field expansion.
  final Map<String, List<Map<String, dynamic>>> catalogSchemas;

  /// Called when the user selects an item.
  /// [key] is the internal tracking key (field key or `__meta.*`).
  /// [template] is the template string to write (e.g. `{{fields.nombre}}`).
  /// When the user picks "Personalizado", both are `null` / empty.
  final void Function(String? key, String template) onSelected;

  /// Currently selected key, or null for "Personalizado" / nothing.
  final String? selectedKey;

  /// Whether catalog schemas are still loading.
  final bool loadingCatalogSchemas;

  /// Placeholder text shown when nothing is selected.
  final String hint;

  List<AppDropdownItem<String?>> _buildItems() {
    final items = <AppDropdownItem<String?>>[];

    // ── "Personalizado…" option ───────────────────────────────────────────
    items.add(const AppDropdownItem<String?>(
      value: '__custom__',
      label: 'Personalizado\u2026',
    ));

    // ── Flow fields section ───────────────────────────────────────────────
    if (flowFields.isNotEmpty) {
      items.add(AppDropdownItem<String?>(
        value: '__section_fields',
        label: 'CAMPOS DEL FLUJO',
        enabled: false,
        icon: Icons.edit_note,
      ));

      for (final f in flowFields) {
        final key = f['key'] as String? ?? '';
        final label = f['label'] as String? ?? key;
        final type = f['type'] as String?;
        final slug = f['catalog_slug'] as String?;

        if (type == 'asset_ref' && slug != null && catalogSchemas.containsKey(slug)) {
          for (final col in catalogSchemas[slug]!) {
            final colKey = col['key'] as String? ?? '';
            final colLabel = col['label'] as String? ?? colKey;
            if (colKey.isEmpty) continue;
            items.add(AppDropdownItem<String?>(
              value: '$key.data.$colKey',
              label: '$label > $colLabel',
              subtitle: 'Campo',
            ));
          }
        } else {
          items.add(AppDropdownItem<String?>(
            value: key,
            label: label,
            subtitle: 'Campo',
          ));
        }
      }
    }

    // ── Metadata sections ─────────────────────────────────────────────────
    for (final section in _kMetaSections) {
      items.add(AppDropdownItem<String?>(
        value: '__section_${section.$1}',
        label: section.$1,
        enabled: false,
        icon: section.$2,
      ));
      for (final v in section.$3) {
        items.add(AppDropdownItem<String?>(
          value: v.key,
          label: v.label,
          subtitle: section.$1,
        ));
      }
    }

    // ── Temporary placeholder for loading compound keys ───────────────────
    if (loadingCatalogSchemas &&
        selectedKey != null &&
        selectedKey!.contains('.') &&
        !selectedKey!.startsWith('__meta.') &&
        !_allFieldKeys().contains(selectedKey)) {
      items.add(AppDropdownItem<String?>(
        value: selectedKey,
        label: 'Cargando\u2026',
      ));
    }

    return items;
  }

  Set<String> _allFieldKeys() {
    final keys = <String>{};
    for (final f in flowFields) {
      final key = f['key'] as String? ?? '';
      final type = f['type'] as String?;
      final slug = f['catalog_slug'] as String?;
      if (type == 'asset_ref' && slug != null && catalogSchemas.containsKey(slug)) {
        for (final col in catalogSchemas[slug]!) {
          final colKey = col['key'] as String? ?? '';
          if (colKey.isNotEmpty) keys.add('$key.data.$colKey');
        }
      } else {
        keys.add(key);
      }
    }
    return keys;
  }

  @override
  Widget build(BuildContext context) {
    // Map __custom__ sentinel to null for display and vice-versa.
    final displayValue = selectedKey ?? '__custom__';

    return AppDropdown<String?>(
      value: displayValue,
      hint: loadingCatalogSchemas ? 'Cargando campos\u2026' : hint,
      searchable: true,
      searchHint: 'Buscar campo o variable\u2026',
      items: _buildItems(),
      onChanged: (value) {
        if (value == '__custom__' || value == null) {
          onSelected(null, '');
          return;
        }

        // Section headers should not trigger selection.
        if (value.startsWith('__section_')) return;

        // Metadata variable selected.
        if (value.startsWith('__meta.')) {
          for (final section in _kMetaSections) {
            for (final v in section.$3) {
              if (v.key == value) {
                onSelected(v.key, v.template);
                return;
              }
            }
          }
          return;
        }

        // Flow field selected.
        onSelected(value, '{{fields.$value}}');
      },
    );
  }
}
