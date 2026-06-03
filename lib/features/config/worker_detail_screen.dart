import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/ai_workers_api.dart';
import '../../core/api/flows_api.dart';
import '../../core/api/groups_api.dart';
import '../../core/api/operator_roles_api.dart';
import '../../core/providers/tenant_provider.dart';
import 'widgets/participants_widget.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_badge.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_detail_header.dart';
import '../../shared/widgets/app_loading_state.dart';
import '../../shared/widgets/app_search_bar.dart';
import '../../shared/widgets/app_stacked_metric_card.dart';
import 'channel_detail_screen.dart';
import 'channels_screen.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_wizard_shell.dart';
import '../flows/flow_detail_screen.dart';

// ── Helpers de archivo ────────────────────────────────────────────────────────

const _kTypeConfig = {
  'logistics':   (label: 'Logística', bg: Color(0xFFDBEAFE), fg: Color(0xFF1E40AF)),
  'sales':       (label: 'Ventas',    bg: Color(0xFFEDE9FE), fg: Color(0xFF6D28D9)),
  'collections': (label: 'Cobranza', bg: Color(0xFFFEF3C7), fg: Color(0xFFB45309)),
  'custom':      (label: 'Custom',   bg: Color(0xFFF3F4F6), fg: Color(0xFF374151)),
};

Color _hexColor(String hex) {
  final h = hex.replaceAll('#', '');
  return Color(int.parse('FF$h', radix: 16));
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  return name.isEmpty ? '?' : name[0].toUpperCase();
}

const _kMeses = [
  'ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic',
];

String _fmtContractDate(String? iso) {
  if (iso == null) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.day} ${_kMeses[dt.month - 1]} ${dt.year}';
  } catch (_) {
    return '—';
  }
}

class WorkerDetailScreen extends ConsumerStatefulWidget {
  const WorkerDetailScreen({required this.workerId, super.key});
  final String workerId;

  @override
  ConsumerState<WorkerDetailScreen> createState() =>
      _WorkerDetailScreenState();
}

class _WorkerDetailScreenState extends ConsumerState<WorkerDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  Map<String, dynamic>? _worker;
  bool _loading = true;
  String? _error;
  String? _selectedChannelId;
  int _activeChannelCount = 0;
  String? _selectedFlowId;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final selectedFlow = GoRouterState.of(context)
          .uri
          .queryParameters['selectedFlow'];
      if (selectedFlow != null && selectedFlow.isNotEmpty) {
        setState(() {
          _selectedFlowId = selectedFlow;
          _tabCtrl.animateTo(2);
        });
      }
      _load();
    });
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
    });
    try {
      final workers = await AiWorkersApi.listTenantWorkers();
      final worker = workers.firstWhere(
        (w) => (w['id'] as String?) == widget.workerId,
        orElse: () => <String, dynamic>{},
      );
      if (!mounted) return;
      setState(() {
        _worker = worker.isNotEmpty ? worker : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String get _workerName =>
      _worker?['display_name'] as String? ??
      _worker?['catalog_name'] as String? ??
      'Worker';

  Widget _buildAvatar() {
    final avatarUrl = _worker?['catalog_icon_url'] as String?;
    if (avatarUrl != null) {
      return Image.network(
        avatarUrl,
        fit: BoxFit.cover,
        width: 40,
        height: 40,
        errorBuilder: (context2, err, stack) {
          debugPrint('Avatar load error: $err');
          return const Icon(Icons.smart_toy_rounded, size: 22, color: AppColors.ctText2);
        },
      );
    }
    return const Icon(Icons.smart_toy_rounded, size: 22, color: AppColors.ctText2);
  }

  PreferredSize get _tabBar => PreferredSize(
        preferredSize: const Size.fromHeight(44),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.ctSurface,
            border: Border(
              bottom: BorderSide(color: AppColors.ctBorder, width: 1),
            ),
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
              Tab(text: 'Canales'),
              Tab(text: 'Torres de Control'),
              Tab(text: 'Flujos'),
            ],
          ),
        ),
      );

  AppDetailHeader _buildHeader() {
    if (_loading) {
      return AppDetailHeader(
        title: '',
        backLabel: 'Mis Workers',
        onBack: () => context.go('/workers'),
        bottom: _tabBar,
      );
    }

    final isActive = _worker?['is_active'] == true;

    return AppDetailHeader(
      title: _workerName,
      backLabel: 'Mis Workers',
      onBack: () => context.go('/workers'),
      subtitle: _worker?['catalog_name'] as String?,
      avatar: _buildAvatar(),
      statusLabel: isActive ? 'Activo' : 'Inactivo',
      statusActive: isActive,
      bottom: _tabBar,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.ctBg,
        appBar: _buildHeader(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: AppColors.ctDanger),
              const SizedBox(height: 12),
              Text(
                _error!,
                style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
              ),
              const SizedBox(height: 16),
              AppButton(
                variant: AppButtonVariant.ghost,
                label: 'Reintentar',
                onPressed: _load,
              ),
            ],
          ),
        ),
      );
    }

    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.ctBg,
        appBar: _buildHeader(),
        body: const AppLoadingState(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.ctBg,
      appBar: _buildHeader(),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _ConfigTab(
            worker: _worker ?? {},
            onWorkerUpdated: _load,
            onTabCanales: () => _tabCtrl.animateTo(1),
            onTabFlujos: () => _tabCtrl.animateTo(2),
          ),
          _selectedChannelId != null
              ? ChannelDetailPanel(
                  key: ValueKey(_selectedChannelId),
                  channelId: _selectedChannelId!,
                  onBack: () => setState(() => _selectedChannelId = null),
                )
              : Column(
                  children: [
                    if (_activeChannelCount == 0)
                      Container(
                        margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.ctWarnBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.ctWarnText.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: AppColors.ctWarnText, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Este worker no tiene canales activos — los operadores no pueden recibir ni enviar mensajes.',
                                style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.ctWarnText),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ChannelsScreen(
                        tenantWorkerId: widget.workerId,
                        onChannelSelected: (id) =>
                            setState(() => _selectedChannelId = id),
                        onActiveCountChanged: (count) =>
                            setState(() => _activeChannelCount = count),
                      ),
                    ),
                  ],
                ),
          _ControlTowersTab(workerId: widget.workerId),
          _selectedFlowId == null
              ? _WorkerFlowsTab(
                  workerId: widget.workerId,
                  onFlowSelected: (id) => setState(() => _selectedFlowId = id),
                )
              : FlowDetailPanel(
                  flowId: _selectedFlowId!,
                  onBack: () => setState(() => _selectedFlowId = null),
                ),
        ],
      ),
    );
  }
}

// ── _ConfigTab ─────────────────────────────────────────────────────────────────

class _ConfigTab extends StatefulWidget {
  const _ConfigTab({
    required this.worker,
    required this.onWorkerUpdated,
    this.onTabCanales,
    this.onTabFlujos,
  });

  final Map<String, dynamic> worker;
  final VoidCallback onWorkerUpdated;
  final VoidCallback? onTabCanales;
  final VoidCallback? onTabFlujos;

  @override
  State<_ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends State<_ConfigTab> {
  bool _showFireModal = false;
  bool _firingWorker = false;
  final TextEditingController _confirmCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _confirmCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  String get _workerName =>
      widget.worker['display_name'] as String? ??
      widget.worker['catalog_name'] as String? ??
      'Worker';

  Future<void> _fireWorker() async {
    if (_confirmCtrl.text.trim() != _workerName) return;
    setState(() { _firingWorker = true; });
    try {
      await AiWorkersApi.fireWorker(widget.worker['id'] as String);
      if (!mounted) return;
      setState(() { _showFireModal = false; _firingWorker = false; });
      context.go('/workers');
    } catch (e) {
      if (!mounted) return;
      setState(() { _firingWorker = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: _buildContent(),
        ),
        if (_showFireModal) _buildFireModal(),
      ],
    );
  }

  Widget _buildContent() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Columna izquierda ─────────────────────────────────────────────
        Expanded(
          flex: 5,
          child: Column(
            children: [
              _IdentityCard(worker: widget.worker, onSaved: widget.onWorkerUpdated),
              const SizedBox(height: 16),
              _StatusCard(worker: widget.worker, onSaved: widget.onWorkerUpdated),
              const SizedBox(height: 16),
              _DangerZoneCard(onFire: () {
                _confirmCtrl.clear();
                setState(() { _showFireModal = true; });
              }),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // ── Columna derecha ───────────────────────────────────────────────
        Expanded(
          flex: 7,
          child: Column(
            children: [
              _MetricsCard(
                worker: widget.worker,
                onTabCanales: widget.onTabCanales,
                onTabFlujos: widget.onTabFlujos,
              ),
              const SizedBox(height: 16),
              _SkillsCard(worker: widget.worker),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInitialsAvatar(double size) {
    final colorHex = widget.worker['catalog_color'] as String? ?? '#59E0CC';
    final name = _workerName;
    final color = _hexColor(colorHex);
    return Container(
      width: size,
      height: size,
      color: color.withValues(alpha: 0.18),
      alignment: Alignment.center,
      child: Text(
        _initials(name),
        style: AppTextStyles.formLabel.copyWith(
          fontFamily: 'Onest',
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildFireModal() {
    final workerName = _workerName;
    final iconUrl    = widget.worker['catalog_icon_url'] as String?;
    final workerType = _kTypeConfig[
          widget.worker['catalog_worker_type'] as String? ?? 'custom'
        ]?.label ?? 'Custom';

    return Stack(
      children: [
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
              color: AppColors.ctDanger.withValues(alpha: 0.10)),
        ),
        Center(
          child: Container(
            width: 500,
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85),
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: AppColors.ctSurface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: AppColors.ctDanger.withValues(alpha: 0.15),
                    blurRadius: 40,
                    offset: const Offset(0, 8)),
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: AppColors.ctRedBg,
                              borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.warning_amber_rounded,
                              color: AppColors.ctDanger, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '¿Despedir a $workerName?',
                                style: AppTextStyles.pageTitle
                                    .copyWith(fontSize: 18),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Esta acción no se puede deshacer. El worker será removido de tu operación de forma permanente.',
                                style: AppTextStyles.navItem
                                    .copyWith(color: AppColors.ctText2),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() {
                            _showFireModal = false;
                            _confirmCtrl.clear();
                          }),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: const Icon(Icons.close,
                                size: 18, color: AppColors.ctText3),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Qué ocurrirá
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: AppColors.ctBg,
                          borderRadius: BorderRadius.circular(10)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'QUÉ OCURRIRÁ',
                            style: AppTextStyles.navItem.copyWith(
                                color: AppColors.ctText3,
                                letterSpacing: 0.6,
                                fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          _ImpactRow(
                            icon: Icons.hub_outlined,
                            text:
                                '${widget.worker['channel_count'] ?? 0} canales desactivados inmediatamente',
                          ),
                          const SizedBox(height: 8),
                          _ImpactRow(
                            icon: Icons.chat_bubble_outline_rounded,
                            text:
                                'Historial de mensajes eliminado permanentemente',
                          ),
                          const SizedBox(height: 8),
                          _ImpactRow(
                            icon: Icons.account_tree_outlined,
                            text:
                                '${(widget.worker['flows'] as List? ?? []).length} flujos liberados de la operación',
                          ),
                          const SizedBox(height: 8),
                          _ImpactRow(
                            icon: Icons.bar_chart_rounded,
                            text:
                                'Las ejecuciones completadas se conservan en reportes',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Mini-card del worker
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.ctRedBg.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.ctDanger.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: AppColors.ctDanger
                                      .withValues(alpha: 0.3),
                                  width: 1.5),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: iconUrl != null
                                  ? Image.network(
                                      iconUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (ctx2, err, stack) =>
                                          _buildInitialsAvatar(36),
                                    )
                                  : _buildInitialsAvatar(36),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(workerName,
                                  style: AppTextStyles.body
                                      .copyWith(fontWeight: FontWeight.w600)),
                              Text(
                                '$workerType · ${widget.worker['channel_count'] ?? 0} canales · ${(widget.worker['flows'] as List? ?? []).length} flujos',
                                style: AppTextStyles.navItem
                                    .copyWith(color: AppColors.ctText2),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Confirmación
                    Text('Escribe "$workerName" para confirmar:',
                        style: AppTextStyles.formLabel),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _confirmCtrl,
                      autofocus: false,
                      style: AppTextStyles.body,
                      decoration: InputDecoration(
                        hintText: workerName,
                        hintStyle: AppTextStyles.navItem
                            .copyWith(color: AppColors.ctText3),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: AppColors.ctBorder)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: AppColors.ctDanger, width: 1.5)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: AppColors.ctBorder)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Botones
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            label: 'Cancelar',
                            variant: AppButtonVariant.ghost,
                            onPressed: () => setState(() {
                              _showFireModal = false;
                              _confirmCtrl.clear();
                            }),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppButton(
                            label: 'Sí, despedir a $workerName',
                            variant: AppButtonVariant.danger,
                            isLoading: _firingWorker,
                            isDisabled: _confirmCtrl.text.trim() !=
                                workerName.trim(),
                            onPressed: _fireWorker,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── _ImpactRow ────────────────────────────────────────────────────────────────

class _ImpactRow extends StatelessWidget {
  const _ImpactRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.ctText2),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.navItem.copyWith(color: AppColors.ctText2),
          ),
        ),
      ],
    );
  }
}

// ── _SectionCard ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.titleColor, // ignore: unused_element_parameter
    this.borderColor, // ignore: unused_element_parameter
    this.backgroundColor, // ignore: unused_element_parameter
  });

  final String title;
  final Widget child;
  final Color? titleColor;
  final Color? borderColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.ctSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor ?? AppColors.ctBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              title,
              style: AppTextStyles.formLabel.copyWith(
                fontFamily: 'Onest',
                fontWeight: FontWeight.w700,
                color: titleColor ?? AppColors.ctText,
              ),
            ),
          ),
          const SizedBox(height: 12),
          child,
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── _IdentityCard ─────────────────────────────────────────────────────────────

class _IdentityCard extends StatefulWidget {
  const _IdentityCard({required this.worker, required this.onSaved});

  final Map<String, dynamic> worker;
  final VoidCallback onSaved;

  @override
  State<_IdentityCard> createState() => _IdentityCardState();
}

class _IdentityCardState extends State<_IdentityCard> {
  bool _editingName = false;
  late TextEditingController _nameCtrl;
  bool _savingName = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
      text: widget.worker['display_name'] as String? ??
          widget.worker['catalog_name'] as String? ??
          '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    if (_savingName) return;
    setState(() => _savingName = true);
    try {
      await AiWorkersApi.updateWorker(
        tenantWorkerId: widget.worker['id'] as String,
        displayName: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() { _editingName = false; _savingName = false; });
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingName = false);
    }
  }

  String _fmtContractedAt() =>
      _fmtContractDate(widget.worker['contracted_at'] as String?);

  @override
  Widget build(BuildContext context) {
    final colorHex   = widget.worker['catalog_color'] as String? ?? '#59E0CC';
    final workerType = widget.worker['catalog_worker_type'] as String? ?? 'custom';
    final iconUrl    = widget.worker['catalog_icon_url'] as String?;
    final workerColor = _hexColor(colorHex);
    final typeEntry  = _kTypeConfig[workerType] ?? _kTypeConfig['custom']!;
    final name       = widget.worker['display_name'] as String? ??
        widget.worker['catalog_name'] as String? ??
        'Worker';
    final initials   = _initials(name);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Identidad del worker',
            style: AppTextStyles.body.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.ctText2,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar 56×56
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: workerColor, width: 2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: iconUrl != null
                        ? Image.network(
                            iconUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context2, err, stack) =>
                                _InitialAvatar(
                                    color: workerColor, initials: initials),
                          )
                        : _InitialAvatar(
                            color: workerColor, initials: initials),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Nombre + badge
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_editingName)
                      GestureDetector(
                        onTap: () => setState(() => _editingName = true),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.text,
                          child: Text(
                            _nameCtrl.text,
                            style: AppTextStyles.pageTitle
                                .copyWith(fontSize: 18),
                          ),
                        ),
                      )
                    else
                      TextField(
                        controller: _nameCtrl,
                        autofocus: true,
                        style: AppTextStyles.pageTitle.copyWith(fontSize: 18),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide:
                                const BorderSide(color: AppColors.ctTeal),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                                color: AppColors.ctTeal, width: 1.5),
                          ),
                        ),
                        onSubmitted: (_) => _saveName(),
                      ),
                    const SizedBox(height: 6),
                    _TypeBadge(
                      label: typeEntry.label,
                      bg: typeEntry.bg,
                      fg: typeEntry.fg,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_editingName) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: 'Cancelar',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                  onPressed: () => setState(() {
                    _editingName = false;
                    _nameCtrl.text = widget.worker['display_name'] as String? ??
                        widget.worker['catalog_name'] as String? ??
                        '';
                  }),
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: 'Guardar',
                  variant: AppButtonVariant.teal,
                  size: AppButtonSize.sm,
                  isLoading: _savingName,
                  onPressed: _saveName,
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.ctBorder),
          const SizedBox(height: 16),
          Text(
            widget.worker['catalog_description'] as String? ?? '—',
            style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 14, color: AppColors.ctText3),
              const SizedBox(width: 6),
              Text(
                'CONTRATADO DESDE',
                style: AppTextStyles.navItem.copyWith(
                    color: AppColors.ctText3, letterSpacing: 0.5),
              ),
              const Spacer(),
              Text(
                _fmtContractedAt(),
                style: AppTextStyles.body
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── _StatusCard ───────────────────────────────────────────────────────────────

class _StatusCard extends StatefulWidget {
  const _StatusCard({required this.worker, required this.onSaved});

  final Map<String, dynamic> worker;
  final VoidCallback onSaved;

  @override
  State<_StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends State<_StatusCard> {
  bool _togglingActive = false;

  Future<void> _toggleActive() async {
    final current = widget.worker['is_active'] == true;
    setState(() { _togglingActive = true; });
    try {
      await AiWorkersApi.updateWorker(
        tenantWorkerId: widget.worker['id'] as String,
        isActive: !current,
      );
      if (!mounted) return;
      setState(() { _togglingActive = false; });
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() { _togglingActive = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.worker['is_active'] == true;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estado del worker',
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.ctText2,
                  ),
                ),
                const SizedBox(height: 12),
                if (isActive)
                  Text(
                    'Worker activo',
                    style: AppTextStyles.body
                        .copyWith(fontWeight: FontWeight.w600),
                  )
                else
                  Text(
                    'Worker inactivo',
                    style: AppTextStyles.body
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                const SizedBox(height: 2),
                Text(
                  isActive
                      ? 'Recibiendo mensajes y ejecutando flujos'
                      : 'No procesa mensajes entrantes',
                  style: AppTextStyles.navItem
                      .copyWith(color: AppColors.ctText2),
                ),
              ],
            ),
          ),
          _togglingActive
              ? const SizedBox(
                  width: 36,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.ctTeal,
                  ),
                )
              : Switch(
                  value: isActive,
                  onChanged: (_) => _toggleActive(),
                  activeThumbColor: AppColors.ctTeal,
                  activeTrackColor:
                      AppColors.ctTeal.withValues(alpha: 0.3),
                ),
        ],
      ),
    );
  }
}

// ── _DangerZoneCard ───────────────────────────────────────────────────────────

class _DangerZoneCard extends StatelessWidget {
  const _DangerZoneCard({required this.onFire});

  final VoidCallback onFire;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.ctRedBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ctDanger.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 16, color: AppColors.ctDanger),
              const SizedBox(width: 6),
              Text(
                'Zona de peligro',
                style: AppTextStyles.formLabel.copyWith(
                  fontFamily: 'Onest',
                  fontWeight: FontWeight.w700,
                  color: AppColors.ctDanger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Despedir al worker',
                      style: AppTextStyles.formLabel.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.ctText),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Se abandonarán ejecuciones activas y se desactivarán canales y flujos.',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.ctText2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AppButton(
                variant: AppButtonVariant.danger,
                label: 'Despedir',
                onPressed: onFire,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── _MetricsCard ──────────────────────────────────────────────────────────────

class _MetricsCard extends StatelessWidget {
  const _MetricsCard({
    required this.worker,
    this.onTabCanales,
    this.onTabFlujos,
  });

  final Map<String, dynamic> worker;
  final VoidCallback? onTabCanales;
  final VoidCallback? onTabFlujos;

  @override
  Widget build(BuildContext context) {
    final flows = (worker['flows'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final channelCount   = worker['channel_count'] as int? ?? 0;
    final executionCount = worker['execution_count'] as int? ?? 0;
    final flowCount      = flows.length;
    final completedToday = flows.fold<int>(
        0, (sum, f) => sum + ((f['completed_today'] as int?) ?? 0));
    final colorHex   = worker['catalog_color'] as String? ?? '#59E0CC';
    final workerColor = _hexColor(colorHex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Métricas de operación',
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: AppStackedMetricCard(
                value: executionCount.toString(),
                label: 'Total ejecuciones',
                icon: Icons.bolt_rounded,
                accentColor: workerColor,
                accentBgColor: workerColor.withValues(alpha: 0.12),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppStackedMetricCard(
                value: completedToday.toString(),
                label: 'Completadas hoy',
                icon: Icons.check_circle_outline_rounded,
                accentColor: AppColors.ctOk,
                accentBgColor: AppColors.ctOkBg,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: AppStackedMetricCard(
                value: channelCount.toString(),
                label: 'Canales activos',
                icon: Icons.hub_outlined,
                accentColor: AppColors.ctInfo,
                accentBgColor: AppColors.ctInfoBg,
                onTap: onTabCanales,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppStackedMetricCard(
                value: flowCount.toString(),
                label: 'Flujos activos',
                icon: Icons.account_tree_outlined,
                accentColor: AppColors.ctWarn,
                accentBgColor: AppColors.ctWarnBg,
                onTap: onTabFlujos,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── _InitialAvatar ────────────────────────────────────────────────────────────

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
        style: AppTextStyles.formLabel.copyWith(
          fontFamily: 'Onest',
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ── _TypeBadge ────────────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label, required this.bg, required this.fg});

  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: AppTextStyles.badge.copyWith(color: fg),
      ),
    );
  }
}

// ── _SkillsCard ───────────────────────────────────────────────────────────────

class _SkillsCard extends StatelessWidget {
  const _SkillsCard({required this.worker});

  final Map<String, dynamic> worker;

  @override
  Widget build(BuildContext context) {
    final skills = (worker['catalog_skills'] as List?)?.cast<String>() ?? [];

    return _SectionCard(
      title: 'Habilidades del worker',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (skills.isEmpty)
              Text('Sin habilidades definidas',
                  style: AppTextStyles.navItem.copyWith(color: AppColors.ctText3))
            else
              Column(
                children: skills.map((skill) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.ctBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.ctTeal,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(skill, style: AppTextStyles.body.copyWith(color: AppColors.ctText)),
                    ],
                  ),
                )).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

// ── _WorkerFlowsTab ─────────────────────────────────────────────────────────

class _WorkerFlowsTab extends ConsumerStatefulWidget {
  const _WorkerFlowsTab({
    required this.workerId,
    required this.onFlowSelected,
  });
  final String workerId;
  final void Function(String flowId) onFlowSelected;

  @override
  ConsumerState<_WorkerFlowsTab> createState() => _WorkerFlowsTabState();
}

class _WorkerFlowsTabState extends ConsumerState<_WorkerFlowsTab> {
  List<Map<String, dynamic>> _flows = [];
  Map<String, String> _roleNames = {};
  bool _loading = true;
  String? _error;
  String _search = '';
  String _viewMode = 'roles';
  final Map<String, bool> _collapsedRoles = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tenantId = ref.read(activeTenantIdProvider);
      final results = await Future.wait([
        FlowsApi.getFlowsByWorker(tenantWorkerId: widget.workerId),
        OperatorRolesApi.listRoles(tenantId: tenantId),
      ]);
      if (!mounted) return;
      final flows = List<Map<String, dynamic>>.from(results[0] as List);
      final roles = List<Map<String, dynamic>>.from(
          (results[1] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
      setState(() {
        _flows = flows;
        _roleNames = {
          for (final r in roles)
            (r['id'] as String? ?? ''): (r['label'] as String? ?? r['name'] as String? ?? ''),
        };
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _flows;
    final q = _search.toLowerCase();
    return _flows.where((f) {
      final name = (f['name'] as String? ?? '').toLowerCase();
      final slug = (f['slug'] as String? ?? '').toLowerCase();
      return name.contains(q) || slug.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
          child: Row(
            children: [
              Text('Flujos de trabajo',
                  style: AppTextStyles.body.copyWith(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const Spacer(),
              AppButton(
                label: '+ Nuevo flujo',
                variant: AppButtonVariant.teal,
                size: AppButtonSize.sm,
                onPressed: () {
                  final tenantId = ref.read(activeTenantIdProvider);
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => _NewFlowDialog(
                      tenantId: tenantId,
                      workerId: widget.workerId,
                      onCreated: (_) => _load(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Controls
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(
            children: [
              Expanded(
                child: AppSearchBar(
                  hint: 'Buscar por nombre o slug\u2026',
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 12),
              _ViewToggle(
                value: _viewMode,
                onChanged: (v) => setState(() => _viewMode = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Body
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ctTeal),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctDanger)),
            const SizedBox(height: 8),
            AppButton(label: 'Reintentar', variant: AppButtonVariant.ghost, size: AppButtonSize.sm, onPressed: _load),
          ],
        ),
      );
    }
    final flows = _filtered;
    if (_flows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_tree_outlined, size: 40, color: AppColors.ctText3),
            const SizedBox(height: 12),
            Text('Sin flujos configurados',
                style: AppTextStyles.body.copyWith(color: AppColors.ctText2)),
          ],
        ),
      );
    }
    if (flows.isEmpty) {
      return Center(
        child: Text('Sin resultados para \u00AB$_search\u00BB',
            style: AppTextStyles.body.copyWith(color: AppColors.ctText2)),
      );
    }
    if (_viewMode == 'roles') {
      return _buildRolesView(flows);
    }
    return _buildListView(flows);
  }

  Widget _buildListView(List<Map<String, dynamic>> flows) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
      itemCount: flows.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _WorkerFlowCard(
        flow: flows[i],
        onTap: () => widget.onFlowSelected(flows[i]['id'] as String? ?? ''),
      ),
    );
  }

  Widget _buildRolesView(List<Map<String, dynamic>> flows) {
    // Collect all role IDs referenced
    final roleGroups = <String, List<Map<String, dynamic>>>{};
    final noRole = <Map<String, dynamic>>[];

    for (final f in flows) {
      final roleIds = (f['allowed_role_ids'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      if (roleIds.isEmpty) {
        noRole.add(f);
      } else {
        for (final rid in roleIds) {
          roleGroups.putIfAbsent(rid, () => []).add(f);
        }
      }
    }

    final sortedKeys = roleGroups.keys.toList()
      ..sort((a, b) => (_roleNames[a] ?? a).compareTo(_roleNames[b] ?? b));

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
      children: [
        for (final rid in sortedKeys)
          _RoleGroup(
            roleName: _roleNames[rid] ?? 'Rol ${rid.substring(0, 8)}\u2026',
            flows: roleGroups[rid]!,
            isCollapsed: _collapsedRoles[rid] ?? false,
            onToggle: () => setState(() =>
                _collapsedRoles[rid] = !(_collapsedRoles[rid] ?? false)),
            onFlowSelected: widget.onFlowSelected,
          ),
        if (noRole.isNotEmpty)
          _RoleGroup(
            roleName: 'Sin rol asignado',
            flows: noRole,
            isCollapsed: _collapsedRoles['__none__'] ?? false,
            onToggle: () => setState(() =>
                _collapsedRoles['__none__'] = !(_collapsedRoles['__none__'] ?? false)),
            onFlowSelected: widget.onFlowSelected,
          ),
      ],
    );
  }
}

// ── _ViewToggle ──────────────────────────────────────────────────────────────

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.ctSurface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleItem('list', 'Lista', value == 'list'),
          _toggleItem('roles', 'Por rol', value == 'roles'),
        ],
      ),
    );
  }

  Widget _toggleItem(String key, String label, bool active) {
    return GestureDetector(
      onTap: () => onChanged(key),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: active ? AppColors.ctSurface : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            boxShadow: active
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 2)]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? AppColors.ctText : AppColors.ctText2,
            ),
          ),
        ),
      ),
    );
  }
}

// ── _RoleGroup ───────────────────────────────────────────────────────────────

class _RoleGroup extends StatelessWidget {
  const _RoleGroup({
    required this.roleName,
    required this.flows,
    required this.isCollapsed,
    required this.onToggle,
    required this.onFlowSelected,
  });
  final String roleName;
  final List<Map<String, dynamic>> flows;
  final bool isCollapsed;
  final VoidCallback onToggle;
  final void Function(String) onFlowSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ctBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header
          GestureDetector(
            onTap: onToggle,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.ctSurface,
                  border: isCollapsed
                      ? null
                      : const Border(bottom: BorderSide(color: AppColors.ctBorder)),
                ),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: isCollapsed ? 0 : 0.25,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.chevron_right_rounded,
                          size: 18, color: AppColors.ctText2),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(roleName,
                          style: AppTextStyles.body.copyWith(
                              fontFamily: 'Onest',
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: AppColors.ctText)),
                    ),
                    AppBadge(
                      label: '${flows.length}',
                      variant: AppBadgeVariant.neutral,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Flows
          if (!isCollapsed)
            ...flows.map((f) => _WorkerFlowCard(
                  flow: f,
                  onTap: () => onFlowSelected(f['id'] as String? ?? ''),
                )),
        ],
      ),
    );
  }
}

// ── _WorkerFlowCard ──────────────────────────────────────────────────────────

class _WorkerFlowCard extends StatefulWidget {
  const _WorkerFlowCard({required this.flow, required this.onTap});
  final Map<String, dynamic> flow;
  final VoidCallback onTap;

  @override
  State<_WorkerFlowCard> createState() => _WorkerFlowCardState();
}

class _WorkerFlowCardState extends State<_WorkerFlowCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.flow;
    final name = f['name'] as String? ?? '\u2014';
    final slug = f['slug'] as String? ?? '';
    final desc = f['description'] as String? ?? '';
    final isActive = f['is_active'] as bool? ?? false;
    final fields = f['fields'] as List? ?? [];
    final triggers = (f['trigger_sources'] as List?)?.cast<String>() ?? [];
    final preconds = f['preconditions'] as List? ?? [];
    final onComplete = f['on_complete'] as Map? ?? {};
    final actions = onComplete['actions'] as List? ?? [];
    final execCount = f['execution_count'] as int? ?? 0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.ctTeal.withValues(alpha: 0.03)
                : AppColors.ctSurface,
            border: const Border(
              bottom: BorderSide(color: AppColors.ctBorder),
            ),
          ),
          child: Row(
            children: [
              // Left: name + slug + desc
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: AppTextStyles.body.copyWith(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    if (slug.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(slug,
                          style: AppTextStyles.caption.copyWith(
                              fontFamily: 'Geist', color: AppColors.ctText3)),
                    ],
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(desc,
                          style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 8),
                    // Chips
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        // Trigger icons
                        for (final t in triggers)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.ctSurface2,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.ctBorder),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  switch (t) {
                                    'conversational' => Icons.chat_bubble_outline_rounded,
                                    'scheduled' => Icons.schedule_rounded,
                                    'on_complete' => Icons.account_tree_rounded,
                                    _ => Icons.bolt_rounded,
                                  },
                                  size: 12,
                                  color: AppColors.ctText2,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  switch (t) {
                                    'conversational' => 'Chat',
                                    'scheduled' => 'Programado',
                                    'on_complete' => 'Al cerrar',
                                    'ingest' => 'API',
                                    _ => t,
                                  },
                                  style: AppTextStyles.caption.copyWith(
                                      color: AppColors.ctText2, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        if (fields.isNotEmpty)
                          AppBadge(
                            label: '${fields.length} campo${fields.length == 1 ? '' : 's'}',
                            variant: AppBadgeVariant.neutral,
                          ),
                        if (execCount > 0)
                          AppBadge(
                            label: '$execCount ejecuci\u00F3n${execCount == 1 ? '' : 'es'}',
                            variant: AppBadgeVariant.info,
                          ),
                        if (preconds.isNotEmpty)
                          AppBadge(
                            label: '${preconds.length} precond.',
                            variant: AppBadgeVariant.warn,
                          ),
                        if (actions.isNotEmpty)
                          AppBadge(
                            label: '${actions.length} al cerrar',
                            variant: AppBadgeVariant.teal,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Right: active badge + chevron
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AppBadge(
                    label: isActive ? 'Activo' : 'Inactivo',
                    variant: isActive ? AppBadgeVariant.ok : AppBadgeVariant.neutral,
                  ),
                  const SizedBox(height: 8),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppColors.ctText3),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _NewFlowDialog ───────────────────────────────────────────────────────────

const _kFlowAccentMap = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
  'æ': 'ae', 'ç': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ð': 'd', 'ñ': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ý': 'y', 'ÿ': 'y', 'þ': 'th', 'ß': 'ss',
};

String _flowSlugify(String input) {
  final lower = input.toLowerCase();
  final buf = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    buf.write(_kFlowAccentMap[ch] ?? ch);
  }
  return buf
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

class _NewFlowDialog extends StatefulWidget {
  const _NewFlowDialog({
    required this.tenantId,
    required this.workerId,
    required this.onCreated,
  });
  final String tenantId;
  final String workerId;
  final void Function(String flowId) onCreated;

  @override
  State<_NewFlowDialog> createState() => _NewFlowDialogState();
}

class _NewFlowDialogState extends State<_NewFlowDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _slugError;

  List<Map<String, dynamic>> _availableRoles = [];
  final List<String> _selectedRoleIds = [];
  final List<String> _selectedTriggers = [];
  bool _loadingRoles = false;

  static const _triggerOptions = [
    ('conversational', 'Conversacional', 'El operador inicia el flujo por chat'),
    ('ingest',         'API / Ingesta',  'Se activa por carga de datos externa'),
    ('scheduled',      'Programado',     'Se ejecuta en horario autom\u00e1tico'),
    ('on_complete',    'Al completar otro flujo', 'Se abre como acci\u00f3n de cierre'),
  ];

  String get _slug => _flowSlugify(_nameCtrl.text.trim());
  bool get _slugValid => _slug.length >= 3;
  bool get _canAdvance => _nameCtrl.text.trim().isNotEmpty && _slugValid;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_onNameChanged);
    _loadRoles();
  }

  void _onNameChanged() {
    if (_slugError != null) {
      setState(() => _slugError = null);
    } else {
      setState(() {});
    }
  }

  Future<void> _loadRoles() async {
    setState(() => _loadingRoles = true);
    try {
      final roles = await OperatorRolesApi.listRoles(tenantId: widget.tenantId);
      if (mounted) {
        setState(() => _availableRoles = List<Map<String, dynamic>>.from(roles));
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingRoles = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_onNameChanged);
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    try {
      final result = await FlowsApi.createFlow(
        tenantWorkerId: widget.workerId,
        name: _nameCtrl.text.trim(),
        slug: _slug,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        allowedRoleIds: _selectedRoleIds.isEmpty ? null : _selectedRoleIds,
        triggerSources: _selectedTriggers.isEmpty ? null : _selectedTriggers,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onCreated(result['id'] as String);
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 409) {
        setState(() => _slugError = 'Ya existe un flujo con este nombre');
        return;
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppWizardShell(
      sidebarTitle: 'Nuevo flujo',
      confirmLabel: 'Crear flujo',
      canAdvance: _canAdvance,
      onCancel: () => Navigator.of(context).pop(),
      onConfirm: _submit,
      steps: [
        AppWizardStep(title: 'Identidad', builder: (_) => _buildStep1()),
        AppWizardStep(title: 'Acceso', builder: (_) => _buildStep2()),
        AppWizardStep(title: 'Confirmar', builder: (_) => _buildStep3()),
      ],
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: _nameCtrl,
          label: 'Nombre del flujo',
          hint: 'Ej: Entrega de paquete',
        ),
        if (_nameCtrl.text.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                _slugValid ? Icons.check_circle_outline : Icons.error_outline,
                size: 14,
                color: _slugError != null
                    ? AppColors.ctDanger
                    : _slugValid
                        ? AppColors.ctOk
                        : AppColors.ctText3,
              ),
              const SizedBox(width: 6),
              Text(
                _slugError ?? 'slug: $_slug',
                style: AppTextStyles.bodySmall.copyWith(
                  fontFamily: 'Geist',
                  color: _slugError != null
                      ? AppColors.ctDanger
                      : _slugValid
                          ? AppColors.ctOk
                          : AppColors.ctText3,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        AppTextField(
          controller: _descCtrl,
          label: 'Descripci\u00f3n (opcional)',
          hint: 'Describe el prop\u00f3sito de este flujo...',
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Roles con acceso',
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          'Selecciona qu\u00e9 roles pueden iniciar este flujo. Si no seleccionas ninguno, todos los roles tendr\u00e1n acceso.',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2),
        ),
        const SizedBox(height: 12),
        if (_loadingRoles)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ctTeal),
            )),
          )
        else if (_availableRoles.isEmpty)
          Text('No hay roles disponibles. Podr\u00e1s asignarlos despu\u00e9s.',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _availableRoles.map((role) {
              final id = role['id'] as String? ?? '';
              final name = role['label'] as String? ?? role['name'] as String? ?? id;
              final selected = _selectedRoleIds.contains(id);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (selected) {
                      _selectedRoleIds.remove(id);
                    } else {
                      _selectedRoleIds.add(id);
                    }
                  });
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.ctTeal.withValues(alpha: 0.1)
                          : AppColors.ctSurface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected ? AppColors.ctTeal : AppColors.ctBorder,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (selected) ...[
                          const Icon(Icons.check_rounded, size: 14, color: AppColors.ctTeal),
                          const SizedBox(width: 4),
                        ],
                        Text(name,
                            style: AppTextStyles.body.copyWith(
                              fontSize: 12,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                              color: selected ? AppColors.ctTealDark : AppColors.ctText2,
                            )),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        const SizedBox(height: 24),
        Text('Or\u00edgenes de ejecuci\u00f3n',
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('\u00bfDesde d\u00f3nde puede iniciarse este flujo?',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2)),
        const SizedBox(height: 12),
        ..._triggerOptions.map((opt) {
          final selected = _selectedTriggers.contains(opt.$1);
          return GestureDetector(
            onTap: () {
              setState(() {
                if (selected) {
                  _selectedTriggers.remove(opt.$1);
                } else {
                  _selectedTriggers.add(opt.$1);
                }
              });
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.ctTeal.withValues(alpha: 0.06)
                      : AppColors.ctSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? AppColors.ctTeal : AppColors.ctBorder,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                      size: 18,
                      color: selected ? AppColors.ctTeal : AppColors.ctBorder2,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(opt.$2,
                              style: AppTextStyles.body.copyWith(
                                fontSize: 13,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                              )),
                          Text(opt.$3,
                              style: AppTextStyles.bodySmall.copyWith(
                                  fontSize: 11, color: AppColors.ctText2)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Resumen',
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        _SummaryRow(label: 'Nombre', value: _nameCtrl.text.trim()),
        _SummaryRow(label: 'Slug', value: _slug),
        if (_descCtrl.text.trim().isNotEmpty)
          _SummaryRow(label: 'Descripci\u00f3n', value: _descCtrl.text.trim()),
        if (_selectedRoleIds.isNotEmpty)
          _SummaryRow(
            label: 'Roles',
            value: _selectedRoleIds.map((id) {
              final r = _availableRoles.where((r) => r['id'] == id).firstOrNull;
              return r?['label'] as String? ?? r?['name'] as String? ?? id;
            }).join(', '),
          ),
        if (_selectedTriggers.isNotEmpty)
          _SummaryRow(
            label: 'Triggers',
            value: _selectedTriggers.map((t) {
              final opt = _triggerOptions.where((o) => o.$1 == t).firstOrNull;
              return opt?.$2 ?? t;
            }).join(', '),
          ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2)),
          ),
          Expanded(
            child: Text(value, style: AppTextStyles.body.copyWith(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ── _ControlTowersTab ─────────────────────────────────────────────────────

class _ControlTowersTab extends StatefulWidget {
  const _ControlTowersTab({required this.workerId});
  final String workerId;

  @override
  State<_ControlTowersTab> createState() => _ControlTowersTabState();
}

class _ControlTowersTabState extends State<_ControlTowersTab> {
  List<Map<String, dynamic>> _towers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final all = await GroupsApi.listControlTowers();
      // Filtrar por worker_id
      final filtered = all.where((t) => t['worker_id'] == widget.workerId).toList();
      if (!mounted) return;
      setState(() {
        _towers = filtered;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _edit(Map<String, dynamic> tower) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _EditTowerDialog(
        tower: tower,
        onSaved: _load,
      ),
    );
    if (result == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> tower) async {
    final towerId = tower['id'] as String? ?? '';
    final displayName = tower['display_name'] as String? ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Torre de Control'),
        content: Text('¿Confirmas eliminar "$displayName"?\n\nEsta acción marcará la torre como inactiva.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.ctDanger),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await GroupsApi.deleteControlTower(towerId: towerId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Torre "$displayName" eliminada')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al eliminar: $e'), backgroundColor: AppColors.ctDanger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
          child: Row(
            children: [
              Text(
                'Torres de Control',
                style: AppTextStyles.body.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              AppButton(
                label: '+ Nueva Torre',
                variant: AppButtonVariant.teal,
                size: AppButtonSize.sm,
                onPressed: () async {
                  final result = await showDialog<bool>(
                    context: context,
                    builder: (_) => _CreateTowerDialog(
                      workerId: widget.workerId,
                      onSaved: _load,
                    ),
                  );
                  if (result == true) _load();
                },
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ctTeal),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctDanger)),
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

    if (_towers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cell_tower, size: 40, color: AppColors.ctText3),
            const SizedBox(height: 12),
            Text(
              'Sin torres de control configuradas',
              style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
      itemCount: _towers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _TowerCard(
        tower: _towers[i],
        onEdit: () => _edit(_towers[i]),
        onDelete: () => _delete(_towers[i]),
      ),
    );
  }
}

// ── _TowerCard ────────────────────────────────────────────────────────────

class _TowerCard extends StatelessWidget {
  const _TowerCard({
    required this.tower,
    required this.onEdit,
    required this.onDelete,
  });
  final Map<String, dynamic> tower;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final displayName = tower['display_name'] as String? ?? '—';
    final description = tower['description'] as String? ?? '';
    final status = tower['status'] as String? ?? 'inactive';
    final channelType = tower['channel_type'] as String? ?? 'whatsapp';
    final externalGroupId = tower['external_group_id'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  displayName,
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              AppBadge(
                label: status == 'active' ? 'Activo' : 'Inactivo',
                variant: status == 'active' ? AppBadgeVariant.ok : AppBadgeVariant.neutral,
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(description, style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2)),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                channelType == 'whatsapp' ? Icons.chat : Icons.forum_outlined,
                size: 14,
                color: AppColors.ctText3,
              ),
              const SizedBox(width: 6),
              Text(
                channelType.toUpperCase(),
                style: AppTextStyles.caption.copyWith(color: AppColors.ctText3),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.tag, size: 14, color: AppColors.ctText3),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  externalGroupId,
                  style: AppTextStyles.caption.copyWith(
                    fontFamily: 'Geist',
                    color: AppColors.ctText3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Editar',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                  onPressed: onEdit,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  label: status == 'inactive' ? 'Inactiva' : 'Eliminar',
                  variant: AppButtonVariant.danger,
                  size: AppButtonSize.sm,
                  onPressed: onDelete,
                  isDisabled: status == 'inactive',
                ),
              ),
            ],
          ),
          if (status == 'inactive')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.ctWarnBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.ctWarn.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, size: 14, color: AppColors.ctWarn),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Torre inactiva - No se enviarán notificaciones',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.ctWarnText,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── _CreateTowerDialog ────────────────────────────────────────────────────

class _CreateTowerDialog extends StatefulWidget {
  const _CreateTowerDialog({
    required this.workerId,
    required this.onSaved,
  });

  final String workerId;
  final VoidCallback onSaved;

  @override
  State<_CreateTowerDialog> createState() => _CreateTowerDialogState();
}

class _CreateTowerDialogState extends State<_CreateTowerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  List<String> _participants = [];
  bool _saving = false;

  // Palabras que disparan filtros de spam de WhatsApp
  static const _spamTriggerWords = [
    'torre', 'tower',
    'test', 'prueba',
    'dev', 'desarrollo', 'development',
    'grupo', 'group',
    'control',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Requerido';

    // Verificar palabras spam
    final lowerText = text.toLowerCase();
    for (final word in _spamTriggerWords) {
      if (lowerText.contains(word)) {
        return 'Evita usar "$word" - puede activar filtros de spam';
      }
    }

    return null;
  }

  void _showNamingGuide() {
    showDialog(
      context: context,
      builder: (context) => const _NamingGuideDialog(),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Validar que haya al menos un participante
    if (_participants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes agregar al menos un participante'),
          backgroundColor: AppColors.ctDanger,
        ),
      );
      return;
    }

    setState(() { _saving = true; });

    try {
      await GroupsApi.createControlTower(
        workerId: widget.workerId,
        displayName: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        participantPhones: _participants,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Torre de control creada exitosamente'),
          backgroundColor: AppColors.ctOk,
        ),
      );
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() { _saving = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al crear torre: $e'),
          backgroundColor: AppColors.ctDanger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva Torre de Control'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre *',
                        hintText: 'Ej: Equipo Ventas',
                      ),
                      validator: _validateName,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _showNamingGuide,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.ctTeal.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.info_outline,
                          size: 18,
                          color: AppColors.ctTeal,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  hintText: 'Opcional',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),
              ParticipantsWidget(
                initial: _participants,
                onChanged: (list) => setState(() => _participants = list),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        AppButton(
          variant: AppButtonVariant.teal,
          size: AppButtonSize.sm,
          label: _saving ? 'Creando...' : 'Crear',
          onPressed: () => _submit(),
          isDisabled: _saving,
        ),
      ],
    );
  }
}

// ── _EditTowerDialog ──────────────────────────────────────────────────────

class _EditTowerDialog extends StatefulWidget {
  const _EditTowerDialog({
    required this.tower,
    required this.onSaved,
  });

  final Map<String, dynamic> tower;
  final VoidCallback onSaved;

  @override
  State<_EditTowerDialog> createState() => _EditTowerDialogState();
}

class _EditTowerDialogState extends State<_EditTowerDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  final _iconUrlCtrl = TextEditingController();
  late String _status;
  late List<String> _participants;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
      text: widget.tower['display_name'] as String? ?? '',
    );
    _descCtrl = TextEditingController(
      text: widget.tower['description'] as String? ?? '',
    );
    _status = widget.tower['status'] as String? ?? 'active';

    // Cargar participantes existentes desde config
    final config = widget.tower['config'] as Map<String, dynamic>? ?? {};
    _participants = (config['participants'] as List?)?.cast<String>() ?? [];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _iconUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { _saving = true; });

    final iconUrl = _iconUrlCtrl.text.trim();

    try {
      await GroupsApi.updateControlTower(
        towerId: widget.tower['id'] as String,
        displayName: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        status: _status,
        participants: _participants,
        iconUrl: iconUrl.isEmpty ? null : iconUrl,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Torre actualizada exitosamente'),
          backgroundColor: AppColors.ctOk,
        ),
      );
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() { _saving = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al actualizar: $e'),
          backgroundColor: AppColors.ctDanger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar Torre de Control'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre *',
                  hintText: 'Ej: Torre Ventas',
                ),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  hintText: 'Opcional',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(
                  labelText: 'Estado',
                ),
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Activa')),
                  DropdownMenuItem(value: 'inactive', child: Text('Inactiva')),
                ],
                onChanged: (val) => setState(() => _status = val ?? 'active'),
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),
              ParticipantsWidget(
                initial: _participants,
                onChanged: (list) => setState(() => _participants = list),
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),
              TextFormField(
                controller: _iconUrlCtrl,
                decoration: const InputDecoration(
                  labelText: 'URL de imagen del grupo',
                  hintText: 'https://ejemplo.com/imagen.jpg',
                  helperText: 'URL pública de la imagen (JPEG/PNG)',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        AppButton(
          variant: AppButtonVariant.teal,
          size: AppButtonSize.sm,
          label: _saving ? 'Guardando...' : 'Guardar',
          onPressed: () => _submit(),
          isDisabled: _saving,
        ),
      ],
    );
  }
}

// ── _NamingGuideDialog ────────────────────────────────────────────────────

class _NamingGuideDialog extends StatelessWidget {
  const _NamingGuideDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.ctTeal.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.info_outline, size: 20, color: AppColors.ctTeal),
          ),
          const SizedBox(width: 10),
          const Text('Guía para nombrar grupos'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Warning banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.ctWarn.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.ctWarn.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber, size: 18, color: AppColors.ctWarn),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'WhatsApp usa inteligencia artificial para detectar spam. Evita nombres que parezcan automatizados.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.ctText,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Good examples
              Text(
                '✓ Nombres recomendados',
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.ctOk,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              _buildExampleCard(
                context,
                isGood: true,
                examples: [
                  'Equipo Ventas',
                  'Coordinación General',
                  'Soporte Técnico',
                  'Comercial México',
                  'Operaciones CDMX',
                ],
              ),
              const SizedBox(height: 16),

              // Bad examples
              Text(
                '✗ Nombres a evitar',
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.ctDanger,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              _buildExampleCard(
                context,
                isGood: false,
                examples: [
                  'Torre Ventas Dev',
                  'Grupo Test',
                  'Torre de Control',
                  'Prueba WhatsApp',
                  'Development Team',
                ],
              ),
              const SizedBox(height: 16),

              // Tips section
              Text(
                'Consejos adicionales',
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              _buildTipItem('Usa nombres naturales y descriptivos'),
              _buildTipItem('Evita palabras como "torre", "test", "dev", "grupo"'),
              _buildTipItem('No crees varios grupos seguidos muy rápido'),
              _buildTipItem('Agrega participantes gradualmente (automático)'),
            ],
          ),
        ),
      ),
      actions: [
        AppButton(
          variant: AppButtonVariant.teal,
          size: AppButtonSize.sm,
          label: 'Entendido',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildExampleCard(BuildContext context, {required bool isGood, required List<String> examples}) {
    final color = isGood ? AppColors.ctOk : AppColors.ctDanger;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: examples.map((example) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(
                  isGood ? Icons.check_circle : Icons.cancel,
                  size: 14,
                  color: color,
                ),
                const SizedBox(width: 8),
                Text(
                  example,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontSize: 12,
                    color: AppColors.ctText,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTipItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 4,
            height: 4,
            decoration: const BoxDecoration(
              color: AppColors.ctTeal,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySmall.copyWith(
                fontSize: 12,
                color: AppColors.ctText2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
