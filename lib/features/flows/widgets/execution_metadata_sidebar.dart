import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

// ── Action type maps (extend as needed) ───────────────────────────────────────

const Map<String, IconData> _kActionIcons = {
  'open_flow':                Icons.account_tree_rounded,
  'webhook_out':              Icons.cloud_upload_outlined,
  'emit_event':               Icons.sensors_rounded,
  'sheets':                   Icons.table_chart_outlined,
  'google_sheets':            Icons.table_chart_outlined,
  'google_sheets_append_row': Icons.table_chart_outlined,
};

const Map<String, String> _kActionLabels = {
  'open_flow':                'Abrir flujo',
  'webhook_out':              'Webhook saliente',
  'emit_event':               'Emitir evento',
  'sheets':                   'Google Sheets',
  'google_sheets':            'Google Sheets',
  'google_sheets_append_row': 'Google Sheets',
};

class ExecutionMetadataSidebar extends StatelessWidget {
  const ExecutionMetadataSidebar({
    super.key,
    required this.exec,
    required this.flow,
    required this.events,
  });

  final Map<String, dynamic> exec;
  final Map<String, dynamic> flow;
  final List<Map<String, dynamic>> events;

  static const _shortMonths = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
  ];

  String _fmtDateLong(String? iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso).toLocal();
      final h = d.hour.toString().padLeft(2, '0');
      final m = d.minute.toString().padLeft(2, '0');
      return '${d.day.toString().padLeft(2, '0')} ${_shortMonths[d.month - 1]} · $h:$m';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final execId = exec['id'] as String? ?? '—';
    final startedAt = exec['created_at'] as String?;
    final completedAt = exec['completed_at'] as String?;
    // Compute progress: match each snapshot field to its field_value by key
    final rawFvList = exec['field_values'] as List? ?? [];
    final fvMap = <String, Map>{};
    for (final fv in rawFvList.whereType<Map>()) {
      final k = fv['field_key'];
      if (k is String && k.isNotEmpty) fvMap[k] = fv;
    }
    final snapshotFields = (flow['fields'] as List?)?.whereType<Map>().toList() ?? [];
    final total = snapshotFields.length;
    int filled = 0;
    for (final field in snapshotFields) {
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

    // Channel (nested Map or fallback to actor_type)
    final channelRaw = exec['channel'];
    final Map<String, dynamic>? channelMap = channelRaw is Map
        ? Map<String, dynamic>.from(channelRaw)
        : null;
    final channelType = channelMap?['channel_type'] as String?;
    final channelDisplayName = channelMap?['display_name'] as String?;
    // Fallback: infer from actor_type when channel is null
    final actorType = exec['actor_type'] as String?;
    final inferredChannelType = channelType ??
        switch (actorType) {
          'operator'    => 'whatsapp',
          'tenant_user' => 'dashboard',
          'system'      => 'api',
          _             => null,
        };
    final resolvedDisplayName = channelDisplayName ??
        switch (inferredChannelType) {
          'whatsapp'  => 'WhatsApp',
          'telegram'  => 'Telegram',
          'api'       => 'API',
          'dashboard' => 'Dashboard',
          _           => null,
        };

    final operatorRaw = exec['operator'];
    final Map<String, dynamic>? operator_ = operatorRaw is Map
        ? Map<String, dynamic>.from(operatorRaw)
        : null;
    final opName = operator_?['name'] as String? ?? 'Sin operador';
    final opAvatar = operator_?['profile_picture_url'] as String?;

    final flowName = flow['name'] as String? ?? '—';
    final flowSlug = flow['slug'] as String? ?? '';
    final flowDesc = flow['description'] as String? ?? '';
    final triggerSources = flow['trigger_sources'] as List?;
    final flowType = triggerSources?.firstOrNull?.toString() ?? 'conversacional';

    // Worker now at exec['worker'] (not flow['worker'])
    final worker = (exec['worker'] as Map?)?.cast<String, dynamic>();
    final workerName = worker?['name'] as String? ?? '—';
    final workerRole = worker?['role'] as String? ?? '';

    // actions_log from execution response
    final rawActionsLog = exec['actions_log'];
    final actionsLog = rawActionsLog is List
        ? rawActionsLog
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList()
        : <Map<String, dynamic>>[];

    final inheritedValues = <String, dynamic>{};

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Detalle de ejecución ──────────────────────────────────────────
          _SideCard(
            title: 'Detalle de ejecución',
            child: Column(
              children: _withDividers([
                _KV(
                  label: 'Execution ID',
                  copyText: exec['id'] as String?,
                  value: Text(execId,
                      style: const TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 12,
                          color: AppColors.ctNavy,
                          letterSpacing: -0.005)),
                ),
                _KV(
                  label: 'Iniciada',
                  copyText: startedAt,
                  value: Text(_fmtDateLong(startedAt),
                      style: AppFonts.geist(fontSize: 12, color: AppColors.ctNavy)),
                ),
                _KV(
                  label: 'Finalizada',
                  copyText: completedAt,
                  value: Text(_fmtDateLong(completedAt),
                      style: AppFonts.geist(fontSize: 12, color: AppColors.ctNavy)),
                ),
                _KV(
                  label: 'Canal',
                  value: inferredChannelType != null
                      ? _ChannelLabel(
                          channelType: inferredChannelType,
                          displayName: resolvedDisplayName ?? '—')
                      : Text('—',
                          style: AppFonts.geist(
                              fontSize: 12, color: AppColors.ctNavy)),
                ),
                _KV(
                  label: 'Progreso',
                  value: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$filled / $total',
                          style: AppFonts.geist(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ctNavy)),
                      const SizedBox(width: 6),
                      Text('campos',
                          style: AppFonts.geist(
                              fontSize: 11, color: const Color(0xFF94A3B8))),
                    ],
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // ── Operador ──────────────────────────────────────────────────────
          _SideCard(
            title: 'Operador',
            child: Row(
              children: [
                _AvatarLarge(src: opAvatar, name: opName, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(opName,
                          style: AppFonts.geist(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ctNavy)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Flujo definido ────────────────────────────────────────────────
          _SideCard(
            title: 'Flujo definido',
            action: TextButton.icon(
              onPressed: () {
                if (flowSlug.isNotEmpty) context.go('/flows/$flowSlug');
              },
              icon: const Icon(Icons.arrow_outward_rounded, size: 12),
              label: const Text('Editor'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.ctTeal,
                textStyle:
                    AppFonts.geist(fontSize: 12, fontWeight: FontWeight.w600),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _FlowIconTile(flowType: flowType),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(flowName,
                              style: AppFonts.geist(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ctNavy)),
                          Text('/$flowSlug',
                              style: const TextStyle(
                                fontFamily: 'Geist',
                                fontSize: 11,
                                color: Color(0xFF475569),
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
                if (flowDesc.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(flowDesc,
                      style: AppFonts.geist(
                          fontSize: 12, color: const Color(0xFF475569), height: 1.55)),
                ],
                if (worker != null) ...[
                  const SizedBox(height: 10),
                  // Worker sub-card
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.ctSurface2,
                      border: Border.all(color: AppColors.ctBorder),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 24, height: 24,
                          decoration: BoxDecoration(
                            color: AppColors.ctNavy,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.auto_awesome_rounded,
                              size: 12, color: AppColors.ctTeal),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(workerName,
                                  style: AppFonts.geist(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.ctNavy)),
                              if (workerRole.isNotEmpty)
                                Text(workerRole,
                                    style: AppFonts.geist(
                                        fontSize: 10,
                                        color: const Color(0xFF475569))),
                            ],
                          ),
                        ),
                        _Badge(label: 'IA'),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Heredados ─────────────────────────────────────────────────────
          if (inheritedValues.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SideCard(
              title: 'Heredados del flujo previo',
              titleIcon: const Icon(Icons.arrow_back_rounded,
                  size: 12, color: Color(0xFF4338CA)),
              child: Column(
                children: inheritedValues.entries.map((e) {
                  final label = e.key.replaceAll('_', ' ');
                  return _KV(
                    label: label,
                    value: Text(e.value.toString(),
                        style: AppFonts.geist(fontSize: 12, color: AppColors.ctNavy)),
                  );
                }).toList(),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // ── Cronología ────────────────────────────────────────────────────
          const SizedBox(height: 16),
          _SideCard(
            title: 'Cronología',
            child: _TimelineSidebar(events: events),
          ),
          const SizedBox(height: 16),

          // ── Comportamiento ────────────────────────────────────────────────
          _SideCard(
            title: 'Comportamiento',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AL COMPLETAR',
                    style: AppFonts.geist(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.06,
                      color: const Color(0xFF94A3B8),
                    )),
                const SizedBox(height: 6),
                if (actionsLog.isEmpty)
                  Text('Sin acciones automáticas',
                      style: AppFonts.geist(
                          fontSize: 12, color: const Color(0xFF94A3B8)))
                else
                  Column(
                    children: actionsLog.map((action) {
                      final actionType =
                          action['action_type'] as String? ?? '';
                      final actionConfig = action['action_config'] as Map?;
                      final status = action['status'] as String?;
                      final condition =
                          actionConfig?['condition'] as String?;
                      final icon = _kActionIcons[actionType] ??
                          Icons.settings_outlined;
                      final label =
                          _kActionLabels[actionType] ?? actionType;
                      final (badgeBg, badgeFg, badgeText) =
                          switch (status) {
                        'completed' || 'success' => (
                            const Color(0xFFD1FAE5),
                            const Color(0xFF065F46),
                            'Completado',
                          ),
                        'failed' || 'error' => (
                            const Color(0xFFFEE2E2),
                            const Color(0xFF991B1B),
                            'Error',
                          ),
                        'pending' || 'queued' => (
                            const Color(0xFFF1F5F9),
                            const Color(0xFF475569),
                            'Pendiente',
                          ),
                        _ => (
                            const Color(0xFFF1F5F9),
                            const Color(0xFF475569),
                            status ?? '—',
                          ),
                      };
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.ctSurface2,
                            border: Border.all(color: AppColors.ctBorder),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(icon,
                                      size: 14, color: AppColors.ctTeal),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(label,
                                        style: const TextStyle(
                                            fontFamily: 'Geist',
                                            fontSize: 12,
                                            color: AppColors.ctNavy)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: badgeBg,
                                      borderRadius:
                                          BorderRadius.circular(99),
                                    ),
                                    child: Text(badgeText,
                                        style: AppFonts.geist(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: badgeFg)),
                                  ),
                                ],
                              ),
                              if (condition != null &&
                                  condition.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    const Icon(Icons.filter_alt_outlined,
                                        size: 11,
                                        color: AppColors.ctText3),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(condition,
                                          style: AppFonts.geist(
                                              fontSize: 10,
                                              color: AppColors.ctText3)),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Private helpers ───────────────────────────────────────────────────────────

List<Widget> _withDividers(List<Widget> items) {
  const divider = Divider(color: AppColors.ctBorder, thickness: 1, height: 1);
  final result = <Widget>[];
  for (var i = 0; i < items.length; i++) {
    result.add(items[i]);
    if (i < items.length - 1) result.add(divider);
  }
  return result;
}

class _SideCard extends StatelessWidget {
  const _SideCard({required this.title, required this.child, this.action, this.titleIcon});
  final String title;
  final Widget child;
  final Widget? action;
  final Widget? titleIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A0F172A), offset: Offset(0, 1), blurRadius: 2),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                if (titleIcon != null) ...[titleIcon!, const SizedBox(width: 6)],
                Expanded(
                  child: Text(title,
                      style: AppFonts.onest(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ctNavy)),
                ),
                ?action,
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.ctBorder),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _KV extends StatelessWidget {
  const _KV({required this.label, required this.value, this.copyText});
  final String label;
  final Widget value;
  final String? copyText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: AppFonts.geist(fontSize: 12, color: const Color(0xFF475569))),
          ),
          const SizedBox(width: 8),
          Expanded(child: value),
          if (copyText != null && copyText!.isNotEmpty) ...[
            const SizedBox(width: 4),
            SizedBox(
              width: 24,
              height: 24,
              child: IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: copyText!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copiado'),
                      duration: Duration(milliseconds: 1500),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded,
                    size: 14, color: AppColors.ctText2),
                padding: EdgeInsets.zero,
                tooltip: 'Copiar',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChannelLabel extends StatelessWidget {
  const _ChannelLabel({required this.channelType, required this.displayName});
  final String channelType;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color color;
    switch (channelType) {
      case 'whatsapp':
        icon = Icons.chat_rounded;
        color = AppColors.ctWa;
      case 'telegram':
        icon = Icons.send_rounded;
        color = AppColors.ctTg;
      case 'api':
        icon = Icons.code_rounded;
        color = AppColors.ctInfo;
      default:
        icon = Icons.dashboard_outlined;
        color = const Color(0xFF475569);
    }
    final Widget iconWidget = switch (channelType) {
      'whatsapp' => SvgPicture.asset('assets/logos/whatsapp.svg',
          width: 14, height: 14),
      'telegram' => Image.asset('assets/logos/telegram',
          width: 14, height: 14),
      _ => Icon(icon, size: 14, color: color),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        iconWidget,
        const SizedBox(width: 6),
        Flexible(
          child: Text(displayName,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.geist(fontSize: 12, color: AppColors.ctNavy)),
        ),
      ],
    );
  }
}

class _FlowIconTile extends StatelessWidget {
  const _FlowIconTile({required this.flowType});
  final String flowType;

  @override
  Widget build(BuildContext context) {
    final icon = switch (flowType) {
      'api'       => Icons.code_rounded,
      'dashboard' => Icons.dashboard_outlined,
      _           => Icons.chat_bubble_outline_rounded,
    };
    return Container(
      width: 34, height: 34,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.ctTeal, Color(0xFF15A99A)],
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
              color: Color(0x260B132B), offset: Offset(0, 1), blurRadius: 2),
        ],
      ),
      child: Icon(icon, size: 16, color: AppColors.ctNavy),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.ctTealLight,
        border: Border.all(color: const Color(0xFF99F6E4)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(label,
          style: AppFonts.geist(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.ctTealText)),
    );
  }
}

class _AvatarLarge extends StatelessWidget {
  const _AvatarLarge({required this.name, required this.size, this.src});
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
                errorBuilder: (ctx, err, stack) => _Initials(initials: initials, size: size))
            : _Initials(initials: initials, size: size),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.initials, required this.size});
  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
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

// ── Timeline sidebar ──────────────────────────────────────────────────────────

class _EventGroup {
  _EventGroup({required this.type, required Map<String, dynamic> first})
      : items = [first];
  final String type;
  final List<Map<String, dynamic>> items;

  int get count => items.length;
  String? get firstAt =>
      items.first['timestamp'] as String? ?? items.first['created_at'] as String?;
  String? get lastAt =>
      items.last['timestamp'] as String? ?? items.last['created_at'] as String?;
}

class _TimelineSidebar extends StatefulWidget {
  const _TimelineSidebar({required this.events});
  final List<Map<String, dynamic>> events;

  static const _months = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];

  static String _fmtFull(String? iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso).toLocal();
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      return '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} · $hh:$mm';
    } catch (_) {
      return iso;
    }
  }

  static String _fmtTime(String? iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  static ({Color color, String label}) _cfg(String type) => switch (type) {
    'flujo_iniciado'       => (color: AppColors.ctTeal,            label: 'Flujo iniciado'),
    'campo_capturado'      => (color: const Color(0xFF10B981),     label: 'Campo capturado'),
    'campo_rechazado'      => (color: const Color(0xFFF59E0B),     label: 'Campo rechazado'),
    'flujo_completado'     => (color: AppColors.ctTeal,            label: 'Flujo completado'),
    'flujo_abandonado'     => (color: const Color(0xFFEF4444),     label: 'Flujo abandonado'),
    'supervisor_intervino' => (color: const Color(0xFF3B82F6),     label: 'Supervisor intervino'),
    'worker_escaló'        => (color: const Color(0xFFF59E0B),     label: 'Worker escaló'),
    'flujo_pausado'        => (color: AppColors.ctText2,           label: 'Flujo pausado'),
    'flujo_retomado'       => (color: AppColors.ctTeal,            label: 'Flujo retomado'),
    _                      => (color: AppColors.ctText2,           label: type),
  };

  static List<String> _dataLines(dynamic raw) {
    if (raw == null) return [];
    if (raw is Map) {
      final m = raw.cast<String, dynamic>();
      if (m.isEmpty) return [];
      return m.entries.map((e) => '${e.key}: ${e.value}').toList();
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final m = decoded.cast<String, dynamic>();
          if (m.isEmpty) return [];
          return m.entries.map((e) => '${e.key}: ${e.value}').toList();
        }
      } catch (_) {}
      return [raw];
    }
    return [];
  }

  static List<_EventGroup> _buildGroups(List<Map<String, dynamic>> sorted) {
    final groups = <_EventGroup>[];
    for (final e in sorted) {
      final type = e['type'] as String? ?? e['event_type'] as String? ?? '';
      if (groups.isNotEmpty && groups.last.type == type) {
        groups.last.items.add(e);
      } else {
        groups.add(_EventGroup(type: type, first: e));
      }
    }
    return groups;
  }

  @override
  State<_TimelineSidebar> createState() => _TimelineSidebarState();
}

class _TimelineSidebarState extends State<_TimelineSidebar> {
  final _expanded = <int>{};

  @override
  Widget build(BuildContext context) {
final sorted = [...widget.events];
    sorted.sort((a, b) {
      final ta = a['timestamp'] as String? ?? a['created_at'] as String? ?? '';
      final tb = b['timestamp'] as String? ?? b['created_at'] as String? ?? '';
      return ta.compareTo(tb);
    });

    if (sorted.isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.timeline_rounded, size: 16, color: AppColors.ctText3),
          const SizedBox(width: 6),
          Text('Sin eventos registrados',
              style: AppFonts.geist(fontSize: 12, color: AppColors.ctText3)),
        ],
      );
    }

    final groups = _TimelineSidebar._buildGroups(sorted);

    return Column(
      children: [
        for (var i = 0; i < groups.length; i++)
          _GroupRow(
            group: groups[i],
            isLast: i == groups.length - 1,
            expanded: _expanded.contains(i),
            onToggle: () => setState(() {
              if (_expanded.contains(i)) {
                _expanded.remove(i);
              } else {
                _expanded.add(i);
              }
            }),
          ),
      ],
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    required this.isLast,
    required this.expanded,
    required this.onToggle,
  });
  final _EventGroup group;
  final bool isLast;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cfg = _TimelineSidebar._cfg(group.type);

    final bool hasExpandable = group.count > 1 ||
        _TimelineSidebar._dataLines(group.items.first['data']).isNotEmpty;

    final String timeStr = group.count == 1
        ? _TimelineSidebar._fmtFull(group.firstAt)
        : '${_TimelineSidebar._fmtTime(group.firstAt)} → ${_TimelineSidebar._fmtTime(group.lastAt)}';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Track ─────────────────────────────────────────────────────
          SizedBox(
            width: 16,
            child: Column(
              children: [
                const SizedBox(height: 3),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: cfg.color,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: AppColors.ctBorder,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // ── Content ───────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0.0 : 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: cfg.label,
                              style: AppFonts.geist(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ctNavy),
                            ),
                            if (group.count > 1)
                              TextSpan(
                                text: ' ×${group.count}',
                                style: AppFonts.geist(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.ctText3),
                              ),
                          ]),
                        ),
                      ),
                      if (hasExpandable)
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: IconButton(
                            onPressed: onToggle,
                            icon: Icon(
                              expanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 14,
                              color: AppColors.ctText3,
                            ),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                    ],
                  ),
                  Text(timeStr,
                      style: AppFonts.geist(
                          fontSize: 11, color: AppColors.ctText3)),
                  if (expanded) ...[
                    const SizedBox(height: 4),
                    if (group.count == 1)
                      _DataLines(
                          lines: _TimelineSidebar
                              ._dataLines(group.items.first['data']))
                    else
                      _SubEventList(items: group.items),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DataLines extends StatelessWidget {
  const _DataLines({required this.lines});
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines
            .map((l) => Text(l,
                style: AppFonts.geist(fontSize: 11, color: AppColors.ctText2)))
            .toList(),
      ),
    );
  }
}

class _SubEventList extends StatelessWidget {
  const _SubEventList({required this.items});
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map((e) {
          final ts = e['timestamp'] as String? ?? e['created_at'] as String?;
          final lines = _TimelineSidebar._dataLines(e['data']);
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _TimelineSidebar._fmtTime(ts),
                  style: AppFonts.geist(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ctText2),
                ),
                ...lines.map((l) => Text(l,
                    style:
                        AppFonts.geist(fontSize: 11, color: AppColors.ctText2))),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
