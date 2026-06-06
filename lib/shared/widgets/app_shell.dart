import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/overview_api.dart';
import '../../core/config.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/escalaciones_provider.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';

// ── Providers globales ────────────────────────────────────────────────────────

/// Estado de colapso del sidebar.
final sidebarCollapsedProvider = StateProvider<bool>((ref) => false);

/// Providers para acciones y metadata de cada pantalla.
final topbarTitleProvider    = StateProvider<String>((ref) => '');
final topbarSubtitleProvider = StateProvider<String?>((ref) => null);
final topbarActionsProvider  = StateProvider<List<Widget>>((ref) => []);

/// Display name del tenant activo para la UI (usa el notifier real).
final activeTenantProvider = Provider<String>((ref) {
  return ref.watch(currentTenantProvider);
});

/// KPIs del tenant activo — usado en el topbar.
final _kpiDataProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, tenantId) async {
  if (tenantId.isEmpty) return {};
  return OverviewApi.getKpis(tenantId: tenantId);
});

// ── AppShell ──────────────────────────────────────────────────────────────────

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final email = ref.read(currentUserEmailProvider);
      if (email.isNotEmpty) {
        ref.read(tenantNotifierProvider.notifier).load(email);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // ADR-414: keep tz_format global in sync with active tenant timezone.
    ref.watch(tenantZoneSyncProvider);

    // Covers fresh-login case: currentUserProvider is a synchronous Provider
    // that caches null and is never invalidated by auth changes.
    // Listening here ensures load() is called when sign-in completes.
    ref.listen(authStateProvider, (prev, next) {
      next.whenData((authState) {
        if (authState.event == AuthChangeEvent.signedIn) {
          final email = authState.session?.user.email ?? '';
          if (email.isNotEmpty) {
            ref.read(tenantNotifierProvider.notifier).load(email);
          }
        }
      });
    });

    return Scaffold(
      backgroundColor: AppColors.ctBg,
      body: Column(
        children: [
          const _Topbar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Sidebar(navigationShell: widget.navigationShell),
                Expanded(child: widget.navigationShell),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Branch index map — sincronizado con el orden de StatefulShellRoute ────────

const _kRouteBranchIndex = {
  '/overview':      0,
  '/conversations': 1,
  '/broadcast':     2,
  '/dashboard':     3,
  '/operators':     4,
  '/executions':    5,
  '/tareas':        6,
  '/escalaciones':  7,
  '/workers':       8,
  '/connections':   9,
  '/settings':      10,
  '/catalogs':      11,
};

// ── TOPBAR ────────────────────────────────────────────────────────────────────

class _Topbar extends ConsumerWidget {
  const _Topbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed  = ref.watch(sidebarCollapsedProvider);
    final email      = ref.watch(currentUserEmailProvider);
    final tenantId   = ref.watch(activeTenantIdProvider);
    final tenantName = ref.watch(activeTenantDisplayProvider);
    final kpiAsync   = ref.watch(_kpiDataProvider(tenantId));

    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: AppColors.ctSurface,
        border: Border(
          bottom: BorderSide(color: AppColors.ctBorder, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          // [A] Toggle hamburguesa
          _TopbarIconBtn(
            icon: collapsed ? Icons.menu_rounded : Icons.menu_open_rounded,
            tooltip: collapsed ? 'Expandir sidebar' : 'Colapsar sidebar',
            onTap: () =>
                ref.read(sidebarCollapsedProvider.notifier).state = !collapsed,
          ),
          const SizedBox(width: 8),

          // [B] Isotipo teal
          SvgPicture.asset(
            'assets/images/Conectamos-Isotipo.svg',
            height: 13,
            fit: BoxFit.contain,
            colorFilter: const ColorFilter.mode(AppColors.ctTeal, BlendMode.srcIn),
          ),
          const SizedBox(width: 6),

          // [C] Wordmark
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'Conectam',
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700, color: AppColors.ctNavy, letterSpacing: -0.26),
                ),
                TextSpan(
                  text: 'OS',
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700, color: AppColors.ctTealText, letterSpacing: -0.26),
                ),
              ],
            ),
          ),

          // [D] Spacer
          const Spacer(),

          // [E] KPI chips
          kpiAsync.when(
            data: (kpis) => kpis.isEmpty
                ? const SizedBox.shrink()
                : _KpiChips(kpis: kpis),
            loading: () => const SizedBox.shrink(),
            error: (e, st) => const Tooltip(
              message: 'Error al cargar KPIs',
              child: Icon(Icons.error_outline, size: 16, color: AppColors.ctDanger),
            ),
          ),
          const SizedBox(width: 8),

          // [F] Tenant selector
          _TenantSelector(name: tenantName),
          const SizedBox(width: 8),

          // [G] Campana
          const _BellIcon(),
          const SizedBox(width: 6),

          // [H] Avatar / menú de usuario
          _UserMenu(email: email),
        ],
      ),
    );
  }
}

// ── Tenant selector (topbar) ──────────────────────────────────────────────────

class _TenantSelector extends ConsumerWidget {
  const _TenantSelector({required this.name});
  final String name;

  void _openMenu(BuildContext context, WidgetRef ref, List tenants) async {
    final box = context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;

    final active = ref.read(activeTenantInfoProvider);

    await showMenu<String>(
      context: context,
      color: AppColors.ctSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.ctBorder),
      ),
      elevation: 8,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height + 4,
        offset.dx + size.width,
        0,
      ),
      items: [
        for (final t in tenants)
          PopupMenuItem<String>(
            value: t.id,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t.displayName,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontSize: 12,
                      fontWeight: t.id == active?.id ? FontWeight.w600 : FontWeight.w400,
                      color: t.id == active?.id ? AppColors.ctTeal : AppColors.ctText,
                    ),
                  ),
                ),
                if (t.id == active?.id)
                  const Icon(Icons.check, size: 13, color: AppColors.ctTeal),
              ],
            ),
          ),
      ],
    ).then((selectedId) {
      if (selectedId == null) return;
      final matches = tenants
          .whereType<TenantInfo>()
          .where((t) => t.id == selectedId)
          .toList();
      if (matches.isEmpty) return;
      ref.read(tenantNotifierProvider.notifier).select(matches.first);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (name.isEmpty) return const SizedBox.shrink();
    final tenants     = ref.watch(allTenantsProvider);
    final hasMultiple = tenants.length > 1;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.ctSurface2,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: AppColors.ctText, letterSpacing: -0.11),
          ),
          if (hasMultiple) ...[
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 14, color: AppColors.ctText3),
          ],
        ],
      ),
    );

    if (!hasMultiple) return chip;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _openMenu(context, ref, tenants),
        child: chip,
      ),
    );
  }
}

// ── Campana (no-op) ───────────────────────────────────────────────────────────

class _BellIcon extends StatelessWidget {
  const _BellIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.notifications_outlined,
          size: 16,
          color: AppColors.ctText2,
        ),
        // TODO: badge de notificaciones — pendiente módulo de notificaciones
      ),
    );
  }
}

// ── KPI chips ─────────────────────────────────────────────────────────────────

class _KpiChips extends StatelessWidget {
  const _KpiChips({required this.kpis});
  final Map<String, dynamic> kpis;

  @override
  Widget build(BuildContext context) {
    final activeOps   = (kpis['operators_active'] as num?)?.toInt();
    final flowsActive = (kpis['flows_active']     as num?)?.toInt();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (activeOps != null)
          _StatusChip(
            dot: AppColors.ctOk,
            bg: AppColors.ctOkBg,
            border: const Color(0xFFA7F3D0),
            textColor: AppColors.ctOkText,
            label: '$activeOps activos',
          ),
        if (activeOps != null && flowsActive != null)
          const SizedBox(width: 5),
        if (flowsActive != null)
          _StatusChip(
            dot: AppColors.ctTeal,
            bg: AppColors.ctTealLight,
            border: const Color(0xFF99F6E4),
            textColor: AppColors.ctTealText,
            label: '$flowsActive flujos',
          ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.dot,
    required this.bg,
    required this.border,
    required this.textColor,
    required this.label,
  });
  final Color dot;
  final Color bg;
  final Color border;
  final Color textColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.kpiLabel.copyWith(color: textColor),
          ),
        ],
      ),
    );
  }
}


// ── Botón de icono en topbar ───────────────────────────────────────────────────

class _TopbarIconBtn extends StatefulWidget {
  const _TopbarIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_TopbarIconBtn> createState() => _TopbarIconBtnState();
}

class _TopbarIconBtnState extends State<_TopbarIconBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit:  (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: _hovered ? AppColors.ctSurface2 : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 16, color: AppColors.ctText3),
          ),
        ),
      ),
    );
  }
}

// ── Menú de usuario ───────────────────────────────────────────────────────────

enum _UserMenuAction { profile, accountSettings, signOut }

class _UserMenu extends ConsumerWidget {
  const _UserMenu({required this.email});
  final String email;

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    _UserMenuAction action,
  ) async {
    switch (action) {
      case _UserMenuAction.profile:
        // TODO: navegar a perfil
        break;
      case _UserMenuAction.accountSettings:
        // TODO: navegar a configuración de cuenta
        break;
      case _UserMenuAction.signOut:
        if (kMockMode) {
          if (context.mounted) context.go('/login');
        } else {
          await Supabase.instance.client.auth.signOut();
          if (context.mounted) context.go('/login');
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initial = email.isNotEmpty ? email[0].toUpperCase() : 'U';

    return Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: AppColors.ctSurface,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppColors.ctBorder),
          ),
          menuPadding: const EdgeInsets.symmetric(vertical: 6),
        ),
      ),
      child: PopupMenuButton<_UserMenuAction>(
        offset: const Offset(0, 34),
        constraints: const BoxConstraints(minWidth: 200),
        onSelected: (action) => _handleAction(context, ref, action),
        itemBuilder: (context) => [
          // Encabezado: email no clickeable
          PopupMenuItem<_UserMenuAction>(
            enabled: false,
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              email,
              style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
            ),
          ),
          const PopupMenuDivider(height: 1),

          // Mi perfil
          _buildMenuItem(
            value: _UserMenuAction.profile,
            icon: Icons.person_outline_rounded,
            label: 'Mi perfil',
          ),

          // Configuración de cuenta
          _buildMenuItem(
            value: _UserMenuAction.accountSettings,
            icon: Icons.settings_outlined,
            label: 'Configuración de cuenta',
          ),

          const PopupMenuDivider(height: 1),

          // Cerrar sesión
          _buildMenuItem(
            value: _UserMenuAction.signOut,
            icon: Icons.logout_rounded,
            label: 'Cerrar sesión',
            color: AppColors.ctDanger,
          ),
        ],
        // Trigger: email (responsivo) + avatar con inicial
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (MediaQuery.of(context).size.width > 1100) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    email,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(letterSpacing: -0.11),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.ctTealLight,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF99F6E4), width: 1),
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w700, color: AppColors.ctTealText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<_UserMenuAction> _buildMenuItem({
    required _UserMenuAction value,
    required IconData icon,
    required String label,
    Color color = AppColors.ctText2,
  }) {
    return PopupMenuItem<_UserMenuAction>(
      value: value,
      height: 40,
      padding: EdgeInsets.zero,
      child: _MenuItemTile(icon: icon, label: label, color: color),
    );
  }
}

class _MenuItemTile extends StatefulWidget {
  const _MenuItemTile({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  State<_MenuItemTile> createState() => _MenuItemTileState();
}

class _MenuItemTileState extends State<_MenuItemTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        color: _hovered ? AppColors.ctSurface2 : Colors.transparent,
        child: Row(
          children: [
            Icon(widget.icon, size: 16, color: widget.color),
            const SizedBox(width: 10),
            Text(
              widget.label,
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500, color: widget.color),
            ),
          ],
        ),
      ),
    );
  }
}

// ── SIDEBAR ───────────────────────────────────────────────────────────────────

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed    = ref.watch(sidebarCollapsedProvider);
    final currentRoute = GoRouterState.of(context).matchedLocation;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: collapsed ? 52 : 220,
      decoration: const BoxDecoration(
        color: AppColors.ctSidebarBg,
        border: Border(right: BorderSide(color: Color(0x0FFFFFFF), width: 1)),
      ),
      // ClipRect evita que el contenido se desborde durante la animación
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: collapsed ? 52 : 220,
          maxWidth: collapsed ? 52 : 220,
          child: SizedBox(
            width: collapsed ? 52 : 220,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),

                // Nav items con scroll
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Operaciones ──────────────────────────────────
                        _NavSection(
                          label: 'Operaciones',
                          collapsed: collapsed,
                        ),
                        _NavItem(
                          icon: Icons.grid_view_rounded,
                          label: 'Vista general',
                          route: '/overview',
                          currentRoute: currentRoute,
                          collapsed: collapsed,
                          navigationShell: navigationShell,
                        ),
                        if (hasPermission(ref, 'flows', 'view'))
                          _NavItem(
                            icon: Icons.receipt_long_outlined,
                            label: 'Ejecuciones',
                            route: '/executions',
                            currentRoute: currentRoute,
                            collapsed: collapsed,
                            navigationShell: navigationShell,
                          ),
                        if (hasPermission(ref, 'assignments', 'view'))
                          _NavItem(
                            icon: Icons.calendar_month_outlined,
                            label: 'Asignaciones',
                            route: '/assignments',
                            currentRoute: currentRoute,
                            collapsed: collapsed,
                            navigationShell: navigationShell,
                          ),
                        _NavItem(
                          icon: Icons.chat_bubble_outline_rounded,
                          label: 'Conversaciones',
                          route: '/conversations',
                          currentRoute: currentRoute,
                          collapsed: collapsed,
                          navigationShell: navigationShell,
                        ),
                        if (hasPermission(ref, 'escalations', 'view'))
                          _EscalacionesNavItem(
                            currentRoute:    currentRoute,
                            collapsed:       collapsed,
                            navigationShell: navigationShell,
                          ),
                        if (hasPermission(ref, 'dashboards', 'view'))
                          _ExpandableNavItem(
                            icon: Icons.bar_chart_rounded,
                            label: 'Dashboards',
                            currentRoute: currentRoute,
                            collapsed: collapsed,
                            children: [
                              _ExpandableSubItem(
                                icon: Icons.dashboard_outlined,
                                label: 'Panel operativo',
                                route: '/dashboard',
                                currentRoute: currentRoute,
                              ),
                              _ExpandableSubItem(
                                icon: Icons.task_alt_outlined,
                                label: 'Tareas',
                                route: '/tareas',
                                currentRoute: currentRoute,
                              ),
                            ],
                          ),
                        const SizedBox(height: 4),
                        // ── Workers ──────────────────────────────────────
                        _NavSection(
                          label: 'Workers',
                          collapsed: collapsed,
                        ),
                        if (hasPermission(ref, 'settings', 'manage'))
                          _NavItem(
                            icon: Icons.smart_toy_rounded,
                            label: 'Mis Workers',
                            route: '/workers',
                            currentRoute: currentRoute,
                            collapsed: collapsed,
                            navigationShell: navigationShell,
                          ),

                        if (hasPermission(ref, 'catalogs', 'view'))
                          _NavItem(
                            icon: Icons.folder_copy_outlined,
                            label: 'Catálogos',
                            route: '/catalogs',
                            currentRoute: currentRoute,
                            collapsed: collapsed,
                            navigationShell: navigationShell,
                          ),
                        const SizedBox(height: 4),
                        // ── Configuración ─────────────────────────────────
                        if (hasPermission(ref, 'settings', 'view') ||
                            hasPermission(ref, 'operators', 'view')) ...[
                          _NavSection(
                            label: 'Configuración',
                            collapsed: collapsed,
                          ),
                          if (hasPermission(ref, 'operators', 'view'))
                            _NavItem(
                              icon: Icons.people_outline_rounded,
                              label: 'Operadores',
                              route: '/operators',
                              currentRoute: currentRoute,
                              collapsed: collapsed,
                              navigationShell: navigationShell,
                            ),
                          if (hasPermission(ref, 'settings', 'view')) ...[
                            _NavItem(
                              icon: Icons.cable_outlined,
                              label: 'Conexiones',
                              route: '/connections',
                              currentRoute: currentRoute,
                              collapsed: collapsed,
                              navigationShell: navigationShell,
                            ),
                            _NavItem(
                              icon: Icons.settings_outlined,
                              label: 'Ajustes',
                              route: '/settings',
                              currentRoute: currentRoute,
                              collapsed: collapsed,
                              navigationShell: navigationShell,
                            ),
                          ],
                        ],
                        // ── Próximamente (comentado) ──────────────────────
                        // _NavSection(label: 'Próximamente', collapsed: collapsed),
                        // _DisabledNavItem(icon: Icons.bar_chart_rounded, label: 'Dashboards', collapsed: collapsed),
                      ],
                    ),
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


// ── Label de sección ──────────────────────────────────────────────────────────

class _NavSection extends StatelessWidget {
  const _NavSection({required this.label, required this.collapsed});
  final String label;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Container(height: 1, color: const Color(0x0FFFFFFF)),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 14, 3),
      child: Text(
        label.toUpperCase(),
        style: AppTextStyles.navSectionLabel.copyWith(
          color: const Color(0x40FFFFFF),
        ),
      ),
    );
  }
}

// ── Nav item ──────────────────────────────────────────────────────────────────

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.route,
    required this.currentRoute,
    required this.collapsed,
    required this.navigationShell,
    this.badgeCount,
  });
  final IconData icon;
  final String label;
  final String route;
  final String currentRoute;
  final bool collapsed;
  final StatefulNavigationShell navigationShell;
  final int? badgeCount;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  bool get _isActive =>
      widget.currentRoute == widget.route ||
      widget.currentRoute.startsWith('${widget.route}/');

  @override
  Widget build(BuildContext context) {
    final content = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          final branchIndex = _kRouteBranchIndex[widget.route];
          if (branchIndex != null) {
            widget.navigationShell.goBranch(
              branchIndex,
              initialLocation: branchIndex == widget.navigationShell.currentIndex,
            );
          } else {
            context.go(widget.route);
          }
        },
        child: widget.collapsed
            ? _buildCollapsed()
            : _buildExpanded(),
      ),
    );

    // Tooltip solo cuando está colapsado
    if (widget.collapsed) {
      return Tooltip(
        message: widget.label,
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: AppColors.ctNavy,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: Colors.white),
        child: content,
      );
    }
    return content;
  }

  // Ítem colapsado: solo ícono centrado (con dot badge opcional)
  Widget _buildCollapsed() {
    final hasBadge = (widget.badgeCount ?? 0) > 0;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 6),
      width: 36,
      height: 32,
      decoration: BoxDecoration(
        color: _isActive
            ? const Color(0x1A59E0CC)
            : _hovered
                ? const Color(0x0DFFFFFF)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
      ),
      alignment: Alignment.center,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            widget.icon,
            size: 18,
            color: _isActive
                ? AppColors.ctTeal
                : _hovered
                    ? const Color(0xCCFFFFFF)
                    : const Color(0x66FFFFFF),
          ),
          if (hasBadge)
            Positioned(
              right: -5,
              top: -5,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.ctTeal,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Ítem expandido: ícono + texto + badge opcional, borde izquierdo si activo
  Widget _buildExpanded() {
    final badgeCount = widget.badgeCount ?? 0;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: _isActive
            ? const Color(0x1A59E0CC)
            : _hovered
                ? const Color(0x0DFFFFFF)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: _isActive
            ? const Border(
                left: BorderSide(color: AppColors.ctTeal, width: 2),
              )
            : const Border(
                left: BorderSide(color: Colors.transparent, width: 2),
              ),
      ),
      child: Row(
        children: [
          Icon(
            widget.icon,
            size: 16,
            color: _isActive
                ? AppColors.ctTeal
                : _hovered
                    ? const Color(0xCCFFFFFF)
                    : const Color(0x66FFFFFF),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              widget.label,
              style: AppTextStyles.bodySmall.copyWith(
                fontSize: 12,
                fontWeight: _isActive ? FontWeight.w600 : FontWeight.w400,
                color: _isActive
                    ? AppColors.ctTeal
                    : _hovered
                        ? const Color(0xCCFFFFFF)
                        : const Color(0x8CFFFFFF),
                letterSpacing: -0.12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (badgeCount > 0) ...[
            const SizedBox(width: 4),
            Container(
              constraints: const BoxConstraints(minWidth: 15),
              height: 15,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AppColors.ctTeal,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                badgeCount > 99 ? '99+' : '$badgeCount',
                style: AppTextStyles.navSectionLabel.copyWith(color: AppColors.ctNavy),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Escalaciones nav item (with Realtime badge) ───────────────────────────────

class _EscalacionesNavItem extends ConsumerWidget {
  const _EscalacionesNavItem({
    required this.currentRoute,
    required this.collapsed,
    required this.navigationShell,
  });
  final String currentRoute;
  final bool   collapsed;
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(openEscalationsCountProvider).valueOrNull ?? 0;
    return _NavItem(
      icon:            Icons.warning_amber_rounded,
      label:           'Escalaciones',
      route:           '/escalaciones',
      currentRoute:    currentRoute,
      collapsed:       collapsed,
      navigationShell: navigationShell,
      badgeCount:      count > 0 ? count : null,
    );
  }
}

// ── Expandable nav item (parent + sub-items) ──────────────────────────────────

class _ExpandableSubItem {
  const _ExpandableSubItem({
    required this.icon,
    required this.label,
    required this.route,
    required this.currentRoute,
  });
  final IconData icon;
  final String label;
  final String route;
  final String currentRoute;

  bool get isActive =>
      currentRoute == route || currentRoute.startsWith('$route/');
}

class _ExpandableNavItem extends StatefulWidget {
  const _ExpandableNavItem({
    required this.icon,
    required this.label,
    required this.currentRoute,
    required this.collapsed,
    required this.children,
  });
  final IconData icon;
  final String label;
  final String currentRoute;
  final bool collapsed;
  final List<_ExpandableSubItem> children;

  @override
  State<_ExpandableNavItem> createState() => _ExpandableNavItemState();
}

class _ExpandableNavItemState extends State<_ExpandableNavItem> {
  bool _hovered = false;

  bool get _anyChildActive =>
      widget.children.any((c) => c.isActive);

  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = _anyChildActive;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.collapsed) {
      // Collapsed: show only icon with tooltip
      return Tooltip(
        message: widget.label,
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: AppColors.ctNavy,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: Colors.white),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 6),
          width: 36, height: 32,
          decoration: BoxDecoration(
            color: _anyChildActive
                ? const Color(0x1A59E0CC)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          alignment: Alignment.center,
          child: Icon(widget.icon, size: 18,
              color: _anyChildActive
                  ? AppColors.ctTeal
                  : const Color(0x66FFFFFF)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Parent row
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit:  (_) => setState(() => _hovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: _anyChildActive
                    ? const Color(0x1A59E0CC)
                    : _hovered ? const Color(0x0DFFFFFF) : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: _anyChildActive
                    ? const Border(
                        left: BorderSide(color: AppColors.ctTeal, width: 2))
                    : const Border(
                        left: BorderSide(color: Colors.transparent, width: 2)),
              ),
              child: Row(
                children: [
                  Icon(widget.icon, size: 16,
                      color: _anyChildActive
                          ? AppColors.ctTeal
                          : _hovered
                              ? const Color(0xCCFFFFFF)
                              : const Color(0x66FFFFFF)),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(widget.label,
                        style: AppTextStyles.bodySmall.copyWith(
                          fontSize: 12,
                          fontWeight: _anyChildActive ? FontWeight.w600 : FontWeight.w400,
                          color: _anyChildActive
                              ? AppColors.ctTeal
                              : _hovered
                                  ? const Color(0xCCFFFFFF)
                                  : const Color(0x8CFFFFFF),
                          letterSpacing: -0.12,
                        ),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 14,
                    color: _anyChildActive
                        ? AppColors.ctTeal
                        : const Color(0x66FFFFFF),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Sub-items
        if (_expanded)
          ...widget.children.map((sub) => _SubItemTile(sub: sub)),
      ],
    );
  }
}

class _SubItemTile extends StatefulWidget {
  const _SubItemTile({required this.sub});
  final _ExpandableSubItem sub;

  @override
  State<_SubItemTile> createState() => _SubItemTileState();
}

class _SubItemTileState extends State<_SubItemTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.sub.isActive;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.go(widget.sub.route),
        child: Container(
          margin: const EdgeInsets.only(left: 24, right: 6, top: 1, bottom: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: active
                ? const Color(0x1A59E0CC)
                : _hovered ? const Color(0x0DFFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: active
                ? const Border(
                    left: BorderSide(color: AppColors.ctTeal, width: 2))
                : const Border(
                    left: BorderSide(color: Colors.transparent, width: 2)),
          ),
          child: Row(
            children: [
              Icon(widget.sub.icon, size: 14,
                  color: active
                      ? AppColors.ctTeal
                      : _hovered
                          ? const Color(0xCCFFFFFF)
                          : const Color(0x66FFFFFF)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(widget.sub.label,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active
                          ? AppColors.ctTeal
                          : _hovered
                              ? const Color(0xCCFFFFFF)
                              : const Color(0x8CFFFFFF),
                      letterSpacing: -0.12,
                    ),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


