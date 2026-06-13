import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import 'app_dropdown.dart';
import 'app_multi_select.dart';
import 'app_text_field.dart';

/// Composite row for configuring a single query metric.
///
/// Shows: field dropdown + ops multi-select + optional display_name + remove.
/// Used by the Consulta tab in the flow detail editor (PLA-205).
class AppMetricConfigRow extends StatefulWidget {
  const AppMetricConfigRow({
    super.key,
    required this.fieldItems,
    required this.selectedKey,
    required this.ops,
    required this.allOps,
    required this.inheritedLabel,
    required this.canManage,
    required this.onKeyChanged,
    required this.onOpsChanged,
    required this.onDisplayNameCommitted,
    required this.onRemove,
    this.displayName,
    this.errorText,
  });

  final List<AppDropdownItem<String>> fieldItems;
  final String? selectedKey;
  final List<String> ops;
  final List<String> allOps;
  final String inheritedLabel;
  final bool canManage;
  final ValueChanged<String?> onKeyChanged;
  final ValueChanged<List<String>> onOpsChanged;
  final ValueChanged<String> onDisplayNameCommitted;
  final VoidCallback onRemove;
  final String? displayName;
  final String? errorText;

  @override
  State<AppMetricConfigRow> createState() => _AppMetricConfigRowState();
}

class _AppMetricConfigRowState extends State<AppMetricConfigRow> {
  late TextEditingController _dnCtrl;

  @override
  void initState() {
    super.initState();
    _dnCtrl = TextEditingController(text: widget.displayName ?? '');
  }

  @override
  void didUpdateWidget(AppMetricConfigRow old) {
    super.didUpdateWidget(old);
    final dn = widget.displayName ?? '';
    if (dn != _dnCtrl.text && dn != old.displayName) {
      _dnCtrl.text = dn;
    }
  }

  @override
  void dispose() {
    _dnCtrl.dispose();
    super.dispose();
  }

  void _commitDisplayName() {
    widget.onDisplayNameCommitted(_dnCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final key = widget.selectedKey ?? '';
    final isStar = key == '*';
    final opsItems = (isStar ? ['count'] : widget.allOps)
        .map((op) => AppMultiSelectItem(value: op, label: op))
        .toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.ctSurface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.errorText != null ? AppColors.ctDanger : AppColors.ctBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: AppDropdown<String>(
                  label: 'Campo',
                  items: widget.fieldItems,
                  value: key.isEmpty ? null : key,
                  hint: 'Selecciona campo',
                  enabled: widget.canManage,
                  onChanged: widget.onKeyChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Operaciones',
                        style: AppTextStyles.bodySmall
                            .copyWith(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    AppMultiSelect<String>(
                      items: opsItems,
                      selectedValues: widget.ops,
                      placeholder: 'Selecciona...',
                      onChanged: widget.onOpsChanged,
                    ),
                  ],
                ),
              ),
              if (widget.canManage) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onRemove,
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Icon(Icons.close_rounded,
                        size: 18, color: AppColors.ctText3),
                  ),
                ),
              ],
            ],
          ),
          if (!isStar && key.isNotEmpty) ...[
            const SizedBox(height: 8),
            Focus(
              onFocusChange: (hasFocus) {
                if (!hasFocus) _commitDisplayName();
              },
              child: AppTextField(
                controller: _dnCtrl,
                label: 'Nombre de presentaci\u00F3n',
                hint: widget.inheritedLabel.isNotEmpty
                    ? widget.inheritedLabel
                    : 'Nombre personalizado',
                onChanged: (_) {},
              ),
            ),
          ],
          if (widget.errorText != null) ...[
            const SizedBox(height: 4),
            Text(widget.errorText!,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.ctDanger)),
          ],
        ],
      ),
    );
  }
}
