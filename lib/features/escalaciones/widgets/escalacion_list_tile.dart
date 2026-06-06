import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/relative_time.dart';

// ── Status chip ───────────────────────────────────────────────────────────────

class EscalacionStatusChip extends StatelessWidget {
  const EscalacionStatusChip({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (status) {
      'open'     => (AppColors.ctRedBg,    AppColors.ctRedText,    'Abierta'),
      'assigned' => (AppColors.ctWarnBg,   AppColors.ctWarnText,   'Asignada'),
      'resolved' => (AppColors.ctOkBg,     AppColors.ctOkText,     'Resuelta'),
      'reopened' => (AppColors.ctOrangeBg, AppColors.ctOrangeText, 'Reabierta'),
      _          => (AppColors.ctSurface2, AppColors.ctText2,       status),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

// ── Tile ──────────────────────────────────────────────────────────────────────

class EscalacionListTile extends StatelessWidget {
  const EscalacionListTile({
    super.key,
    required this.escalacion,
    required this.onTap,
  });

  final Map<String, dynamic> escalacion;
  final VoidCallback onTap;

  String _operatorName() {
    final op = escalacion['operator'];
    if (op is Map) {
      return op['name'] as String? ?? op['email'] as String? ?? 'Operador';
    }
    return escalacion['operator_name'] as String? ?? '—';
  }

  String _assignedToName() {
    final u = escalacion['assigned_to_user'];
    if (u is Map) {
      return u['name'] as String? ?? u['email'] as String? ?? 'Asignado';
    }
    return escalacion['assigned_to_name'] as String? ?? 'Sin asignar';
  }

  @override
  Widget build(BuildContext context) {
    final status          = escalacion['status'] as String? ?? '';
    final reason          = escalacion['reason']  as String? ?? '—';
    final openedAt        = escalacion['opened_at'] as String?;
    final workerCanResume = escalacion['worker_can_resume'] as bool? ?? false;
    final hasAssignee     = escalacion['assigned_to'] != null;

    return Card(
      elevation: 0,
      color: AppColors.ctSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.ctBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Left: operator + reason + assignee
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _operatorName(),
                            style: AppTextStyles.cardTitle.copyWith(fontSize: 14, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (workerCanResume) ...[
                          const SizedBox(width: 6),
                          const Tooltip(
                            message: 'Worker puede reanudar',
                            child: Icon(
                              Icons.play_circle_outline_rounded,
                              size: 14,
                              color: AppColors.ctTeal,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reason,
                      style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasAssignee ? _assignedToName() : 'Sin asignar',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: hasAssignee ? AppColors.ctText2 : AppColors.ctText3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Right: chip + time
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  EscalacionStatusChip(status: status),
                  const SizedBox(height: 4),
                  Text(
                    fmtRelative(openedAt, compact: true, absoluteAfterDays: 7, nullLabel: ''),
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
