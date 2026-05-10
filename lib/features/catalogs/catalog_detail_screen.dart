import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/catalogs_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

String _fmtSync(String? iso) {
  if (iso == null) return 'Nunca';
  try {
    final dt = DateTime.parse(iso).toLocal();
    final d = DateTime.now().difference(dt);
    if (d.inSeconds < 60) return 'Hace ${d.inSeconds}s';
    if (d.inMinutes < 60) return 'Hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'Hace ${d.inHours}h';
    if (d.inDays == 1) return 'Ayer';
    return 'Hace ${d.inDays} días';
  } catch (_) {
    return '—';
  }
}

// ── CatalogDetailScreen ───────────────────────────────────────────────────────

class CatalogDetailScreen extends ConsumerStatefulWidget {
  const CatalogDetailScreen({super.key, required this.slug});
  final String slug;

  @override
  ConsumerState<CatalogDetailScreen> createState() =>
      _CatalogDetailScreenState();
}

class _CatalogDetailScreenState extends ConsumerState<CatalogDetailScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _catalog;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final tenantId = ref.read(activeTenantIdProvider);
      final data = await CatalogsApi.getCatalogBySlug(
        tenantId: tenantId,
        slug: widget.slug,
      );
      if (mounted) setState(() { _catalog = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.ctNavy,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => context.go('/catalogs'),
      ),
      title: Text(
        _catalog?['label'] as String? ?? widget.slug,
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
        labelStyle: const TextStyle(
            fontFamily: 'Geist', fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontFamily: 'Geist', fontSize: 12),
        tabs: const [
          Tab(text: 'CONFIGURACIÓN'),
          Tab(text: 'FUENTE'),
          Tab(text: 'ITEMS'),
          Tab(text: 'SYNC'),
          Tab(text: 'USO'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.ctBg,
        appBar: _buildAppBar(),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.ctTeal),
        ),
      );
    }

    if (_error != null || _catalog == null) {
      return Scaffold(
        backgroundColor: AppColors.ctBg,
        appBar: _buildAppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.ctDanger),
              const SizedBox(height: 12),
              Text(
                _error ?? 'No se encontró el catálogo',
                style: AppFonts.geist(fontSize: 14, color: AppColors.ctText2),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton(onPressed: _load, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }

    final canManage = hasPermission(ref, 'catalogs', 'manage');
    final catalog = _catalog!;

    return Scaffold(
      backgroundColor: AppColors.ctBg,
      appBar: _buildAppBar(),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _ConfigTab(catalog: catalog, canManage: canManage),
          _SourceTab(catalog: catalog, canManage: canManage),
          _ItemsTab(catalog: catalog),
          const _SyncTab(),
          const _UsoTab(),
        ],
      ),
    );
  }
}

// ── Tab 0 — CONFIGURACIÓN ─────────────────────────────────────────────────────

class _ConfigTab extends ConsumerStatefulWidget {
  const _ConfigTab({required this.catalog, required this.canManage});
  final Map<String, dynamic> catalog;
  final bool canManage;

  @override
  ConsumerState<_ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends ConsumerState<_ConfigTab> {
  List<Map<String, dynamic>> _fields = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final raw = widget.catalog['fields_schema'];
    _fields = raw is List
        ? List<Map<String, dynamic>>.from(
            raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)))
        : [];
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _fields.removeAt(oldIndex);
      _fields.insert(newIndex, item);
    });
  }

  Future<void> _save() async {
    final tenantId = ref.read(activeTenantIdProvider);
    final catalogId = widget.catalog['id'] as String? ?? '';
    if (catalogId.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await CatalogsApi.updateCatalog(
        tenantId: tenantId,
        catalogId: catalogId,
        body: {'fields_schema': _fields},
      );
      if (mounted) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Cambios guardados'),
          duration: Duration(milliseconds: 2000),
        ));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('Error al guardar: $e'),
          backgroundColor: AppColors.ctDanger,
          duration: const Duration(milliseconds: 3000),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_fields.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schema_outlined, size: 48, color: AppColors.ctText2),
            const SizedBox(height: 10),
            Text('Sin esquema de campos definido',
                style: AppFonts.geist(fontSize: 14, color: AppColors.ctText2)),
          ],
        ),
      );
    }

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 80),
              sliver: SliverReorderableList(
                itemCount: _fields.length,
                onReorder: widget.canManage ? _onReorder : (a, b) {},
                itemBuilder: (ctx, i) {
                  final field = _fields[i];
                  final fieldKey = field['key'] as String? ?? i.toString();
                  return _FieldSchemaCard(
                    key: ValueKey(fieldKey),
                    field: field,
                    index: i,
                    canManage: widget.canManage,
                    onSearchableChanged: (v) => setState(() {
                      _fields[i] = {..._fields[i], 'searchable': v};
                    }),
                    onLiveChanged: (v) => setState(() {
                      _fields[i] = {..._fields[i], 'is_live': v};
                    }),
                  );
                },
              ),
            ),
          ],
        ),
        if (widget.canManage)
          Positioned(
            bottom: 20,
            right: 20,
            child: _saving
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.ctTeal),
                  )
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.ctTeal,
                      foregroundColor: AppColors.ctNavy,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                    onPressed: _save,
                    child: Text(
                      'Guardar cambios',
                      style: AppFonts.geist(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
          ),
      ],
    );
  }
}

class _FieldSchemaCard extends StatelessWidget {
  const _FieldSchemaCard({
    super.key,
    required this.field,
    required this.index,
    required this.canManage,
    required this.onSearchableChanged,
    required this.onLiveChanged,
  });
  final Map<String, dynamic> field;
  final int index;
  final bool canManage;
  final ValueChanged<bool> onSearchableChanged;
  final ValueChanged<bool> onLiveChanged;

  @override
  Widget build(BuildContext context) {
    final key = field['key'] as String? ?? '';
    final label = field['label'] as String? ?? key;
    final type = field['type'] as String? ?? 'text';
    final searchable = field['searchable'] as bool? ?? false;
    final isLive = field['is_live'] as bool? ?? false;
    final isPrimary = field['is_primary'] as bool? ?? false;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.ctSurface,
        border: Border(
            bottom: BorderSide(color: AppColors.ctBorder, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (canManage)
            ReorderableDragStartListener(
              index: index,
              child: const MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Icon(Icons.drag_handle_rounded,
                    color: AppColors.ctText2, size: 18),
              ),
            )
          else
            const SizedBox(width: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: AppFonts.geist(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ctText),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isPrimary) ...[
                      const SizedBox(width: 5),
                      const Icon(Icons.star_rounded,
                          size: 12, color: AppColors.ctTeal),
                    ],
                  ],
                ),
                Text(
                  key,
                  style: AppFonts.geist(
                      fontSize: 11, color: AppColors.ctText3),
                ),
              ],
            ),
          ),
          _FieldTypeBadge(type: type),
          const SizedBox(width: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Buscable',
                  style: AppFonts.geist(
                      fontSize: 11, color: AppColors.ctText2)),
              Switch(
                value: searchable,
                activeThumbColor: AppColors.ctTeal,
                onChanged: canManage ? onSearchableChanged : null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          const SizedBox(width: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Live',
                  style: AppFonts.geist(
                      fontSize: 11, color: AppColors.ctText2)),
              Switch(
                value: isLive,
                activeThumbColor: AppColors.ctTeal,
                onChanged: canManage ? onLiveChanged : null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Tab 1 — FUENTE ────────────────────────────────────────────────────────────

class _SourceTab extends StatefulWidget {
  const _SourceTab({required this.catalog, required this.canManage});
  final Map<String, dynamic> catalog;
  final bool canManage;

  @override
  State<_SourceTab> createState() => _SourceTabState();
}

class _SourceTabState extends State<_SourceTab> {
  bool _syncing = false;

  bool _isSensitive(String k) {
    final lower = k.toLowerCase();
    return lower.contains('token') ||
        lower.contains('secret') ||
        lower.contains('password');
  }

  Future<void> _sync() async {
    final catalogId = widget.catalog['id'] as String? ?? '';
    if (catalogId.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _syncing = true);
    try {
      await CatalogsApi.syncCatalog(catalogId: catalogId);
      if (mounted) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Sincronización iniciada'),
          duration: Duration(milliseconds: 2000),
        ));
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
    final catalog = widget.catalog;
    final sourceType = catalog['source_type'] as String? ?? '';
    final rawConfig = catalog['source_config'];
    final sourceConfig = rawConfig is Map
        ? Map<String, dynamic>.from(rawConfig.cast<String, dynamic>())
        : <String, dynamic>{};
    final syncInterval = catalog['sync_interval_minutes'] as int?;
    final lastSynced = catalog['last_synced_at'] as String?;

    final (icon, sourceLabel) = switch (sourceType) {
      'manual'         => (Icons.edit_note_rounded, 'Manual'),
      'google_sheets'  => (Icons.table_chart_outlined, 'Google Sheets'),
      'onedrive_excel' => (Icons.grid_on_outlined, 'OneDrive Excel'),
      'webhook_push'   => (Icons.webhook_outlined, 'Webhook Push'),
      'api_pull'       => (Icons.cloud_download_outlined, 'API Pull'),
      _                => (Icons.storage_rounded,
          sourceType.isEmpty ? 'Sin fuente' : sourceType),
    };

    final showOAuth =
        sourceType == 'google_sheets' || sourceType == 'onedrive_excel';
    final connected = sourceConfig['connected'] as bool?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Tipo de fuente ──────────────────────────────────────────
          _SectionCard(
            title: 'Fuente de datos',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20, color: AppColors.ctText2),
                    const SizedBox(width: 8),
                    Text(
                      sourceLabel,
                      style: AppFonts.onest(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ctText),
                    ),
                    if (showOAuth) ...[
                      const SizedBox(width: 10),
                      _OAuthBadge(connected: connected),
                    ],
                  ],
                ),
                if (syncInterval != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Se sincroniza cada $syncInterval min',
                    style: AppFonts.geist(
                        fontSize: 12, color: AppColors.ctText2),
                  ),
                ],
                if (lastSynced != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Último sync: ${_fmtSync(lastSynced)}',
                    style: AppFonts.geist(
                        fontSize: 12, color: AppColors.ctText2),
                  ),
                ],
              ],
            ),
          ),
          if (sourceConfig.isNotEmpty) ...[
            const SizedBox(height: 16),
            // ── Configuración key/value ─────────────────────────────
            _SectionCard(
              title: 'Configuración',
              child: Column(
                children: sourceConfig.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 180,
                        child: Text(
                          e.key,
                          style: AppFonts.geist(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ctText2),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _isSensitive(e.key)
                              ? '••••••'
                              : e.value.toString(),
                          style: AppFonts.geist(
                              fontSize: 12, color: AppColors.ctText),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )).toList(),
              ),
            ),
          ],
          if (widget.canManage) ...[
            const SizedBox(height: 24),
            _syncing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.ctTeal),
                  )
                : ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.ctTeal,
                      foregroundColor: AppColors.ctNavy,
                    ),
                    onPressed: _sync,
                    icon: const Icon(Icons.sync_rounded, size: 16),
                    label: Text('Sincronizar ahora',
                        style: AppFonts.geist(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
          ],
        ],
      ),
    );
  }
}

// ── Tab 2 — ITEMS ─────────────────────────────────────────────────────────────

class _ItemsTab extends ConsumerStatefulWidget {
  const _ItemsTab({required this.catalog});
  final Map<String, dynamic> catalog;

  @override
  ConsumerState<_ItemsTab> createState() => _ItemsTabState();
}

class _ItemsTabState extends ConsumerState<_ItemsTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  Timer? _debounce;

  List<Map<String, dynamic>> get _fields {
    final raw = widget.catalog['fields_schema'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  String get _catalogId => widget.catalog['id'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadItems());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadItems() async {
    if (!mounted) return;
    final tenantId = ref.read(activeTenantIdProvider);
    setState(() => _loading = true);
    try {
      final items = await CatalogsApi.listItems(
        tenantId: tenantId,
        catalogId: _catalogId,
      );
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _search(String q) async {
    if (!mounted) return;
    if (q.isEmpty) { _loadItems(); return; }
    if (q.length < 2) return;
    final tenantId = ref.read(activeTenantIdProvider);
    setState(() => _loading = true);
    try {
      final items = await CatalogsApi.searchItems(
        tenantId: tenantId,
        catalogId: _catalogId,
        q: q,
      );
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            onChanged: _onSearchChanged,
            style: AppFonts.geist(fontSize: 13, color: AppColors.ctText),
            decoration: InputDecoration(
              hintText: 'Buscar en items...',
              hintStyle:
                  AppFonts.geist(fontSize: 13, color: AppColors.ctText3),
              prefixIcon: const Icon(Icons.search_rounded,
                  size: 17, color: AppColors.ctText3),
              filled: true,
              fillColor: AppColors.ctSurface,
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
                borderSide: const BorderSide(
                    color: AppColors.ctTeal, width: 1.5),
              ),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.ctTeal))
              : _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.inbox_outlined,
                              size: 48, color: AppColors.ctText2),
                          const SizedBox(height: 10),
                          Text(
                            'Sin items',
                            style: AppFonts.onest(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ctText2),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'No hay items que coincidan con la búsqueda.',
                            style: AppFonts.geist(
                                fontSize: 12, color: AppColors.ctText3),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: _ItemsTable(
                          items: _items,
                          fields: _fields,
                        ),
                      ),
                    ),
        ),
      ],
    );
  }
}

class _ItemsTable extends StatelessWidget {
  const _ItemsTable({required this.items, required this.fields});
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> fields;

  static const double _cellWidth = 160;
  static const _headerStyle = TextStyle(
    fontFamily: 'Geist',
    fontSize: 10,
    fontWeight: FontWeight.w600,
    color: AppColors.ctText2,
    letterSpacing: 0.4,
  );

  @override
  Widget build(BuildContext context) {
    final columns = fields.isNotEmpty
        ? fields
        : items.isNotEmpty
            ? items.first.keys
                .map((k) => <String, dynamic>{'key': k, 'label': k})
                .toList()
            : <Map<String, dynamic>>[];

    if (columns.isEmpty) {
      return Text('Sin columnas',
          style: AppFonts.geist(fontSize: 12, color: AppColors.ctText2));
    }

    final tableWidth = columns.length * _cellWidth;

    return Container(
      width: tableWidth,
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: tableWidth,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.ctSurface2,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(9),
                topRight: Radius.circular(9),
              ),
            ),
            child: Row(
              children: columns
                  .map((col) => SizedBox(
                        width: _cellWidth,
                        child: Text(
                          (col['label'] as String? ??
                                  col['key'] as String? ??
                                  '')
                              .toUpperCase(),
                          style: _headerStyle,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
            ),
          ),
          ...items.asMap().entries.map((entry) {
            final isLast = entry.key == items.length - 1;
            return Column(
              children: [
                _ItemRow(item: entry.value, columns: columns),
                if (!isLast)
                  const Divider(height: 1, color: AppColors.ctBorder),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _ItemRow extends StatefulWidget {
  const _ItemRow({required this.item, required this.columns});
  final Map<String, dynamic> item;
  final List<Map<String, dynamic>> columns;

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        color: _hovered ? AppColors.ctBg : AppColors.ctSurface,
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: widget.columns.map((col) {
            final key = col['key'] as String? ?? '';
            final isPrimary = col['is_primary'] as bool? ?? false;
            final value = widget.item[key];
            final text = value == null ? '—' : value.toString();
            return SizedBox(
              width: _ItemsTable._cellWidth,
              child: Text(
                text,
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 12,
                  fontWeight:
                      isPrimary ? FontWeight.w600 : FontWeight.w400,
                  color: AppColors.ctText,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Tab 3 — SYNC ──────────────────────────────────────────────────────────────

class _SyncTab extends StatelessWidget {
  const _SyncTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.history_rounded, size: 48, color: AppColors.ctText2),
          const SizedBox(height: 12),
          Text(
            'Historial de sincronizaciones',
            style: AppFonts.onest(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.ctText2),
          ),
          const SizedBox(height: 6),
          Text(
            'Disponible próximamente — endpoint en desarrollo.',
            style: AppFonts.geist(fontSize: 12, color: AppColors.ctText3),
          ),
        ],
      ),
    );
  }
}

// ── Tab 4 — USO ───────────────────────────────────────────────────────────────

class _UsoTab extends StatelessWidget {
  const _UsoTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.hub_outlined, size: 48, color: AppColors.ctText2),
          const SizedBox(height: 12),
          Text(
            'Uso en flujos',
            style: AppFonts.onest(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.ctText2),
          ),
          const SizedBox(height: 6),
          Text(
            'Disponible en Fase 1.B — asset_ref',
            style: AppFonts.geist(fontSize: 12, color: AppColors.ctText3),
          ),
        ],
      ),
    );
  }
}

// ── Widgets auxiliares ────────────────────────────────────────────────────────

class _FieldTypeBadge extends StatelessWidget {
  const _FieldTypeBadge({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (type) {
      'text'    => (AppColors.ctInfoBg, AppColors.ctInfoText, 'texto'),
      'number'  => (AppColors.ctWarnBg, AppColors.ctWarnText, 'número'),
      'date'    => (const Color(0xFFEDE9FE), const Color(0xFF5B21B6), 'fecha'),
      'boolean' => (AppColors.ctOkBg, AppColors.ctOkText, 'booleano'),
      'select'  => (const Color(0xFFFEF3C7), const Color(0xFF92400E), 'selección'),
      _         => (AppColors.ctSurface2, AppColors.ctText2,
          type.isEmpty ? 'tipo' : type),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: AppFonts.geist(
              fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class _OAuthBadge extends StatelessWidget {
  const _OAuthBadge({required this.connected});
  final bool? connected;

  @override
  Widget build(BuildContext context) {
    if (connected == null) {
      return Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
            color: AppColors.ctSurface2,
            borderRadius: BorderRadius.circular(10)),
        child: Text('No verificado',
            style: AppFonts.geist(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.ctText2)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: connected! ? AppColors.ctOkBg : AppColors.ctRedBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        connected! ? 'Conectado' : 'Desconectado',
        style: AppFonts.geist(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: connected! ? AppColors.ctOkText : AppColors.ctRedText,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.ctText2,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
