import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_menu_button.dart';
import 'execution_export.dart';

// ── Public widget ────────────────────────────────────────────────────────────

class ExecutionHeaderBlock extends StatelessWidget {
  const ExecutionHeaderBlock({
    super.key,
    required this.exec,
    required this.flow,
    this.showAbandon = false,
    this.onAbandon,
  });

  final Map<String, dynamic> exec;
  final Map<String, dynamic> flow;
  final bool showAbandon;
  final VoidCallback? onAbandon;

  @override
  Widget build(BuildContext context) {
    final status = exec['status'] as String? ?? 'completed';
    // Compute progress: match each snapshot field to its field_value by key
    final rawFvList = exec['field_values'] as List? ?? [];
    final fvMap = <String, Map>{};
    for (final fv in rawFvList.whereType<Map>()) {
      final k = fv['field_key'];
      if (k is String && k.isNotEmpty) fvMap[k] = fv;
    }
    final snapshotFields = (flow['fields'] as List?)?.whereType<Map>().toList() ?? [];
    final execStatus = exec['status'] as String? ?? '';
    // Filter out fields hidden by show_if
    final visibleFields = snapshotFields.where((field) {
      final showIf = field['show_if'];
      if (showIf is! Map) return true;
      final depField = showIf['field'] as String?;
      final op = showIf['op'] as String?;
      final expected = showIf['value'];
      if (depField == null || op == null || expected == null) return true;
      final controlValue = fvMap[depField]?['value_text'] as String?;
      if (controlValue == null) {
        return const {'created', 'active'}.contains(execStatus);
      }
      String norm(String v) {
        final lc = v.trim().toLowerCase();
        if (lc == 'sí' || lc == 'si') return 'true';
        if (lc == 'no') return 'false';
        return lc;
      }
      final a = norm(controlValue);
      final b = norm(expected.toString());
      return switch (op) {
        'eq' || '==' => a == b,
        'neq' || '!=' => a != b,
        _ => true,
      };
    }).toList();
    final total = visibleFields.length.clamp(1, 9999);
    int filled = 0;
    for (final field in visibleFields) {
      final key = field['key'];
      if (key is! String) continue;
      final fv = fvMap[key];
      if (fv != null &&
          (fv['value_text'] != null ||
           fv['value_numeric'] != null ||
           fv['value_media_url'] != null ||
           fv['value_jsonb'] != null)) {
        filled++;
      }
    }
    final triggerSources = flow['trigger_sources'] as List?;
    final flowType = triggerSources?.firstOrNull?.toString() ?? 'conversacional';
    final flowName = flow['name'] as String? ?? '—';
    final execId = (exec['id'] as String? ?? '').isNotEmpty
        ? (exec['id'] as String).substring(0, 8).toUpperCase()
        : '—';
    final operatorRaw = exec['operator'];
    final Map<String, dynamic>? operator_ = operatorRaw is Map
        ? Map<String, dynamic>.from(operatorRaw)
        : null;
    final opName = operator_?['name'] as String? ?? 'Sin operador';
    final opAvatar = operator_?['profile_picture_url'] as String?;
    final waitingFor = exec['waiting_for'] as String? ?? exec['waitingFor'] as String?;
    final failureReason = exec['failure_reason'] as String? ?? exec['failureReason'] as String?;
    final flowId = flow['id'] as String? ?? '';

    // Channel
    final channelRaw = exec['channel'];
    final channelMap = channelRaw is Map
        ? Map<String, dynamic>.from(channelRaw)
        : null;
    final channelType = channelMap?['channel_type'] as String? ??
        switch (exec['actor_type'] as String?) {
          'operator'    => 'whatsapp',
          'tenant_user' => 'dashboard',
          'system'      => 'api',
          _             => null,
        };

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.ctBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProgressRing(filled: filled, total: total, status: status, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(execId,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.ctText3,
                          letterSpacing: -0.005,
                        )),
                    const SizedBox(height: 4),
                    Text(flowName,
                        style: AppFonts.onest(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ctNavy,
                          letterSpacing: -0.025,
                        )),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _StatusPill(status: status),
                        _TypeBadge(flowType: flowType),
                        if (channelType != null) _ChannelBadge(channelType: channelType),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('por ', style: AppFonts.geist(fontSize: 12, color: const Color(0xFF6B7280))),
                            _Avatar(src: opAvatar, name: opName, size: 18),
                            const SizedBox(width: 5),
                            Text(opName,
                                style: AppFonts.geist(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.ctNavy)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showAbandon) ...[
                    AppButton(
                      label: 'Abandonar',
                      onPressed: onAbandon ?? () {},
                      variant: AppButtonVariant.danger,
                      size: AppButtonSize.sm,
                      prefixIcon: const Icon(Icons.cancel_outlined, size: 14, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                  ],
                  AppButton(
                    label: 'Ver definición',
                    onPressed: () {
                      final wId = flow['tenant_worker_id'] as String?;
                      if (wId != null && flowId.isNotEmpty) {
                        context.go('/workers/$wId?selectedFlow=$flowId');
                      }
                    },
                    variant: AppButtonVariant.outline,
                    size: AppButtonSize.sm,
                    prefixIcon: const Icon(Icons.open_in_new_rounded, size: 13, color: AppColors.ctInk700),
                  ),
                  const SizedBox(width: 6),
                  AppMenuButton(
                    label: 'Exportar',
                    icon: Icons.download_rounded,
                    items: [
                      AppMenuButtonItem(
                        label: 'Exportar PDF',
                        icon: Icons.picture_as_pdf_rounded,
                        onTap: () => exportExecutionPdf(exec, flow),
                      ),
                      AppMenuButtonItem(
                        label: 'Exportar XLS',
                        icon: Icons.table_chart_rounded,
                        onTap: () => exportExecutionXls(exec, flow),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          if ((status == 'failed' || status == 'escalated') && failureReason != null) ...[
            const SizedBox(height: 12),
            _FailedBanner(reason: failureReason),
          ],
          if (status == 'in_progress' || status == 'active') ...[
            const SizedBox(height: 12),
            _InProgressBanner(waitingFor: waitingFor),
          ],
        ],
      ),
    );
  }
}

// ── Progress Ring ─────────────────────────────────────────────────────────────

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({
    required this.filled,
    required this.total,
    required this.status,
    required this.size,
  });

  final int filled;
  final int total;
  final String status;
  final double size;

  Color get _color => switch (status) {
    'completed'                    => AppColors.ctOk,
    'in_progress' || 'active'     => AppColors.ctInfo,
    'failed' || 'escalated'       => AppColors.ctDanger,
    'paused'                       => AppColors.ctWarn,
    _                              => AppColors.ctTeal,
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          filled: filled,
          total: total,
          progressColor: _color,
        ),
        child: Center(
          child: Text('$filled/$total',
              style: AppFonts.onest(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.ctNavy,
                letterSpacing: -0.02,
              )),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.filled, required this.total, required this.progressColor});
  final int filled;
  final int total;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 6) / 2;

    final bgPaint = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius, bgPaint);

    final pct = total > 0 ? filled / total : 0.0;
    if (pct > 0) {
      final fgPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * pct,
        false,
        fgPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.filled != filled || old.total != total || old.progressColor != progressColor;
}

// ── Banners ───────────────────────────────────────────────────────────────────

class _FailedBanner extends StatelessWidget {
  const _FailedBanner({required this.reason});
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.ctRedBg,
        border: Border.all(color: const Color(0xFFFECACA)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.ctDanger),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Motivo de falla',
                    style: AppFonts.geist(
                        fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ctRedText)),
                const SizedBox(height: 2),
                Text(reason,
                    style: AppFonts.geist(fontSize: 13, color: AppColors.ctRedText)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          AppButton(
            label: 'Ver escalación',
            onPressed: () {},
            variant: AppButtonVariant.danger,
            size: AppButtonSize.sm,
          ),
        ],
      ),
    );
  }
}

class _InProgressBanner extends StatefulWidget {
  const _InProgressBanner({required this.waitingFor});
  final String? waitingFor;

  @override
  State<_InProgressBanner> createState() => _InProgressBannerState();
}

class _InProgressBannerState extends State<_InProgressBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _opacity,
            builder: (context2, child2) => Opacity(
              opacity: _opacity.value,
              child: Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.ctInfo,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: 'En espera del operador',
                    style: AppFonts.geist(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ctInfoText)),
                if (widget.waitingFor != null) ...[
                  TextSpan(
                      text: ' · El AI Worker pidió: ',
                      style: AppFonts.geist(fontSize: 13, color: const Color(0xFF475569))),
                  TextSpan(
                      text: widget.waitingFor,
                      style: AppFonts.geist(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ctNavy)),
                ],
              ]),
            ),
          ),
          const SizedBox(width: 12),
          Text('Última actividad hace 2 min',
              style: AppFonts.geist(fontSize: 11, color: const Color(0xFF94A3B8))),
        ],
      ),
    );
  }
}

// ── Small helpers ─────────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, bd, label) = switch (status) {
      'completed'                => (AppColors.ctOkBg, AppColors.ctOkText, const Color(0xFFA7F3D0), 'Completado'),
      'in_progress' || 'active' => (AppColors.ctInfoBg, AppColors.ctInfoText, const Color(0xFFBFDBFE), 'En curso'),
      'paused'                   => (AppColors.ctWarnBg, AppColors.ctWarnText, const Color(0xFFFDE68A), 'Pausado'),
      'abandoned'                => (AppColors.ctSurface2, AppColors.ctText2, AppColors.ctBorder, 'Abandonado'),
      'escalated'                => (AppColors.ctRedBg, AppColors.ctRedText, const Color(0xFFFECACA), 'Escalado'),
      'failed'                   => (AppColors.ctRedBg, AppColors.ctRedText, const Color(0xFFFECACA), 'Fallido'),
      _                          => (AppColors.ctSurface2, AppColors.ctText2, AppColors.ctBorder, status),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: bd),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 6, height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label,
              style:
                  AppFonts.geist(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.flowType});
  final String flowType;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, bd, icon, label) = switch (flowType) {
      'api'       => (AppColors.ctInfoBg, AppColors.ctInfoText, const Color(0xFFBFDBFE), Icons.code_rounded, 'API / Sistema'),
      'dashboard' => (AppColors.ctNavy, Colors.white, AppColors.ctNavy, Icons.dashboard_outlined, 'Dashboard'),
      _           => (AppColors.ctTealLight, const Color(0xFF0F766E), const Color(0xFF99F6E4), Icons.chat_bubble_outline_rounded, 'Conversacional'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: bd),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 4),
          Text(label,
              style:
                  AppFonts.geist(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.size, this.src});
  final String? src;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return ClipOval(
      child: SizedBox(
        width: size, height: size,
        child: src != null
            ? Image.network(src!, fit: BoxFit.cover,
                errorBuilder: (ctx, err, stack) => _InitialAvatar(initials: initials, size: size))
            : _InitialAvatar(initials: initials, size: size),
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.initials, required this.size});
  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      color: const Color(0xFFE0F2FE),
      child: Center(
        child: Text(initials,
            style: AppFonts.geist(
                fontSize: size * 0.36,
                fontWeight: FontWeight.w600,
                color: AppColors.ctInfoText)),
      ),
    );
  }
}

class _ChannelBadge extends StatelessWidget {
  const _ChannelBadge({required this.channelType});
  final String channelType;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, bd, icon, label) = switch (channelType) {
      'whatsapp'  => (const Color(0xFFE8F8EF), const Color(0xFF1A7A45), const Color(0xFFBBF7D0), Icons.chat_rounded, 'WhatsApp'),
      'telegram'  => (AppColors.ctInfoBg, AppColors.ctInfoText, const Color(0xFFBFDBFE), Icons.send_rounded, 'Telegram'),
      'api'       => (AppColors.ctInfoBg, AppColors.ctInfoText, const Color(0xFFBFDBFE), Icons.code_rounded, 'API'),
      'dashboard' => (AppColors.ctSurface2, const Color(0xFF475569), AppColors.ctBorder, Icons.dashboard_outlined, 'Dashboard'),
      _           => (AppColors.ctSurface2, AppColors.ctText2, AppColors.ctBorder, Icons.link_rounded, channelType),
    };
    final Widget iconWidget = switch (channelType) {
      'whatsapp' => SvgPicture.asset('assets/logos/whatsapp.svg',
          width: 11, height: 11),
      'telegram' => Image.asset('assets/logos/telegram',
          width: 11, height: 11),
      _ => Icon(icon, size: 11, color: fg),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: bd),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconWidget,
          const SizedBox(width: 4),
          Text(label,
              style: AppFonts.geist(
                  fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}


