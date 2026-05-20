import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.description,
    this.actions = const [],
  });

  final String title;
  final String? description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
      decoration: const BoxDecoration(
        color: AppColors.ctSurface,
        border: Border(bottom: BorderSide(color: AppColors.ctBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: AppTextStyles.pageTitle),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(description!,
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.ctText2)),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 16),
            ...actions,
          ],
        ],
      ),
    );
  }
}
