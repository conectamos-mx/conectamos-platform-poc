import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/ai_workers_api.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_detail_header.dart';
import '../../shared/widgets/app_loading_state.dart';
import 'channels_screen.dart';
import 'workflows_screen.dart';

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
          ),
          ChannelsScreen(tenantWorkerId: widget.workerId),
          WorkflowsScreen(tenantWorkerId: widget.workerId),
        ],
      ),
    );
  }
}

// ── _ConfigTab ─────────────────────────────────────────────────────────────────

class _ConfigTab extends StatefulWidget {
  const _ConfigTab({required this.worker, required this.onWorkerUpdated});

  final Map<String, dynamic> worker;
  final VoidCallback onWorkerUpdated;

  @override
  State<_ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends State<_ConfigTab> {
  bool _showFireModal = false;
  bool _firingWorker = false;
  final TextEditingController _confirmCtrl = TextEditingController();
  String? _fireError;

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
              _MetricsCard(worker: widget.worker),
              const SizedBox(height: 16),
              _SkillsCard(worker: widget.worker),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFireModal() {
    final bool canFire =
        _confirmCtrl.text.trim() == _workerName && !_firingWorker;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: Container(
        color: Colors.black.withValues(alpha: 0.45),
        alignment: Alignment.center,
        child: Container(
          width: 440,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.ctSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.ctBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.ctRedBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.warning_amber_rounded,
                        color: AppColors.ctDanger, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Dar de baja al worker',
                            style: AppTextStyles.cardTitle.copyWith(
                              fontFamily: 'Onest',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ctText,
                            )),
                        Text('Esta acción no se puede deshacer',
                            style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.ctText3)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _firingWorker
                        ? null
                        : () => setState(() => _showFireModal = false),
                    child: const Icon(Icons.close,
                        color: AppColors.ctText3, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Impact list
              _ImpactRow(
                icon: Icons.stop_circle_outlined,
                label: 'Se abandonarán todas las ejecuciones activas',
              ),
              const SizedBox(height: 8),
              _ImpactRow(
                icon: Icons.link_off_rounded,
                label: 'Se desactivarán todos los canales asociados',
              ),
              const SizedBox(height: 8),
              _ImpactRow(
                icon: Icons.alt_route_rounded,
                label: 'Se desactivarán todos los flujos asociados',
              ),
              const SizedBox(height: 20),
              // Confirm input
              Text(
                'Escribe el nombre del worker para confirmar:',
                style:
                    AppTextStyles.formLabel.copyWith(color: AppColors.ctText2),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmCtrl,
                enabled: !_firingWorker,
                onChanged: (_) => setState(() {}),
                style: AppTextStyles.body.copyWith(color: AppColors.ctText),
                decoration: InputDecoration(
                  hintText: _workerName,
                  hintStyle:
                      AppTextStyles.body.copyWith(color: AppColors.ctText3),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  filled: true,
                  fillColor: AppColors.ctSurface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: AppColors.ctBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: AppColors.ctBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: AppColors.ctDanger, width: 1.5),
                  ),
                ),
              ),
              if (_fireError != null) ...[
                const SizedBox(height: 8),
                Text(_fireError!,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.ctDanger)),
              ],
              const SizedBox(height: 20),
              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    variant: AppButtonVariant.ghost,
                    label: 'Cancelar',
                    isDisabled: _firingWorker,
                    onPressed: () => setState(() => _showFireModal = false),
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    variant: AppButtonVariant.danger,
                    label: _firingWorker ? 'Dando de baja…' : 'Dar de baja',
                    isDisabled: !canFire,
                    onPressed: _fireWorker,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _ImpactRow ────────────────────────────────────────────────────────────────

class _ImpactRow extends StatelessWidget {
  const _ImpactRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.ctDanger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2),
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
  late TextEditingController _nameCtrl;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
      text: widget.worker['display_name'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { _saving = true; _saveError = null; });
    try {
      await AiWorkersApi.updateWorker(
        tenantWorkerId: widget.worker['id'] as String,
        displayName: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() { _saving = false; });
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() { _saving = false; _saveError = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Identidad',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nombre personalizado',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2)),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              enabled: !_saving,
              style: AppTextStyles.body.copyWith(color: AppColors.ctText),
              decoration: InputDecoration(
                hintText: widget.worker['catalog_name'] as String? ?? '',
                hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                filled: true,
                fillColor: AppColors.ctSurface2,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.ctBorder)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.ctBorder)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: AppColors.ctTeal, width: 1.5)),
              ),
            ),
            if (_saveError != null) ...[
              const SizedBox(height: 6),
              Text(_saveError!,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.ctDanger)),
            ],
            const SizedBox(height: 12),
            AppButton(
              variant: AppButtonVariant.teal,
              label: _saving ? 'Guardando…' : 'Guardar nombre',
              isDisabled: _saving,
              onPressed: _save,
            ),
          ],
        ),
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
  bool _toggling = false;

  Future<void> _toggle() async {
    final current = widget.worker['is_active'] == true;
    setState(() { _toggling = true; });
    try {
      await AiWorkersApi.updateWorker(
        tenantWorkerId: widget.worker['id'] as String,
        isActive: !current,
      );
      if (!mounted) return;
      setState(() { _toggling = false; });
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() { _toggling = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.worker['is_active'] == true;

    return _SectionCard(
      title: 'Estado',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isActive ? AppColors.ctOk : AppColors.ctText3,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isActive ? 'Activo' : 'Inactivo',
              style: AppTextStyles.body.copyWith(
                color: isActive ? AppColors.ctOkText : AppColors.ctText2,
              ),
            ),
            const Spacer(),
            AppButton(
              variant: isActive
                  ? AppButtonVariant.ghost
                  : AppButtonVariant.teal,
              label: _toggling
                  ? 'Actualizando…'
                  : (isActive ? 'Desactivar' : 'Activar'),
              isDisabled: _toggling,
              onPressed: _toggle,
            ),
          ],
        ),
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
    return _SectionCard(
      title: 'Zona de peligro',
      titleColor: AppColors.ctDanger,
      borderColor: AppColors.ctDanger.withValues(alpha: 0.25),
      backgroundColor: AppColors.ctRedBg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dar de baja al worker',
                      style: AppTextStyles.formLabel.copyWith(
                          fontWeight: FontWeight.w600, color: AppColors.ctText)),
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
              label: 'Dar de baja',
              onPressed: onFire,
            ),
          ],
        ),
      ),
    );
  }
}

// ── _MetricsCard ──────────────────────────────────────────────────────────────

class _MetricsCard extends StatelessWidget {
  const _MetricsCard({required this.worker});

  final Map<String, dynamic> worker;

  @override
  Widget build(BuildContext context) {
    final flows = (worker['flows'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final channelCount = worker['channel_count'] as int? ?? 0;
    final executionCount = worker['execution_count'] as int? ?? 0;
    final completedToday = flows.fold<int>(
        0, (sum, f) => sum + ((f['completed_today'] as int?) ?? 0));

    return _SectionCard(
      title: 'Métricas',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.ctSurface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.ctBorder),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _MetricCell(
                    label: 'Flujos activos',
                    value: flows.length.toString(),
                  ),
                ),
                const VerticalDivider(
                    width: 1, thickness: 1, color: AppColors.ctBorder),
                Expanded(
                  child: _MetricCell(
                    label: 'Canales',
                    value: channelCount.toString(),
                  ),
                ),
                const VerticalDivider(
                    width: 1, thickness: 1, color: AppColors.ctBorder),
                Expanded(
                  child: _MetricCell(
                    label: 'Completadas hoy',
                    value: completedToday.toString(),
                    valueColor: completedToday > 0
                        ? AppColors.ctTeal
                        : AppColors.ctText2,
                  ),
                ),
                const VerticalDivider(
                    width: 1, thickness: 1, color: AppColors.ctBorder),
                Expanded(
                  child: _MetricCell(
                    label: 'Total ejecuciones',
                    value: executionCount.toString(),
                    valueColor: executionCount > 0
                        ? AppColors.ctOkText
                        : AppColors.ctText2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── _MetricCell ───────────────────────────────────────────────────────────────

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTextStyles.cardTitle.copyWith(
              fontFamily: 'Onest',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppColors.ctText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
          ),
        ],
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
    final description =
        worker['catalog_description'] as String? ?? '';

    return _SectionCard(
      title: 'Habilidades',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (description.isNotEmpty) ...[
              Text(description,
                  style: AppTextStyles.body.copyWith(color: AppColors.ctText2)),
              const SizedBox(height: 12),
            ],
            if (skills.isEmpty)
              Text('Sin habilidades registradas.',
                  style: AppTextStyles.body.copyWith(color: AppColors.ctText3))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final skill in skills)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.ctTeal.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.ctTeal.withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        skill,
                        style: AppTextStyles.formLabel
                            .copyWith(color: AppColors.ctTeal),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
