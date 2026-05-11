import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/screen_header.dart';

class AssignmentTypesScreen extends ConsumerWidget {
  const AssignmentTypesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.ctBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenHeader(
            title: 'Tipos de asignación',
            subtitle: 'Configura los tipos de asignación de tu tenant.',
            actions: [
              GestureDetector(
                onTap: () => context.go('/assignments'),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back_rounded,
                          size: 14, color: AppColors.ctText2),
                      const SizedBox(width: 4),
                      Text(
                        'Asignaciones',
                        style: AppFonts.geist(
                            fontSize: 13, color: AppColors.ctText2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.ctBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.category_outlined,
                        size: 36, color: AppColors.ctText3),
                    const SizedBox(height: 12),
                    Text(
                      'Configura los tipos de asignación de tu tenant.',
                      style: AppFonts.geist(
                          fontSize: 14, color: AppColors.ctText2),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'TODO: implementación completa en Parte B',
                      style: AppFonts.geist(
                        fontSize: 12,
                        color: AppColors.ctText3,
                      ).copyWith(fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
