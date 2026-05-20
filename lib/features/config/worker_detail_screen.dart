import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/ai_workers_api.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_detail_header.dart';
import '../../shared/widgets/app_loading_state.dart';
import '../../shared/widgets/app_stacked_metric_card.dart';
import 'channel_detail_screen.dart';
import 'channels_screen.dart';
import 'workflows_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
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
          WorkflowsScreen(tenantWorkerId: widget.workerId),
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
  String? _fireError;

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
    setState(() { _firingWorker = true; _fireError = null; });
    try {
      await AiWorkersApi.fireWorker(widget.worker['id'] as String);
      if (!mounted) return;
      setState(() { _showFireModal = false; _firingWorker = false; });
      context.go('/workers');
    } catch (e) {
      if (!mounted) return;
      setState(() { _firingWorker = false; _fireError = e.toString(); });
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
                setState(() { _showFireModal = true; _fireError = null; });
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
    this.titleColor,
    this.borderColor,
    this.backgroundColor,
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
