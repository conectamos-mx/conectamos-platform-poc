import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/catalogs_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/screen_header.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

String _formatLastSync(String? iso) {
  if (iso == null) return 'Nunca';
  try {
    final dt = DateTime.parse(iso).toLocal();
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Hace ${diff.inSeconds}s';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours}h';
    if (diff.inDays == 1) return 'Ayer';
    return 'Hace ${diff.inDays} días';
  } catch (_) {
    return '—';
  }
}

// ── Detail placeholder (ID-136) ───────────────────────────────────────────────

class CatalogDetailPlaceholder extends StatelessWidget {
  const CatalogDetailPlaceholder({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ctBg,
      appBar: AppBar(
        backgroundColor: AppColors.ctBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.ctText),
          onPressed: () => context.go('/catalogs'),
        ),
        title: Text(
          'Catálogo: $slug',
          style: AppFonts.onest(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.ctText,
          ),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_copy_outlined,
                size: 48, color: AppColors.ctText2),
            const SizedBox(height: 12),
            Text(
              'Próximamente — ID-136',
              style: AppFonts.geist(fontSize: 14, color: AppColors.ctText2),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pantalla principal ────────────────────────────────────────────────────────

class CatalogsScreen extends ConsumerStatefulWidget {
  const CatalogsScreen({super.key});

  @override
  ConsumerState<CatalogsScreen> createState() => _CatalogsScreenState();
}

class _CatalogsScreenState extends ConsumerState<CatalogsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _catalogs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tenantId = ref.read(activeTenantIdProvider);
      if (tenantId.isNotEmpty) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tenantId = ref.read(activeTenantIdProvider);
      final data = await CatalogsApi.listCatalogs(tenantId: tenantId);
      if (mounted) setState(() { _catalogs = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(activeTenantIdProvider, (prev, next) {
      if (next.isNotEmpty && prev != next) _load();
    });

    final canManage = hasPermission(ref, 'catalogs', 'manage');

    return Column(
      children: [
        ScreenHeader(
          title: 'Catálogos',
          subtitle: 'Datos del tenant referenciables desde flujos y workers.',
          actions: [
            if (canManage)
              Tooltip(
                message: 'Próximamente',
                child: _PrimaryButton(label: '+ Nuevo catálogo', onTap: null),
              ),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.ctTeal))
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!,
                              style: AppFonts.geist(
                                  fontSize: 14, color: AppColors.ctDanger)),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _load,
                            child: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(22),
                      child: _CatalogsBody(
                        catalogs: _catalogs,
                        canManage: canManage,
                        onRefresh: _load,
                      ),
                    ),
        ),
      ],
    );
  }
}

// ── Body con filtros y tabla ──────────────────────────────────────────────────

class _CatalogsBody extends StatefulWidget {
  const _CatalogsBody({
    required this.catalogs,
    required this.canManage,
    required this.onRefresh,
  });
  final List<Map<String, dynamic>> catalogs;
  final bool canManage;
  final VoidCallback onRefresh;

  @override
  State<_CatalogsBody> createState() => _CatalogsBodyState();
}

class _CatalogsBodyState extends State<_CatalogsBody> {
  String _filterSource = 'all';
  String _filterStatus = 'all';

  static const _sourceOptions = [
    ('all', 'Todos'),
    ('manual', 'Manual'),
    ('google_sheets', 'Google Sheets'),
    ('onedrive_excel', 'OneDrive Excel'),
    ('webhook_push', 'Webhook'),
    ('api_pull', 'API Pull'),
  ];

  static const _statusOptions = ['all', 'synced', 'failed', 'running', 'manual'];

  static String _statusLabel(String s) => switch (s) {
    'all'     => 'Todos los estados',
    'synced'  => 'Sincronizado',
    'failed'  => 'Error',
    'running' => 'Sincronizando',
    'manual'  => 'Manual',
    _         => s,
  };

  List<Map<String, dynamic>> get _filtered {
    return widget.catalogs.where((cat) {
      final source = cat['source_type'] as String? ?? '';
      final matchSource =
          _filterSource == 'all' || source == _filterSource;
      final status = cat['sync_status'] as String? ?? '';
      final matchStatus =
          _filterStatus == 'all' || status == _filterStatus;
      return matchSource && matchStatus;
    }).toList();
  }

  static const _headerStyle = TextStyle(
    fontFamily: 'Geist',
    fontSize: 10,
    fontWeight: FontWeight.w600,
    color: AppColors.ctText2,
    letterSpacing: 0.4,
  );

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Filtros ──────────────────────────────────────────────────────────
        Row(
          children: [
            // Pills de source
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _sourceOptions.map((opt) {
                  final (value, label) = opt;
                  final active = _filterSource == value;
                  return _SourcePill(
                    label: label,
                    active: active,
                    onTap: () => setState(() => _filterSource = value),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(width: 12),
            // Dropdown status
            _StatusDropdown(
              value: _filterStatus,
              options: _statusOptions,
              labelOf: _statusLabel,
              onChanged: (v) => setState(() => _filterStatus = v),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // ── Tabla ────────────────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: AppColors.ctSurface,
            border: Border.all(color: AppColors.ctBorder),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  color: AppColors.ctSurface2,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(9),
                    topRight: Radius.circular(9),
                  ),
                ),
                child: const Row(
                  children: [
                    Expanded(flex: 3, child: Text('NOMBRE', style: _headerStyle)),
                    Expanded(flex: 2, child: Text('FUENTE', style: _headerStyle)),
                    Expanded(flex: 1, child: Text('ITEMS', style: _headerStyle)),
                    Expanded(flex: 2, child: Text('ÚLTIMO SYNC', style: _headerStyle)),
                    Expanded(flex: 1, child: Text('STATUS', style: _headerStyle)),
                    Expanded(flex: 1, child: Text('ACCIONES', style: _headerStyle)),
                  ],
                ),
              ),

              // Filas
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.folder_open_outlined,
                            size: 48, color: AppColors.ctText2),
                        const SizedBox(height: 10),
                        Text(
                          'Sin catálogos',
                          style: AppFonts.onest(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ctText2),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'No hay catálogos que coincidan con los filtros aplicados.',
                          style: AppFonts.geist(
                              fontSize: 12, color: AppColors.ctText3),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...rows.asMap().entries.map((entry) {
                  final isLast = entry.key == rows.length - 1;
                  return Column(
                    children: [
                      _CatalogRow(
                        cat: entry.value,
                        canManage: widget.canManage,
                        onRefresh: widget.onRefresh,
                      ),
                      if (!isLast)
                        const Divider(height: 1, color: AppColors.ctBorder),
                    ],
                  );
                }),
            ],
          ),
        ),

        // Pie
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            '${rows.length} de ${widget.catalogs.length} catálogos',
            style: AppFonts.geist(fontSize: 11, color: AppColors.ctText2),
          ),
        ),
      ],
    );
  }
}

// ── Fila de catálogo ──────────────────────────────────────────────────────────

class _CatalogRow extends StatefulWidget {
  const _CatalogRow({
    required this.cat,
    required this.canManage,
    required this.onRefresh,
  });
  final Map<String, dynamic> cat;
  final bool canManage;
  final VoidCallback onRefresh;

  @override
  State<_CatalogRow> createState() => _CatalogRowState();
}

class _CatalogRowState extends State<_CatalogRow> {
  bool _hovered = false;
  bool _syncing = false;

  Future<void> _sync(BuildContext ctx) async {
    final id = widget.cat['id'] as String? ?? '';
    if (id.isEmpty) return;
    final messenger = ScaffoldMessenger.of(ctx);
    setState(() => _syncing = true);
    try {
      await CatalogsApi.syncCatalog(catalogId: id);
      if (mounted) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Sincronización iniciada'),
          duration: Duration(milliseconds: 2000),
        ));
        widget.onRefresh();
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('Error al sincronizar: $e'),
          backgroundColor: AppColors.ctDanger,
          duration: const Duration(milliseconds: 3000),
        ));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.cat;
    final id = cat['id'] as String? ?? '';
    final label = cat['label'] as String? ?? cat['name'] as String? ?? '—';
    final slug = cat['slug'] as String? ?? '';
    final sourceType = cat['source_type'] as String? ?? '';
    final itemsCount = cat['items_count'] as int? ?? 0;
    final lastSyncedAt = cat['last_synced_at'] as String?;
    final syncStatus = cat['sync_status'] as String? ?? 'manual';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        color: _hovered ? AppColors.ctBg : AppColors.ctSurface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // NOMBRE
            Expanded(
              flex: 3,
              child: GestureDetector(
                onTap: id.isNotEmpty ? () => context.go('/catalogs/$slug') : null,
                child: MouseRegion(
                  cursor: id.isNotEmpty
                      ? SystemMouseCursors.click
                      : MouseCursor.defer,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ctText,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (slug.isNotEmpty)
                        Text(
                          slug,
                          style: AppFonts.geist(
                              fontSize: 11, color: AppColors.ctText3),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // FUENTE
            Expanded(
              flex: 2,
              child: _SourceBadge(sourceType: sourceType),
            ),

            // ITEMS
            Expanded(
              flex: 1,
              child: Text(
                '$itemsCount',
                style: AppFonts.geist(fontSize: 12, color: AppColors.ctText2),
              ),
            ),

            // ÚLTIMO SYNC
            Expanded(
              flex: 2,
              child: Text(
                _formatLastSync(lastSyncedAt),
                style: AppFonts.geist(fontSize: 12, color: AppColors.ctText2),
              ),
            ),

            // STATUS
            Expanded(
              flex: 1,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _SyncStatusBadge(status: syncStatus),
              ),
            ),

            // ACCIONES
            Expanded(
              flex: 1,
              child: widget.canManage
                  ? _syncing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.ctTeal),
                        )
                      : Tooltip(
                          message: 'Sincronizar ahora',
                          child: IconButton(
                            onPressed: () => _sync(context),
                            icon: const Icon(Icons.sync_rounded,
                                size: 18, color: AppColors.ctText2),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Widgets auxiliares ────────────────────────────────────────────────────────

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.sourceType});
  final String sourceType;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (sourceType) {
      'manual'          => (Icons.edit_note_rounded, 'Manual'),
      'google_sheets'   => (Icons.table_chart_outlined, 'Google Sheets'),
      'onedrive_excel'  => (Icons.grid_on_outlined, 'OneDrive Excel'),
      'webhook_push'    => (Icons.webhook_outlined, 'Webhook'),
      'api_pull'        => (Icons.cloud_download_outlined, 'API Pull'),
      _                 => (Icons.storage_rounded, sourceType.isEmpty ? '—' : sourceType),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.ctText2),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            style: AppFonts.geist(fontSize: 12, color: AppColors.ctText2),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _SyncStatusBadge extends StatelessWidget {
  const _SyncStatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (status) {
      'synced'  => (AppColors.ctTealLight, AppColors.ctTealDark, 'Sincronizado'),
      'failed'  => (AppColors.ctRedBg, AppColors.ctRedText, 'Error'),
      'running' => (AppColors.ctWarnBg, AppColors.ctWarnText, 'Sincronizando'),
      'manual'  => (AppColors.ctSurface2, AppColors.ctText3, 'Manual'),
      _         => (AppColors.ctSurface2, AppColors.ctText2, status.isEmpty ? '—' : status),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: AppFonts.geist(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class _SourcePill extends StatelessWidget {
  const _SourcePill({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? AppColors.ctTealLight : AppColors.ctSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? AppColors.ctTeal : AppColors.ctBorder2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active ? AppColors.ctTealDark : AppColors.ctText2,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusDropdown extends StatelessWidget {
  const _StatusDropdown({
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
  });
  final String value;
  final List<String> options;
  final String Function(String) labelOf;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      height: 36,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.ctSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.ctBorder2),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isDense: true,
            isExpanded: true,
            style: AppFonts.geist(fontSize: 12, color: AppColors.ctText),
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                size: 16, color: AppColors.ctText3),
            items: options
                .map((o) => DropdownMenuItem(
                    value: o,
                    child: Text(labelOf(o))))
                .toList(),
            onChanged: (v) { if (v != null) onChanged(v); },
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  const _PrimaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.forbidden,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: widget.onTap == null
                ? AppColors.ctSurface2
                : _hovered
                    ? AppColors.ctTealDark
                    : AppColors.ctTeal,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.label,
            style: AppFonts.onest(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: widget.onTap == null
                  ? AppColors.ctText2
                  : AppColors.ctNavy,
            ),
          ),
        ),
      ),
    );
  }
}
