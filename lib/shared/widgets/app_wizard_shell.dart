import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import 'app_button.dart';

class AppWizardStep {
  const AppWizardStep({required this.title, required this.builder});
  final String title;
  final WidgetBuilder builder;
}

class AppWizardShell extends StatefulWidget {
  const AppWizardShell({
    super.key,
    required this.steps,
    required this.onCancel,
    required this.onConfirm,
    this.isLoading = false,
    this.canAdvance = true,
    this.confirmLabel = 'Confirmar',
    this.sidebarTitle = 'Nuevo elemento',
  });

  final List<AppWizardStep> steps;
  final VoidCallback onCancel;
  final Future<void> Function() onConfirm;
  final bool isLoading;
  final bool canAdvance;
  final String confirmLabel;
  final String sidebarTitle;

  static Future<T?> show<T>({
    required BuildContext context,
    required List<AppWizardStep> steps,
    required VoidCallback onCancel,
    required Future<void> Function() onConfirm,
    bool canAdvance = true,
    String confirmLabel = 'Confirmar',
    String sidebarTitle = 'Nuevo elemento',
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AppWizardShell(
        steps: steps,
        onCancel: onCancel,
        onConfirm: onConfirm,
        canAdvance: canAdvance,
        confirmLabel: confirmLabel,
        sidebarTitle: sidebarTitle,
      ),
    );
  }

  @override
  State<AppWizardShell> createState() => _AppWizardShellState();
}

class _AppWizardShellState extends State<AppWizardShell> {
  int _currentStep = 0;
  bool _submitting = false;

  void _next() {
    if (_currentStep < widget.steps.length - 1) {
      setState(() => _currentStep++);
    }
  }

  void _prev() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  Future<void> _confirm() async {
    setState(() => _submitting = true);
    try {
      await widget.onConfirm();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  bool get _isLastStep => _currentStep == widget.steps.length - 1;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: SizedBox(
        width: 640,
        height: 520,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSidebar(),
            const VerticalDivider(width: 1, color: AppColors.ctBorder),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Text(
              widget.sidebarTitle,
              style: AppTextStyles.body.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.ctBorder),
          const SizedBox(height: 12),
          for (int i = 0; i < widget.steps.length; i++)
            _buildSideStep(i),
        ],
      ),
    );
  }

  Widget _buildSideStep(int idx) {
    final isActive = _currentStep == idx;
    final isCompleted = _currentStep > idx;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: isCompleted
                  ? AppColors.ctOk
                  : isActive
                      ? AppColors.ctTeal
                      : AppColors.ctBorder2,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: isCompleted
                ? const Icon(Icons.check, size: 12, color: Colors.white)
                : Text(
                    '${idx + 1}',
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isActive ? AppColors.ctNavy : AppColors.ctText2,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              widget.steps[idx].title,
              style: AppTextStyles.bodySmall.copyWith(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? AppColors.ctText : AppColors.ctText2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Text(
            widget.steps[_currentStep].title,
            style: AppTextStyles.body.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Divider(height: 1, color: AppColors.ctBorder),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: widget.steps[_currentStep].builder(context),
          ),
        ),
        const Divider(height: 1, color: AppColors.ctBorder),
        _buildFooter(),
      ],
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          AppButton(
            label: 'Cancelar',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: widget.onCancel,
          ),
          const Spacer(),
          if (_currentStep > 0) ...[
            AppButton(
              label: 'Atr\u00E1s',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              onPressed: _prev,
            ),
            const SizedBox(width: 8),
          ],
          if (!_isLastStep)
            AppButton(
              label: 'Siguiente \u2192',
              variant: AppButtonVariant.primary,
              size: AppButtonSize.sm,
              isDisabled: !widget.canAdvance,
              onPressed: _next,
            )
          else
            AppButton(
              label: widget.confirmLabel,
              variant: AppButtonVariant.teal,
              size: AppButtonSize.sm,
              isLoading: _submitting || widget.isLoading,
              isDisabled: !widget.canAdvance || _submitting,
              onPressed: _confirm,
            ),
        ],
      ),
    );
  }
}
