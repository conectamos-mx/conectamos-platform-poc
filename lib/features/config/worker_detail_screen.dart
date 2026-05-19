import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/ai_workers_api.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_badge.dart';
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
    _tabCtrl = TabController(length: 2, vsync: this);
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
      final workers = await AiWorkersApi.listWorkers();
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
    final avatarUrl = _worker?['avatar_url'] as String?;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: avatarUrl != null
          ? Image.network(avatarUrl, width: 40, height: 40, fit: BoxFit.cover)
          : Container(
              width: 40,
              height: 40,
              color: AppColors.ctSurface2,
              child: const Icon(
                Icons.smart_toy_rounded,
                size: 22,
                color: AppColors.ctText2,
              ),
            ),
    );
  }

  AppDetailHeader _buildHeader() {
    final tabBar = TabBar(
      controller: _tabCtrl,
      labelColor: AppColors.ctTeal,
      unselectedLabelColor: AppColors.ctText2,
      indicatorColor: AppColors.ctTeal,
      indicatorWeight: 2,
      labelStyle: AppTextStyles.formLabel,
      unselectedLabelStyle: AppTextStyles.navItem,
      tabs: const [
        Tab(text: 'Flujos'),
        Tab(text: 'Canales'),
      ],
    );

    if (_loading) {
      return AppDetailHeader(
        title: '',
        backLabel: 'Workers',
        onBack: () => context.go('/workers'),
        bottom: tabBar,
      );
    }

    final isActive = _worker?['is_active'] == true;
    final catalogName = _worker?['catalog_name'] as String?;

    return AppDetailHeader(
      title: _workerName,
      backLabel: 'Workers',
      onBack: () => context.go('/workers'),
      subtitle: catalogName,
      avatar: _buildAvatar(),
      chips: [
        AppBadge(
          label: isActive ? 'Activo' : 'Inactivo',
          variant: isActive ? AppBadgeVariant.ok : AppBadgeVariant.neutral,
          dot: true,
        ),
      ],
      bottom: tabBar,
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
          WorkflowsScreen(tenantWorkerId: widget.workerId),
          ChannelsScreen(tenantWorkerId: widget.workerId),
        ],
      ),
    );
  }
}
