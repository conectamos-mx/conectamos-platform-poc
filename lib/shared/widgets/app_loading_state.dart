import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

enum _AppLoadingVariant { full, inline, overlay }

class AppLoadingState extends StatelessWidget {
  const AppLoadingState({super.key, this.message})
      : _variant = _AppLoadingVariant.full;

  const AppLoadingState.inline({super.key, this.message})
      : _variant = _AppLoadingVariant.inline;

  const AppLoadingState.overlay({super.key, this.message})
      : _variant = _AppLoadingVariant.overlay;

  final String? message;
  final _AppLoadingVariant _variant;

  @override
  Widget build(BuildContext context) {
    final spinner = _Spinner(message: message);

    switch (_variant) {
      case _AppLoadingVariant.full:
        return Center(child: spinner);
      case _AppLoadingVariant.inline:
        return SizedBox(
          height: 120,
          child: Center(child: spinner),
        );
      case _AppLoadingVariant.overlay:
        return Stack(
          children: [
            const Opacity(
              opacity: 0.4,
              child: ModalBarrier(dismissible: false, color: Colors.black),
            ),
            Center(child: spinner),
          ],
        );
    }
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner({this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            color: AppColors.ctTeal,
            strokeWidth: 2.0,
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 16),
          Text(
            message!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
