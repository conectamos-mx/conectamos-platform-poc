import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

IconData _typeIconFor(String? src) => switch (src) {
      'whatsapp' || 'telegram' || 'conversacional' || 'operator'
          => Icons.chat_bubble_outline_rounded,
      'api'       => Icons.code_rounded,
      'dashboard' => Icons.dashboard_outlined,
      _           => Icons.bolt_rounded,
    };

String? _firstTrigger(List triggers) =>
    triggers.isNotEmpty ? triggers.first?.toString() : null;

// ── Public widget ─────────────────────────────────────────────────────────────

class LineageBreadcrumb extends StatelessWidget {
  const LineageBreadcrumb({super.key, required this.exec});
  final Map<String, dynamic> exec;

  @override
  Widget build(BuildContext context) {
    // Safe dart2js casts
    final rawParent = exec['parent'];
    final parent = rawParent is Map
        ? Map<String, dynamic>.from(rawParent)
        : null;

    final rawChildren = exec['children'];
    final children = rawChildren is List
        ? List<Map<String, dynamic>>.from(
            rawChildren
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e)))
        : <Map<String, dynamic>>[];

    final rawSnapshot = exec['flow_definition_snapshot'];
    final snapshot = rawSnapshot is Map
        ? Map<String, dynamic>.from(rawSnapshot)
        : <String, dynamic>{};

    final currentFlowName = snapshot['name'] as String? ?? '—';
    final currentTrigger =
        _firstTrigger(snapshot['trigger_sources'] as List? ?? []);

    final child0 = children.isNotEmpty ? children.first : null;
    final extraChildCount = children.length > 1 ? children.length - 1 : 0;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (ctx, bc) {
          final wide = bc.maxWidth >= 900;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: wide
                ? _DesktopRow(
                    parent: parent,
                    currentFlowName: currentFlowName,
                    currentTrigger: currentTrigger,
                    child0: child0,
                    extraChildCount: extraChildCount,
                  )
                : _CompactRow(
                    parent: parent,
                    currentFlowName: currentFlowName,
                    currentTrigger: currentTrigger,
                    child0: child0,
                  ),
          );
        },
      ),
    );
  }
}

// ── Desktop row ───────────────────────────────────────────────────────────────

class _DesktopRow extends StatelessWidget {
  const _DesktopRow({
    required this.parent,
    required this.currentFlowName,
    required this.currentTrigger,
    required this.child0,
    required this.extraChildCount,
  });

  final Map<String, dynamic>? parent;
  final String currentFlowName;
  final String? currentTrigger;
  final Map<String, dynamic>? child0;
  final int extraChildCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (parent != null)
          _ParentChip(parent: parent!)
        else
          const _AbsentText('Sin flujo anterior'),
        const _Dots(),
        _CurrentChip(flowName: currentFlowName, trigger: currentTrigger),
        const _Dots(),
        if (child0 != null)
          _ChildChip(child: child0!)
        else
          const _AbsentText('Sin flujo posterior'),
        if (extraChildCount > 0) ...[
          const _Dots(),
          _MoreChip(count: extraChildCount),
        ],
      ],
    );
  }
}

// ── Compact row ───────────────────────────────────────────────────────────────

class _CompactRow extends StatelessWidget {
  const _CompactRow({
    required this.parent,
    required this.currentFlowName,
    required this.currentTrigger,
    required this.child0,
  });

  final Map<String, dynamic>? parent;
  final String currentFlowName;
  final String? currentTrigger;
  final Map<String, dynamic>? child0;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ANTERIOR
        if (parent != null)
          Tooltip(
            message: parent!['flow_name'] as String? ?? '—',
            child: _CompactCircle(
              bg: const Color(0xFFEEF2FF),
              border: const Color(0xFFC7D2FE),
              icon: _typeIconFor(
                  _firstTrigger(parent!['trigger_sources'] as List? ?? [])),
              iconColor: const Color(0xFF4338CA),
              onTap: () {
                final id = parent!['id'] as String?;
                if (id != null) context.go('/executions/$id');
              },
            ),
          )
        else
          const Tooltip(
            message: 'Sin flujo anterior',
            child: _EmptyCompactCircle(),
          ),
        const _Dots(),
        // ACTUAL
        Tooltip(
          message: currentFlowName,
          child: _CompactCircle(
            bg: AppColors.ctNavy,
            border: AppColors.ctNavy,
            icon: _typeIconFor(currentTrigger),
            iconColor: AppColors.ctTeal,
          ),
        ),
        const _Dots(),
        // POSTERIOR
        if (child0 != null)
          Tooltip(
            message: child0!['flow_name'] as String? ?? '—',
            child: _CompactCircle(
              bg: const Color(0xFFE6FBF6),
              border: const Color(0xFF99F6E4),
              icon: _typeIconFor(
                  _firstTrigger(child0!['trigger_sources'] as List? ?? [])),
              iconColor: AppColors.ctTealText,
              onTap: () {
                final id = child0!['id'] as String?;
                if (id != null) context.go('/executions/$id');
              },
            ),
          )
        else
          const Tooltip(
            message: 'Sin flujo posterior',
            child: _EmptyCompactCircle(),
          ),
      ],
    );
  }
}

// ── Chip: ANTERIOR ────────────────────────────────────────────────────────────

class _ParentChip extends StatelessWidget {
  const _ParentChip({required this.parent});
  final Map<String, dynamic> parent;

  @override
  Widget build(BuildContext context) {
    final flowName = parent['flow_name'] as String? ?? '—';
    final shortId = parent['short_id'] as String? ?? '';
    final trigger = _firstTrigger(parent['trigger_sources'] as List? ?? []);

    const bg = Color(0xFFEEF2FF);
    const bd = Color(0xFFC7D2FE);
    const fg = Color(0xFF4338CA);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          final id = parent['id'] as String?;
          if (id != null) context.go('/executions/$id');
        },
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: bd),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.arrow_back_rounded, size: 11, color: fg),
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('VINO DE',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.08,
                        color: fg.withValues(alpha: 0.65),
                      )),
                  Text(flowName,
                      style: const TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      )),
                ],
              ),
              const SizedBox(width: 8),
              Container(width: 1, height: 20, color: bd),
              const SizedBox(width: 8),
              Icon(_typeIconFor(trigger), size: 11, color: fg),
              if (shortId.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(shortId,
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 10,
                      color: const Color(0xFF6366F1).withValues(alpha: 0.7),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Chip: ACTUAL ──────────────────────────────────────────────────────────────

class _CurrentChip extends StatelessWidget {
  const _CurrentChip({required this.flowName, required this.trigger});
  final String flowName;
  final String? trigger;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.ctNavy,
          border: Border.all(color: AppColors.ctNavy),
          borderRadius: BorderRadius.circular(99),
          boxShadow: const [
            BoxShadow(
              color: Color(0x400F2937),
              offset: Offset(0, 2),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(_typeIconFor(trigger), size: 11, color: AppColors.ctTeal),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ESTA EJECUCIÓN',
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.08,
                      color: AppColors.ctTeal.withValues(alpha: 0.7),
                    )),
                Text(flowName,
                    style: const TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Chip: POSTERIOR ───────────────────────────────────────────────────────────

class _ChildChip extends StatelessWidget {
  const _ChildChip({required this.child});
  final Map<String, dynamic> child;

  static Color _statusDotColor(String? status) => switch (status) {
        'active' || 'in_progress' => AppColors.ctInfo,
        'abandoned' || 'escalated' => AppColors.ctDanger,
        _ => AppColors.ctWarn,
      };

  @override
  Widget build(BuildContext context) {
    final flowName = child['flow_name'] as String? ?? '—';
    final shortId = child['short_id'] as String? ?? '';
    final status = child['status'] as String?;
    final trigger = _firstTrigger(child['trigger_sources'] as List? ?? []);
    final showDot = status != null && status != 'completed';

    const bg = Color(0xFFE6FBF6);
    const bd = Color(0xFF99F6E4);
    const fg = AppColors.ctTealText;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          final id = child['id'] as String?;
          if (id != null) context.go('/executions/$id');
        },
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: bd),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DETONÓ',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.08,
                        color: fg.withValues(alpha: 0.65),
                      )),
                  Text(flowName,
                      style: const TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      )),
                ],
              ),
              const SizedBox(width: 8),
              Container(width: 1, height: 20, color: bd),
              const SizedBox(width: 8),
              Icon(_typeIconFor(trigger), size: 11, color: fg),
              if (shortId.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(shortId,
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 10,
                      color: fg.withValues(alpha: 0.7),
                    )),
              ],
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, size: 11, color: fg),
              if (showDot) ...[
                const SizedBox(width: 6),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _statusDotColor(status),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── "+ N más" chip ────────────────────────────────────────────────────────────

class _MoreChip extends StatelessWidget {
  const _MoreChip({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Center(
        child: Text('+ $count más',
            style: AppFonts.geist(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
            )),
      ),
    );
  }
}

// ── Absent text ───────────────────────────────────────────────────────────────

class _AbsentText extends StatelessWidget {
  const _AbsentText(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: Center(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppFonts.geist(fontSize: 11, color: const Color(0xFF94A3B8))
              .copyWith(fontStyle: FontStyle.italic),
        ),
      ),
    );
  }
}

// ── Compact circle ────────────────────────────────────────────────────────────

class _CompactCircle extends StatelessWidget {
  const _CompactCircle({
    required this.bg,
    required this.border,
    required this.icon,
    required this.iconColor,
    this.onTap,
  });

  final Color bg;
  final Color border;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget w = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 14, color: iconColor),
    );
    if (onTap != null) {
      w = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: onTap, child: w),
      );
    }
    return w;
  }
}

class _EmptyCompactCircle extends StatelessWidget {
  const _EmptyCompactCircle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.remove_rounded, size: 14, color: Color(0xFFCBD5E1)),
    );
  }
}

// ── Dotted connector ──────────────────────────────────────────────────────────

class _Dots extends StatelessWidget {
  const _Dots();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(width: 12),
        ...List.generate(5, (i) => Padding(
              padding: EdgeInsets.only(right: i < 4 ? 3.0 : 0.0),
              child: Container(
                width: 3,
                height: 3,
                decoration: const BoxDecoration(
                  color: AppColors.ctBorder2,
                  shape: BoxShape.circle,
                ),
              ),
            )),
        const SizedBox(width: 12),
      ],
    );
  }
}
