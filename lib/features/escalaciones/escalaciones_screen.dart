import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/escalaciones_api.dart';
import '../../core/providers/escalaciones_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/screen_header.dart';
import 'widgets/escalacion_detail_sheet.dart';
import 'widgets/escalacion_list_tile.dart';

// ── Screen ────────────────────────────────────────────────────────────────────

class EscalacionesScreen extends ConsumerStatefulWidget {
  const EscalacionesScreen({super.key});

  @override
  ConsumerState<EscalacionesScreen> createState() => _EscalacionesScreenState();
}

class _EscalacionesScreenState extends ConsumerState<EscalacionesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _statuses = ['open', 'assigned', 'resolved', 'reopened'];

  final _dataByStatus = <String, List<Map<String, dynamic>>>{
    'open':     [],
    'assigned': [],
    'resolved': [],
    'reopened': [],
  };
  final _loadingByStatus = <String, bool>{
    'open':     false,
    'assigned': false,
    'resolved': false,
    'reopened': false,
  };
  final _errorByStatus = <String, String?>{
    'open':     null,
    'assigned': null,
    'resolved': null,
    'reopened': null,
  };

  String? _assignedToFilter;
  Map<String, dynamic>? _selectedEscalacion;

  String get _currentStatus => _statuses[_tabController.index];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTab('open'));
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _loadTab(_currentStatus);
  }

  Future<void> _loadTab(String status) async {
    if (!mounted) return;
    final tenantId = ref.read(activeTenantIdProvider);
    if (tenantId.isEmpty) return;

    setState(() {
      _loadingByStatus[status] = true;
      _errorByStatus[status]   = null;
    });
    try {
      final data = await EscalacionesApi.getEscalaciones(
        status:     status,
        assignedTo: _assignedToFilter,
      );
      if (!mounted) return;
      setState(() {
        _dataByStatus[status]    = data;
        _loadingByStatus[status] = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorByStatus[status]   = 'No se pudo cargar. Verifica tu conexión.';
        _loadingByStatus[status] = false;
      });
    }
  }

  void _openDetail(Map<String, dynamic> esc) {
    setState(() => _selectedEscalacion = esc);
  }

  void _closeDetail() {
    setState(() => _selectedEscalacion = null);
  }

  void _onActionDone() {
    _closeDetail();
    _loadTab(_currentStatus);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(activeTenantIdProvider, (prev, next) {
      if (next.isNotEmpty && next != prev) {
        for (final s in _statuses) {
          setState(() {
            _dataByStatus[s]    = [];
            _loadingByStatus[s] = false;
            _errorByStatus[s]   = null;
          });
        }
        _loadTab(_currentStatus);
      }
    });

    final tenantUsers =
        ref.watch(tenantUsersForEscalacionesProvider).valueOrNull ?? [];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── List panel ─────────────────────────────────────────────────────
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(tenantUsers),
              _buildTabBar(),
              Expanded(child: _buildTabViews()),
            ],
          ),
        ),

        // ── Detail panel (inline, shown on tile tap) ──────────────────────
        if (_selectedEscalacion != null) ...[
          const VerticalDivider(width: 1, thickness: 1, color: AppColors.ctBorder),
          SizedBox(
            width: 420,
            child: EscalacionDetailSheet(
              key: ValueKey(_selectedEscalacion!['id']),
              escalacion: _selectedEscalacion!,
              onActionDone: _onActionDone,
              onClose: _closeDetail,
            ),
          ),
        ],
      ],
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(List<Map<String, dynamic>> tenantUsers) {
    return ScreenHeader(
      title: 'Escalaciones',
      subtitle: 'Casos escalados pendientes de resolución',
      actions: [
        if (tenantUsers.isNotEmpty)
          _AssignedToDropdown(
            users:    tenantUsers,
            value:    _assignedToFilter,
            onChanged: (v) {
              setState(() => _assignedToFilter = v);
              _loadTab(_currentStatus);
            },
          ),
        IconButton(
          icon: const Icon(
            Icons.refresh_rounded,
            size: 20,
            color: AppColors.ctText2,
          ),
          tooltip: 'Actualizar',
          onPressed: () => _loadTab(_currentStatus),
        ),
      ],
    );
  }

  // ── Tab bar ────────────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return TabBar(
      controller:            _tabController,
      labelColor:            AppColors.ctTealDark,
      unselectedLabelColor:  AppColors.ctText2,
      indicatorColor:        AppColors.ctTeal,
      dividerColor:          AppColors.ctBorder,
      labelStyle:            AppTextStyles.formLabel.copyWith(fontSize: 13),
      unselectedLabelStyle:  AppTextStyles.body.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.ctText2,
      ),
      tabs: const [
        Tab(text: 'Abiertas'),
        Tab(text: 'Asignadas'),
        Tab(text: 'Resueltas'),
        Tab(text: 'Reabiertas'),
      ],
    );
  }

  // ── Tab views ──────────────────────────────────────────────────────────────

  Widget _buildTabViews() {
    return TabBarView(
      controller: _tabController,
      children: _statuses.map(_buildTabContent).toList(),
    );
  }

  Widget _buildTabContent(String status) {
    final loading = _loadingByStatus[status] ?? false;
    final error   = _errorByStatus[status];
    final items   = _dataByStatus[status] ?? [];

    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.ctTeal),
      );
    }

    if (error != null) {
      return _ErrorState(message: error, onRetry: () => _loadTab(status));
    }

    if (items.isEmpty) {
      return _EmptyState(status: status);
    }

    return ListView.separated(
      padding:          const EdgeInsets.fromLTRB(20, 12, 20, 20),
      itemCount:        items.length,
      separatorBuilder: (_, i) => const SizedBox(height: 8),
      itemBuilder:      (_, i) => EscalacionListTile(
        key:          ValueKey(items[i]['id']),
        escalacion:   items[i],
        onTap:        () => _openDetail(items[i]),
      ),
    );
  }
}

// ── AssignedTo filter dropdown ────────────────────────────────────────────────

class _AssignedToDropdown extends StatelessWidget {
  const _AssignedToDropdown({
    required this.users,
    required this.value,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> users;
  final String?                    value;
  final ValueChanged<String?>      onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      height: 36,
      child: DropdownButtonFormField<String>(
        key:          ValueKey(value),
        initialValue: value,
        isExpanded:   true,
        style:       AppTextStyles.body.copyWith(fontSize: 12),
        hint: Text(
          'Asignado a',
          style: AppTextStyles.caption.copyWith(fontSize: 12),
        ),
        decoration: InputDecoration(
          filled:           true,
          fillColor:        AppColors.ctSurface,
          isDense:          true,
          contentPadding:   const EdgeInsets.symmetric(
            horizontal: 10,
            vertical:    8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:   const BorderSide(color: AppColors.ctBorder2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:   const BorderSide(color: AppColors.ctBorder2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:   const BorderSide(color: AppColors.ctTeal),
          ),
        ),
        items: [
          const DropdownMenuItem<String>(
            value: null,
            child: Text('Todos'),
          ),
          ...users.map((u) {
            final id   = u['id']    as String? ?? u['user_id'] as String? ?? '';
            final name = u['name']  as String? ?? u['email']   as String? ?? id;
            return DropdownMenuItem<String>(
              value: id,
              child: Text(name, overflow: TextOverflow.ellipsis),
            );
          }),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

// ── Empty & error states ──────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.status});
  final String status;

  String get _label => switch (status) {
    'open'     => 'No hay escalaciones abiertas',
    'assigned' => 'No hay escalaciones asignadas',
    'resolved' => 'No hay escalaciones resueltas',
    'reopened' => 'No hay escalaciones reabiertas',
    _          => 'Sin resultados',
  };

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.warning_amber_outlined,
            size: 48,
            color: AppColors.ctText3,
          ),
          const SizedBox(height: 12),
          Text(
            _label,
            style: AppTextStyles.pageTitle.copyWith(
              fontSize: 16,
              color: AppColors.ctText2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String       message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline,
            size:  40,
            color: AppColors.ctDanger,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: AppTextStyles.pageSubtitle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          AppButton(
            label: 'Reintentar',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
