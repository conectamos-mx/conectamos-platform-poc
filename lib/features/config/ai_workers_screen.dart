import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/ai_workers_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/page_header.dart';

// ── Constants ─────────────────────────────────────────────────────────────────


const _kTypeConfig = {
  'logistics':   (label: 'Logística', bg: Color(0xFFDBEAFE), fg: Color(0xFF1E40AF)),
  'sales':       (label: 'Ventas',    bg: Color(0xFFEDE9FE), fg: Color(0xFF6D28D9)),
  'collections': (label: 'Cobranza', bg: Color(0xFFFEF3C7), fg: Color(0xFFB45309)),
  'custom':      (label: 'Custom',   bg: Color(0xFFF3F4F6), fg: Color(0xFF374151)),
};

// ── Helpers ───────────────────────────────────────────────────────────────────

Color _hexColor(String hex) {
  final h = hex.replaceAll('#', '');
  return Color(int.parse('FF$h', radix: 16));
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  return name.isEmpty ? '?' : name[0].toUpperCase();
}

String _fmtDate(String? iso) {
  if (iso == null) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.day}/${dt.month}/${dt.year}';
  } catch (_) {
    return '—';
  }
}

String _dioError(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      final d = data['detail'];
      if (d != null) return 'Error: $d';
    }
    final s = e.response?.statusCode;
    if (s != null) return 'Error $s al procesar la solicitud';
  }
  return e.toString();
}

// ── Screen ────────────────────────────────────────────────────────────────────

class AiWorkersScreen extends ConsumerStatefulWidget {
  const AiWorkersScreen({super.key});

  @override
  ConsumerState<AiWorkersScreen> createState() => _AiWorkersScreenState();
}

class _AiWorkersScreenState extends ConsumerState<AiWorkersScreen> {
  List<Map<String, dynamic>> _myWorkers = [];
  List<Map<String, dynamic>> _catalog   = [];
  bool    _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchAll());
  }

  Future<void> _fetchAll() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        AiWorkersApi.listWorkers(),
        AiWorkersApi.listCatalog(),
      ]);
      if (!mounted) return;
      setState(() {
        _myWorkers = results[0];
        _catalog   = results[1];
        _loading   = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = _dioError(e); });
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> worker) async {
    final id       = worker['id'] as String? ?? '';
    final isActive = worker['is_active'] as bool? ?? false;
    // Optimistic update
    setState(() {
      _myWorkers = [
        for (final w in _myWorkers)
          if ((w['id'] as String?) == id)
            {...w, 'is_active': !isActive}
          else
            w,
      ];
    });
    try {
      await AiWorkersApi.updateWorker(
        tenantWorkerId: id,
        isActive: !isActive,
      );
    } catch (e) {
      if (!mounted) return;
      // Revert
      setState(() {
        _myWorkers = [
          for (final w in _myWorkers)
            if ((w['id'] as String?) == id)
              {...w, 'is_active': isActive}
            else
              w,
        ];
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_dioError(e)),
        backgroundColor: AppColors.ctDanger,
      ));
    }
  }

  void _openRename(Map<String, dynamic> worker) async {
    await showDialog(
      context: context,
      builder: (_) => _RenameDialog(
        worker: worker,
        tenantId: ref.read(activeTenantIdProvider),
        onSaved: _fetchAll,
      ),
    );
  }

  void _openCatalog() async {
    final messenger = ScaffoldMessenger.of(context);
    await showDialog(
      context: context,
      builder: (_) => _CatalogDialog(
        catalog: _catalog,
        myWorkers: _myWorkers,
        tenantId: ref.read(activeTenantIdProvider),
        onContracted: () async {
          await _fetchAll();
          messenger.showSnackBar(const SnackBar(
            content: Text('Worker contratado exitosamente'),
            backgroundColor: AppColors.ctOk,
          ));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(activeTenantIdProvider, (prev, next) {
      if (prev != next) _fetchAll();
    });
    final canManage = hasPermission(ref, 'settings', 'manage');
    return Column(
      children: [
        PageHeader(
          eyebrow: 'Workers',
          title: 'Mis AI Workers',
          description: 'Workers de IA contratados para tu operación',
          actions: [
            _PrimaryBtn(label: '+ Contratar worker', onTap: _openCatalog, disabled: _loading || !canManage),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.ctTeal, strokeWidth: 2,
                  ),
                )
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _error!,
                            style: AppTextStyles.body.copyWith(color: AppColors.ctDanger),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          _GhostBtn(label: 'Reintentar', onTap: _fetchAll),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      child: _myWorkers.isEmpty
                          ? _EmptyState(onOpenCatalog: _openCatalog, canManage: canManage)
                          : _WorkersBody(
                              workers: _myWorkers,
                              onToggle: _toggleActive,
                              onRename: _openRename,
                              onTap: (worker) {
                                final id = worker['id'] as String? ?? '';
                                if (id.isNotEmpty) context.go('/workers/$id');
                              },
                              canManage: canManage,
                            ),
                    ),
        ),
      ],
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onOpenCatalog, this.canManage = true});
  final VoidCallback onOpenCatalog;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No tienes workers contratados aún.',
              style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
            ),
            const SizedBox(height: 14),
            _PrimaryBtn(label: 'Ver catálogo', onTap: onOpenCatalog, disabled: !canManage),
          ],
        ),
      ),
    );
  }
}

// ── Workers body ──────────────────────────────────────────────────────────────

class _WorkersBody extends StatelessWidget {
  const _WorkersBody({
    required this.workers,
    required this.onToggle,
    required this.onRename,
    required this.onTap,
    this.canManage = true,
  });
  final List<Map<String, dynamic>> workers;
  final void Function(Map<String, dynamic>) onToggle;
  final void Function(Map<String, dynamic>) onRename;
  final void Function(Map<String, dynamic>) onTap;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          ...workers.map((w) => SizedBox(
                width: 380,
                child: _WorkerCard(
                  worker: w,
                  onTap: () => onTap(w),
                  onToggle: canManage ? () => onToggle(w) : null,
                  onRename: canManage ? () => onRename(w) : null,
                ),
              )),
          SizedBox(
            width: 380,
            child: _AddWorkerCard(
              onTap: () => context.go('/catalog/workers'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Worker card ───────────────────────────────────────────────────────────────

class _WorkerCard extends StatefulWidget {
  const _WorkerCard({
    required this.worker,
    this.onTap,
    this.onToggle,
    this.onRename,
  });
  final Map<String, dynamic> worker;
  final VoidCallback? onTap;
  final VoidCallback? onToggle;
  final VoidCallback? onRename;

  @override
  State<_WorkerCard> createState() => _WorkerCardState();
}

class _WorkerCardState extends State<_WorkerCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final w           = widget.worker;
    final displayName = w['display_name'] as String? ?? w['catalog_name'] as String? ?? '—';
    final colorHex    = w['catalog_color'] as String? ?? '#59E0CC';
    final workerType  = w['catalog_worker_type'] as String? ?? 'custom';
    final isActive    = w['is_active'] as bool? ?? false;
    final iconUrl     = w['catalog_icon_url'] as String?;
    final typeEntry   = _kTypeConfig[workerType] ?? _kTypeConfig['custom']!;
    final flowCount   = (w['flows'] as List? ?? []).length;
    final runningNow  = w['running_now'] as int? ?? 0;
    final channelCount = w['channel_count'] as int? ?? 0;
    final contractedAt = w['contracted_at'] as String?;
    final workerColor = _hexColor(colorHex);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: AppColors.ctSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered ? workerColor : AppColors.ctBorder,
              width: 1.5,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: workerColor.withValues(alpha: 0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Gradiente superior
              Container(
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      workerColor.withValues(alpha: 0.18),
                      workerColor.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              // Row 1 — Avatar + nombre + badges
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: workerColor, width: 2),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: iconUrl != null
                              ? Image.network(
                                  iconUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context2, err, stack) => _InitialAvatar(
                                    color: workerColor,
                                    initials: _initials(displayName),
                                  ),
                                )
                              : _InitialAvatar(
                                  color: workerColor,
                                  initials: _initials(displayName),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayName,
                          style: AppTextStyles.cardTitle,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        _TypeBadge(
                          label: typeEntry.label,
                          bg: typeEntry.bg,
                          fg: typeEntry.fg,
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.ctOkBg
                          : AppColors.ctSurface2,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isActive ? 'Activo' : 'Inactivo',
                      style: AppTextStyles.badge.copyWith(
                        color: isActive
                            ? AppColors.ctOkText
                            : AppColors.ctText2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Row 2 — KPIs
              Container(
                decoration: BoxDecoration(
                  color: AppColors.ctSurface2,
                  border: Border.all(color: AppColors.ctBorder),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Expanded(child: _KpiCell(value: runningNow.toString(), label: 'Ejecuciones', valueColor: workerColor)),
                      const VerticalDivider(width: 1, color: AppColors.ctBorder),
                      Expanded(child: _KpiCell(value: channelCount.toString(), label: 'Canales', valueColor: workerColor)),
                      const VerticalDivider(width: 1, color: AppColors.ctBorder),
                      Expanded(child: _KpiCell(value: flowCount.toString(), label: 'Flujos', valueColor: workerColor)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Row 3 — Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Desde ${_fmtDate(contractedAt)}',
                    style: AppTextStyles.navItem.copyWith(
                        color: AppColors.ctText3),
                  ),
                  GestureDetector(
                    onTap: widget.onTap,
                    child: Text(
                      'Abrir workspace →',
                      style: AppTextStyles.navItem.copyWith(
                          color: AppColors.ctTeal),
                    ),
                  ),
                ],
              ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Initial avatar fallback ───────────────────────────────────────────────────

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.color, required this.initials});
  final Color color;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color.withValues(alpha: 0.18),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: AppTextStyles.badge.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }
}

// ── KPI cell ──────────────────────────────────────────────────────────────────

class _KpiCell extends StatelessWidget {
  const _KpiCell({required this.value, required this.label, this.valueColor});
  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            value,
            style: AppTextStyles.cardTitle.copyWith(
                fontSize: 18, fontWeight: FontWeight.w700, color: valueColor),
          ),
          Text(label, style: AppTextStyles.navItem),
        ],
      ),
    );
  }
}

// ── Add worker card ───────────────────────────────────────────────────────────

class _AddWorkerCard extends StatefulWidget {
  const _AddWorkerCard({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_AddWorkerCard> createState() => _AddWorkerCardState();
}

class _AddWorkerCardState extends State<_AddWorkerCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: _hovered
                ? AppColors.ctTeal
                : AppColors.ctText3.withValues(alpha: 0.4),
            isHovered: _hovered,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            constraints: const BoxConstraints(minHeight: 200),
            decoration: BoxDecoration(
              color: _hovered
                  ? AppColors.ctTeal.withValues(alpha: 0.06)
                  : AppColors.ctSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add,
                    size: 24,
                    color: _hovered ? AppColors.ctTeal : AppColors.ctText3),
                const SizedBox(height: 8),
                Text(
                  'Contratar worker',
                  style: AppTextStyles.body.copyWith(
                      color: _hovered ? AppColors.ctText : null),
                ),
                Text(
                  'Explorar catálogo',
                  style:
                      AppTextStyles.navItem.copyWith(color: AppColors.ctText3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Dashed border painter ─────────────────────────────────────────────────────

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.isHovered});
  final Color color;
  final bool isHovered;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    const radius = 12.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.75, 0.75, size.width - 1.5, size.height - 1.5),
      const Radius.circular(radius),
    );
    final path = Path()..addRRect(rect);
    final pathMetrics = path.computeMetrics();
    for (final metric in pathMetrics) {
      double distance = 0;
      while (distance < metric.length) {
        final extractPath =
            metric.extractPath(distance, distance + dashWidth);
        canvas.drawPath(extractPath, paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.isHovered != isHovered;
}

// ── Rename dialog ─────────────────────────────────────────────────────────────

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({
    required this.worker,
    required this.tenantId,
    required this.onSaved,
  });
  final Map<String, dynamic> worker;
  final String tenantId;
  final Future<void> Function() onSaved;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _nameCtrl;
  bool    _saving   = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    final current = widget.worker['display_name'] as String? ??
        widget.worker['catalog_name'] as String? ?? '';
    _nameCtrl = TextEditingController(text: current);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMsg = 'El nombre no puede estar vacío.');
      return;
    }
    setState(() { _saving = true; _errorMsg = null; });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final id = widget.worker['id'] as String? ?? '';
      await AiWorkersApi.updateWorker(
        tenantWorkerId: id,
        displayName: name,
      );
      if (!mounted) return;
      Navigator.pop(context);
      await widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() { _saving = false; _errorMsg = _dioError(e); });
      messenger.showSnackBar(SnackBar(
        content: Text(_dioError(e)),
        backgroundColor: AppColors.ctDanger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final originalName = widget.worker['catalog_name'] as String? ?? '';

    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.ctBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Renombrar worker',
                style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist'),
              ),
              if (originalName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Nombre original: $originalName',
                  style: AppTextStyles.navItem,
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Nombre personalizado',
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                style: AppTextStyles.body,
                decoration: InputDecoration(
                  hintText: 'Ej: Worker Logística Norte',
                  hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                  filled: true,
                  fillColor: AppColors.ctSurface2,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.ctBorder2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.ctBorder2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: AppColors.ctTeal, width: 1.5),
                  ),
                ),
                onSubmitted: (_) => _save(),
              ),
              if (_errorMsg != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.ctRedBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMsg!,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontSize: 12, color: AppColors.ctRedText),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _GhostBtn(
                    label: 'Cancelar',
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  _saving
                      ? _loadingBtn()
                      : _PrimaryBtn(label: 'Guardar', onTap: _save),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Catalog dialog ────────────────────────────────────────────────────────────

class _CatalogDialog extends StatefulWidget {
  const _CatalogDialog({
    required this.catalog,
    required this.myWorkers,
    required this.tenantId,
    required this.onContracted,
  });
  final List<Map<String, dynamic>> catalog;
  final List<Map<String, dynamic>> myWorkers;
  final String tenantId;
  final Future<void> Function() onContracted;

  @override
  State<_CatalogDialog> createState() => _CatalogDialogState();
}

class _CatalogDialogState extends State<_CatalogDialog> {
  final Set<String> _contracting = {};

  bool _isContracted(String catalogId) => widget.myWorkers.any(
    (w) => (w['catalog_worker_id'] as String?) == catalogId,
  );

  Future<void> _contract(String catalogId) async {
    if (_contracting.contains(catalogId)) return;
    setState(() => _contracting.add(catalogId));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AiWorkersApi.contractWorker(
        catalogWorkerId: catalogId,
      );
      if (!mounted) return;
      Navigator.pop(context);
      await widget.onContracted();
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _contracting.remove(catalogId));
      final status = e.response?.statusCode;
      final String msg;
      final Color color;
      if (status == 409) {
        msg   = 'Ya tienes este worker contratado.';
        color = AppColors.ctWarn;
      } else if (status == 400) {
        final data = e.response?.data;
        msg   = (data is Map && data['detail'] != null)
            ? 'Error: ${data['detail']}'
            : 'Solicitud inválida.';
        color = AppColors.ctDanger;
      } else {
        msg   = _dioError(e);
        color = AppColors.ctDanger;
      }
      messenger.showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: color,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _contracting.remove(catalogId));
      messenger.showSnackBar(SnackBar(
        content: Text(_dioError(e)),
        backgroundColor: AppColors.ctDanger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.ctBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Catálogo de Workers',
                    style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist'),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Selecciona un worker para agregarlo a tu operación.',
                    style: AppTextStyles.navItem,
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: AppColors.ctBorder),

            // Catalog list
            Flexible(
              child: widget.catalog.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'No hay workers en el catálogo.',
                          style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: widget.catalog.length,
                      itemBuilder: (_, i) {
                        final item        = widget.catalog[i];
                        final catalogId   = item['id'] as String? ?? '';
                        final name        = item['name'] as String? ?? item['display_name'] as String? ?? '—';
                        final description = item['description'] as String? ?? '';
                        final colorHex    = item['color'] as String? ?? '#59E0CC';
                        final isPublished = item['is_published'] as bool? ?? true;
                        final contracted  = _isContracted(catalogId);
                        final contracting = _contracting.contains(catalogId);

                        final rawSkills = item['skills'] as List<dynamic>? ?? [];
                        final skills    = rawSkills.map((s) => s.toString()).toList();

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: AppColors.ctSurface,
                            border: Border.all(color: AppColors.ctBorder),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Avatar
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _hexColor(colorHex),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  _initials(name),
                                  style: AppTextStyles.body.copyWith(
                                    fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                              ),
                              const SizedBox(width: 14),

                              // Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: AppTextStyles.body.copyWith(
                                        fontSize: 14, fontWeight: FontWeight.w600),
                                    ),
                                    if (description.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        description,
                                        style: AppTextStyles.navItem,
                                      ),
                                    ],
                                    if (skills.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: skills.map((s) {
                                          return Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.ctSurface2,
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(color: AppColors.ctBorder),
                                            ),
                                            child: Text(
                                              s,
                                              style: AppTextStyles.bodySmall,
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Action
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (!isPublished)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: AppColors.ctSurface2,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: AppColors.ctBorder),
                                      ),
                                      child: Text(
                                        'Próximamente',
                                        style: AppTextStyles.bodySmall.copyWith(
                                          fontWeight: FontWeight.w500),
                                      ),
                                    )
                                  else if (contracted)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: AppColors.ctOkBg,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        'Contratado',
                                        style: AppTextStyles.badge.copyWith(
                                          color: AppColors.ctOkText,
                                        )),
                                    )
                                  else
                                    contracting
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: AppColors.ctTeal,
                                            ),
                                          )
                                        : _PrimaryBtn(
                                            label: 'Contratar',
                                            onTap: () => _contract(catalogId),
                                          ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            const Divider(height: 1, color: AppColors.ctBorder),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _GhostBtn(
                    label: 'Cerrar',
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Type badge ────────────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({
    required this.label,
    required this.bg,
    required this.fg,
  });
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: AppTextStyles.badge.copyWith(color: fg),
      ),
    );
  }
}

// ── Loading button helper ─────────────────────────────────────────────────────

Widget _loadingBtn() => Container(
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
  decoration: BoxDecoration(
    color: AppColors.ctTeal, borderRadius: BorderRadius.circular(8),
  ),
  child: const SizedBox(
    width: 16, height: 16,
    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ctNavy),
  ),
);

// ── Button helpers ────────────────────────────────────────────────────────────

class _PrimaryBtn extends StatefulWidget {
  const _PrimaryBtn({
    required this.label,
    required this.onTap,
    this.disabled = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool disabled;

  @override
  State<_PrimaryBtn> createState() => _PrimaryBtnState();
}

class _PrimaryBtnState extends State<_PrimaryBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: widget.disabled
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.disabled ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: widget.disabled
                ? AppColors.ctBorder2
                : _hovered ? AppColors.ctTealDark : AppColors.ctTeal,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.label,
            style: AppTextStyles.body.copyWith(
              fontWeight: FontWeight.w600,
              color: widget.disabled ? AppColors.ctText3 : AppColors.ctNavy,
            ),
          ),
        ),
      ),
    );
  }
}

class _GhostBtn extends StatefulWidget {
  const _GhostBtn({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_GhostBtn> createState() => _GhostBtnState();
}

class _GhostBtnState extends State<_GhostBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.ctSurface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.ctBorder),
          ),
          child: Text(
            widget.label,
            style: AppTextStyles.btnSecondary.copyWith(color: AppColors.ctText2),
          ),
        ),
      ),
    );
  }
}

