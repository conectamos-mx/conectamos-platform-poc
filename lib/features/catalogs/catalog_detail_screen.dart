import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/catalogs_api.dart';
import '../../core/api/connections_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_action_button.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_confirm_dialog.dart';
import '../../shared/widgets/app_detail_header.dart';
import '../../core/utils/relative_time.dart';
import '../../core/utils/sync_poller.dart';
import '../../shared/widgets/catalog_item_form.dart';

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

  int _syncVersion = 0;
  bool _syncing = false;
  bool _saving = false;
  bool _deleting = false;
  bool _hasChanges = false;
  Map<String, dynamic> _pendingPatch = {};
  bool _canManage = false;

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
    setState(() {
      _loading = true;
      _error = null;
      _pendingPatch = {};
      _hasChanges = false;
    });
    try {
      final tenantId = ref.read(activeTenantIdProvider);
      final dio = ref.read(apiClientProvider).dio;
      final data = await CatalogsApi.getCatalogBySlug(
        dio: dio,
        tenantId: tenantId,
        slug: widget.slug,
      );
      if (mounted) {
        setState(() {
          _catalog = data;
          _canManage = hasPermission(ref, 'catalogs', 'manage');
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _onPatchChanged(Map<String, dynamic> patch) {
    setState(() {
      _pendingPatch = {..._pendingPatch, ...patch};
      _hasChanges = true;
    });
  }

  Future<void> _doSave() async {
    if (!_hasChanges || _saving) return;
    final catalogId = _catalog?['id'] as String? ?? '';
    if (catalogId.isEmpty) return;
    final tenantId = ref.read(activeTenantIdProvider);
    final dio = ref.read(apiClientProvider).dio;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await CatalogsApi.updateCatalog(
        dio: dio,
        tenantId: tenantId,
        catalogId: catalogId,
        body: _pendingPatch,
      );
      await _load();
      if (mounted) {
        setState(() => _saving = false);
        messenger.showSnackBar(const SnackBar(
          content: Text('Cambios guardados'),
          duration: Duration(milliseconds: 2000),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        messenger.showSnackBar(SnackBar(
          content: Text('Error al guardar: $e'),
          backgroundColor: AppColors.ctDanger,
          duration: const Duration(milliseconds: 3000),
        ));
      }
    }
  }

  Future<void> _doDelete() async {
    final catalog = _catalog;
    if (catalog == null) return;
    final label = catalog['label'] as String? ?? catalog['slug'] as String? ?? 'este catálogo';
    final catalogId = catalog['id'] as String? ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.ctSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Eliminar catálogo',
            style: AppFonts.onest(fontSize: 16, fontWeight: FontWeight.w700,
                color: AppColors.ctText)),
        content: Text(
          '¿Estás seguro de que quieres eliminar "$label"? '
          'Esta acción no se puede deshacer.',
          style: AppFonts.geist(fontSize: 13, color: AppColors.ctText2),
        ),
        actions: [
          AppButton(
            key: const Key('delete_catalog_cancel'),
            label: 'Cancelar',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          AppButton(
            key: const Key('delete_catalog_confirm'),
            label: 'Eliminar',
            variant: AppButtonVariant.danger,
            size: AppButtonSize.sm,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await CatalogsApi.deleteCatalog(dio: ref.read(apiClientProvider).dio, catalogId: catalogId);
      if (mounted) context.go('/catalogs', extra: {'refresh': true});
    } catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al eliminar: $e'),
          backgroundColor: AppColors.ctDanger,
        ));
      }
    }
  }

  Future<void> _doSync() async {
    if (_syncing) return;
    final catalogId = _catalog?['id'] as String? ?? '';
    if (catalogId.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _syncing = true);
    try {
      await CatalogsApi.syncCatalog(dio: ref.read(apiClientProvider).dio, catalogId: catalogId);
      if (mounted) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Sincronización iniciada'),
          duration: Duration(milliseconds: 2000),
        ));
        setState(() => _syncVersion++);
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
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.ctTeal),
      );
    }

    if (_error != null || _catalog == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: AppColors.ctDanger),
            const SizedBox(height: 12),
            Text(
              _error ?? 'No se encontró el catálogo',
              style: AppFonts.geist(fontSize: 14, color: AppColors.ctText2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            AppButton(
              label: 'Reintentar',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              onPressed: _load,
            ),
          ],
        ),
      );
    }

    final catalog = _catalog!;
    final sourceType = catalog['source_type'] as String? ?? '';
    final slug = catalog['slug'] as String? ?? '';
    final label = catalog['label'] as String? ?? slug;
    final isSyncable =
        sourceType == 'google_sheets' || sourceType == 'onedrive_excel';

    final Widget avatar;
    if (sourceType == 'google_sheets') {
      avatar = Image.asset('assets/logos/drive.png', width: 28, height: 28);
    } else if (sourceType == 'onedrive_excel') {
      avatar = SvgPicture.asset('assets/logos/onedrive.svg',
          width: 28, height: 28);
    } else {
      avatar = const Icon(Icons.table_chart_outlined,
          size: 24, color: AppColors.ctText2);
    }

    return Column(
      children: [
          AppDetailHeader(
            title: label,
            subtitle: slug,
            backLabel: 'Catálogos',
            onBack: () => context.go('/catalogs'),
            avatar: avatar,
            avatarRounded: false,
            actions: [
              if (_canManage)
                AppActionButton(
                  key: const Key('detail_delete_btn'),
                  variant: AppActionVariant.delete,
                  onPressed: _doDelete,
                  isLoading: _deleting,
                  isDisabled: _deleting,
                ),
              if (_canManage && isSyncable) ...[
                const SizedBox(width: 4),
                AppButton(
                  key: const Key('detail_sync_btn'),
                  label: 'Sincronizar ahora',
                  variant: AppButtonVariant.outline,
                  size: AppButtonSize.sm,
                  isLoading: _syncing,
                  prefixIcon: const Icon(Icons.sync_rounded,
                      size: 14, color: AppColors.ctInk700),
                  onPressed: _doSync,
                ),
                const SizedBox(width: 8),
              ],
              if (_canManage)
                AppButton(
                  key: const Key('detail_save_btn'),
                  label: 'Guardar',
                  variant: AppButtonVariant.teal,
                  size: AppButtonSize.sm,
                  isLoading: _saving,
                  isDisabled: !_hasChanges,
                  onPressed: _doSave,
                ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(44),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.ctSurface,
                  border:
                      Border(bottom: BorderSide(color: AppColors.ctBorder)),
                ),
                child: TabBar(
                  controller: _tabCtrl,
                  isScrollable: true,
                  labelColor: AppColors.ctTeal,
                  unselectedLabelColor: AppColors.ctText2,
                  indicatorColor: AppColors.ctTeal,
                  indicatorWeight: 2,
                  dividerColor: Colors.transparent,
                  labelStyle: AppTextStyles.formLabel,
                  unselectedLabelStyle: AppTextStyles.navItem,
                  tabs: const [
                    Tab(text: 'Configuración'),
                    Tab(text: 'Fuente'),
                    Tab(text: 'Items'),
                    Tab(text: 'Sincronización'),
                    Tab(text: 'Uso'),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _ConfigTab(
                  key: ValueKey(catalog['id']),
                  catalog: catalog,
                  canManage: _canManage,
                  onChanged: _onPatchChanged,
                ),
                _SourceTab(
                  catalog: catalog,
                  canManage: _canManage,
                  onChanged: _onPatchChanged,
                  onReload: _load,
                ),
                _ItemsTab(
                  key: ValueKey(catalog['id']),
                  catalog: catalog,
                  canManage: _canManage,
                ),
                _SyncTab(
                  key: ValueKey('${catalog['id']}_$_syncVersion'),
                  catalog: catalog,
                  polling: _syncVersion > 0,
                ),
                _UsoTab(catalog: catalog),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Tab 0 — CONFIGURACIÓN ─────────────────────────────────────────────────────

class _ConfigTab extends ConsumerStatefulWidget {
  const _ConfigTab({
    super.key,
    required this.catalog,
    required this.canManage,
    required this.onChanged,
  });
  final Map<String, dynamic> catalog;
  final bool canManage;
  final void Function(Map<String, dynamic>) onChanged;

  @override
  ConsumerState<_ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends ConsumerState<_ConfigTab> {
  late TextEditingController _labelCtrl;
  late TextEditingController _descriptionCtrl;
  late TextEditingController _displayLabelCtrl;
  late TextEditingController _embedThresholdCtrl;
  String? _displayField;
  List<Map<String, dynamic>> _fields = [];

  bool get _isAutoSource {
    final st = widget.catalog['source_type'] as String? ?? '';
    return st == 'google_sheets' || st == 'onedrive_excel';
  }

  @override
  void initState() {
    super.initState();
    _initFromCatalog(widget.catalog);
  }

  void _initFromCatalog(Map<String, dynamic> catalog) {
    _labelCtrl =
        TextEditingController(text: catalog['label'] as String? ?? '');
    _descriptionCtrl = TextEditingController(
        text: catalog['description'] as String? ?? '');
    _displayLabelCtrl = TextEditingController(
        text: catalog['display_label'] as String? ?? '');
    final thresh = catalog['embed_threshold'];
    _embedThresholdCtrl = TextEditingController(
        text: thresh != null ? thresh.toString() : '');

    _displayField = catalog['display_field'] as String?;

    final raw = catalog['fields_schema'];
    _fields = raw is List
        ? List<Map<String, dynamic>>.from(
            raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)))
        : [];
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _descriptionCtrl.dispose();
    _displayLabelCtrl.dispose();
    _embedThresholdCtrl.dispose();
    super.dispose();
  }

  void _onIdentificationChanged() {
    final patch = <String, dynamic>{
      'label': _labelCtrl.text.trim(),
    };
    if (_descriptionCtrl.text.isNotEmpty) {
      patch['description'] = _descriptionCtrl.text.trim();
    }
    if (_displayLabelCtrl.text.isNotEmpty) {
      patch['display_label'] = _displayLabelCtrl.text.trim();
    }
    final thresh = double.tryParse(_embedThresholdCtrl.text.trim());
    if (thresh != null) patch['embed_threshold'] = thresh;
    if (_displayField != null) patch['display_field'] = _displayField;
    widget.onChanged(patch);
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _fields.removeAt(oldIndex);
      _fields.insert(newIndex, item);
    });
    widget.onChanged({'fields_schema': _fields});
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // ── Identification section ───────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          sliver: SliverToBoxAdapter(
            child: _SectionCard(
              title: 'Identificación',
              child: Column(
                children: [
                  _IdField(
                    label: 'Nombre',
                    ctrl: _labelCtrl,
                    enabled: widget.canManage,
                    onChanged: (_) => _onIdentificationChanged(),
                  ),
                  const SizedBox(height: 12),
                  _IdField(
                    label: 'Descripción',
                    ctrl: _descriptionCtrl,
                    enabled: widget.canManage,
                    onChanged: (_) => _onIdentificationChanged(),
                  ),
                  const SizedBox(height: 12),
                  _IdField(
                    label: 'Etiqueta visible al operador',
                    ctrl: _displayLabelCtrl,
                    enabled: widget.canManage,
                    onChanged: (_) => _onIdentificationChanged(),
                  ),
                  const SizedBox(height: 12),
                  _ReadOnlyField(
                    label: 'Slug',
                    value: widget.catalog['slug'] as String? ?? '',
                  ),
                  const SizedBox(height: 12),
                  _IdField(
                    label: 'Umbral de embed',
                    ctrl: _embedThresholdCtrl,
                    enabled: widget.canManage,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    onChanged: (_) => _onIdentificationChanged(),
                  ),
                  if (_fields.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Tooltip(
                      message: 'Este campo se muestra como nombre del item '
                          'al seleccionarlo en un flow',
                      child: _KeyDropdown(
                        label: 'Campo de display',
                        value: _displayField,
                        keys: _fields
                            .map((f) => f['key'] as String? ?? '')
                            .where((k) => k.isNotEmpty)
                            .toList(),
                        enabled: widget.canManage,
                        onChanged: (v) {
                          setState(() => _displayField = v);
                          _onIdentificationChanged();
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        // ── Campos header ────────────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Text(
                  'CAMPOS',
                  style: AppFonts.geist(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ctText2,
                  ).copyWith(letterSpacing: 0.4),
                ),
                const Spacer(),
                Text(
                  '${_fields.length} campo${_fields.length == 1 ? '' : 's'}',
                  style: AppFonts.geist(
                      fontSize: 11, color: AppColors.ctText3),
                ),
              ],
            ),
          ),
        ),
        // ── Info banner for auto sources ─────────────────────────────
        if (_isAutoSource)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            sliver: SliverToBoxAdapter(
              child: _InfoBanner(
                icon: Icons.info_outline_rounded,
                message:
                    'Los campos se derivan automáticamente de la fuente. '
                    'Puedes cambiar "Buscable" y "Live", pero el esquema '
                    'se actualiza en el próximo sync.',
              ),
            ),
          ),
        // ── Fields list ──────────────────────────────────────────────
        if (_fields.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 16),
                    const Icon(Icons.schema_outlined,
                        size: 40, color: AppColors.ctText2),
                    const SizedBox(height: 8),
                    Text('Sin esquema de campos',
                        style: AppFonts.geist(
                            fontSize: 13, color: AppColors.ctText2)),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
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
                  onSearchableChanged: (v) {
                    setState(() {
                      _fields[i] = {..._fields[i], 'searchable': v};
                    });
                    widget.onChanged({'fields_schema': _fields});
                  },
                  onLiveChanged: (v) {
                    setState(() {
                      _fields[i] = {..._fields[i], 'is_live': v};
                    });
                    widget.onChanged({'fields_schema': _fields});
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}

class _IdField extends StatelessWidget {
  const _IdField({
    required this.label,
    required this.ctrl,
    required this.onChanged,
    this.enabled = true,
    this.keyboardType,
  });
  final String label;
  final TextEditingController ctrl;
  final bool enabled;
  final TextInputType? keyboardType;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      enabled: enabled,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: AppFonts.geist(fontSize: 13, color: AppColors.ctText),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            AppFonts.geist(fontSize: 12, color: AppColors.ctText2),
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return TextField(
      readOnly: true,
      controller: TextEditingController(text: value),
      style: AppFonts.geist(fontSize: 13, color: AppColors.ctText2),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            AppFonts.geist(fontSize: 12, color: AppColors.ctText3),
        filled: true,
        fillColor: AppColors.ctSurface2,
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.ctInfoBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.ctInfoText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: AppFonts.geist(
                    fontSize: 12, color: AppColors.ctInfoText)),
          ),
        ],
      ),
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

class _SourceTab extends ConsumerStatefulWidget {
  const _SourceTab({
    required this.catalog,
    required this.canManage,
    required this.onChanged,
    this.onReload,
  });
  final Map<String, dynamic> catalog;
  final bool canManage;
  final void Function(Map<String, dynamic>) onChanged;
  final VoidCallback? onReload;

  @override
  ConsumerState<_SourceTab> createState() => _SourceTabState();
}

class _SourceTabState extends ConsumerState<_SourceTab> {
  bool _loadingOAuth = false;
  Map<String, dynamic>? _oauthStatus;
  bool _reconnecting = false;
  StreamSubscription<html.MessageEvent>? _oauthSub;
  Timer? _oauthTimer;

  // Google Sheets editable fields
  late TextEditingController _sheetUrlCtrl;
  List<String> _availableSheets = [];
  String? _selectedSheet;
  bool _loadingPreview = false;
  Timer? _sheetUrlDebounce;

  String get _sourceType => widget.catalog['source_type'] as String? ?? '';
  bool get _isOAuth =>
      _sourceType == 'google_sheets' || _sourceType == 'onedrive_excel';
  bool get _isGoogle => _sourceType == 'google_sheets';

  bool _isSensitive(String k) {
    final lower = k.toLowerCase();
    return lower.contains('token') ||
        lower.contains('secret') ||
        lower.contains('password');
  }

  @override
  void initState() {
    super.initState();
    _sheetUrlCtrl = TextEditingController(
      text: widget.catalog['sheet_url'] as String? ?? '',
    );
    _selectedSheet = widget.catalog['sheet_name'] as String?;
    _sheetUrlCtrl.addListener(_onSheetUrlChanged);
    if (_isOAuth) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadOAuthStatus());
    }
  }

  @override
  void dispose() {
    _sheetUrlCtrl.dispose();
    _sheetUrlDebounce?.cancel();
    _oauthSub?.cancel();
    _oauthTimer?.cancel();
    super.dispose();
  }

  void _onSheetUrlChanged() {
    _sheetUrlDebounce?.cancel();
    final url = _sheetUrlCtrl.text.trim();
    if (url.contains('spreadsheets/d/')) {
      _sheetUrlDebounce = Timer(
        const Duration(milliseconds: 800),
        () { if (mounted) _loadSheetPreview(); },
      );
    }
  }

  Future<void> _loadSheetPreview({String? sheetName}) async {
    if (_sheetUrlCtrl.text.trim().isEmpty) return;
    setState(() => _loadingPreview = true);
    try {
      final tenantId = ref.read(activeTenantIdProvider);
      final result = await CatalogsApi.sheetsPreview(
        dio: ref.read(apiClientProvider).dio,
        tenantId: tenantId,
        sheetUrl: _sheetUrlCtrl.text.trim(),
        sheetName: sheetName ?? _selectedSheet,
      );
      setState(() {
        _availableSheets = List<String>.from(result['sheets'] as List? ?? []);
        _selectedSheet = result['selected_sheet'] as String?;
        _loadingPreview = false;
      });
      _emitPatch();
    } catch (_) {
      setState(() => _loadingPreview = false);
    }
  }

  void _emitPatch() {
    widget.onChanged({
      'sheet_url': _sheetUrlCtrl.text.trim(),
      if (_selectedSheet != null) 'sheet_name': _selectedSheet,
    });
  }

  Future<void> _loadOAuthStatus() async {
    if (!mounted) return;
    final tenantId = ref.read(activeTenantIdProvider);
    setState(() => _loadingOAuth = true);
    try {
      Map<String, dynamic> status;
      if (_isGoogle) {
        status = await ConnectionsApi.getGoogleStatus();
      } else {
        final raw =
            await ConnectionsApi.getMicrosoftStatus(tenantId: tenantId);
        final connections = raw['connections'] as List? ?? [];
        final ms = connections.firstWhere(
          (c) => c['provider'] == 'microsoft' && c['status'] == 'active',
          orElse: () => <String, dynamic>{},
        );
        status = (ms as Map).isEmpty
            ? {'connected': false}
            : {
                'connected': true,
                'email': ms['email'],
                'connected_at': ms['connected_at'],
                'token_expiry': ms['token_expiry'],
              };
      }
      if (mounted) {
        setState(() {
          _oauthStatus = status;
          _loadingOAuth = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _oauthStatus = {'connected': false};
          _loadingOAuth = false;
        });
      }
    }
  }

  Future<void> _reconnect() async {
    if (_reconnecting) return;
    final tenantId = ref.read(activeTenantIdProvider);
    setState(() => _reconnecting = true);
    try {
      final String authUrl;
      final String successMsg;
      if (_isGoogle) {
        authUrl = await ConnectionsApi.getGoogleAuthUrl();
        successMsg = 'google=success';
      } else {
        authUrl =
            await ConnectionsApi.getMicrosoftAuthUrl(tenantId: tenantId);
        successMsg = 'microsoft=success';
      }
      html.window.open(
          authUrl, '_blank', 'width=520,height=620,toolbar=0,menubar=0,location=0');
      _oauthSub?.cancel();
      _oauthTimer?.cancel();
      _oauthSub = html.window.onMessage.listen((event) {
        final data = event.data?.toString() ?? '';
        final errMsg = _isGoogle ? 'google=error' : 'microsoft=error';
        if (data != successMsg && data != errMsg) return;
        _oauthSub?.cancel();
        _oauthTimer?.cancel();
        if (mounted) {
          setState(() => _reconnecting = false);
          _loadOAuthStatus();
          widget.onReload?.call();
          if (data == successMsg) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Conexión renovada correctamente'),
              duration: Duration(seconds: 2),
            ));
          }
        }
      });
      _oauthTimer = Timer(const Duration(minutes: 5), () {
        _oauthSub?.cancel();
        if (mounted) setState(() => _reconnecting = false);
      });
    } catch (e) {
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  _OAuthState get _oauthState {
    if (!_isOAuth) return _OAuthState.notApplicable;
    if (_loadingOAuth) return _OAuthState.loading;

    // Prioritize integration_status from backend when available
    final integrationStatus =
        widget.catalog['integration_status'] as String?;
    if (integrationStatus != null) {
      return switch (integrationStatus) {
        'active' => _OAuthState.connected,
        'error' || 'reauth_required' => _OAuthState.reauthRequired,
        'revoked' => _OAuthState.revoked,
        'paused' => _OAuthState.paused,
        _ => _OAuthState.disconnected,
      };
    }

    // Backward compat: infer from OAuth status when integration_status absent
    final status = _oauthStatus;
    if (status == null) return _OAuthState.unknown;
    if (status['connected'] != true) return _OAuthState.disconnected;
    final expiry = status['token_expiry'] as String?;
    if (expiry != null) {
      try {
        final exp = DateTime.parse(expiry);
        if (exp.isBefore(DateTime.now())) return _OAuthState.expired;
      } catch (_) {}
    }
    return _OAuthState.connected;
  }

  @override
  Widget build(BuildContext context) {
    final sourceType = widget.catalog['source_type'] as String? ?? '';
    final rawConfig = widget.catalog['source_config'];
    final sourceConfig = rawConfig is Map
        ? Map<String, dynamic>.from(rawConfig.cast<String, dynamic>())
        : <String, dynamic>{};
    final syncInterval = widget.catalog['sync_interval_minutes'] as int?;
    final lastSynced = widget.catalog['last_synced_at'] as String?;
    final oauthSt = _oauthState;

    final (icon, sourceLabel) = switch (sourceType) {
      'manual'         => (Icons.edit_note_rounded, 'Manual'),
      'google_sheets'  => (Icons.table_chart_outlined, 'Google Sheets'),
      'onedrive_excel' => (Icons.grid_on_outlined, 'OneDrive Excel'),
      'webhook_push'   => (Icons.webhook_outlined, 'Webhook Push'),
      'api_pull'       => (Icons.cloud_download_outlined, 'API Pull'),
      _                => (Icons.storage_rounded,
          sourceType.isEmpty ? 'Sin fuente' : sourceType),
    };

    final sheetUrl = sourceConfig['sheet_url'] as String? ?? '';
    final fileName = sourceConfig['file_name'] as String? ?? '';
    final configIncomplete =
        (sourceType == 'google_sheets' && sheetUrl.isEmpty) ||
            (sourceType == 'onedrive_excel' && fileName.isEmpty);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner config incompleta
          if (configIncomplete) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.ctWarnBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.ctWarn.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 16, color: AppColors.ctWarn),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'La configuración de la fuente está incompleta. Este catálogo no puede sincronizarse.',
                      style: AppFonts.geist(
                          fontSize: 12, color: AppColors.ctWarnText),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Banner OAuth problema
          if (_isOAuth &&
              oauthSt != _OAuthState.connected &&
              oauthSt != _OAuthState.loading &&
              oauthSt != _OAuthState.notApplicable) ...[
            () {
              final isWarn = oauthSt == _OAuthState.reauthRequired ||
                  oauthSt == _OAuthState.expired;
              final bannerBg =
                  isWarn ? AppColors.ctWarnBg : AppColors.ctRedBg;
              final bannerBorder = isWarn
                  ? AppColors.ctWarn.withValues(alpha: 0.4)
                  : AppColors.ctDanger.withValues(alpha: 0.3);
              final bannerFg =
                  isWarn ? AppColors.ctWarn : AppColors.ctDanger;
              final bannerIcon = isWarn
                  ? Icons.warning_amber_rounded
                  : Icons.link_off_rounded;
              final bannerText = switch (oauthSt) {
                _OAuthState.reauthRequired =>
                  'La conexión con $sourceLabel necesita reconexión. Los sincronizados están fallando hasta que se reconecte.',
                _OAuthState.expired =>
                  'El token de acceso ha expirado. Reconecta para continuar sincronizando.',
                _OAuthState.revoked =>
                  'La conexión con $sourceLabel fue revocada. Los sincronizados están fallando hasta que se reconecte.',
                _OAuthState.disconnected =>
                  'La cuenta no está conectada. Conecta para habilitar la sincronización.',
                _OAuthState.paused =>
                  'La integración está pausada. Los sincronizados no se ejecutarán hasta que se reactive.',
                _ =>
                  'La conexión con $sourceLabel no está activa.',
              };
              final showReconnect = oauthSt != _OAuthState.paused &&
                  oauthSt != _OAuthState.unknown;
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: bannerBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: bannerBorder),
                ),
                child: Row(
                  children: [
                    Icon(bannerIcon, size: 16, color: bannerFg),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        bannerText,
                        style: AppFonts.geist(
                            fontSize: 12, color: bannerFg),
                      ),
                    ),
                    if (showReconnect) ...[
                      const SizedBox(width: 8),
                      AppButton(
                        key: const Key('source_reconnect_btn'),
                        label: 'Reconectar ahora',
                        variant: isWarn
                            ? AppButtonVariant.outline
                            : AppButtonVariant.danger,
                        size: AppButtonSize.sm,
                        isLoading: _reconnecting,
                        onPressed: _reconnect,
                      ),
                    ],
                  ],
                ),
              );
            }(),
          ],

          // Card fuente principal
          _SectionCard(
            title: 'Fuente de datos',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20, color: AppColors.ctText2),
                    const SizedBox(width: 8),
                    Text(sourceLabel,
                        style: AppFonts.onest(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ctText)),
                    if (_isOAuth) ...[
                      const SizedBox(width: 10),
                      _OAuthStateBadge(
                          state: oauthSt, loading: _loadingOAuth),
                    ],
                    const Spacer(),
                    if (_isOAuth && oauthSt == _OAuthState.connected) ...[
                      AppButton(
                        label: 'Renovar',
                        variant: AppButtonVariant.ghost,
                        size: AppButtonSize.sm,
                        isDisabled: _reconnecting,
                        prefixIcon: const Icon(Icons.refresh_rounded, size: 14, color: AppColors.ctTeal),
                        onPressed: _reconnect,
                      ),
                    ] else if (_isOAuth &&
                        oauthSt != _OAuthState.connected &&
                        oauthSt != _OAuthState.loading &&
                        oauthSt != _OAuthState.paused &&
                        oauthSt != _OAuthState.notApplicable) ...[
                      AppButton(
                        label: 'Reconectar',
                        variant: AppButtonVariant.danger,
                        size: AppButtonSize.sm,
                        isLoading: _reconnecting,
                        onPressed: _reconnect,
                      ),
                    ],
                  ],
                ),
                if (_oauthStatus?['email'] != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.account_circle_outlined,
                          size: 14, color: AppColors.ctText3),
                      const SizedBox(width: 6),
                      Text(_oauthStatus!['email'] as String,
                          style: AppFonts.geist(
                              fontSize: 12, color: AppColors.ctText2)),
                    ],
                  ),
                ],
                if (syncInterval != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.schedule_rounded,
                          size: 14, color: AppColors.ctText3),
                      const SizedBox(width: 6),
                      Text('Se sincroniza cada $syncInterval min',
                          style: AppFonts.geist(
                              fontSize: 12, color: AppColors.ctText2)),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      lastSynced != null
                          ? Icons.check_circle_outline_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 14,
                      color: lastSynced != null
                          ? AppColors.ctOkText
                          : AppColors.ctText3,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      lastSynced != null
                          ? 'Último sync: ${fmtRelative(lastSynced, showSeconds: true)}'
                          : 'Nunca sincronizado',
                      style: AppFonts.geist(
                          fontSize: 12,
                          color: lastSynced != null
                              ? AppColors.ctText2
                              : AppColors.ctText3),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Card archivo / sheet
          if (sourceConfig.isNotEmpty && sourceType != 'manual') ...[
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Archivo de datos',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (sourceType == 'google_sheets') ...[
                    if (widget.canManage) ...[
                      TextField(
                        key: const Key('source_sheet_url'),
                        controller: _sheetUrlCtrl,
                        style: AppFonts.geist(
                            fontSize: 13, color: AppColors.ctText),
                        decoration: InputDecoration(
                          labelText: 'URL de la hoja',
                          labelStyle: AppFonts.geist(
                              fontSize: 12, color: AppColors.ctText2),
                          hintText:
                              'https://docs.google.com/spreadsheets/d/...',
                          hintStyle: AppFonts.geist(
                              fontSize: 12, color: AppColors.ctText3),
                          suffixIcon: _loadingPreview
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.ctTeal),
                                  ),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_availableSheets.isNotEmpty)
                        DropdownButtonFormField<String>(
                          key: const Key('source_sheet_tab'),
                          initialValue: _selectedSheet,
                          decoration: InputDecoration(
                            labelText: 'Pestaña',
                            labelStyle: AppFonts.geist(
                                fontSize: 12, color: AppColors.ctText2),
                          ),
                          style: AppFonts.geist(
                              fontSize: 13, color: AppColors.ctText),
                          items: _availableSheets
                              .map((s) => DropdownMenuItem(
                                  value: s, child: Text(s)))
                              .toList(),
                          onChanged: (v) {
                            setState(() => _selectedSheet = v);
                            _emitPatch();
                          },
                        )
                      else if (_selectedSheet != null)
                        _ReadOnlyField(
                            label: 'Pestaña', value: _selectedSheet!),
                    ] else ...[
                      _ConfigRow(
                        label: 'Hoja de cálculo',
                        value: sheetUrl.isNotEmpty ? sheetUrl : '—',
                        isUrl: sheetUrl.isNotEmpty,
                      ),
                      if ((sourceConfig['sheet_name'] as String? ?? '')
                          .isNotEmpty)
                        _ConfigRow(
                          label: 'Pestaña',
                          value: sourceConfig['sheet_name'] as String,
                        ),
                    ],
                  ] else if (sourceType == 'onedrive_excel') ...[
                    _ConfigRow(
                      label: 'Archivo',
                      value: fileName.isNotEmpty ? fileName : '—',
                    ),
                    if ((sourceConfig['sheet_name'] as String? ?? '')
                        .isNotEmpty)
                      _ConfigRow(
                        label: 'Hoja',
                        value: sourceConfig['sheet_name'] as String,
                      ),
                  ] else ...[
                    ...sourceConfig.entries
                        .where((e) => !_isSensitive(e.key))
                        .map((e) =>
                            _ConfigRow(label: e.key, value: e.value.toString())),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Estado OAuth enum
enum _OAuthState { notApplicable, loading, unknown, connected, expired, disconnected, reauthRequired, revoked, paused }

// Badge de estado OAuth
class _OAuthStateBadge extends StatelessWidget {
  const _OAuthStateBadge({required this.state, required this.loading});
  final _OAuthState state;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.ctTeal));
    }
    final (bg, fg, label, icon) = switch (state) {
      _OAuthState.connected => (
          AppColors.ctOkBg,
          AppColors.ctOkText,
          'Conectado',
          Icons.check_circle_rounded
        ),
      _OAuthState.reauthRequired => (
          AppColors.ctWarnBg,
          AppColors.ctWarn,
          'Necesita reconexión',
          Icons.warning_rounded
        ),
      _OAuthState.expired => (
          AppColors.ctWarnBg,
          AppColors.ctWarn,
          'Token expirado',
          Icons.warning_rounded
        ),
      _OAuthState.revoked => (
          AppColors.ctRedBg,
          AppColors.ctRedText,
          'Acceso revocado',
          Icons.link_off_rounded
        ),
      _OAuthState.disconnected => (
          AppColors.ctRedBg,
          AppColors.ctRedText,
          'Desconectado',
          Icons.link_off_rounded
        ),
      _OAuthState.paused => (
          AppColors.ctSurface2,
          AppColors.ctText2,
          'Pausada',
          Icons.pause_circle_rounded
        ),
      _ => (
          AppColors.ctSurface2,
          AppColors.ctText2,
          'Sin conectar',
          Icons.help_outline_rounded
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 4),
          Text(label,
              style: AppFonts.geist(
                  fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

// Fila de configuración legible
class _ConfigRow extends StatelessWidget {
  const _ConfigRow(
      {required this.label, required this.value, this.isUrl = false});
  final String label;
  final String value;
  final bool isUrl;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: AppFonts.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ctText2)),
          ),
          Expanded(
            child: isUrl
                ? InkWell(
                    onTap: () => html.window.open(value, '_blank'),
                    child: Text(value,
                        style: AppFonts.geist(
                                fontSize: 12, color: AppColors.ctTeal)
                            .copyWith(
                                decoration: TextDecoration.underline),
                        overflow: TextOverflow.ellipsis),
                  )
                : Text(value,
                    style:
                        AppFonts.geist(fontSize: 12, color: AppColors.ctText),
                    overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

// ── Tab 2 — ITEMS ─────────────────────────────────────────────────────────────

class _ItemsTab extends ConsumerStatefulWidget {
  const _ItemsTab(
      {super.key, required this.catalog, required this.canManage});
  final Map<String, dynamic> catalog;
  final bool canManage;

  @override
  ConsumerState<_ItemsTab> createState() => _ItemsTabState();
}

class _ItemsTabState extends ConsumerState<_ItemsTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  int _page = 1;
  int _totalPages = 1;
  int _totalItems = 0;
  static const int _pageSize = 50;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  bool get _isManual =>
      (widget.catalog['source_type'] as String? ?? '') == 'manual';

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPage());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPage() async {
    if (!mounted) return;
    final tenantId = ref.read(activeTenantIdProvider);
    setState(() => _loading = true);
    try {
      final q = _searchCtrl.text.trim();
      final result = await CatalogsApi.listItemsPaged(
        dio: ref.read(apiClientProvider).dio,
        tenantId: tenantId,
        catalogId: _catalogId,
        page: _page,
        pageSize: _pageSize,
        search: q.isNotEmpty ? q : null,
      );
      if (mounted) {
        setState(() {
          _items = (result['items'] as List?)
                  ?.whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList() ??
              [];
          _totalItems = result['total'] as int? ?? 0;
          _totalPages = result['pages'] as int? ?? 1;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() { _page = 1; });
      _loadPage();
    });
  }

  Future<void> _showItemDetail(Map<String, dynamic> item) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.ctSurface,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _ItemDetailSheet(
        item: item,
        fields: _fields,
        catalog: widget.catalog,
        canManage: _isManual && widget.canManage,
      ),
    );
    if (changed == true && mounted) {
      setState(() { _page = 1; });
      _loadPage();
    }
  }

  Future<void> _showAddItem() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.ctSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _AddItemSheet(catalog: widget.catalog, fields: _fields),
        ),
      ),
    );
    if (ok == true && mounted) {
      setState(() { _page = 1; });
      _loadPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Toolbar ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('items_search'),
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  style: AppFonts.geist(
                      fontSize: 13, color: AppColors.ctText),
                  decoration: InputDecoration(
                    hintText: 'Buscar en items...',
                    hintStyle: AppFonts.geist(
                        fontSize: 13, color: AppColors.ctText3),
                    prefixIcon: const Icon(Icons.search_rounded,
                        size: 17, color: AppColors.ctText3),
                    filled: true,
                    fillColor: AppColors.ctSurface,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: AppColors.ctBorder2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: AppColors.ctBorder2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: AppColors.ctTeal, width: 1.5),
                    ),
                  ),
                ),
              ),
              if (_isManual && widget.canManage) ...[
                const SizedBox(width: 8),
                AppButton(
                  key: const Key('items_add_btn'),
                  label: 'Agregar',
                  variant: AppButtonVariant.teal,
                  size: AppButtonSize.sm,
                  prefixIcon: const Icon(Icons.add_rounded, size: 14, color: AppColors.ctNavy),
                  onPressed: _showAddItem,
                ),
              ],
            ],
          ),
        ),
        // ── Content ──────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.ctTeal))
              : _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.inbox_outlined,
                              size: 48, color: AppColors.ctText2),
                          const SizedBox(height: 10),
                          Text('Sin items',
                              style: AppFonts.onest(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ctText2)),
                          const SizedBox(height: 4),
                          Text('No hay items que coincidan.',
                              style: AppFonts.geist(
                                  fontSize: 12,
                                  color: AppColors.ctText3)),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.ctBorder),
                          borderRadius: BorderRadius.circular(10),
                          color: AppColors.ctSurface,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Header
                            Container(
                              height: 36,
                              decoration: const BoxDecoration(
                                color: AppColors.ctSurface2,
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(9),
                                  topRight: Radius.circular(9),
                                ),
                                border: Border(
                                    bottom: BorderSide(color: AppColors.ctBorder)),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: _fields
                                    .map((col) => Expanded(
                                          child: Text(
                                            (col['label'] ?? col['key'] ?? '')
                                                .toString()
                                                .toUpperCase(),
                                            style: AppFonts.geist(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.ctText2,
                                              letterSpacing: 0.4,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ))
                                    .toList(),
                              ),
                            ),
                            // Rows
                            Expanded(
                              child: ListView.separated(
                                itemCount: _items.length,
                                separatorBuilder: (context, i) => const Divider(
                                    height: 1, color: AppColors.ctBorder),
                                itemBuilder: (_, i) {
                                  final item = _items[i];
                                  final rawData = item['data'] is Map
                                      ? Map<String, dynamic>.from(
                                          item['data'] as Map)
                                      : <String, dynamic>{};
                                  return _CatalogItemRow(
                                    key: ValueKey(
                                        'item_row_${item['id'] ?? ''}'),
                                    item: item,
                                    rawData: rawData,
                                    fields: _fields,
                                    onTap: () => _showItemDetail(item),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
        ),
        // ── Pagination ───────────────────────────────────────────────
        if (!_loading && _totalPages > 1)
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              border:
                  Border(top: BorderSide(color: AppColors.ctBorder)),
            ),
            child: Row(
              children: [
                Text(
                  '$_totalItems resultado${_totalItems == 1 ? '' : 's'}',
                  style: AppFonts.geist(
                      fontSize: 12, color: AppColors.ctText2),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded,
                      size: 20),
                  onPressed: _page > 1
                      ? () {
                          setState(() => _page--);
                          _loadPage();
                        }
                      : null,
                  color: AppColors.ctText2,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 32, minHeight: 32),
                ),
                Text('$_page / $_totalPages',
                    style: AppFonts.geist(
                        fontSize: 12, color: AppColors.ctText)),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded,
                      size: 20),
                  onPressed: _page < _totalPages
                      ? () {
                          setState(() => _page++);
                          _loadPage();
                        }
                      : null,
                  color: AppColors.ctText2,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Item sheets ───────────────────────────────────────────────────────────────

class _ItemDetailSheet extends ConsumerStatefulWidget {
  const _ItemDetailSheet({
    required this.item,
    required this.fields,
    required this.catalog,
    required this.canManage,
  });
  final Map<String, dynamic> item;
  final List<Map<String, dynamic>> fields;
  final Map<String, dynamic> catalog;
  final bool canManage;

  @override
  ConsumerState<_ItemDetailSheet> createState() =>
      _ItemDetailSheetState();
}

class _ItemDetailSheetState extends ConsumerState<_ItemDetailSheet> {
  Map<String, dynamic> get _rawData =>
      widget.item['data'] is Map
          ? Map<String, dynamic>.from(widget.item['data'] as Map)
          : <String, dynamic>{};

  String get _itemId => widget.item['id'] as String? ?? '';

  String get _catalogId => widget.catalog['id'] as String? ?? '';

  String get _primaryKeyField =>
      widget.catalog['primary_key'] as String? ??
      (widget.fields.isNotEmpty
          ? (widget.fields.first['key'] as String? ?? '')
          : '');

  Future<void> _openEditDialog() async {
    final formKey = GlobalKey<CatalogItemFormState>();
    bool saving = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: AppColors.ctSurface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Editar item',
                          style: AppFonts.onest(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ctText)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            size: 20, color: AppColors.ctText2),
                        onPressed: () =>
                            Navigator.of(ctx).pop(false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CatalogItemForm(
                    key: formKey,
                    fieldsSchema: widget.fields,
                    primaryKeyField: _primaryKeyField,
                    initialData: _rawData,
                  ),
                  const SizedBox(height: 8),
                  AppButton(
                    key: const Key('item_edit_save'),
                    label: 'Guardar',
                    variant: AppButtonVariant.teal,
                    expand: true,
                    isLoading: saving,
                    onPressed: () async {
                      final fs = formKey.currentState;
                      if (fs == null || !fs.validate()) return;
                      setDialogState(() => saving = true);
                      try {
                        final tenantId =
                            ref.read(activeTenantIdProvider);
                        await CatalogsApi.updateItem(
                          dio: ref.read(apiClientProvider).dio,
                          tenantId: tenantId,
                          catalogId: _catalogId,
                          itemId: _itemId,
                          data: fs.getValue(),
                        );
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop(true);
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          setDialogState(() => saving = false);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Error al actualizar item: $e'),
                              backgroundColor: AppColors.ctDanger,
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (ok == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await AppConfirmDialog.show(
      context: context,
      title: 'Eliminar item',
      body: 'Esta accion no se puede deshacer. '
          'El item sera eliminado permanentemente.',
      confirmLabel: 'Eliminar',
      variant: AppConfirmDialogVariant.danger,
    );
    if (confirmed != true || !mounted) return;
    try {
      final tenantId = ref.read(activeTenantIdProvider);
      final result = await CatalogsApi.deleteItem(
        dio: ref.read(apiClientProvider).dio,
        tenantId: tenantId,
        catalogId: _catalogId,
        itemId: _itemId,
      );
      final unlinked =
          result['unlinked_assignment_resources'] as int? ?? 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(unlinked > 0
              ? 'Item eliminado. $unlinked recursos desreferenciados.'
              : 'Item eliminado.'),
        ));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al eliminar item: $e'),
          backgroundColor: AppColors.ctDanger,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawData = _rawData;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (_, ctrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Text('Detalle del item',
                    style: AppFonts.onest(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ctText)),
                const Spacer(),
                if (widget.canManage) ...[
                  IconButton(
                    key: const Key('item_detail_edit'),
                    tooltip: 'Editar',
                    icon: const Icon(Icons.edit_outlined,
                        size: 18, color: AppColors.ctTeal),
                    onPressed: _openEditDialog,
                  ),
                  IconButton(
                    key: const Key('item_detail_delete'),
                    tooltip: 'Eliminar',
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 18, color: AppColors.ctDanger),
                    onPressed: _confirmDelete,
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 20, color: AppColors.ctText2),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.ctBorder),
          Expanded(
            child: widget.fields.isNotEmpty
                ? ListView.separated(
                    controller: ctrl,
                    padding: const EdgeInsets.all(20),
                    itemCount: widget.fields.length,
                    separatorBuilder: (context, index) =>
                        const Divider(
                            height: 16, color: AppColors.ctBorder),
                    itemBuilder: (context, i) {
                      final field = widget.fields[i];
                      final k = field['key'] as String? ?? '';
                      final lbl =
                          field['label'] as String? ?? k;
                      final val = widget.item[k] ?? rawData[k];
                      return _DetailRow(
                          label: lbl,
                          value: val?.toString() ?? '—');
                    },
                  )
                : ListView.separated(
                    controller: ctrl,
                    padding: const EdgeInsets.all(20),
                    itemCount: widget.item.length,
                    separatorBuilder: (context, index) =>
                        const Divider(
                            height: 16, color: AppColors.ctBorder),
                    itemBuilder: (context, i) {
                      final entry =
                          widget.item.entries.elementAt(i);
                      return _DetailRow(
                          label: entry.key,
                          value:
                              entry.value?.toString() ?? '—');
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(label,
              style: AppFonts.geist(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ctText2)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value,
              style: AppFonts.geist(
                  fontSize: 12, color: AppColors.ctText)),
        ),
      ],
    );
  }
}

class _AddItemSheet extends ConsumerStatefulWidget {
  const _AddItemSheet(
      {required this.catalog, required this.fields});
  final Map<String, dynamic> catalog;
  final List<Map<String, dynamic>> fields;

  @override
  ConsumerState<_AddItemSheet> createState() =>
      _AddItemSheetState();
}

class _AddItemSheetState extends ConsumerState<_AddItemSheet> {
  final _formKey = GlobalKey<CatalogItemFormState>();
  bool _saving = false;

  String get _primaryKeyField =>
      widget.catalog['primary_key'] as String? ??
      (widget.fields.isNotEmpty
          ? (widget.fields.first['key'] as String? ?? '')
          : '');

  Future<void> _submit() async {
    if (_saving) return;
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) return;
    final tenantId = ref.read(activeTenantIdProvider);
    final catalogId = widget.catalog['id'] as String? ?? '';
    final data = formState.getValue();
    setState(() => _saving = true);
    try {
      await CatalogsApi.createItem(
          dio: ref.read(apiClientProvider).dio, tenantId: tenantId, catalogId: catalogId, data: data);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al crear item: $e'),
          backgroundColor: AppColors.ctDanger,
        ));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Row(
              children: [
                Text('Agregar item',
                    style: AppFonts.onest(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ctText)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 20, color: AppColors.ctText2),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            CatalogItemForm(
              key: _formKey,
              fieldsSchema: widget.fields,
              primaryKeyField: _primaryKeyField,
            ),
            const SizedBox(height: 8),
            AppButton(
              key: const Key('item_add_save'),
              label: 'Guardar',
              variant: AppButtonVariant.teal,
              expand: true,
              isLoading: _saving,
              onPressed: _submit,
            ),
          ],
        ),
    );
  }
}

// ── _CatalogItemRow ───────────────────────────────────────────────────────────

class _CatalogItemRow extends StatefulWidget {
  const _CatalogItemRow({
    super.key,
    required this.item,
    required this.rawData,
    required this.fields,
    required this.onTap,
  });
  final Map<String, dynamic> item;
  final Map<String, dynamic> rawData;
  final List<Map<String, dynamic>> fields;
  final VoidCallback onTap;

  @override
  State<_CatalogItemRow> createState() => _CatalogItemRowState();
}

class _CatalogItemRowState extends State<_CatalogItemRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          color: _hovered ? AppColors.ctBg : AppColors.ctSurface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: widget.fields.map((col) {
              final key = col['key'] as String? ?? '';
              final isPrimary = col['is_primary'] as bool? ?? false;
              final value = widget.rawData[key] ?? widget.item[key];
              final text = value == null ? '—' : value.toString();
              return Expanded(
                child: Text(
                  text,
                  style: AppFonts.geist(
                    fontSize: 13,
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
      ),
    );
  }
}

// ── Tab 3 — SYNC ──────────────────────────────────────────────────────────────

class _SyncTab extends ConsumerStatefulWidget {
  const _SyncTab({super.key, required this.catalog, this.polling = false});
  final Map<String, dynamic> catalog;
  final bool polling;

  @override
  ConsumerState<_SyncTab> createState() => _SyncTabState();
}

class _SyncTabState extends ConsumerState<_SyncTab> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  String? _error;

  SyncPoller? _poller;

  String get _catalogId => widget.catalog['id'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadLogs();
      if (widget.polling) _startPolling();
    });
  }

  @override
  void dispose() {
    _poller?.dispose();
    super.dispose();
  }

  void _startPolling() {
    _poller?.dispose();
    _poller = SyncPoller(
      poll: () async {
        if (!mounted) return false;
        await _loadLogs();
        return _logs.isEmpty || _logs.first['status'] == 'running';
      },
    );
    _poller!.start();
  }

  Future<void> _loadLogs() async {
    if (!mounted) return;
    final tenantId = ref.read(activeTenantIdProvider);
    setState(() { _loading = true; _error = null; });
    try {
      final logs = await CatalogsApi.listSyncLog(
          dio: ref.read(apiClientProvider).dio, tenantId: tenantId, catalogId: _catalogId);
      if (mounted) setState(() { _logs = logs; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() { _error = e.toString(); _loading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.ctTeal));
    }
    if (_error != null) {
      return Center(
          child: Text(_error!,
              style: AppFonts.geist(
                  fontSize: 13, color: AppColors.ctDanger)));
    }
    if (_logs.isEmpty) {
      return Center(
        key: const Key('sync_empty_state'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history_rounded,
                size: 48, color: AppColors.ctText2),
            const SizedBox(height: 12),
            Text('Sin historial de sync',
                style: AppFonts.onest(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ctText2)),
            const SizedBox(height: 4),
            Text(
                'Aquí aparecerán los registros cuando se ejecute un sync.',
                style: AppFonts.geist(
                    fontSize: 12, color: AppColors.ctText3)),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_logs.isNotEmpty && _logs.first['status'] == 'running') ...[
          Container(
            key: const Key('sync_running_banner'),
            margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.ctTealLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.ctTeal.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ctTeal),
                ),
                const SizedBox(width: 10),
                Text('Sincronización en curso...',
                    style: AppFonts.geist(fontSize: 13, color: AppColors.ctTealDark,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: _logs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final log = _logs[i];
              return _SyncLogRow(
                key: ValueKey('sync_log_${log['id'] ?? i}'),
                log: log,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SyncLogRow extends StatelessWidget {
  const _SyncLogRow({super.key, required this.log});
  final Map<String, dynamic> log;

  @override
  Widget build(BuildContext context) {
    final status = log['status'] as String? ?? 'unknown';
    final startedAt = log['started_at'] as String?;
    final durationMs = log['duration_ms'] as int?;
    final added = log['items_added'] as int? ?? 0;
    final updated = log['items_updated'] as int? ?? 0;
    final deleted = log['items_deleted'] as int? ?? 0;
    final triggeredBy =
        log['triggered_by'] as String? ?? 'scheduled';
    final errorMsg = log['error_message'] as String?;

    final (statusBg, statusFg, statusLabel) = switch (status) {
      'success'     => (AppColors.ctOkBg, AppColors.ctOkText, 'Exitoso'),
      'error'       => (AppColors.ctRedBg, AppColors.ctRedText, 'Error'),
      'in_progress' => (
          AppColors.ctInfoBg,
          AppColors.ctInfoText,
          'En progreso'
        ),
      _ => (AppColors.ctSurface2, AppColors.ctText2, status),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(statusLabel,
                    style: AppFonts.geist(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: statusFg)),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                    color: AppColors.ctSurface2,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(triggeredBy,
                    style: AppFonts.geist(
                        fontSize: 10, color: AppColors.ctText2)),
              ),
              const Spacer(),
              if (startedAt != null)
                Text(fmtRelative(startedAt, showSeconds: true),
                    style: AppFonts.geist(
                        fontSize: 11, color: AppColors.ctText3)),
              if (durationMs != null) ...[
                const SizedBox(width: 6),
                Text(
                    '${(durationMs / 1000).toStringAsFixed(1)}s',
                    style: AppFonts.geist(
                        fontSize: 11, color: AppColors.ctText3)),
              ],
            ],
          ),
          if (added > 0 || updated > 0 || deleted > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (added > 0)
                  _DeltaBadge(
                      label: '+$added', color: AppColors.ctOk),
                if (updated > 0) ...[
                  if (added > 0) const SizedBox(width: 4),
                  _DeltaBadge(
                      label: '~$updated',
                      color: AppColors.ctWarn),
                ],
                if (deleted > 0) ...[
                  if (added > 0 || updated > 0)
                    const SizedBox(width: 4),
                  _DeltaBadge(
                      label: '-$deleted',
                      color: AppColors.ctDanger),
                ],
              ],
            ),
          ],
          if (errorMsg != null && errorMsg.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(errorMsg,
                style: AppFonts.geist(
                    fontSize: 11, color: AppColors.ctDanger),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: AppFonts.geist(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color)),
    );
  }
}

// ── Tab 4 — USO ───────────────────────────────────────────────────────────────

class _UsoTab extends ConsumerStatefulWidget {
  const _UsoTab({required this.catalog});
  final Map<String, dynamic> catalog;

  @override
  ConsumerState<_UsoTab> createState() => _UsoTabState();
}

class _UsoTabState extends ConsumerState<_UsoTab> {
  List<Map<String, dynamic>> _usages = [];
  bool _loading = true;
  String? _error;

  String get _catalogId => widget.catalog['id'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final tenantId = ref.read(activeTenantIdProvider);
    setState(() { _loading = true; _error = null; });
    try {
      final usages = await CatalogsApi.getUsages(
          dio: ref.read(apiClientProvider).dio, tenantId: tenantId, catalogId: _catalogId);
      if (mounted) setState(() { _usages = usages; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.ctTeal));
    }
    if (_error != null) {
      return Center(
          child: Text(_error!,
              style: AppFonts.geist(fontSize: 13, color: AppColors.ctDanger)));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionCard(
            title: 'Flujos que usan este catálogo',
            child: _usages.isEmpty
                ? Column(
                    key: const Key('uso_empty_state'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.hub_outlined, size: 36,
                          color: AppColors.ctText2),
                      const SizedBox(height: 8),
                      Text(
                          'Este catálogo no está referenciado en ningún flujo aún.',
                          style: AppFonts.geist(
                              fontSize: 12, color: AppColors.ctText2)),
                    ],
                  )
                : Column(
                    children: _usages
                        .map((u) => _UsageRow(
                              key: ValueKey(
                                  'usage_${u['flow_slug'] ?? ''}'),
                              flowSlug: u['flow_slug'] as String? ?? '',
                              flowLabel: u['flow_label'] as String? ?? '',
                              fieldLabel: u['field_label'] as String? ?? '',
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({
    super.key,
    required this.flowSlug,
    required this.flowLabel,
    required this.fieldLabel,
  });
  final String flowSlug;
  final String flowLabel;
  final String fieldLabel;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: null, // Flow detail lives under /workers/:id — no workerId available here
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            const Icon(Icons.account_tree_outlined,
                size: 16, color: AppColors.ctTeal),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(flowLabel,
                      style: AppFonts.geist(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ctText)),
                  Text('Campo: $fieldLabel',
                      style: AppFonts.geist(
                          fontSize: 11, color: AppColors.ctText2)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 12, color: AppColors.ctText3),
          ],
        ),
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
      'date'    => (AppColors.ctPurpleBg, AppColors.ctPurpleText, 'fecha'),
      'boolean' => (AppColors.ctOkBg, AppColors.ctOkText, 'booleano'),
      'select'  => (AppColors.ctWarnBg, AppColors.ctWarnText, 'selección'),
      _ => (AppColors.ctSurface2, AppColors.ctText2,
          type.isEmpty ? 'tipo' : type),
    };
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: AppFonts.geist(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: fg)),
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
            style: AppFonts.geist(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.ctText2,
            ).copyWith(letterSpacing: 0.4),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _KeyDropdown extends StatelessWidget {
  const _KeyDropdown({
    required this.label,
    required this.value,
    required this.keys,
    required this.onChanged,
    this.enabled = true,
  });
  final String label;
  final String? value;
  final List<String> keys;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: AppFonts.geist(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.ctText2)),
        const SizedBox(height: 4),
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.ctSurface,
            border: Border.all(color: AppColors.ctBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: (value != null && keys.contains(value)) ? value : null,
              hint: Text('Seleccionar',
                  style: AppFonts.geist(
                      fontSize: 12, color: AppColors.ctText2)),
              isDense: true,
              isExpanded: true,
              style: AppFonts.geist(fontSize: 12, color: AppColors.ctText),
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 15, color: AppColors.ctText2),
              items: keys
                  .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                  .toList(),
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ),
      ],
    );
  }
}
