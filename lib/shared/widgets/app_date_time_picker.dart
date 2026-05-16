// TODO: reemplazar con AppDateRangePicker custom en sesión dedicada
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class AppDateTimePicker {
  static Future<DateTime?> show(
    BuildContext context, {
    DateTime? initial,
  }) async {
    final rootContext =
        Navigator.of(context, rootNavigator: true).context;
    final now = initial ?? DateTime.now();
    final baseTheme = Theme.of(rootContext).copyWith(
      colorScheme: Theme.of(rootContext).colorScheme.copyWith(
        primary: AppColors.ctTeal,
        onPrimary: Colors.white,
        surface: AppColors.ctSurface,
        onSurface: AppColors.ctText,
      ),
    );

    final date = await showDatePicker(
      context: rootContext,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      locale: const Locale('es', 'MX'),
      builder: (context, child) => Theme(data: baseTheme, child: child!),
    );
    if (date == null) return null;
    if (!rootContext.mounted) return null;

    final time = await showTimePicker(
      context: rootContext,
      initialTime: TimeOfDay.fromDateTime(now),
      builder: (context, child) => Theme(data: baseTheme, child: child!),
    );
    if (time == null) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }
}
