import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/assignments_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

(DateTime?, DateTime?) _parseScope(String? raw) {
  if (raw == null || raw.isEmpty) return (null, null);
  try {
    final clean = raw
        .replaceAll('"', '')
        .replaceAll('[', '')
        .replaceAll('(', '')
        .replaceAll(']', '')
        .replaceAll(')', '');
    final parts = clean.split(',');
    if (parts.length < 2) return (null, null);
    final lower = parts[0].trim();
    final upper = parts[1].trim();
    if (lower.isEmpty || upper.isEmpty) return (null, null);
    return (DateTime.parse(lower), DateTime.parse(upper));
  } catch (_) {
    return (null, null);
  }
}

final _dateFmt = DateFormat('d MMM', 'es');
final _dtFmt   = DateFormat('d MMM HH:mm', 'es');

String _fmtScope(String? raw) {
  final (lo, hi) = _parseScope(raw);
  if (lo == null || hi == null) return '—';
  return '${_dtFmt.format(lo.toLocal())} – ${_dtFmt.format(hi.toLocal())}';
}

String _fmtCreatedAt(String? raw) {
  if (raw == null) return '—';
  try {
    final dt = DateTime.parse(raw).toLocal();
    return _dateFmt.format(dt);
  } catch (_) {
    return raw;
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class AssignmentDetailScreen extends ConsumerStatefulWidget {
  const AssignmentDetailScreen({super.key, required this.assignmentId});
  final String assignmentId;

  @override
  ConsumerState<AssignmentDetailScreen> createState() =>
      _AssignmentDetailScreenState();
}

class _AssignmentDetailScreenState
    extends ConsumerState<AssignmentDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _assignment;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final tenantId = ref.read(activeTenantIdProvider);
      final data = await AssignmentsApi.getAssignment(
        tenantId: tenantId,
        assignmentId: widget.assignmentId,
      );
      setState(() { _assignment = data; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(userPermissionsProvider);
    if (perms.valueOrNull != null &&
        !perms.valueOrNull!.contains('assignments.view')) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => context.go('/overview'));
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: AppColors.ctSurface,
      appBar: AppBar(
        backgroundColor: AppColors.ctNavy,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/assignments'),
        ),
        title: Text(
          'Asignación',
          style: AppFonts.onest(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppColors.ctTeal,
          unselectedLabelColor: Colors.white60,
          indicatorColor: AppColors.ctTeal,
          labelStyle: AppFonts.geist(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          tabs: const [
            Tab(text: 'INFO'),
            Tab(text: 'ACTIVOS'),
            Tab(text: 'FLOWS'),
            Tab(text: 'HISTORIAL'),
          ],
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.ctTeal))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!,
                          style: AppFonts.geist(
                              fontSize: 13, color: AppColors.ctDanger)),
                      const SizedBox(height: 12),
                      TextButton(
                          onPressed: _load,
                          child: const Text('Reintentar')),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _InfoTab(assignment: _assignment!),
                    _ActivosTab(assignment: _assignment!),
                    _FlowsTab(assignment: _assignment!),
                    const _HistorialTab(),
                  ],
                ),
    );
  }
}

// ── Tab INFO ──────────────────────────────────────────────────────────────────

class _InfoTab extends StatelessWidget {
  const _InfoTab({required this.assignment});
  final Map<String, dynamic> assignment;

  @override
  Widget build(BuildContext context) {
    final opName  = assignment['operator_name'] as String? ?? '—';
    final opPhone = assignment['operator_phone'] as String? ?? '';
    final scope   = _fmtScope(assignment['scope'] as String?);
    final source  = assignment['source'] as String? ?? 'manual';
    final created = _fmtCreatedAt(assignment['created_at'] as String?);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _Card(
        children: [
          _InfoRow(label: 'Operador',
              value: opPhone.isNotEmpty ? '$opName · $opPhone' : opName),
          _InfoRow(label: 'Ventana', value: scope),
          _InfoRow(
            label: 'Fuente',
            valueWidget: _SourceBadge(source: source),
          ),
          _InfoRow(label: 'Creado', value: created),
        ],
      ),
    );
  }
}

// ── Tab ACTIVOS ───────────────────────────────────────────────────────────────

class _ActivosTab extends StatelessWidget {
  const _ActivosTab({required this.assignment});
  final Map<String, dynamic> assignment;

  @override
  Widget build(BuildContext context) {
    final resources = (assignment['resources'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];

    if (resources.isEmpty) {
      return Center(
        child: Text('Sin activos asignados',
            style: AppFonts.geist(fontSize: 13, color: AppColors.ctText2)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: resources.length,
      itemBuilder: (context, i) {
        final r = resources[i];
        final catalog = r['catalog_slug'] as String? ?? '—';
        final data = r['data'] as Map?;
        final itemLabel = data?['nombre'] as String? ??
            data?['name'] as String? ??
            data?['label'] as String? ??
            r['asset_item_id'] as String? ??
            '—';
        final type = r['resource_type'] as String?;
        return _Card(
          margin: const EdgeInsets.only(bottom: 10),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(catalog,
                      style: AppFonts.onest(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ctText)),
                ),
                if (type != null && type.isNotEmpty)
                  _Badge(
                      label: type,
                      bg: AppColors.ctSurface2,
                      fg: AppColors.ctText2),
              ],
            ),
            const SizedBox(height: 4),
            Text(itemLabel,
                style: AppFonts.geist(
                    fontSize: 12, color: AppColors.ctText2)),
          ],
        );
      },
    );
  }
}

// ── Tab FLOWS ─────────────────────────────────────────────────────────────────

class _FlowsTab extends StatelessWidget {
  const _FlowsTab({required this.assignment});
  final Map<String, dynamic> assignment;

  @override
  Widget build(BuildContext context) {
    final flows = (assignment['flows'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];

    if (flows.isEmpty) {
      return Center(
        child: Text('Sin flows asignados',
            style: AppFonts.geist(fontSize: 13, color: AppColors.ctText2)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: flows.length,
      itemBuilder: (context, i) {
        final f = flows[i];
        final rawId  = f['flow_definition_id'] as String? ?? '';
        // TODO: backend debe incluir flow_name en assignment_flows response
        final name   = f['flow_name'] as String? ??
            f['flow_slug'] as String? ??
            (rawId.length > 8 ? '${rawId.substring(0, 8)}…' : rawId.isNotEmpty ? rawId : '—');
        final behavior = f['behavior'] as String? ?? '—';
        final trigger  = f['trigger_offset'];
        final window   = f['completion_window'];

        final (bg, fg) = switch (behavior) {
          'scheduled'  => (AppColors.ctTealLight, AppColors.ctTealText),
          'permissive' => (AppColors.ctSurface2,  AppColors.ctNavy),
          'proactive'  => (AppColors.ctWarnBg,    AppColors.ctWarnText),
          _            => (AppColors.ctSurface2,  AppColors.ctText2),
        };

        return _Card(
          margin: const EdgeInsets.only(bottom: 10),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(name,
                      style: AppFonts.onest(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ctText)),
                ),
                _Badge(label: behavior, bg: bg, fg: fg),
              ],
            ),
            if (trigger != null) ...[
              const SizedBox(height: 4),
              Text('Offset: $trigger',
                  style: AppFonts.geist(
                      fontSize: 12, color: AppColors.ctText2)),
            ],
            if (window != null) ...[
              const SizedBox(height: 4),
              Text('Ventana: $window',
                  style: AppFonts.geist(
                      fontSize: 12, color: AppColors.ctText2)),
            ],
          ],
        );
      },
    );
  }
}

// ── Tab HISTORIAL ─────────────────────────────────────────────────────────────

class _HistorialTab extends StatelessWidget {
  const _HistorialTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Próximamente — ejecuciones relacionadas a esta asignación',
        style: AppFonts.geist(fontSize: 13, color: AppColors.ctText2),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.children, this.margin});
  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, this.value, this.valueWidget});
  final String label;
  final String? value;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: AppFonts.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ctText2)),
          ),
          Expanded(
            child: valueWidget ??
                Text(value ?? '—',
                    style: AppFonts.geist(
                        fontSize: 12, color: AppColors.ctText)),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.bg, required this.fg});
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: AppFonts.geist(
              fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});
  final String source;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (source) {
      'csv'  => (AppColors.ctInfoBg,   AppColors.ctInfoText,   'CSV'),
      'sync' => (AppColors.ctOkBg,     AppColors.ctOkText,     'sync'),
      'api'  => (AppColors.ctOrangeBg, AppColors.ctOrangeText, 'api'),
      _      => (AppColors.ctSurface2, AppColors.ctText2,      'manual'),
    };
    return _Badge(label: label, bg: bg, fg: fg);
  }
}
