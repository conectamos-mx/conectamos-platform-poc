import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.formLabel.copyWith(
              color: enabled ? AppColors.ctText : AppColors.ctText3,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 24,
          child: Switch.adaptive(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: AppColors.ctTeal,
            activeTrackColor: AppColors.ctTealLight,
            inactiveThumbColor: AppColors.ctText3,
            inactiveTrackColor: AppColors.ctBorder,
          ),
        ),
      ],
    );
  }
}
