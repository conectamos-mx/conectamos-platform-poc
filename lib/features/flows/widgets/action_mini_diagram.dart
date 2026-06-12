import 'package:flutter/material.dart';

class ActionMiniDiagram extends StatelessWidget {
  const ActionMiniDiagram({
    super.key,
    required this.type,
    required this.catColor,
  });

  final String type;
  final Color catColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 60,
      child: _buildDiagram(),
    );
  }

  Widget _buildDiagram() => switch (type) {
        'open_flow' => _openFlow(),
        'open_flow_n_times' => _openFlowNTimes(),
        'webhook_out' => _webhookOut(),
        'google_sheets_append_row' => _sheetsAppend(),
        'google_sheets_update_row' => _sheetsUpdate(),
        'excel_onedrive_append_row' => _sheetsAppend(),
        'excel_onedrive_update_row' => _sheetsUpdate(),
        'emit_event' => _emitEvent(),
        'notify_group' => _notifyGroup(),
        _ => const SizedBox.expand(),
      };

  Widget _box(String label, Color color, Color bg, {double w = 28, double h = 24}) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color),
        ),
      ),
    );
  }

  Widget _arrow() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 1.5, color: catColor.withValues(alpha: 0.4)),
          Icon(Icons.arrow_right_rounded, size: 10, color: catColor),
        ],
      );

  Widget _checkBox() => _box(
        '\u2713',
        const Color(0xFF15803D),
        const Color(0xFFDCFCE7),
      );

  // ── open_flow ──────────────────────────────────────────────────────────────

  Widget _openFlow() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _checkBox(),
          _arrow(),
          _box('\u25B6', catColor, catColor.withValues(alpha: 0.1)),
        ],
      );

  // ── open_flow_n_times ──────────────────────────────────────────────────────

  Widget _openFlowNTimes() => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _checkBox(),
              _arrow(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    _box('', catColor, catColor.withValues(alpha: 0.1), w: 14, h: 18),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '\u00D7N',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: catColor,
            ),
          ),
        ],
      );

  // ── webhook_out ────────────────────────────────────────────────────────────

  Widget _webhookOut() => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'POST',
            style: TextStyle(
              fontSize: 7,
              fontWeight: FontWeight.w700,
              color: catColor.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _checkBox(),
              _arrow(),
              Container(
                width: 28,
                height: 24,
                decoration: BoxDecoration(
                  color: catColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: catColor, width: 1.2),
                ),
                child: Center(
                  child: Text(
                    '\u26A1',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      );

  // ── google_sheets_append_row ───────────────────────────────────────────────

  Widget _sheetsAppend() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _checkBox(),
          _arrow(),
          _miniTable(highlightLast: true, highlightColor: catColor),
        ],
      );

  // ── google_sheets_update_row ───────────────────────────────────────────────

  Widget _sheetsUpdate() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _checkBox(),
          _arrow(),
          _miniTable(highlightLast: false, highlightColor: const Color(0xFFF59E0B)),
        ],
      );

  Widget _miniTable({required bool highlightLast, required Color highlightColor}) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: const Color(0xFFD1D5DB), width: 1),
      ),
      child: Column(
        children: [
          _tableRow(const Color(0xFFF3F4F6), isFirst: true),
          _tableRow(
            highlightLast ? const Color(0xFFF9FAFB) : highlightColor.withValues(alpha: 0.25),
          ),
          _tableRow(
            highlightLast ? highlightColor.withValues(alpha: 0.25) : const Color(0xFFF9FAFB),
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _tableRow(Color bg, {bool isFirst = false, bool isLast = false}) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.vertical(
            top: isFirst ? const Radius.circular(2) : Radius.zero,
            bottom: isLast ? const Radius.circular(2) : Radius.zero,
          ),
          border: Border(
            bottom: isLast
                ? BorderSide.none
                : BorderSide(color: const Color(0xFFE5E7EB), width: 0.5),
          ),
        ),
      ),
    );
  }

  // ── notify_group ───────────────────────────────────────────────────────────

  Widget _notifyGroup() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _checkBox(),
          _arrow(),
          SizedBox(
            width: 32,
            height: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: catColor.withValues(alpha: 0.15),
                    border: Border.all(color: catColor, width: 1.2),
                  ),
                  child: Center(
                    child: Icon(Icons.groups, size: 12, color: catColor),
                  ),
                ),
                // chat bubble accent
                Positioned(
                  top: 1,
                  right: 1,
                  child: Container(
                    width: 10,
                    height: 8,
                    decoration: BoxDecoration(
                      color: catColor.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Center(
                      child: Container(
                        width: 4,
                        height: 1.5,
                        decoration: BoxDecoration(
                          color: catColor,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  // ── emit_event ─────────────────────────────────────────────────────────────

  Widget _emitEvent() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _checkBox(),
          _arrow(),
          SizedBox(
            width: 32,
            height: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: catColor.withValues(alpha: 0.15),
                    border: Border.all(color: catColor, width: 1.2),
                  ),
                  child: const Center(
                    child: Text('\uD83D\uDCE1', style: TextStyle(fontSize: 10)),
                  ),
                ),
                // radiating dots
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: catColor.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 0,
                  child: Container(
                    width: 3,
                    height: 3,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: catColor.withValues(alpha: 0.35),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 4,
                  right: 1,
                  child: Container(
                    width: 3,
                    height: 3,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: catColor.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}
