import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import 'app_button.dart';

/// A section with view/edit toggle pattern.
///
/// In view mode shows [viewChild] with an optional "Editar" button.
/// In edit mode shows [editChild] with "Guardar" / "Cancelar" buttons.
/// [onSave] is async — the section shows a loading state on the save button
/// until it completes.
class AppEditableSection extends StatefulWidget {
  const AppEditableSection({
    super.key,
    required this.title,
    required this.viewChild,
    required this.editChild,
    required this.onSave,
    required this.onCancel,
    this.isEditing = false,
    this.onEdit,
    this.canSave = true,
    this.canEdit = true,
    this.errorText,
  });

  /// Section title shown as uppercase label.
  final String title;

  /// Content displayed in view mode.
  final Widget viewChild;

  /// Content displayed in edit mode.
  final Widget editChild;

  /// Called when the user taps "Guardar". Should throw on failure.
  final Future<void> Function() onSave;

  /// Called when the user taps "Cancelar".
  final VoidCallback onCancel;

  /// Called when the user taps "Editar".
  final VoidCallback? onEdit;

  /// Whether the section is currently in edit mode.
  final bool isEditing;

  /// Whether the save button is enabled.
  final bool canSave;

  /// Whether the edit button is shown (false hides it — read-only section).
  final bool canEdit;

  /// Error text shown below the edit content on save failure.
  final String? errorText;

  @override
  State<AppEditableSection> createState() => _AppEditableSectionState();
}

class _AppEditableSectionState extends State<AppEditableSection> {
  bool _saving = false;

  Future<void> _handleSave() async {
    setState(() => _saving = true);
    try {
      await widget.onSave();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: title + action button
        Row(
          children: [
            Text(
              widget.title.toUpperCase(),
              style: AppTextStyles.kpiLabel.copyWith(letterSpacing: 0.6),
            ),
            const Spacer(),
            if (!widget.isEditing && widget.canEdit && widget.onEdit != null)
              AppButton(
                label: 'Editar',
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.sm,
                prefixIcon: const Icon(Icons.edit_outlined,
                    size: 12, color: AppColors.ctTeal),
                onPressed: widget.onEdit!,
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Content
        if (widget.isEditing) ...[
          widget.editChild,
          if (widget.errorText != null) ...[
            const SizedBox(height: 8),
            Text(widget.errorText!,
                style:
                    AppTextStyles.bodySmall.copyWith(color: AppColors.ctDanger)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              AppButton(
                label: 'Cancelar',
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.sm,
                onPressed: _saving ? () {} : widget.onCancel,
              ),
              const SizedBox(width: 8),
              AppButton(
                label: 'Guardar',
                variant: AppButtonVariant.teal,
                size: AppButtonSize.sm,
                isLoading: _saving,
                isDisabled: !widget.canSave,
                onPressed:
                    widget.canSave && !_saving ? _handleSave : () {},
              ),
            ],
          ),
        ] else
          widget.viewChild,
      ],
    );
  }
}
