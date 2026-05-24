import 'package:flutter/material.dart';

/// 86×60 dp mini diagram for each precondition type.
class PrecondMiniDiagram extends StatelessWidget {
  const PrecondMiniDiagram({
    super.key,
    required this.type,
    required this.catColor,
  });

  final String type;
  final Color catColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 86,
      height: 60,
      child: switch (type) {
        'no_active_execution' => _noActiveExecution(),
        'requires_active_execution' => _requiresActiveExecution(),
        'no_concurrent_execution' => _noConcurrentExecution(),
        'requires_completed_sibling' => _requiresCompletedSibling(),
        'no_active_sibling' => _noActiveSibling(),
        'all_children_completed' => _allChildrenCompleted(),
        'requires_parent' => _requiresParent(),
        'operator_role_in' => _operatorRoleIn(),
        'requires_active_assignment' => _requiresActiveAssignment(),
        'field_unique_in_window' => _fieldUniqueInWindow(),
        'time_window' => _timeWindow(),
        _ => Center(
            child: Icon(Icons.help_outline, size: 24, color: catColor.withValues(alpha: 0.4)),
          ),
      },
    );
  }

  Widget _pill(String label, Color bg, Color fg, {double fontSize = 7}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: fg)),
      );

  Widget _box({
    double w = 24,
    double h = 18,
    Color? bg,
    Color? border,
    Widget? child,
    bool dashed = false,
  }) =>
      Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: bg ?? catColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4),
          border: dashed
              ? Border.all(color: border ?? catColor.withValues(alpha: 0.4), width: 1)
              : Border.all(color: border ?? catColor.withValues(alpha: 0.25)),
        ),
        child: child != null ? Center(child: child) : null,
      );

  Widget _arrow({bool vertical = false}) => Icon(
        vertical ? Icons.arrow_downward_rounded : Icons.arrow_forward_rounded,
        size: 10,
        color: catColor.withValues(alpha: 0.5),
      );

  Widget _checkIcon([double size = 10]) =>
      Icon(Icons.check_rounded, size: size, color: const Color(0xFF16A34A));

  Widget _crossIcon([double size = 10]) =>
      Icon(Icons.close_rounded, size: size, color: const Color(0xFFDC2626));

  // ── Diagrams ──────────────────────────────────────────────────────────────

  Widget _noActiveExecution() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _box(child: Text('⚡', style: TextStyle(fontSize: 10))),
          const SizedBox(width: 4),
          CustomPaint(size: const Size(12, 2), painter: _DashedLine(const Color(0xFFDC2626))),
          const SizedBox(width: 4),
          Container(
            width: 18, height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFEE2E2),
              border: Border.all(color: const Color(0xFFDC2626), width: 1),
            ),
            child: _crossIcon(9),
          ),
        ],
      );

  Widget _requiresActiveExecution() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _box(bg: const Color(0xFFDCFCE7), child: _checkIcon()),
          const SizedBox(width: 4),
          _arrow(),
          const SizedBox(width: 4),
          _box(bg: Colors.transparent, border: catColor),
        ],
      );

  Widget _noConcurrentExecution() => Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _box(w: 22, h: 16),
              Transform.translate(
                offset: const Offset(-6, 4),
                child: _box(w: 22, h: 16),
              ),
            ],
          ),
          CustomPaint(
            size: const Size(30, 30),
            painter: _DiagonalLine(const Color(0xFFDC2626)),
          ),
        ],
      );

  Widget _requiresCompletedSibling() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _box(w: 20, h: 14, bg: const Color(0xFFDCFCE7), child: _checkIcon(8)),
              const SizedBox(height: 2),
              Text('prev', style: TextStyle(fontSize: 6, color: catColor.withValues(alpha: 0.6))),
            ],
          ),
          const SizedBox(width: 3),
          _arrow(),
          const SizedBox(width: 3),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _box(w: 20, h: 14, border: catColor),
              const SizedBox(height: 2),
              Text('now', style: TextStyle(fontSize: 6, color: catColor.withValues(alpha: 0.6))),
            ],
          ),
        ],
      );

  Widget _noActiveSibling() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _box(bg: const Color(0xFFFEE2E2), child: Text('⚡', style: TextStyle(fontSize: 10))),
          const SizedBox(width: 4),
          CustomPaint(size: const Size(12, 2), painter: _DashedLine(const Color(0xFFDC2626))),
          const SizedBox(width: 4),
          _box(child: Text('?', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: catColor))),
        ],
      );

  Widget _allChildrenCompleted() => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _box(w: 30, h: 12, child: Text('padre', style: TextStyle(fontSize: 6, color: catColor))),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _box(w: 14, h: 12, bg: const Color(0xFFDCFCE7), child: _checkIcon(7)),
              const SizedBox(width: 2),
              _box(w: 14, h: 12, bg: const Color(0xFFDCFCE7), child: _checkIcon(7)),
              const SizedBox(width: 2),
              _box(w: 14, h: 12, bg: const Color(0xFFFEF3C7),
                  child: Text('⧗', style: TextStyle(fontSize: 7, color: const Color(0xFF92400E)))),
              const SizedBox(width: 2),
              _box(w: 14, h: 12, bg: const Color(0xFFFEF3C7),
                  child: Text('⧗', style: TextStyle(fontSize: 7, color: const Color(0xFF92400E)))),
            ],
          ),
        ],
      );

  Widget _requiresParent() => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _box(w: 28, h: 12, child: Text('padre', style: TextStyle(fontSize: 6, color: catColor))),
          _arrow(vertical: true),
          _box(w: 28, h: 12, dashed: true,
              child: Text('este', style: TextStyle(fontSize: 6, color: catColor))),
        ],
      );

  Widget _operatorRoleIn() => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: catColor.withValues(alpha: 0.1),
            ),
            child: Center(child: Text('👤', style: TextStyle(fontSize: 10))),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _pill('rol A', catColor.withValues(alpha: 0.12), catColor),
              const SizedBox(width: 3),
              _pill('rol B', catColor.withValues(alpha: 0.12), catColor),
            ],
          ),
        ],
      );

  Widget _requiresActiveAssignment() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: catColor.withValues(alpha: 0.1),
            ),
            child: Center(child: Text('👤', style: TextStyle(fontSize: 10))),
          ),
          const SizedBox(width: 4),
          _arrow(),
          const SizedBox(width: 4),
          _box(child: Text('📋', style: TextStyle(fontSize: 10))),
        ],
      );

  Widget _fieldUniqueInWindow() => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CustomPaint(
            size: const Size(50, 8),
            painter: _DashedLine(const Color(0xFFDC2626)),
          ),
          const SizedBox(height: 2),
          _pill('duplicado', const Color(0xFFFEE2E2), const Color(0xFFDC2626), fontSize: 6),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _box(w: 16, h: 14, child: Text('A', style: TextStyle(fontSize: 7, fontWeight: FontWeight.w700, color: catColor))),
              const SizedBox(width: 3),
              _box(w: 16, h: 14, child: Text('B', style: TextStyle(fontSize: 7, fontWeight: FontWeight.w700, color: catColor))),
              const SizedBox(width: 3),
              _box(w: 16, h: 14, bg: const Color(0xFFFEE2E2),
                  child: Text('A', style: TextStyle(fontSize: 7, fontWeight: FontWeight.w700, color: const Color(0xFFDC2626)))),
            ],
          ),
        ],
      );

  Widget _timeWindow() => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('🕐', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 3),
          Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                width: 60, height: 6,
                decoration: BoxDecoration(
                  color: catColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Positioned(
                left: 12,
                child: Container(
                  width: 28, height: 6,
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('permitido', style: TextStyle(fontSize: 6, color: catColor.withValues(alpha: 0.6))),
        ],
      );
}

// ── Custom painters ─────────────────────────────────────────────────────────

class _DashedLine extends CustomPainter {
  _DashedLine(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    const dashWidth = 3.0;
    const dashSpace = 2.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset((x + dashWidth).clamp(0, size.width), size.height / 2),
        paint,
      );
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DiagonalLine extends CustomPainter {
  _DiagonalLine(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
