import 'dart:async';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:omni_datetime_picker/omni_datetime_picker.dart';

import '../../core/api/api_client.dart';
import '../../core/api/executions_api.dart';
import '../../core/api/operators_api.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/relative_time.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_shell.dart';

// ── _ColDef ───────────────────────────────────────────────────────────────────

class _ColDef {
  final String id;
  final String label;
  bool visible;
  _ColDef(this.id, this.label, {this.visible = true});
}

// ── _DateHeader sentinel ──────────────────────────────────────────────────────

class _DateHeader {
  final String label;
  const _DateHeader(this.label);
}

// ── Top-level helpers ─────────────────────────────────────────────────────────

double _colWidth(String id) => switch (id) {
  'worker'   => 130,
  'status'   => 110,
  'operator' => 130,
  'channel'  => 90,
  'created'  => 140,
  'elapsed'  => 90,
  'progress' => 90,
  _          => 100,
};



// ── Screen ────────────────────────────────────────────────────────────────────

class AllExecutionsScreen extends ConsumerStatefulWidget {
  const AllExecutionsScreen({super.key});

  @override
  ConsumerState<AllExecutionsScreen> createState() =>
      _AllExecutionsScreenState();
}

class _AllExecutionsScreenState extends ConsumerState<AllExecutionsScreen> {
  // ── Async state ──────────────────────────────────────────────────────────────
  bool    _loading = true;
  String? _error;
  List<Map<String, dynamic>> _executions = [];
  int     _total = 0;
  int     _page  = 1;
  static const int _limit = 25;

  // ── Sort / grouping ──────────────────────────────────────────────────────────
  String _sortCol = 'created_at';
  String _sortDir = 'desc';
  String _grouping = 'date'; // 'none' | 'date' | 'flow' | 'type' | 'operator' | 'status'

  // ── Columns ──────────────────────────────────────────────────────────────────
  late List<_ColDef> _columns;
  bool _showColumnPicker = false;

  // ── Timer ────────────────────────────────────────────────────────────────────
  Timer?    _refreshTimer;
  Timer?    _ticker;
  DateTime? _lastFetch;

  // ── Filters ──────────────────────────────────────────────────────────────────
  List<String> _filterStatus      = [];
  List<String> _filterWorkerIds   = [];
  List<String> _filterOperatorIds = [];
  List<String> _filterFlowIds     = [];
  List<String> _filterActorTypes  = [];
  String?      _filterChannelType;
  String?      _filterDateRange;
  String       _filterDateField   = 'created_at';
  String?      _filterDateFrom;
  String?      _filterDateTo;
  String       _searchText        = '';
  bool         _showFilterSidebar = false;
  bool         _showExportModal   = false;
  bool         _exporting         = false;

  // ── Workers ──────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _availableWorkers = [];
  bool                       _showWorkerPicker = false;

  // ── Operators ─────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _availableOperators = [];

  // ── Flows ─────────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _availableFlows = [];
  int _flowsLoadVersion = 0;

  // ── Views ────────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _savedViews = [];
  String? _activeViewId;
  bool    _viewsDirty = false;

  // ── Search debounce ──────────────────────────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  // ── Advanced field search ────────────────────────────────────────────────────
  Map<String, dynamic>      _searchableFields    = {};
  Map<String, List<String>> _activeFieldSearches = {};
  bool                      _showFieldDropdown   = false;
  String?                   _pendingField;

  // ────────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _columns = [
      _ColDef('flow',     'Flujo',    visible: true),
      _ColDef('worker',   'Worker',   visible: true),
      _ColDef('type',     'Tipo',     visible: true),
      _ColDef('status',   'Estado',   visible: true),
      _ColDef('operator', 'Operador', visible: true),
      _ColDef('channel',  'Canal',    visible: true),
      _ColDef('created',  'Creada',   visible: true),
      _ColDef('elapsed',  'Tiempo',   visible: false),
      _ColDef('progress', 'Campos',   visible: false),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(topbarTitleProvider.notifier).state    = 'Ejecuciones';
      ref.read(topbarSubtitleProvider.notifier).state = null;
      final tenantId = ref.read(activeTenantIdProvider);
      if (tenantId.isNotEmpty) {
        _load();
        _loadViews();
        _loadWorkers();
        _loadOperators();
        _loadFlows();
        _loadSearchableFields();
        _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
          if (mounted) _load();
        });
        _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _ticker?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _load() async {
    final tenantId = ref.read(activeTenantIdProvider);
    if (tenantId.isEmpty) return;
    // Sin workers seleccionados = sin resultados
    if (_filterWorkerIds.isEmpty) {
      setState(() {
        _executions = [];
        _total      = 0;
        _loading    = false;
      });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      debugPrint('[Search] query="$_searchText" fields=$_activeFieldSearches');
      final fieldEntry = _activeFieldSearches.entries.firstOrNull;
      final data = await ExecutionsApi.listExecutions(
        tenantId:    tenantId,
        status:      _filterStatus.isNotEmpty ? _filterStatus : null,
        workerIds:   _filterWorkerIds.isNotEmpty ? _filterWorkerIds : null,
        operatorIds: _filterOperatorIds.isNotEmpty ? _filterOperatorIds : null,
        flowIds:     _filterFlowIds.isNotEmpty ? _filterFlowIds : null,
        actorTypes:  _filterActorTypes.isNotEmpty ? _filterActorTypes : null,
        channelType: _filterChannelType,
        dateRange:   _filterDateRange,
        dateField:   _filterDateField,
        dateFrom:    _filterDateFrom,
        dateTo:      _filterDateTo,
        search:      _searchText.isNotEmpty ? _searchText : null,
        fieldKey:    fieldEntry?.key,
        fieldValues: fieldEntry?.value,
        sortCol:     _sortCol,
        sortDir:     _sortDir,
        page:        _page,
        limit:       _limit,
      );
      final raw = data['items'] ?? data['executions'] ?? data['data'] ?? [];
      setState(() {
        _executions = List<Map<String, dynamic>>.from(
          (raw as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
        );
        _total     = (data['total'] as num?)?.toInt() ?? _executions.length;
        _lastFetch = DateTime.now();
        _loading   = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadViews() async {
    final tenantId = ref.read(activeTenantIdProvider);
    debugPrint('[Views] loading for tenant: '
        '${ref.read(activeTenantIdProvider)}');
    if (tenantId.isEmpty) return;
    try {
      final views = await ExecutionsApi.listViews(tenantId: tenantId);
      debugPrint('[Views] response: ${views.toString().substring(0, views.toString().length.clamp(0, 200))}');
      if (mounted) {
        setState(() {
          _savedViews = views
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          debugPrint('[Views] setState: ${_savedViews.length} views');
        });
      }
    } catch (e) {
      debugPrint('[Views] error: $e');
    }
  }

  Future<void> _loadWorkers() async {
    final tenantId = ref.read(activeTenantIdProvider);
    if (tenantId.isEmpty) return;
    final wasEmpty = _filterWorkerIds.isEmpty;
    try {
      final resp = await ApiClient.instance.get('/workers');
      debugPrint('[Workers] resp.data type: ${resp.data.runtimeType}');
      debugPrint('[Workers] resp.data: ${resp.data.toString().substring(0, resp.data.toString().length.clamp(0, 300))}');
      final list = resp.data is List
          ? resp.data as List
          : ((resp.data['workers'] ?? resp.data['items'] ?? []) as List);
      if (!mounted) return;
      setState(() {
        _availableWorkers = list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((w) => w['is_active'] == true)
            .toList();
        // Seleccionar todos por default si no había filtro activo
        if (wasEmpty) {
          _filterWorkerIds = _availableWorkers
              .map((w) => w['id'] as String? ?? '')
              .where((id) => id.isNotEmpty)
              .toList();
        }
        // Auto-hide worker column if only 1 worker
        if (_availableWorkers.length == 1) {
          final idx = _columns.indexWhere((c) => c.id == 'worker');
          if (idx >= 0) _columns[idx].visible = false;
        }
      });
      debugPrint('[Workers] loaded: ${_availableWorkers.length}');
      // Recargar solo si era la primera carga (seleccionamos workers por default)
      if (wasEmpty && mounted) {
        _load();
        _loadFlows();
      }
    } catch (e) {
      debugPrint('[Workers] error: $e');
    }
  }

  Future<void> _loadOperators() async {
    final tenantId = ref.read(activeTenantIdProvider);
    if (tenantId.isEmpty) return;
    try {
      final list = await OperatorsApi.listOperators();
      if (mounted) {
        setState(() {
          _availableOperators = list;
        });
      }
    } catch (e) {
      debugPrint('[Operators] error: $e');
    }
  }

  Future<void> _loadFlows() async {
    final tenantId = ref.read(activeTenantIdProvider);
    if (tenantId.isEmpty) return;

    // Snapshot de workers al inicio de esta llamada
    final workerSnapshot = List<String>.from(_filterWorkerIds);
    // Versión de esta llamada — descarta respuestas de llamadas anteriores
    _flowsLoadVersion++;
    final myVersion = _flowsLoadVersion;

    try {
      final resp = await ApiClient.instance.get('/flows');

      // Si se lanzó una llamada más nueva, descartar
      if (myVersion != _flowsLoadVersion) return;
      if (!mounted) return;

      final list = resp.data is List
          ? resp.data as List
          : ((resp.data['flows'] ?? resp.data['items'] ??
             resp.data['flow_definitions'] ?? []) as List);

      var flows = list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((f) => f['is_active'] == true)
          .toList();

      // Filtrar por workers usando el snapshot (no el estado mutable)
      if (workerSnapshot.isNotEmpty) {
        flows = flows.where((f) {
          final fwid = f['tenant_worker_id'] as String?;
          return fwid != null && workerSnapshot.contains(fwid);
        }).toList();
      }

      setState(() {
        _availableFlows = flows;
        // Remove flow IDs that are no longer available
        _filterFlowIds = _filterFlowIds
            .where((id) => _availableFlows.any((f) => f['id'] == id))
            .toList();
      });
      debugPrint('[Flows] loaded: ${_availableFlows.length} '
          '(workers: ${workerSnapshot.length}, v$myVersion)');
    } catch (e) {
      debugPrint('[Flows] error: $e');
    }
  }

  void _toggleWorker(String id) {
    setState(() {
      if (_filterWorkerIds.contains(id)) {
        _filterWorkerIds = List.from(_filterWorkerIds)..remove(id);
      } else {
        _filterWorkerIds = List.from(_filterWorkerIds)..add(id);
      }
      _page = 1;
      _filterFlowIds     = [];
      _filterOperatorIds = [];
    });
    _markDirty();
    _loadFlows();
    _loadOperators();
    _loadSearchableFields();
    _load();
  }

  Future<void> _loadSearchableFields() async {
    final tenantId = ref.read(activeTenantIdProvider);
    if (tenantId.isEmpty) return;
    try {
      final fields = await ExecutionsApi.getSearchableFields(
        tenantId: tenantId,
        workerIds: _filterWorkerIds.isEmpty ? null : _filterWorkerIds,
      );
      if (mounted) {
        setState(() => _searchableFields = fields);
      }
    } catch (e) {
      debugPrint('[SearchableFields] error: $e');
    }
  }

  // ── Filter helpers ────────────────────────────────────────────────────────

  int _activeFiltersCount() {
    var count = _filterStatus.length + _filterOperatorIds.length
        + _filterFlowIds.length + _filterActorTypes.length;
    if (_filterChannelType != null) count++;
    if (_filterDateRange != null)   count++;
    return count;
  }

  bool _hasActiveFilters() =>
      _activeFiltersCount() > 0 ||
      _searchText.isNotEmpty ||
      _activeFieldSearches.isNotEmpty;

  void _markDirty() {
    if (_activeViewId != null && !_viewsDirty) {
      setState(() => _viewsDirty = true);
    }
  }

  void _clearFilters() {
    setState(() {
      _filterStatus        = [];
      _filterWorkerIds     = [];
      _filterOperatorIds   = [];
      _filterFlowIds       = [];
      _filterActorTypes    = [];
      _filterChannelType   = null;
      _filterDateRange     = null;
      _filterDateField     = 'created_at';
      _filterDateFrom      = null;
      _filterDateTo        = null;
      _searchText          = '';
      _searchCtrl.clear();
      _activeFieldSearches = {};
      _activeViewId        = null;
      _viewsDirty          = false;
      _page                = 1;
    });
    _load();
  }

  void _applyView(Map<String, dynamic> view) {
    final filters = view['filters'] as Map<String, dynamic>? ?? {};
    final savedFieldSearches =
        filters['field_searches'] as Map<String, dynamic>? ?? {};
    setState(() {
      _filterStatus      = List<String>.from(filters['status']       ?? []);
      _filterWorkerIds   = List<String>.from(filters['worker_ids']   ?? []);
      _filterOperatorIds = List<String>.from(filters['operator_ids'] ?? []);
      _filterFlowIds     = List<String>.from(filters['flow_ids']     ?? []);
      _filterActorTypes  = List<String>.from(filters['actor_types']  ?? []);
      _filterChannelType = filters['channel_type'] as String?;
      _filterDateRange   = filters['date_range']   as String?;
      _filterDateField   = filters['date_field']   as String? ?? 'created_at';
      _filterDateFrom    = filters['date_from']    as String?;
      _filterDateTo      = filters['date_to']      as String?;
      _searchText        = filters['search']       as String? ?? '';
      if (_searchText.isNotEmpty) _searchCtrl.text = _searchText;
      _activeFieldSearches = {
        for (final e in savedFieldSearches.entries)
          e.key: List<String>.from(e.value as List? ?? []),
      };
      _activeViewId = view['id'] as String?;
      _viewsDirty   = false;
      _page         = 1;
    });
    _load();
  }

  Map<String, dynamic> _currentFiltersMap() => {
    if (_filterStatus.isNotEmpty)           'status':         _filterStatus,
    if (_filterWorkerIds.isNotEmpty)        'worker_ids':     _filterWorkerIds,
    if (_filterOperatorIds.isNotEmpty)      'operator_ids':   _filterOperatorIds,
    if (_filterFlowIds.isNotEmpty)          'flow_ids':       _filterFlowIds,
    if (_filterActorTypes.isNotEmpty)       'actor_types':    _filterActorTypes,
    if (_filterChannelType != null)         'channel_type':   _filterChannelType,
    if (_filterDateRange != null) 'date_range': _filterDateRange,
    'date_field': _filterDateField,
    if (_filterDateFrom != null) 'date_from': _filterDateFrom,
    if (_filterDateTo != null)   'date_to':   _filterDateTo,
    if (_searchText.isNotEmpty)             'search':         _searchText,
    if (_activeFieldSearches.isNotEmpty)    'field_searches': _activeFieldSearches,
  };

  String _statusLabel(String s) => switch (s) {
    'active' || 'in_progress'               => 'Activa',
    'completed'                             => 'Completada',
    'pending'                               => 'Pendiente',
    'pending_dashboard' || 'pending_review' => 'En revisión',
    'paused'                                => 'Pausada',
    'abandoned'                             => 'Abandonada',
    'cancelled'                             => 'Cancelada',
    'failed' || 'error'                     => 'Error',
    _                                       => s,
  };

  String _dateRangeLabel(String r) => switch (r) {
    'today'        => 'Hoy',
    'yesterday'    => 'Ayer',
    'last_7_days'  => 'Últimos 7 días',
    'last_30_days' => 'Últimos 30 días',
    'this_month'   => 'Este mes',
    'custom'       => 'Rango personalizado',
    _              => r,
  };

  // ── Sort ──────────────────────────────────────────────────────────────────

  void _onSort(String apiCol) {
    setState(() {
      if (_sortCol == apiCol) {
        _sortDir = _sortDir == 'asc' ? 'desc' : 'asc';
      } else {
        _sortCol = apiCol;
        _sortDir = 'desc';
      }
      _page = 1;
    });
    _load();
  }

  String _apiCol(String colId) => switch (colId) {
    'flow'     => 'flow_name',
    'status'   => 'status',
    'operator' => 'operator_name',
    'created'  => 'created_at',
    'elapsed'  => 'elapsed_seconds',
    _          => colId,
  };

  String _fieldLabel(String key) {
    // Flat structure: {fields: [...]}
    final flat = _searchableFields['fields'] as List? ?? [];
    for (final f in flat) {
      if (f is Map && f['key'] == key) return f['label'] as String? ?? key;
    }
    // Grouped by flow: {flows: [{fields: [...]}]}
    final flows = _searchableFields['flows'] as List? ?? [];
    for (final flow in flows) {
      if (flow is! Map) continue;
      for (final f in (flow['fields'] as List? ?? [])) {
        if (f is Map && f['key'] == key) return f['label'] as String? ?? key;
      }
    }
    return key;
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(activeTenantIdProvider, (_, next) {
      if (next.isNotEmpty) {
        _page = 1;
        _load();
        _loadViews();
        _loadWorkers();
        _loadOperators();
        _loadFlows();
        _loadSearchableFields();
      }
    });

    final totalPages = _total > 0 ? (_total / _limit).ceil() : 1;

    return Scaffold(
      backgroundColor: AppColors.ctBg,
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopbar(),
              _buildSearchRow(),
              if (_activeFiltersCount() > 0) _buildChipsBar(),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_showFilterSidebar)
                      _FilterSidebar(
                        filterStatus:       _filterStatus,
                        filterChannelType:  _filterChannelType,
                        filterDateRange:    _filterDateRange,
                        filterOperatorIds:  _filterOperatorIds,
                        availableOperators: _availableOperators,
                        filterActorTypes:   _filterActorTypes,
                        onStatusToggle: (s) {
                          setState(() {
                            _filterStatus = _filterStatus.contains(s)
                                ? _filterStatus.where((x) => x != s).toList()
                                : [..._filterStatus, s];
                            _page = 1;
                          });
                          _markDirty();
                          _load();
                        },
                        onChannelTypeSelect: (c) {
                          setState(() { _filterChannelType = c; _page = 1; });
                          _markDirty();
                          _load();
                        },
                        onDateRangeSelect: (d) {
                          setState(() { _filterDateRange = d; _page = 1; });
                          _markDirty();
                          _load();
                        },
                        filterDateField: _filterDateField,
                        filterDateFrom:  _filterDateFrom,
                        filterDateTo:    _filterDateTo,
                        onDateFieldSelect: (field) {
                          setState(() { _filterDateField = field; _page = 1; });
                          _markDirty();
                          _load();
                        },
                        onDateRangeChange: (range, from, to) {
                          setState(() {
                            _filterDateRange = range;
                            _filterDateFrom  = from;
                            _filterDateTo    = to;
                            _page = 1;
                          });
                          _markDirty();
                          _load();
                        },
                        onOperatorToggle: (id) {
                          setState(() {
                            _filterOperatorIds = _filterOperatorIds.contains(id)
                                ? _filterOperatorIds.where((x) => x != id).toList()
                                : [..._filterOperatorIds, id];
                            _page = 1;
                          });
                          _markDirty();
                          _load();
                        },
                        onActorTypeToggle: (t) {
                          setState(() {
                            _filterActorTypes = _filterActorTypes.contains(t)
                                ? _filterActorTypes.where((x) => x != t).toList()
                                : [..._filterActorTypes, t];
                            _page = 1;
                          });
                          _markDirty();
                          _load();
                        },
                        filterFlowIds:  _filterFlowIds,
                        availableFlows: _availableFlows,
                        onFlowToggle: (id) {
                          setState(() {
                            _filterFlowIds = _filterFlowIds.contains(id)
                                ? _filterFlowIds.where((x) => x != id).toList()
                                : [..._filterFlowIds, id];
                            _page = 1;
                          });
                          _markDirty();
                          _load();
                        },
                        hasWorkers: _filterWorkerIds.isNotEmpty,
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: (MediaQuery.of(context).size.width -
                                  (_showFilterSidebar ? 484 : 220))
                              .clamp(900.0, double.infinity),
                          child: Column(
                            children: [
                              _buildTableHeader(),
                              Expanded(child: _buildBody()),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_total > _limit) _buildPaginationFooter(totalPages),
            ],
          ),
          // Dismiss layer for worker picker
          if (_showWorkerPicker)
            GestureDetector(
              onTap: () => setState(() => _showWorkerPicker = false),
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          // Worker picker card
          if (_showWorkerPicker)
            Positioned(
              top: 58,
              left: 24,
              child: _buildWorkerPickerCard(),
            ),
          // Dismiss layer for field dropdown / value input
          if (_showFieldDropdown || _pendingField != null)
            GestureDetector(
              onTap: () => setState(() {
                _showFieldDropdown = false;
                _pendingField = null;
              }),
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          // Field search dropdown
          if (_showFieldDropdown)
            Positioned(
              top: 96,
              left: 20,
              right: 300,
              child: _buildFieldDropdown(),
            ),
          // Value input panel
          if (_pendingField != null)
            Positioned(
              top: 96,
              left: 20,
              width: 380,
              child: _ValueInput(
                fieldKey:   _pendingField!,
                fieldLabel: _fieldLabel(_pendingField!),
                initialValues: _activeFieldSearches[_pendingField!] ?? [],
                onSubmit: (values) {
                  setState(() {
                    if (values.isNotEmpty) {
                      _activeFieldSearches = Map.from(_activeFieldSearches)
                        ..[_pendingField!] = values;
                    } else {
                      _activeFieldSearches = Map.from(_activeFieldSearches)
                        ..remove(_pendingField);
                    }
                    _pendingField = null;
                    _page = 1;
                  });
                  _markDirty();
                  _load();
                },
                onCancel: () => setState(() => _pendingField = null),
              ),
            ),
          // Dismiss layer for column picker
          if (_showColumnPicker)
            GestureDetector(
              onTap: () => setState(() => _showColumnPicker = false),
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          // Column picker card
          if (_showColumnPicker)
            Positioned(
              top: 96,
              right: 24,
              child: _buildColumnPickerCard(),
            ),
          // Export modal backdrop
          if (_showExportModal)
            GestureDetector(
              onTap: () => setState(() => _showExportModal = false),
              behavior: HitTestBehavior.opaque,
              child: Container(
                  color: Colors.black.withValues(alpha: 0.3)),
            ),
          // Export modal
          if (_showExportModal)
            Center(child: _buildExportModal()),
        ],
      ),
    );
  }

  // ── Topbar ────────────────────────────────────────────────────────────────

  Widget _buildTopbar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Row(
        children: [
          Text(
            'Todas las ejecuciones',
            style: AppFonts.onest(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.ctText,
            ),
          ),
          if (_total > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.ctNavy,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$_total',
                style: AppFonts.geist(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
          const SizedBox(width: 16),
          _buildWorkerSelector(),
          const Spacer(),
          if (_lastFetch != null)
            Text(
              'Act. ${fmtRelative(_lastFetch!.toUtc().toIso8601String(), compact: true, showSeconds: true)}',
              style: AppFonts.geist(fontSize: 11, color: AppColors.ctText3),
            ),
          const SizedBox(width: 4),
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: _loading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.ctTeal,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded,
                      size: 16, color: AppColors.ctText3),
              onPressed: _loading ? null : _load,
            ),
          ),
        ],
      ),
    );
  }

  // ── Worker selector ───────────────────────────────────────────────────────

  Color _workerColor(String workerId) {
    const colors = [
      Color(0xFF6366F1),
      Color(0xFF8B5CF6),
      Color(0xFF0891B2),
      Color(0xFF059669),
      Color(0xFFD97706),
    ];
    return colors[workerId.hashCode.abs() % colors.length];
  }

  Widget _buildWorkerSelector() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pills de workers seleccionados
        for (final wid in _filterWorkerIds) ...[
          Builder(builder: (ctx) {
            final worker = _availableWorkers.firstWhere(
              (w) => w['id'] == wid,
              orElse: () => {'id': wid, 'display_name': wid},
            );
            final name = worker['display_name'] as String?
                ?? worker['catalog_name'] as String?
                ?? worker['name'] as String?
                ?? wid;
            return Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
              decoration: BoxDecoration(
                color: AppColors.ctNavy,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: _workerColor(wid),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: AppFonts.geist(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    name,
                    style: AppFonts.geist(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => _toggleWorker(wid),
                    child: const Icon(Icons.close_rounded,
                        size: 12, color: Colors.white70),
                  ),
                ],
              ),
            );
          }),
        ],
        // Botón "+" para abrir picker
        GestureDetector(
          onTap: () =>
              setState(() => _showWorkerPicker = !_showWorkerPicker),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _filterWorkerIds.isEmpty
                  ? AppColors.ctSurface2
                  : AppColors.ctNavy.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _filterWorkerIds.isEmpty
                    ? AppColors.ctBorder
                    : AppColors.ctNavy.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_rounded,
                  size: 13,
                  color: _filterWorkerIds.isEmpty
                      ? AppColors.ctText2
                      : AppColors.ctNavy,
                ),
                const SizedBox(width: 4),
                Text(
                  _filterWorkerIds.isEmpty ? 'Worker' : 'Agregar',
                  style: AppFonts.geist(
                    fontSize: 12,
                    color: _filterWorkerIds.isEmpty
                        ? AppColors.ctText2
                        : AppColors.ctNavy,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkerPickerCard() {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      shadowColor: Colors.black12,
      child: Container(
        width: 260,
        constraints: const BoxConstraints(maxHeight: 300),
        decoration: BoxDecoration(
          color: AppColors.ctSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.ctBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                children: [
                  Text(
                    'Workers',
                    style: AppFonts.geist(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ctText2,
                    ),
                  ),
                  const Spacer(),
                  if (_filterWorkerIds.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _filterWorkerIds   = [];
                          _filterFlowIds     = [];
                          _filterOperatorIds = [];
                          _page = 1;
                        });
                        _markDirty();
                        _loadFlows();
                        _loadOperators();
                        _loadSearchableFields();
                        _load();
                      },
                      child: Text(
                        'Limpiar',
                        style: AppFonts.geist(
                            fontSize: 11, color: AppColors.ctTeal),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Lista
            if (_availableWorkers.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No hay workers disponibles',
                  style: AppFonts.geist(
                      fontSize: 13, color: AppColors.ctText3),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _availableWorkers.length,
                  itemBuilder: (ctx, i) {
                    final w        = _availableWorkers[i];
                    final id       = w['id'] as String? ?? '';
                    final name     = w['display_name'] as String?
                        ?? w['catalog_name'] as String?
                        ?? w['name'] as String?
                        ?? id;
                    final selected = _filterWorkerIds.contains(id);
                    return InkWell(
                      onTap: () => _toggleWorker(id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 9),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: _workerColor(id),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  name.isNotEmpty
                                      ? name[0].toUpperCase()
                                      : '?',
                                  style: AppFonts.geist(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                name,
                                style: AppFonts.geist(
                                    fontSize: 13, color: AppColors.ctText),
                              ),
                            ),
                            if (selected)
                              const Icon(Icons.check_rounded,
                                  size: 16, color: AppColors.ctTeal),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Search row ────────────────────────────────────────────────────────────

  Widget _buildSearchRow() {
    final visCount = _columns.where((c) => c.visible).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Row(
        children: [
          Expanded(child: _buildSearchBar()),
          const SizedBox(width: 8),
          _GroupingChip(
            grouping: _grouping,
            onSelect: (g) => setState(() => _grouping = g),
          ),
          const SizedBox(width: 8),
          _TopbarChip(
            icon: Icons.view_column_outlined,
            label: '$visCount col.',
            active: _showColumnPicker,
            onTap: () =>
                setState(() => _showColumnPicker = !_showColumnPicker),
          ),
          const SizedBox(width: 8),
          _TopbarChip(
            icon: Icons.filter_list_rounded,
            label: _activeFiltersCount() > 0
                ? 'Filtros (${_activeFiltersCount()})'
                : 'Filtros',
            active: _showFilterSidebar || _hasActiveFilters(),
            onTap: () =>
                setState(() => _showFilterSidebar = !_showFilterSidebar),
          ),
          const SizedBox(width: 8),
          _ViewsMenu(
            views:        _savedViews,
            activeViewId: _activeViewId,
            isDirty:      _viewsDirty,
            onSelect:     _applyView,
            onSave:       _showSaveViewDialog,
            onDelete:     _deleteView,
          ),
          const SizedBox(width: 8),
          _TopbarChip(
            icon: Icons.download_rounded,
            label: 'Exportar',
            active: false,
            onTap: () => setState(() => _showExportModal = true),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        border: Border.all(
          color: _showFieldDropdown || _pendingField != null
              ? AppColors.ctTeal
              : AppColors.ctBorder,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          const Icon(Icons.search_rounded, size: 16, color: AppColors.ctText3),
          const SizedBox(width: 6),
          // Active field search tags
          for (final entry in _activeFieldSearches.entries) ...[
            _FieldSearchTag(
              fieldKey: entry.key,
              values:   entry.value,
              label:    _fieldLabel(entry.key),
              onEdit: () => setState(() {
                _pendingField = entry.key;
                _showFieldDropdown = false;
              }),
              onRemove: () {
                setState(() {
                  _activeFieldSearches = Map.from(_activeFieldSearches)
                    ..remove(entry.key);
                  _page = 1;
                });
                _markDirty();
                _load();
              },
            ),
            const SizedBox(width: 4),
          ],
          // Plain text search input
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: AppFonts.geist(fontSize: 13, color: AppColors.ctText),
              decoration: InputDecoration(
                hintText: _activeFieldSearches.isEmpty
                    ? 'Buscar por operador, flujo...'
                    : '',
                hintStyle:
                    AppFonts.geist(fontSize: 13, color: AppColors.ctText3),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (v) {
                _searchDebounce?.cancel();
                _searchDebounce =
                    Timer(const Duration(milliseconds: 400), () {
                  if (!mounted) return;
                  setState(() { _searchText = v; _page = 1; });
                  _markDirty();
                  _load();
                });
              },
            ),
          ),
          // "+" button to open field search dropdown
          GestureDetector(
            onTap: () =>
                setState(() => _showFieldDropdown = !_showFieldDropdown),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                Icons.tune_rounded,
                size: 15,
                color: _showFieldDropdown || _activeFieldSearches.isNotEmpty
                    ? AppColors.ctTeal
                    : AppColors.ctText3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldDropdown() {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(10),
      shadowColor: Colors.black12,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 320),
        decoration: BoxDecoration(
          color: AppColors.ctSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.ctBorder),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _buildFieldSections(),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFieldSections() {
    final flat = (_searchableFields['fields'] as List? ?? [])
        .whereType<Map>()
        .toList();

    if (flat.isEmpty) return [_noFieldsPlaceholder()];

    final result = <Widget>[];

    // Campos generales primero
    final generals = flat.where((f) => f['type'] == 'general').toList();
    if (generals.isNotEmpty) {
      result.add(Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Text('CAMPOS GENERALES', style: AppFonts.geist(
          fontSize: 10, fontWeight: FontWeight.w700,
          color: AppColors.ctText3,
        )),
      ));
      for (final f in generals) {
        result.add(_buildFieldItem(
          f['key']        as String? ?? '',
          f['label']      as String? ?? (f['key'] as String? ?? ''),
          f['field_type'] as String? ?? 'text',
          null,
        ));
      }
    }

    // Agrupar metadata por flow_name
    final metadata = flat.where((f) => f['type'] == 'metadata').toList();
    final Map<String, List<Map>> byFlow = {};
    for (final f in metadata) {
      final flowName = f['flow_name'] as String? ?? 'Sin flow';
      byFlow.putIfAbsent(flowName, () => []).add(f as Map<String, dynamic>);
    }

    for (final entry in byFlow.entries) {
      result.add(Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Text('METADATA — ${entry.key}', style: AppFonts.geist(
          fontSize: 10, fontWeight: FontWeight.w700,
          color: AppColors.ctText3,
        )),
      ));
      for (final f in entry.value) {
        result.add(_buildFieldItem(
          f['key']        as String? ?? '',
          f['label']      as String? ?? (f['key'] as String? ?? ''),
          f['field_type'] as String? ?? 'text',
          entry.key,
        ));
      }
    }

    return result.isEmpty ? [_noFieldsPlaceholder()] : result;
  }

  Widget _noFieldsPlaceholder() => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No hay campos disponibles',
          style: AppFonts.geist(fontSize: 13, color: AppColors.ctText3),
        ),
      );

  Widget _buildFieldItem(
      String key, String label, String type, String? flowName) {
    final active = _activeFieldSearches.containsKey(key);
    return InkWell(
      onTap: () {
        setState(() {
          _showFieldDropdown = false;
          _pendingField      = key;
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Icon(_fieldIcon(type), size: 13, color: AppColors.ctText3),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: AppFonts.geist(fontSize: 13, color: AppColors.ctText),
              ),
            ),
            if (flowName != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.ctSurface2,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  flowName,
                  style: AppFonts.geist(fontSize: 10, color: AppColors.ctText2),
                ),
              ),
            ],
            if (active) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.ctTealLight,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${_activeFieldSearches[key]!.length}',
                  style: AppFonts.geist(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ctTealDark,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _fieldIcon(String type) => switch (type) {
        'number' || 'int' || 'float' => Icons.tag_rounded,
        'email'                      => Icons.email_outlined,
        'phone'                      => Icons.phone_outlined,
        'date'                       => Icons.calendar_today_outlined,
        'select' || 'list'           => Icons.list_rounded,
        _                            => Icons.text_fields_rounded,
      };

  // ── Chips bar ─────────────────────────────────────────────────────────────

  Widget _buildChipsBar() {
    final chips = <Widget>[];

    for (final s in _filterStatus) {
      chips.add(_FilterChip(
        label: _statusLabel(s),
        onRemove: () {
          setState(() {
            _filterStatus = _filterStatus.where((x) => x != s).toList();
            _page = 1;
          });
          _markDirty();
          _load();
        },
      ));
    }
    if (_filterChannelType != null) {
      chips.add(_FilterChip(
        label: _filterChannelType!,
        onRemove: () {
          setState(() { _filterChannelType = null; _page = 1; });
          _markDirty();
          _load();
        },
      ));
    }
    if (_filterDateRange != null || _filterDateFrom != null) {
      final fieldLabel = switch (_filterDateField) {
        'updated_at'   => 'Actualizada',
        'completed_at' => 'Completada',
        _              => 'Creada',
      };
      String dateLabel;
      if (_filterDateRange == 'custom' &&
          (_filterDateFrom != null || _filterDateTo != null)) {
        final from = _filterDateFrom != null
            ? fmtDateTimeCompact(_filterDateFrom!) : '?';
        final to = _filterDateTo != null
            ? fmtDateTimeCompact(_filterDateTo!) : '?';
        dateLabel = '$fieldLabel: $from → $to';
      } else {
        dateLabel = '$fieldLabel: ${_dateRangeLabel(_filterDateRange ?? '')}';
      }
      chips.add(_FilterChip(
        label: dateLabel,
        onRemove: () {
          setState(() {
            _filterDateRange = null;
            _filterDateFrom  = null;
            _filterDateTo    = null;
            _page = 1;
          });
          _markDirty();
          _load();
        },
      ));
    }
    for (final opId in _filterOperatorIds) {
      chips.add(_FilterChip(
        label: 'Op: $opId',
        onRemove: () {
          setState(() {
            _filterOperatorIds =
                _filterOperatorIds.where((x) => x != opId).toList();
            _page = 1;
          });
          _markDirty();
          _load();
        },
      ));
    }
    for (final flowId in _filterFlowIds) {
      final flow = _availableFlows.firstWhere(
        (f) => f['id'] == flowId,
        orElse: () => {'name': flowId},
      );
      chips.add(_FilterChip(
        label: 'Flujo: ${flow['name'] as String? ?? flowId}',
        onRemove: () {
          setState(() {
            _filterFlowIds = _filterFlowIds.where((x) => x != flowId).toList();
            _page = 1;
          });
          _markDirty();
          _load();
        },
      ));
    }
    for (final t in _filterActorTypes) {
      final label = switch (t) {
        'operator'    => 'Tipo: Conversacional',
        'system'      => 'Tipo: API',
        'tenant_user' => 'Tipo: Dashboard',
        _             => 'Tipo: $t',
      };
      chips.add(_FilterChip(
        label: label,
        onRemove: () {
          setState(() {
            _filterActorTypes = _filterActorTypes.where((x) => x != t).toList();
            _page = 1;
          });
          _markDirty();
          _load();
        },
      ));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ...chips,
          AppButton(
            label: 'Limpiar todo',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: _clearFilters,
          ),
        ],
      ),
    );
  }

  // ── Save / delete views ───────────────────────────────────────────────────

  Future<void> _showSaveViewDialog() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.ctSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Guardar vista',
          style: AppFonts.onest(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ctText,
          ),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: AppFonts.geist(fontSize: 13, color: AppColors.ctText),
          decoration: InputDecoration(
            labelText: 'Nombre de la vista',
            labelStyle: AppFonts.geist(fontSize: 13, color: AppColors.ctText2),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.ctTeal),
            ),
          ),
          onSubmitted: (_) => Navigator.of(ctx).pop(ctrl.text.trim()),
        ),
        actions: [
          AppButton(
            label: 'Cancelar',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          AppButton(
            label: 'Guardar',
            variant: AppButtonVariant.teal,
            size: AppButtonSize.sm,
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final tenantId = ref.read(activeTenantIdProvider);
    try {
      final view = await ExecutionsApi.createView(
        tenantId: tenantId,
        name:     name,
        filters:  _currentFiltersMap(),
      );
      if (!mounted) return;
      setState(() {
        _savedViews   = [..._savedViews, view];
        _activeViewId = view['id'] as String?;
        _viewsDirty   = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar vista: $e')),
      );
    }
  }

  Future<void> _deleteView(String viewId) async {
    try {
      await ExecutionsApi.deleteView(viewId: viewId);
      if (!mounted) return;
      setState(() {
        _savedViews = _savedViews.where((v) => v['id'] != viewId).toList();
        if (_activeViewId == viewId) {
          _activeViewId = null;
          _viewsDirty   = false;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al eliminar vista: $e')),
      );
    }
  }

  // ── Table header ──────────────────────────────────────────────────────────

  Widget _buildTableHeader() {
    final visible = _columns.where((c) => c.visible).toList();
    return Container(
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.ctSurface2,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: const BorderRadius.only(
          topLeft:  Radius.circular(8),
          topRight: Radius.circular(8),
        ),
      ),
      child: Row(
        children: [
          ...visible.map((col) {
            final apiField = _apiCol(col.id);
            final isSorted = _sortCol == apiField;
            final isFlow   = col.id == 'flow';
            final cell = InkWell(
              onTap: () => _onSort(apiField),
              child: SizedBox(
                height: 36,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          col.label,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.geist(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isSorted
                                ? AppColors.ctText
                                : AppColors.ctText2,
                          ),
                        ),
                      ),
                      if (isSorted) ...[
                        const SizedBox(width: 3),
                        Icon(
                          _sortDir == 'asc'
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 10,
                          color: AppColors.ctTeal,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
            return isFlow
                ? Expanded(child: cell)
                : SizedBox(width: _colWidth(col.id), child: cell);
          }),
          const SizedBox(width: 32),
        ],
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    if (_loading && _executions.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.ctTeal),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                style: AppFonts.geist(
                    fontSize: 13, color: AppColors.ctDanger)),
            const SizedBox(height: 8),
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
    if (_executions.isEmpty) {
      return Center(
        child: Text(
          'Sin ejecuciones registradas',
          style: AppFonts.geist(fontSize: 13, color: AppColors.ctText3),
        ),
      );
    }

    final items = _groupedItems();

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      decoration: const BoxDecoration(
        color: AppColors.ctSurface,
        border: Border(
          left:   BorderSide(color: AppColors.ctBorder),
          right:  BorderSide(color: AppColors.ctBorder),
          bottom: BorderSide(color: AppColors.ctBorder),
        ),
        borderRadius: BorderRadius.only(
          bottomLeft:  Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft:  Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
        child: ListView.builder(
          itemCount: items.length,
          itemBuilder: (ctx, i) {
            final item = items[i];
            if (item is _DateHeader) return _buildDateSeparator(item.label);
            return _buildExecutionRow(item as Map<String, dynamic>);
          },
        ),
      ),
    );
  }

  String _groupKeyFor(Map<String, dynamic> exec) {
    switch (_grouping) {
      case 'date':
        final raw = exec['created_at'] as String?;
        if (raw == null) return '—';
        try { return fmtDateGroupLabel(DateTime.parse(raw)); } catch (_) { return '—'; }
      case 'flow':
        return exec['flow_name'] as String?
            ?? (exec['flow_definition'] as Map?)?['name'] as String?
            ?? (exec['flow'] as Map?)?['name'] as String?
            ?? '—';
      case 'type':
        final t = exec['actor_type'] as String? ?? '';
        return switch (t) {
          'operator'    => 'Conversacional',
          'system'      => 'API',
          'tenant_user' => 'Dashboard',
          _             => t.isEmpty ? '—' : t,
        };
      case 'operator':
        return (exec['operator'] as Map?)?['name'] as String?
            ?? exec['operator_name'] as String?
            ?? '—';
      case 'status':
        final s = exec['status'] as String? ?? 'unknown';
        return _statusLabel(s);
      default:
        return '';
    }
  }

  List<dynamic> _groupedItems() {
    if (_grouping == 'none') return _executions;
    final sorted = _grouping == 'date'
        ? List<Map<String, dynamic>>.from(_executions)
        : (List<Map<String, dynamic>>.from(_executions)
            ..sort((a, b) => _groupKeyFor(a).compareTo(_groupKeyFor(b))));
    final result = <dynamic>[];
    String? lastLbl;
    for (final exec in sorted) {
      final lbl = _groupKeyFor(exec);
      if (lbl != lastLbl) {
        result.add(_DateHeader(lbl));
        lastLbl = lbl;
      }
      result.add(exec);
    }
    return result;
  }

  Widget _buildDateSeparator(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: const BoxDecoration(
        color: AppColors.ctSurface2,
        border: Border(bottom: BorderSide(color: AppColors.ctBorder)),
      ),
      child: Text(
        label,
        style: AppFonts.geist(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.ctText2,
        ),
      ),
    );
  }

  Widget _buildExecutionRow(Map<String, dynamic> exec) {
    final id = exec['execution_id'] as String?
        ?? exec['id'] as String?
        ?? '';

    final flowName = exec['flow_name'] as String?
        ?? (exec['flow_definition'] as Map<String, dynamic>?)?['name'] as String?
        ?? (exec['flow'] as Map<String, dynamic>?)?['name'] as String?;

    final operator_ = exec['operator'] as Map<String, dynamic>?;
    final worker_   = exec['worker']   as Map<String, dynamic>?;
    final status    = exec['status']   as String? ?? 'unknown';

    final channelObj  = exec['channel'] as Map<String, dynamic>?;
    final singleType = channelObj?['channel_type'] as String?
        ?? exec['channel_type'] as String?;
    final List<String> channelTypes;
    if (singleType != null) {
      channelTypes = [singleType];
    } else {
      final resolved = exec['resolved_channels'];
      if (resolved is List && resolved.isNotEmpty) {
        channelTypes = resolved
            .whereType<Map>()
            .map((c) => c['channel_type'] as String? ?? '')
            .where((t) => t.isNotEmpty)
            .toSet()
            .toList();
      } else {
        channelTypes = [];
      }
    }

    final createdStr = exec['created_at']      as String?;
    final elapsedSec = exec['elapsed_seconds'] as int?;
    final actorType  = exec['actor_type']      as String?;

    final progressMap = exec['fields_progress'] as Map<String, dynamic>?;
    final total    = (progressMap?['total']  as num?)?.toInt() ?? 0;
    final captured = (progressMap?['filled'] as num?)?.toInt() ?? 0;

    DateTime? createdDt;
    if (createdStr != null) {
      try { createdDt = DateTime.parse(createdStr); } catch (_) {}
    }

    final visible = _columns.where((c) => c.visible).toList();

    return InkWell(
      onTap: () => context.push('/executions/$id').then((_) {
        if (mounted) _load();
      }),
      child: Container(
        height: 48,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.ctBorder)),
        ),
        child: Row(
          children: [
            ...visible.map((col) {
              final isFlow = col.id == 'flow';
              final cell = Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _cellContent(
                    colId:       col.id,
                    flowName:    flowName,
                    operator_:   operator_,
                    worker_:     worker_,
                    status:      status,
                    channelTypes: channelTypes,
                    createdStr:  createdStr,
                    createdDt:   createdDt,
                    elapsedSec:  elapsedSec,
                    captured:    captured,
                    total:       total,
                    actorType:   actorType,
                  ),
                ),
              );
              return isFlow
                  ? Expanded(child: cell)
                  : SizedBox(width: _colWidth(col.id), child: cell);
            }),
            const SizedBox(
              width: 32,
              child: Center(
                child: Icon(Icons.chevron_right_rounded,
                    size: 14, color: AppColors.ctText3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cellContent({
    required String colId,
    required String? flowName,
    required Map<String, dynamic>? operator_,
    required Map<String, dynamic>? worker_,
    required String status,
    required List<String> channelTypes,
    required String? createdStr,
    required DateTime? createdDt,
    required int? elapsedSec,
    required int captured,
    required int total,
    String? actorType,
  }) {
    switch (colId) {
      case 'flow':
        return Text(
          flowName ?? '—',
          overflow: TextOverflow.ellipsis,
          style: AppFonts.geist(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: flowName != null ? AppColors.ctText : AppColors.ctText3,
          ).copyWith(
            fontStyle: flowName == null ? FontStyle.italic : FontStyle.normal,
          ),
        );
      case 'worker':
        final name = worker_?['display_name'] as String?
            ?? worker_?['name'] as String?
            ?? worker_?['id'] as String?
            ?? '—';
        return Text(
          name,
          overflow: TextOverflow.ellipsis,
          style: AppFonts.geist(fontSize: 12, color: AppColors.ctText2),
        );
      case 'type':
        final at = actorType ?? '';
        final icon = switch (at) {
          'operator'    => Icons.chat_bubble_outline_rounded,
          'system'      => Icons.code_rounded,
          'tenant_user' => Icons.dashboard_outlined,
          _             => Icons.help_outline_rounded,
        };
        return Tooltip(
          message: switch (at) {
            'operator'    => 'Conversacional',
            'system'      => 'API',
            'tenant_user' => 'Dashboard',
            _             => at.isEmpty ? '—' : at,
          },
          child: Icon(icon, size: 14, color: AppColors.ctText2),
        );
      case 'status':
        return _StatusBadge(status: status);
      case 'operator':
        final name = operator_?['name'] as String? ?? '—';
        return Text(
          name,
          overflow: TextOverflow.ellipsis,
          style: AppFonts.geist(fontSize: 12, color: AppColors.ctText2),
        );
      case 'channel':
        return _ChannelBadge(channelTypes: channelTypes);
      case 'created':
        final cell = fmtCreatedCell(createdStr);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment:  MainAxisAlignment.center,
          children: [
            Text(cell.dateLine,
                style: AppFonts.geist(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ctText,
                )),
            Text(cell.relativeLine,
                style: AppFonts.geist(
                    fontSize: 11, color: AppColors.ctText2)),
          ],
        );
      case 'elapsed':
        return Text(
          fmtElapsedSeconds(elapsedSec),
          style: AppFonts.geist(fontSize: 12, color: AppColors.ctText2),
        );
      case 'progress':
        if (total == 0) {
          return Text('—',
              style: AppFonts.geist(fontSize: 12, color: AppColors.ctText3));
        }
        return Text(
          '$captured/$total',
          style: AppFonts.geist(
            fontSize: 12,
            color: captured == total
                ? AppColors.ctOkText
                : AppColors.ctTealDark,
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Pagination ────────────────────────────────────────────────────────────

  Widget _buildPaginationFooter(int totalPages) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.ctSurface,
        border: Border(top: BorderSide(color: AppColors.ctBorder)),
      ),
      child: Row(
        children: [
          Text(
            'Pág. $_page de $totalPages  ·  $_total resultados',
            style: AppFonts.geist(fontSize: 12, color: AppColors.ctText2),
          ),
          const Spacer(),
          AppButton(
            label: '← Anterior',
            variant: AppButtonVariant.outline,
            size: AppButtonSize.sm,
            isDisabled: _page <= 1 || _loading,
            onPressed: () { setState(() => _page--); _load(); },
          ),
          const SizedBox(width: 8),
          AppButton(
            label: 'Siguiente →',
            variant: AppButtonVariant.outline,
            size: AppButtonSize.sm,
            isDisabled: _page >= totalPages || _loading,
            onPressed: () { setState(() => _page++); _load(); },
          ),
        ],
      ),
    );
  }

  // ── Column picker card ────────────────────────────────────────────────────

  // ── Export modal ────────────────────────────────────────────────────────────

  void _downloadBytes(Uint8List bytes, String filename) {
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.document.createElement('a') as html.AnchorElement
      ..href = url
      ..style.display = 'none'
      ..download = filename;
    html.document.body!.children.add(anchor);
    anchor.click();
    html.document.body!.children.remove(anchor);
    html.Url.revokeObjectUrl(url);
  }

  Future<void> _doExport() async {
    final tenantId = ref.read(activeTenantIdProvider);
    if (tenantId.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final fieldEntry = _activeFieldSearches.entries.firstOrNull;
      final bytes = await ExecutionsApi.exportExecutions(
        tenantId:    tenantId,
        status:      _filterStatus.isEmpty ? null : _filterStatus,
        workerIds:   _filterWorkerIds.isEmpty ? null : _filterWorkerIds,
        operatorIds: _filterOperatorIds.isEmpty ? null : _filterOperatorIds,
        flowIds:     _filterFlowIds.isEmpty ? null : _filterFlowIds,
        actorTypes:  _filterActorTypes.isEmpty ? null : _filterActorTypes,
        channelType: _filterChannelType,
        dateRange:   _filterDateRange,
        dateField:   _filterDateField,
        dateFrom:    _filterDateFrom,
        dateTo:      _filterDateTo,
        search:      _searchText.isEmpty ? null : _searchText,
        fieldKey:    fieldEntry?.key,
        fieldValues: fieldEntry?.value,
      );
      final now = DateTime.now();
      final filename =
          'ejecuciones_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.xlsx';
      _downloadBytes(bytes, filename);
      if (mounted) {
        setState(() {
          _exporting = false;
          _showExportModal = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _exporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar: $e'),
            backgroundColor: AppColors.ctDanger,
          ),
        );
      }
    }
  }

  Widget _buildExportFilterSummary() {
    final parts = <String>[];
    if (_filterWorkerIds.isNotEmpty) {
      final names = _filterWorkerIds.map((id) {
        final w = _availableWorkers.firstWhere(
          (w) => w['id'] == id,
          orElse: () => {'display_name': id},
        );
        return w['display_name'] as String?
            ?? w['catalog_name'] as String?
            ?? id;
      }).join(', ');
      parts.add('Workers: $names');
    }
    if (_filterStatus.isNotEmpty) {
      parts.add('Estado: ${_filterStatus.map(_statusLabel).join(', ')}');
    }
    if (_filterFlowIds.isNotEmpty) {
      final names = _filterFlowIds.map((id) {
        final flow = _availableFlows.firstWhere(
          (f) => f['id'] == id,
          orElse: () => {'name': id},
        );
        return flow['name'] as String? ?? id;
      }).join(', ');
      parts.add('Flujo: $names');
    }
    if (_filterChannelType != null) {
      parts.add('Canal: $_filterChannelType');
    }
    if (_filterDateRange != null) {
      parts.add('Fecha: ${_dateRangeLabel(_filterDateRange!)}');
    }
    if (_searchText.isNotEmpty) {
      parts.add('Búsqueda: "$_searchText"');
    }
    if (_activeFieldSearches.isNotEmpty) {
      for (final e in _activeFieldSearches.entries) {
        parts.add('${_fieldLabel(e.key)}: ${e.value.join(', ')}');
      }
    }
    return Text(
      parts.isEmpty ? 'Todas las ejecuciones' : parts.join(' · '),
      style: AppFonts.geist(fontSize: 12, color: AppColors.ctText),
    );
  }

  Widget _buildExportModal() {
    return Material(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.ctSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.ctBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('Exportar ejecuciones',
                  style: AppFonts.onest(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ctText,
                  )),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _showExportModal = false),
                child: const Icon(Icons.close_rounded,
                    size: 18, color: AppColors.ctText2),
              ),
            ]),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.ctSurface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.ctBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Filtros activos',
                      style: AppFonts.geist(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ctText2,
                      )),
                  const SizedBox(height: 6),
                  _buildExportFilterSummary(),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.info_outline_rounded,
                  size: 14, color: AppColors.ctText3),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Máximo 2,500 ejecuciones por exportación. '
                  'Si necesitas más, aplica filtros adicionales.',
                  style: AppFonts.geist(
                      fontSize: 11, color: AppColors.ctText3),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Text('Formato',
                style: AppFonts.geist(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ctText2,
                )),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.ctTealLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.ctTeal),
              ),
              child: Row(children: [
                const Icon(Icons.table_chart_outlined,
                    size: 16, color: AppColors.ctTeal),
                const SizedBox(width: 8),
                Text(
                  'XLSX — 3 hojas (Ejecuciones + Metadata + Eventos)',
                  style: AppFonts.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ctTealDark,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AppButton(
                  label: 'Cancelar',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                  isDisabled: _exporting,
                  onPressed: () => setState(() => _showExportModal = false),
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: 'Descargar XLSX',
                  variant: AppButtonVariant.teal,
                  size: AppButtonSize.sm,
                  isLoading: _exporting,
                  prefixIcon: const Icon(Icons.download_rounded, size: 14, color: AppColors.ctNavy),
                  onPressed: _doExport,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColumnPickerCard() {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(10),
      shadowColor: Colors.black12,
      child: Container(
        width: 210,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.ctSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.ctBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
              child: Text(
                'Columnas visibles',
                style: AppFonts.geist(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ctText2,
                ),
              ),
            ),
            ..._columns.map((col) => InkWell(
              onTap: () => setState(() => col.visible = !col.visible),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: col.visible
                            ? AppColors.ctTeal
                            : AppColors.ctSurface2,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: col.visible
                              ? AppColors.ctTeal
                              : AppColors.ctBorder2,
                        ),
                      ),
                      child: col.visible
                          ? const Icon(Icons.check_rounded,
                              size: 10, color: AppColors.ctNavy)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      col.label,
                      style: AppFonts.geist(
                          fontSize: 13, color: AppColors.ctText),
                    ),
                  ],
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }
}

// ── _FieldSearchTag ───────────────────────────────────────────────────────────

class _FieldSearchTag extends StatelessWidget {
  const _FieldSearchTag({
    required this.fieldKey,
    required this.values,
    required this.label,
    required this.onRemove,
    this.onEdit,
  });

  final String        fieldKey;
  final List<String>  values;
  final String        label;
  final VoidCallback  onRemove;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final displayValues = values.length <= 2
        ? values.join(', ')
        : '${values.take(2).join(', ')} +${values.length - 2}';

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 2, 4, 2),
      decoration: BoxDecoration(
        color: AppColors.ctTealLight,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.ctTeal),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MouseRegion(
            cursor: onEdit != null
                ? SystemMouseCursors.click
                : MouseCursor.defer,
            child: GestureDetector(
              onTap: onEdit,
              child: Text(
                '$label: $displayValues',
                style: AppFonts.geist(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ctTealDark,
                ),
              ),
            ),
          ),
          const SizedBox(width: 3),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded,
                size: 11, color: AppColors.ctTealDark),
          ),
        ],
      ),
    );
  }
}

// ── _ValueInput ───────────────────────────────────────────────────────────────

class _ValueInput extends StatefulWidget {
  const _ValueInput({
    required this.fieldKey,
    required this.fieldLabel,
    required this.onSubmit,
    required this.onCancel,
    this.initialValues = const [],
  });

  final String             fieldKey;
  final String             fieldLabel;
  final List<String>       initialValues;
  final void Function(List<String>) onSubmit;
  final VoidCallback       onCancel;

  @override
  State<_ValueInput> createState() => _ValueInputState();
}

class _ValueInputState extends State<_ValueInput> {
  static const int _maxValues = 200;

  final _ctrl  = TextEditingController();
  final _focus = FocusNode();
  late List<String> _values;

  @override
  void initState() {
    super.initState();
    ServicesBinding.instance.keyboard.addHandler(_handleKeyEvent);
    _values = List.from(widget.initialValues);
    _ctrl.addListener(_onTextChanged);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    ServicesBinding.instance.keyboard.removeHandler(_handleKeyEvent);
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _ctrl.text;
    if (text.contains('\n') || text.contains('\r') || text.contains('\t')) {
      _addValues(text);
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final isPaste =
          (HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed) &&
          event.logicalKey == LogicalKeyboardKey.keyV;
      if (isPaste) {
        Future.delayed(const Duration(milliseconds: 50), () async {
          final data = await Clipboard.getData('text/plain');
          if (data?.text != null && mounted) {
            _addValues(data!.text!);
          }
        });
      }
    }
    return false; // no consumir el evento
  }

  void _addValues(String raw) {
    final parts = raw
        .split(RegExp(r'[\n\r\t,]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return;
    setState(() {
      for (final v in parts) {
        if (_values.length >= _maxValues) break;
        if (!_values.contains(v)) _values.add(v);
      }
      _ctrl.clear();
    });
    widget.onSubmit(_values);
    if (_values.length >= _maxValues) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Máximo $_maxValues valores por búsqueda',
              style: AppFonts.geist(fontSize: 13, color: Colors.white),
            ),
            backgroundColor: AppColors.ctNavy,
            duration: const Duration(seconds: 3),
          ),
        );
      });
    }
  }

  void _removeValue(String v) {
    setState(() => _values.remove(v));
    widget.onSubmit(_values);
  }

  void _submit() {
    if (_ctrl.text.trim().isNotEmpty) _addValues(_ctrl.text);
    widget.onSubmit(_values);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(10),
      shadowColor: Colors.black12,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.ctSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.ctBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Text(
                  'Filtrar por ${widget.fieldLabel}',
                  style: AppFonts.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ctText2,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: widget.onCancel,
                  child: const Icon(Icons.close_rounded,
                      size: 14, color: AppColors.ctText3),
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  '${_values.length} / $_maxValues valores',
                  style: AppFonts.geist(
                    fontSize: 11,
                    color: _values.length >= _maxValues
                        ? AppColors.ctDanger
                        : AppColors.ctText3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Active value chips
            if (_values.isNotEmpty) ...[
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final v in _values)
                    _FilterChip(
                      label: v,
                      onRemove: () => _removeValue(v),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            // Text input
            TextField(
              controller: _ctrl,
              focusNode: _focus,
              style:
                  AppFonts.geist(fontSize: 13, color: AppColors.ctText),
              decoration: InputDecoration(
                hintText: 'Escribe o pega valores (Enter para añadir)',
                hintStyle:
                    AppFonts.geist(fontSize: 12, color: AppColors.ctText3),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                filled: true,
                fillColor: AppColors.ctSurface2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppColors.ctBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppColors.ctBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppColors.ctTeal),
                ),
                isDense: true,
              ),
              onChanged: (v) {
                // _onTextChanged via listener maneja el paste
                // onChanged solo para detección manual de separadores
                if (v.endsWith('\n') || v.endsWith('\t') ||
                    v.endsWith(',')) {
                  _addValues(v);
                }
              },
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) _addValues(v);
                if (_values.isNotEmpty) _submit();
              },
            ),
            const SizedBox(height: 10),
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: 'Cancelar',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                  onPressed: widget.onCancel,
                ),
                const SizedBox(width: 6),
                AppButton(
                  label: 'Aplicar',
                  variant: AppButtonVariant.teal,
                  size: AppButtonSize.sm,
                  isDisabled: _values.isEmpty && _ctrl.text.trim().isEmpty,
                  onPressed: _submit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── _StatusBadge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (status) {
      'active' || 'in_progress' =>
          (AppColors.ctTealLight, AppColors.ctTealDark, 'activa'),
      'completed' =>
          (AppColors.ctOkBg, AppColors.ctOkText, 'completada'),
      'paused' =>
          (AppColors.ctWarnBg, AppColors.ctWarnText, 'pausada'),
      'abandoned' =>
          (AppColors.ctSurface2, AppColors.ctText3, 'abandonada'),
      'escalated' =>
          (AppColors.ctRedBg, AppColors.ctRedText, 'escalada'),
      'pending_dashboard' || 'pending_review' =>
          (AppColors.ctInfoBg, AppColors.ctInfoText, 'en revisión'),
      'pending_completion' =>
          (const Color(0xFFE8F4FD), const Color(0xFF1565C0), 'completando'),
      'pending_input' =>
          (AppColors.ctWarnBg, AppColors.ctWarnText, 'esperando input'),
      'created' =>
          (const Color(0xFFF3F4F6), const Color(0xFF6B7280), 'creada'),
      'cancelled' =>
          (AppColors.ctSurface2, AppColors.ctText3, 'cancelada'),
      'failed' || 'error' =>
          (AppColors.ctRedBg, AppColors.ctRedText, 'error'),
      _ =>
          (AppColors.ctSurface2, AppColors.ctText2, status),
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

// ── _ChannelBadge ─────────────────────────────────────────────────────────────

class _ChannelBadge extends StatelessWidget {
  const _ChannelBadge({required this.channelTypes});

  final List<String> channelTypes;

  @override
  Widget build(BuildContext context) {
    if (channelTypes.isEmpty) {
      return Text('—',
          style: AppFonts.geist(fontSize: 12, color: AppColors.ctText3));
    }
    if (channelTypes.length == 1) {
      return _singleBadge(channelTypes.first);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < channelTypes.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          _singleBadge(channelTypes[i]),
        ],
      ],
    );
  }

  static Widget _singleBadge(String type) {
    final lc = type.toLowerCase();

    final (bg, bd) = switch (lc) {
      'whatsapp' || 'wa' => (const Color(0xFFE8F8EF), const Color(0xFFBBF7D0)),
      'telegram' || 'tg' => (AppColors.ctInfoBg,      const Color(0xFFBFDBFE)),
      _                  => (AppColors.ctSurface2,     AppColors.ctBorder),
    };

    final Widget logo = switch (lc) {
      'whatsapp' || 'wa' => SvgPicture.asset(
          'assets/logos/whatsapp.svg',
          width: 11, height: 11,
        ),
      'telegram' || 'tg' => Image.asset(
          'assets/logos/telegram',
          width: 11, height: 11,
        ),
      _ => const Icon(Icons.link_rounded, size: 11, color: AppColors.ctText2),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: bd),
      ),
      child: logo,
    );
  }
}

// ── _TopbarChip ───────────────────────────────────────────────────────────────

class _TopbarChip extends StatefulWidget {
  const _TopbarChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  State<_TopbarChip> createState() => _TopbarChipState();
}

class _TopbarChipState extends State<_TopbarChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: widget.active
                ? AppColors.ctTealLight
                : (_hovered ? AppColors.ctSurface2 : AppColors.ctSurface),
            border: Border.all(
              color: widget.active ? AppColors.ctTeal : AppColors.ctBorder,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 13,
                color: widget.active
                    ? AppColors.ctTealDark
                    : AppColors.ctText2,
              ),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: AppFonts.geist(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: widget.active
                      ? AppColors.ctTealDark
                      : AppColors.ctText2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _FilterChip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 3, 4, 3),
      decoration: BoxDecoration(
        color: AppColors.ctTealLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.ctTeal),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppFonts.geist(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.ctTealDark,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded,
                size: 12, color: AppColors.ctTealDark),
          ),
        ],
      ),
    );
  }
}

// ── _GroupingChip ─────────────────────────────────────────────────────────────

class _GroupingChip extends StatefulWidget {
  const _GroupingChip({required this.grouping, required this.onSelect});
  final String grouping;
  final void Function(String) onSelect;
  @override
  State<_GroupingChip> createState() => _GroupingChipState();
}

class _GroupingChipState extends State<_GroupingChip> {
  final _key = GlobalKey();

  static const _options = [
    ('none',     'Sin agrupar',   Icons.format_list_bulleted_rounded),
    ('date',     'Por fecha',     Icons.calendar_today_outlined),
    ('flow',     'Por flujo',     Icons.account_tree_outlined),
    ('type',     'Por tipo',      Icons.category_outlined),
    ('operator', 'Por operador',  Icons.person_outline_rounded),
    ('status',   'Por estatus',   Icons.circle_outlined),
  ];

  String _label() {
    for (final (v, l, _) in _options) {
      if (v == widget.grouping) return l;
    }
    return 'Sin agrupar';
  }

  void _openMenu() {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final offset     = box.localToGlobal(Offset.zero);
    final size       = box.size;
    final screenSize = MediaQuery.of(context).size;

    final items = <PopupMenuEntry<String>>[
      for (final (value, label, icon) in _options)
        PopupMenuItem<String>(
          value: value,
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 14,
                    color: widget.grouping == value
                        ? AppColors.ctTeal : AppColors.ctText2),
                const SizedBox(width: 8),
                Text(label,
                    style: AppFonts.geist(fontSize: 13,
                        color: widget.grouping == value
                            ? AppColors.ctTeal : AppColors.ctText)),
                if (widget.grouping == value) ...[
                  const Spacer(),
                  const Icon(Icons.check_rounded,
                      size: 13, color: AppColors.ctTeal),
                ],
              ],
            ),
          ),
        ),
    ];

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height + 4,
        screenSize.width - offset.dx - size.width,
        0,
      ),
      items:       items,
      color:       AppColors.ctSurface,
      elevation:   4,
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 220),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.ctBorder),
      ),
    ).then((value) {
      if (value == null || !mounted) return;
      widget.onSelect(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _TopbarChip(
      key:    _key,
      icon:   Icons.group_work_outlined,
      label:  _label(),
      active: widget.grouping != 'none',
      onTap:  _openMenu,
    );
  }
}

// ── _FilterSidebar ────────────────────────────────────────────────────────────

class _FilterSidebar extends StatefulWidget {
  const _FilterSidebar({
    required this.filterStatus,
    required this.filterChannelType,
    required this.filterDateRange,
    required this.filterDateField,
    required this.filterDateFrom,
    required this.filterDateTo,
    required this.filterOperatorIds,
    required this.availableOperators,
    required this.filterActorTypes,
    required this.filterFlowIds,
    required this.availableFlows,
    required this.onStatusToggle,
    required this.onChannelTypeSelect,
    required this.onDateRangeSelect,
    required this.onDateFieldSelect,
    required this.onDateRangeChange,
    required this.onOperatorToggle,
    required this.onActorTypeToggle,
    required this.onFlowToggle,
    required this.hasWorkers,
  });

  final List<String>                              filterStatus;
  final String?                                   filterChannelType;
  final String?                                   filterDateRange;
  final String                                    filterDateField;
  final String?                                   filterDateFrom;
  final String?                                   filterDateTo;
  final List<String>                              filterOperatorIds;
  final List<Map<String, dynamic>>                availableOperators;
  final List<String>                              filterActorTypes;
  final List<String>                              filterFlowIds;
  final List<Map<String, dynamic>>                availableFlows;
  final bool                                      hasWorkers;
  final void Function(String)                     onStatusToggle;
  final void Function(String?)                    onChannelTypeSelect;
  final void Function(String?)                    onDateRangeSelect;
  final void Function(String)                     onDateFieldSelect;
  final void Function(String?, String?, String?)  onDateRangeChange;
  final void Function(String)                     onOperatorToggle;
  final void Function(String)                     onActorTypeToggle;
  final void Function(String)                     onFlowToggle;

  @override
  State<_FilterSidebar> createState() => _FilterSidebarState();
}

class _FilterSidebarState extends State<_FilterSidebar> {
  List<Map<String, String>> _availableStatuses = [];

  @override
  void initState() {
    super.initState();
    _loadStatuses();
  }

  Future<void> _loadStatuses() async {
    final statuses = await ExecutionsApi.getExecutionStatuses();
    if (mounted) setState(() => _availableStatuses = statuses);
  }

  @override
  Widget build(BuildContext context) {
    final statuses = _availableStatuses.isNotEmpty
        ? _availableStatuses
        : [
            {'value': 'active',             'label': 'Activa'},
            {'value': 'paused',             'label': 'Pausada'},
            {'value': 'completed',          'label': 'Completada'},
            {'value': 'abandoned',          'label': 'Abandonada'},
            {'value': 'escalated',          'label': 'Escalada'},
            {'value': 'pending_completion', 'label': 'Pendiente de completar'},
            {'value': 'pending_dashboard',  'label': 'En revisión'},
            {'value': 'pending_input',      'label': 'Esperando respuesta'},
            {'value': 'created',            'label': 'Creada'},
          ];

    const channels = [
      ('whatsapp', 'WhatsApp'),
      ('telegram', 'Telegram'),
    ];

    const actorTypes = [
      ('operator',    'Conversacional'),
      ('system',      'API'),
      ('tenant_user', 'Dashboard'),
    ];

    return Container(
      width: 264,
      decoration: const BoxDecoration(
        color: AppColors.ctSurface,
        border: Border(right: BorderSide(color: AppColors.ctBorder)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          _SidebarSection(
            title: 'Estado',
            children: [
              for (final s in statuses)
                _SidebarCheckRow(
                  label:    s['label'] ?? s['value'] ?? '',
                  selected: widget.filterStatus.contains(s['value'] ?? ''),
                  onTap:    () => widget.onStatusToggle(s['value'] ?? ''),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _SidebarSection(
            title: 'Tipo',
            children: [
              for (final (value, label) in actorTypes)
                _SidebarCheckRow(
                  label:    label,
                  selected: widget.filterActorTypes.contains(value),
                  onTap:    () => widget.onActorTypeToggle(value),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _SidebarSection(
            title: 'Fecha',
            children: [
              // Selector de campo
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Campo:', style: AppFonts.geist(
                      fontSize: 11, color: AppColors.ctText2)),
                    for (final (field, label) in [
                      ('created_at',   'Creada'),
                      ('updated_at',   'Actualizada'),
                      ('completed_at', 'Completada'),
                    ])
                      GestureDetector(
                        onTap: () => widget.onDateFieldSelect(field),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: widget.filterDateField == field
                                ? AppColors.ctTeal
                                : AppColors.ctSurface2,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: widget.filterDateField == field
                                  ? AppColors.ctTeal
                                  : AppColors.ctBorder,
                            ),
                          ),
                          child: Text(label, style: AppFonts.geist(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: widget.filterDateField == field
                                ? AppColors.ctNavy
                                : AppColors.ctText2,
                          )),
                        ),
                      ),
                  ],
                ),
              ),
              // Opciones rápidas
              for (final (value, label) in [
                ('today',        'Hoy'),
                ('yesterday',    'Ayer'),
                ('last_7_days',  'Últimos 7 días'),
                ('last_30_days', 'Últimos 30 días'),
                ('this_month',   'Este mes'),
              ])
                _SidebarRadioRow(
                  label:    label,
                  selected: widget.filterDateRange == value,
                  onTap: () => widget.onDateRangeChange(
                    widget.filterDateRange == value ? null : value, null, null),
                ),
              // Rango personalizado — un solo modal con inicio + fin
              _SidebarRangePickerRow(
                filterDateFrom:   widget.filterDateFrom,
                filterDateTo:     widget.filterDateTo,
                isActive:         widget.filterDateRange == 'custom',
                onRangeSelected:  (from, to) =>
                    widget.onDateRangeChange('custom', from, to),
                onClear: () => widget.onDateRangeChange(null, null, null),
              ),
            ],
          ),
          if (widget.hasWorkers) ...[
            const SizedBox(height: 8),
            _SidebarSection(
              title: 'Canal',
              children: [
                for (final (value, label) in channels)
                  _SidebarRadioRow(
                    label:    label,
                    selected: widget.filterChannelType == value,
                    onTap:    () => widget.onChannelTypeSelect(
                        widget.filterChannelType == value ? null : value),
                  ),
              ],
            ),
          ],
          if (widget.hasWorkers && widget.availableOperators.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SidebarSection(
              title: 'Operadores',
              children: [
                for (final op in widget.availableOperators)
                  _SidebarCheckRow(
                    label: op['display_name'] as String? ??
                        op['name'] as String? ??
                        op['id'] as String? ?? '—',
                    selected: widget.filterOperatorIds.contains(op['id'] as String? ?? ''),
                    onTap: () => widget.onOperatorToggle(op['id'] as String? ?? ''),
                  ),
              ],
            ),
          ],
          if (widget.hasWorkers && widget.availableFlows.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SidebarSection(
              title: 'Flujo',
              children: [
                for (final flow in widget.availableFlows)
                  _SidebarCheckRow(
                    label: flow['name'] as String? ?? '—',
                    selected: widget.filterFlowIds.contains(flow['id'] as String? ?? ''),
                    onTap: () => widget.onFlowToggle(flow['id'] as String? ?? ''),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── _SidebarRangePickerRow ────────────────────────────────────────────────────

class _SidebarRangePickerRow extends StatelessWidget {
  const _SidebarRangePickerRow({
    required this.filterDateFrom,
    required this.filterDateTo,
    required this.isActive,
    required this.onRangeSelected,
    required this.onClear,
  });

  final String?  filterDateFrom;
  final String?  filterDateTo;
  final bool     isActive;
  final void Function(String from, String to) onRangeSelected;
  final VoidCallback onClear;


  @override
  Widget build(BuildContext context) {
    final hasRange = filterDateFrom != null || filterDateTo != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () async {
            final ctx = context;
            final startInit = filterDateFrom != null
                ? DateTime.tryParse(filterDateFrom!)?.toLocal()
                    ?? DateTime.now()
                : DateTime.now();
            final endInit = filterDateTo != null
                ? DateTime.tryParse(filterDateTo!)?.toLocal()
                    ?? DateTime.now()
                : DateTime.now();

            // ignore: use_build_context_synchronously
            final result = await showOmniDateTimeRangePicker(
              context: ctx,
              startInitialDate: startInit,
              startFirstDate: DateTime(2020),
              startLastDate: DateTime(2030, 12, 30),
              endInitialDate: endInit,
              endFirstDate: DateTime(2020),
              endLastDate: DateTime(2030, 12, 31),
              is24HourMode: true,
              isShowSeconds: false,
              isForceEndDateAfterStartDate: true,
              borderRadius: const BorderRadius.all(Radius.circular(16)),
              constraints: const BoxConstraints(
                maxWidth: 350,
                maxHeight: 650,
              ),
            );

            if (result == null || result.length < 2) return;
            onRangeSelected(
              result[0].toUtc().toIso8601String(),
              result[1].toUtc().toIso8601String(),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(children: [
              Icon(
                isActive
                    ? Icons.date_range_rounded
                    : Icons.date_range_outlined,
                size: 14,
                color: isActive ? AppColors.ctTeal : AppColors.ctText2,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Rango personalizado',
                  style: AppFonts.geist(
                    fontSize: 12,
                    fontWeight: isActive
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: isActive ? AppColors.ctTeal : AppColors.ctText,
                  ),
                ),
              ),
              if (hasRange)
                GestureDetector(
                  onTap: onClear,
                  child: const Icon(Icons.close_rounded,
                      size: 13, color: AppColors.ctText3),
                ),
            ]),
          ),
        ),
        if (hasRange)
          Padding(
            padding: const EdgeInsets.fromLTRB(34, 0, 12, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (filterDateFrom != null)
                  Text('Desde: ${fmtDateSlash(filterDateFrom!)}',
                      style: AppFonts.geist(
                          fontSize: 11, color: AppColors.ctTeal)),
                if (filterDateTo != null)
                  Text('Hasta: ${fmtDateSlash(filterDateTo!)}',
                      style: AppFonts.geist(
                          fontSize: 11, color: AppColors.ctTeal)),
              ],
            ),
          ),
      ],
    );
  }
}

// ── _SidebarSection ───────────────────────────────────────────────────────────

class _SidebarSection extends StatelessWidget {
  const _SidebarSection({required this.title, required this.children});

  final String        title;
  final List<Widget>  children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Text(
            title.toUpperCase(),
            style: AppFonts.geist(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.ctText3,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

// ── _SidebarCheckRow ──────────────────────────────────────────────────────────

class _SidebarCheckRow extends StatelessWidget {
  const _SidebarCheckRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String       label;
  final bool         selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: selected ? AppColors.ctTeal : AppColors.ctSurface,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: selected ? AppColors.ctTeal : AppColors.ctBorder2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      size: 10, color: AppColors.ctNavy)
                  : null,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppFonts.geist(
                fontSize: 13,
                color: selected ? AppColors.ctText : AppColors.ctText2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _SidebarRadioRow ──────────────────────────────────────────────────────────

class _SidebarRadioRow extends StatelessWidget {
  const _SidebarRadioRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String       label;
  final bool         selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.ctTeal : AppColors.ctBorder2,
                  width: selected ? 4.5 : 1.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppFonts.geist(
                fontSize: 13,
                color: selected ? AppColors.ctText : AppColors.ctText2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _ViewsMenu ────────────────────────────────────────────────────────────────

class _ViewsMenu extends StatefulWidget {
  const _ViewsMenu({
    required this.views,
    required this.activeViewId,
    required this.isDirty,
    required this.onSelect,
    required this.onSave,
    required this.onDelete,
  });

  final List<Map<String, dynamic>> views;
  final String?                    activeViewId;
  final bool                       isDirty;
  final void Function(Map<String, dynamic>) onSelect;
  final VoidCallback               onSave;
  final void Function(String)      onDelete;

  @override
  State<_ViewsMenu> createState() => _ViewsMenuState();
}

class _ViewsMenuState extends State<_ViewsMenu> {
  final _key = GlobalKey();

  String _label() {
    if (widget.activeViewId == null) return 'Vistas';
    final v = widget.views.firstWhere(
        (v) => v['id'] == widget.activeViewId, orElse: () => {});
    final name = v['name'] as String? ?? 'Vista';
    return widget.isDirty ? '$name ●' : name;
  }

  void _openMenu() {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final offset     = box.localToGlobal(Offset.zero);
    final size       = box.size;
    final screenSize = MediaQuery.of(context).size;

    final items = <PopupMenuEntry<String>>[
      ...widget.views.map((v) {
        final id       = v['id'] as String;
        final name     = v['name'] as String? ?? id;
        final isActive = widget.activeViewId == id;
        return PopupMenuItem<String>(
          value:   'select_$id',
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  isActive
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  size:  14,
                  color: isActive ? AppColors.ctTeal : AppColors.ctText3,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name,
                      style: AppFonts.geist(
                          fontSize: 13, color: AppColors.ctText)),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onDelete(id);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close_rounded,
                        size: 12, color: AppColors.ctText3),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
      if (widget.views.isNotEmpty) const PopupMenuDivider(height: 1),
      PopupMenuItem<String>(
        value:   'save',
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.bookmark_add_outlined,
                  size: 14, color: AppColors.ctText2),
              const SizedBox(width: 8),
              Text('Guardar vista actual',
                  style:
                      AppFonts.geist(fontSize: 13, color: AppColors.ctText)),
            ],
          ),
        ),
      ),
    ];

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height + 4,
        screenSize.width - offset.dx - size.width,
        0,
      ),
      items:       items,
      color:       AppColors.ctSurface,
      elevation:   4,
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.ctBorder),
      ),
    ).then((value) {
      if (value == null || !mounted) return;
      if (value == 'save') {
        widget.onSave();
      } else if (value.startsWith('select_')) {
        final id = value.substring(7);
        final v  = widget.views.firstWhere(
            (v) => v['id'] == id, orElse: () => {});
        if (v.isNotEmpty) widget.onSelect(v);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _TopbarChip(
      key:    _key,
      icon:   Icons.bookmarks_outlined,
      label:  _label(),
      active: widget.activeViewId != null,
      onTap:  _openMenu,
    );
  }
}
