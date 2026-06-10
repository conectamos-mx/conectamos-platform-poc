// lib/features/config/connections_screen.dart
// Centro de Aplicaciones — V1 (diseño aprobado)

import 'dart:async';
import 'dart:html' as html;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/catalogs_api.dart';
import '../../core/api/connections_api.dart';
import '../../core/api/flows_api.dart';
import '../../core/api/ai_workers_api.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_shell.dart';

// ─── Design tokens locales ────────────────────────────────────────────────────

const _teal400  = AppColors.ctTeal;
const _teal500  = Color(0xFF5BC0BE);
const _steel300 = Color(0xFFA9C6D8);
const _steel400 = Color(0xFF7B92A7);
const _text4    = Color(0xFF4C5D73);
const _success  = Color(0xFF107C41);
const _warn     = Color(0xFFFFB700);
const _warnText = Color(0xFFb07a00);
const _surface50 = Color(0xFFFAFAFA);
const _surface100 = Color(0xFFF1F1F1);
const _tealNewText = Color(0xFF007e6e);
const _tealBetaText = Color(0xFF2c7a78);
const _dotMuted = Color(0xFF9AA0A3);

// ─── Enum & modelo ────────────────────────────────────────────────────────────

enum IntegrationState { available, connected, soon, attention, newItem, beta }

enum IntegrationCategory { all, storage, calendar, automation, finance, analytics }

class Integration {
  const Integration({
    required this.id,
    required this.name,
    required this.category,
    required this.logoKey,
    required this.short,
    required this.desc,
    required this.state,
    required this.auth,
    this.accountLabel,
    this.lastSync,
    this.permissions,
  });

  final String id;
  final String name;
  final IntegrationCategory category;
  final String logoKey;
  final String short;
  final String desc;
  final IntegrationState state;
  final String auth;
  final String? accountLabel;
  final String? lastSync;
  final List<String>? permissions;

  Integration copyWith({
    IntegrationState? state,
    String? accountLabel,
    String? lastSync,
  }) => Integration(
    id: id, name: name, category: category, logoKey: logoKey,
    short: short, desc: desc, state: state ?? this.state, auth: auth,
    accountLabel: accountLabel ?? this.accountLabel,
    lastSync: lastSync ?? this.lastSync,
    permissions: permissions,
  );
}

// ─── Catálogo ─────────────────────────────────────────────────────────────────

const _kCategories = <({IntegrationCategory id, String label, IconData icon})>[
  (id: IntegrationCategory.all,        label: 'Todas',                   icon: Icons.grid_view_rounded),
  (id: IntegrationCategory.storage,    label: 'Almacenamiento',          icon: Icons.folder_outlined),
  (id: IntegrationCategory.calendar,   label: 'Calendarios',             icon: Icons.calendar_today_outlined),
  (id: IntegrationCategory.automation, label: 'Automatización',          icon: Icons.bolt_outlined),
  (id: IntegrationCategory.finance,    label: 'Finanzas y Contabilidad', icon: Icons.account_balance_outlined),
  (id: IntegrationCategory.analytics,  label: 'Análisis y BI',           icon: Icons.bar_chart_rounded),
];

const _kApps = <Integration>[
  Integration(
    id: 'gdrive', name: 'Google Drive', category: IntegrationCategory.storage,
    logoKey: 'gdrive', short: 'Almacenamiento en la nube',
    desc: 'Adjunta archivos de Drive en tareas, sincroniza carpetas y comparte documentos sin salir de Conectamos.',
    state: IntegrationState.connected, auth: 'oauth',
    accountLabel: 'tomas@conectamos.mx', lastSync: 'hace 4 min',
    permissions: ['Leer y escribir archivos', 'Listar carpetas compartidas', 'Crear enlaces de acceso'],
  ),
  Integration(
    id: 'onedrive', name: 'OneDrive', category: IntegrationCategory.storage,
    logoKey: 'onedrive', short: 'Almacenamiento de Microsoft',
    desc: 'Sincroniza archivos y carpetas de OneDrive personal o empresarial directamente en tus operaciones.',
    state: IntegrationState.available, auth: 'oauth',
    permissions: ['Leer y escribir archivos', 'Listar carpetas compartidas'],
  ),
  Integration(
    id: 'dropbox', name: 'Dropbox', category: IntegrationCategory.storage,
    logoKey: 'dropbox', short: 'Almacenamiento colaborativo',
    desc: 'Conecta carpetas de Dropbox para adjuntar archivos y mantener versiones sincronizadas.',
    state: IntegrationState.soon, auth: 'oauth',
  ),
  Integration(
    id: 'gcal', name: 'Google Calendar', category: IntegrationCategory.calendar,
    logoKey: 'gcal', short: 'Calendario de Google',
    desc: 'Crea eventos, sincroniza horarios de workers y genera recordatorios automáticos en tu calendario.',
    state: IntegrationState.connected, auth: 'oauth',
    accountLabel: 'operaciones@conectamos.mx', lastSync: 'hace 12 min',
    permissions: ['Leer eventos', 'Crear y modificar eventos', 'Acceso a calendarios compartidos'],
  ),
  Integration(
    id: 'outlook', name: 'Outlook Calendar', category: IntegrationCategory.calendar,
    logoKey: 'outlook', short: 'Calendario de Microsoft',
    desc: 'Sincroniza la agenda de Outlook con tareas y disponibilidad de tu equipo.',
    state: IntegrationState.attention, auth: 'oauth',
    accountLabel: 'tomas@empresa.com', lastSync: 'hace 2 días',
    permissions: ['Leer eventos', 'Crear y modificar eventos'],
  ),
  Integration(
    id: 'n8n', name: 'n8n', category: IntegrationCategory.automation,
    logoKey: 'n8n', short: 'Automatización open source',
    desc: 'Dispara flujos de n8n con cualquier evento de Conectamos y recibe respuestas en tiempo real.',
    state: IntegrationState.newItem, auth: 'webhook',
    permissions: ['Disparar webhooks', 'Recibir respuestas', 'Mapear datos de tareas'],
  ),
  Integration(
    id: 'zapier', name: 'Zapier', category: IntegrationCategory.automation,
    logoKey: 'zapier', short: 'Automatización sin código',
    desc: 'Conecta Conectamos con miles de aplicaciones a través de Zaps, sin escribir una sola línea.',
    state: IntegrationState.available, auth: 'oauth',
    permissions: ['Disparar Zaps', 'Recibir acciones', 'Mapear campos'],
  ),
  Integration(
    id: 'make', name: 'Make', category: IntegrationCategory.automation,
    logoKey: 'make', short: 'Escenarios visuales',
    desc: 'Construye escenarios complejos de automatización con la interfaz visual de Make.',
    state: IntegrationState.beta, auth: 'oauth',
    permissions: ['Disparar escenarios', 'Recibir respuestas'],
  ),
  Integration(
    id: 'tableau', name: 'Tableau', category: IntegrationCategory.analytics,
    logoKey: 'tableau', short: 'Visualización de datos',
    desc: 'Envía datos de Conectamos a Tableau para construir dashboards y análisis avanzados.',
    state: IntegrationState.soon, auth: 'apikey',
  ),
  Integration(
    id: 'quickbooks', name: 'QuickBooks', category: IntegrationCategory.finance,
    logoKey: 'quickbooks', short: 'Contabilidad y facturación',
    desc: 'Sincroniza facturas, gastos y clientes con tu contabilidad de QuickBooks.',
    state: IntegrationState.soon, auth: 'oauth',
  ),
  Integration(
    id: 'alegra', name: 'Alegra', category: IntegrationCategory.finance,
    logoKey: 'alegra', short: 'Facturación electrónica LATAM',
    desc: 'Genera facturas electrónicas, lleva inventario y sincroniza clientes con Alegra.',
    state: IntegrationState.available, auth: 'apikey',
    permissions: ['Crear facturas', 'Leer y crear clientes', 'Gestionar inventario'],
  ),
  Integration(
    id: 'gsheets', name: 'Google Sheets', category: IntegrationCategory.analytics,
    logoKey: 'gsheets', short: 'Hojas de cálculo en la nube',
    desc: 'Exporta ejecuciones, campos y datos de operadores directamente a Google Sheets en tiempo real.',
    state: IntegrationState.available, auth: 'oauth',
    permissions: ['Leer y escribir hojas de cálculo', 'Crear y compartir documentos', 'Acceso a Google Drive'],
  ),
];

const _kApiIntegrations = <Integration>[
  Integration(
    id: 'rest-api', name: 'API REST de Conectamos', category: IntegrationCategory.all,
    logoKey: 'code', short: 'Endpoints HTTP públicos',
    desc: 'Crea, lee y actualiza recursos de tu workspace con endpoints REST autenticados por token.',
    state: IntegrationState.connected, auth: 'apikey',
    accountLabel: '3 tokens activos',
  ),
  Integration(
    id: 'webhooks', name: 'Webhooks salientes', category: IntegrationCategory.all,
    logoKey: 'webhook', short: 'Eventos en tiempo real',
    desc: 'Recibe eventos de tareas, workers y canales en tu propio endpoint cada vez que algo cambia.',
    state: IntegrationState.connected, auth: 'webhook',
    accountLabel: '5 webhooks configurados',
  ),
  Integration(
    id: 'oauth-app', name: 'Apps OAuth de terceros', category: IntegrationCategory.all,
    logoKey: 'key', short: 'Permite conexiones externas',
    desc: 'Registra una app OAuth para que servicios externos accedan a tu workspace con permisos granulares.',
    state: IntegrationState.available, auth: 'oauth',
  ),
  Integration(
    id: 'graphql', name: 'API GraphQL', category: IntegrationCategory.all,
    logoKey: 'globe', short: 'Consultas tipadas',
    desc: 'Consulta solo los campos que necesitas con un esquema GraphQL fuertemente tipado.',
    state: IntegrationState.beta, auth: 'apikey',
  ),
  Integration(
    id: 'sdk-node', name: 'SDK de Node.js', category: IntegrationCategory.all,
    logoKey: 'code', short: 'Librería oficial JS/TS',
    desc: 'Cliente oficial para Node con tipados completos, retries y manejo de paginación.',
    state: IntegrationState.newItem, auth: 'apikey',
  ),
  Integration(
    id: 'sdk-python', name: 'SDK de Python', category: IntegrationCategory.all,
    logoKey: 'code', short: 'Librería oficial Python',
    desc: 'Cliente oficial para Python 3.10+ con soporte async y modelos Pydantic.',
    state: IntegrationState.soon, auth: 'apikey',
  ),
];

// ─── Pantalla principal ───────────────────────────────────────────────────────

class ConnectionsScreen extends ConsumerStatefulWidget {
  const ConnectionsScreen({super.key});
  @override
  ConsumerState<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends ConsumerState<ConnectionsScreen>
    with SingleTickerProviderStateMixin {

  String _activeTab = 'apps';
  IntegrationCategory _activeCategory = IntegrationCategory.all;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  late Set<String> _connectedIds;
  Integration? _managingItem;

  // Google Sheets runtime state
  String? _gsheetsEmail;
  String? _gsheetsConnectedAt;
  Timer? _gsheetsOAuthTimer;
  StreamSubscription<html.MessageEvent>? _oauthMessageSub;

  // Microsoft / OneDrive runtime state
  String? _microsoftEmail;
  String? _microsoftConnectedAt;
  Timer? _microsoftOAuthTimer;
  StreamSubscription<html.MessageEvent>? _microsoftOAuthSub;

  late final AnimationController _drawerCtrl;
  late final Animation<Offset> _drawerSlide;

  @override
  void initState() {
    super.initState();
    _connectedIds = {
      ..._kApps.where((i) => i.state == IntegrationState.connected).map((i) => i.id),
      ..._kApiIntegrations.where((i) => i.state == IntegrationState.connected).map((i) => i.id),
    };
    _drawerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _drawerSlide = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _drawerCtrl, curve: Curves.easeOut));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(topbarTitleProvider.notifier).state = 'Conexiones';
      ref.read(topbarSubtitleProvider.notifier).state = 'Centro de aplicaciones';
      ref.read(topbarActionsProvider.notifier).state = [];
      _loadGoogleStatus();
      _loadMicrosoftStatus();
    });
  }

  Future<void> _loadGoogleStatus() async {
    try {
      final status = await ConnectionsApi.getGoogleStatus();
      if (!mounted) return;
      final connected = status['connected'] as bool? ?? false;
      setState(() {
        if (connected) {
          _connectedIds = {..._connectedIds, 'gsheets'};
          _gsheetsEmail = status['email'] as String?;
          _gsheetsConnectedAt = status['connected_at'] as String?;
        } else {
          _connectedIds = Set.from(_connectedIds)..remove('gsheets');
          _gsheetsEmail = null;
          _gsheetsConnectedAt = null;
        }
      });
    } catch (_) {
      // silently ignore — keep static state
    }
  }

  Future<void> _loadMicrosoftStatus() async {
    try {
      final tenantId = ref.read(activeTenantIdProvider);
      if (tenantId.isEmpty) return;
      final status = await ConnectionsApi.getMicrosoftStatus(tenantId: tenantId);
      if (!mounted) return;
      final connections = (status['connections'] as List?) ?? [];
      final microsoftConn = connections
          .cast<Map<String, dynamic>>()
          .where((c) => c['provider'] == 'microsoft' && c['status'] == 'active')
          .firstOrNull;
      final connected = microsoftConn != null;
      setState(() {
        if (connected) {
          _connectedIds = {..._connectedIds, 'onedrive'};
          _microsoftEmail = microsoftConn['email'] as String?;
          _microsoftConnectedAt = microsoftConn['connected_at'] as String?;
        } else {
          _connectedIds = Set.from(_connectedIds)..remove('onedrive');
          _microsoftEmail = null;
          _microsoftConnectedAt = null;
        }
      });
    } catch (_) {
      // silently ignore — keep static state
    }
  }

  @override
  void dispose() {
    _gsheetsOAuthTimer?.cancel();
    _oauthMessageSub?.cancel();
    _microsoftOAuthTimer?.cancel();
    _microsoftOAuthSub?.cancel();
    _drawerCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Integration> get _filtered {
    final base = _activeTab == 'apps' ? _kApps : _kApiIntegrations;
    return base.where((it) {
      final inCat = _activeTab == 'api' ||
          _activeCategory == IntegrationCategory.all ||
          it.category == _activeCategory;
      final q = _searchQuery.toLowerCase();
      final inQ = q.isEmpty ||
          it.name.toLowerCase().contains(q) ||
          it.short.toLowerCase().contains(q);
      return inCat && inQ;
    }).map((it) {
      if (_connectedIds.contains(it.id)) {
        if (it.id == 'gsheets') {
          return it.copyWith(
            state: IntegrationState.connected,
            accountLabel: _gsheetsEmail,
            lastSync: _gsheetsConnectedAt != null ? 'Conectado el $_gsheetsConnectedAt' : null,
          );
        }
        if (it.id == 'onedrive') {
          return it.copyWith(
            state: IntegrationState.connected,
            accountLabel: _microsoftEmail,
            lastSync: _microsoftConnectedAt != null ? 'Conectado el $_microsoftConnectedAt' : null,
          );
        }
        return it.copyWith(state: IntegrationState.connected);
      }
      return it;
    }).toList();
  }

  int _catCount(IntegrationCategory cat) => cat == IntegrationCategory.all
      ? _kApps.length
      : _kApps.where((i) => i.category == cat).length;

  void _onCardTap(Integration item) {
    if (item.state == IntegrationState.soon) return;
    if (item.id == 'rest-api') {
      _showManageSheet(item, 'inbound');
      return;
    }
    if (item.id == 'webhooks') {
      _showManageSheet(item, 'outbound');
      return;
    }
    if (item.id == 'gsheets') {
      final isConnected = _connectedIds.contains('gsheets');
      if (isConnected || item.state == IntegrationState.attention) {
        _openManage(item);
      } else {
        _connectGsheets();
      }
      return;
    }
    if (item.id == 'onedrive') {
      final isConnected = _connectedIds.contains('onedrive');
      if (isConnected || item.state == IntegrationState.attention) {
        _openManage(item);
      } else {
        _connectMicrosoft();
      }
      return;
    }
    final isConnected = _connectedIds.contains(item.id);
    if (isConnected || item.state == IntegrationState.attention) {
      _openManage(item);
    } else {
      _showOAuth(item);
    }
  }

  Future<void> _connectGsheets() async {
    try {
      final authUrl = await ConnectionsApi.getGoogleAuthUrl();
      final popup = html.window.open(
        authUrl,
        'google_oauth',
        'width=500,height=600,scrollbars=yes,resizable=yes',
      );

      // Primary: receive postMessage from the popup close page
      _oauthMessageSub?.cancel();
      _oauthMessageSub = html.window.onMessage.listen((event) {
        final data = event.data?.toString() ?? '';
        if (data != 'google=success' && data != 'google=error') return;
        _oauthMessageSub?.cancel();
        _gsheetsOAuthTimer?.cancel();
        if (!mounted) return;
        _loadGoogleStatus();
        if (data == 'google=success') {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Google Sheets conectado correctamente.'),
            backgroundColor: Color(0xFF107C41),
            duration: Duration(seconds: 4),
          ));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Error al conectar Google Sheets. Intenta de nuevo.'),
            backgroundColor: AppColors.ctDanger,
            duration: const Duration(seconds: 4),
          ));
        }
      });

      // Fallback: poll popup.closed (user closed manually or postMessage missed)
      _gsheetsOAuthTimer?.cancel();
      _gsheetsOAuthTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!mounted) {
          _gsheetsOAuthTimer?.cancel();
          _oauthMessageSub?.cancel();
          return;
        }
        if (popup.closed == true) {
          _gsheetsOAuthTimer?.cancel();
          _oauthMessageSub?.cancel();
          _loadGoogleStatus();
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se pudo iniciar la conexión: ${_connDioError(e)}'),
        backgroundColor: AppColors.ctDanger,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  Future<void> _connectMicrosoft() async {
    try {
      final tenantId = ref.read(activeTenantIdProvider);
      final authUrl = await ConnectionsApi.getMicrosoftAuthUrl(tenantId: tenantId);
      final popup = html.window.open(
        authUrl,
        'microsoft_oauth',
        'width=500,height=600,scrollbars=yes,resizable=yes',
      );

      // Primary: receive postMessage from the popup close page
      _microsoftOAuthSub?.cancel();
      _microsoftOAuthSub = html.window.onMessage.listen((event) {
        final data = event.data?.toString() ?? '';
        if (data != 'microsoft=success' && data != 'microsoft=error') return;
        _microsoftOAuthSub?.cancel();
        _microsoftOAuthTimer?.cancel();
        if (!mounted) return;
        _loadMicrosoftStatus();
        if (data == 'microsoft=success') {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('OneDrive conectado correctamente.'),
            backgroundColor: Color(0xFF107C41),
            duration: Duration(seconds: 4),
          ));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Error al conectar OneDrive. Intenta de nuevo.'),
            backgroundColor: AppColors.ctDanger,
            duration: const Duration(seconds: 4),
          ));
        }
      });

      // Fallback: poll popup.closed (user closed manually or postMessage missed)
      _microsoftOAuthTimer?.cancel();
      _microsoftOAuthTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!mounted) {
          _microsoftOAuthTimer?.cancel();
          _microsoftOAuthSub?.cancel();
          return;
        }
        if (popup.closed == true) {
          _microsoftOAuthTimer?.cancel();
          _microsoftOAuthSub?.cancel();
          _loadMicrosoftStatus();
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se pudo iniciar la conexión: ${_connDioError(e)}'),
        backgroundColor: AppColors.ctDanger,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  void _showManageSheet(Integration item, String typeFilter) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _IntegrationsManagementSheet(
        item: item,
        typeFilter: typeFilter,
      ),
    );
  }

  void _openManage(Integration item) {
    setState(() => _managingItem = item);
    _drawerCtrl.forward();
  }

  void _closeManage() {
    _drawerCtrl.reverse().whenComplete(() {
      if (mounted) setState(() => _managingItem = null);
    });
  }

  void _disconnect(Integration item) {
    _closeManage();
    if (item.id == 'gsheets') {
      Future.delayed(const Duration(milliseconds: 260), () async {
        if (!mounted) return;
        setState(() {
          _connectedIds = Set.from(_connectedIds)..remove('gsheets');
          _gsheetsEmail = null;
          _gsheetsConnectedAt = null;
        });
        try {
          await ConnectionsApi.disconnectGoogle();
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error al desconectar: ${_connDioError(e)}'),
            backgroundColor: AppColors.ctDanger,
            duration: const Duration(seconds: 4),
          ));
          // Reload real status to reconcile UI
          _loadGoogleStatus();
        }
      });
      return;
    }
    if (item.id == 'onedrive') {
      Future.delayed(const Duration(milliseconds: 260), () async {
        if (!mounted) return;
        setState(() {
          _connectedIds = Set.from(_connectedIds)..remove('onedrive');
          _microsoftEmail = null;
          _microsoftConnectedAt = null;
        });
        try {
          final tenantId = ref.read(activeTenantIdProvider);
          await ConnectionsApi.disconnectMicrosoft(tenantId: tenantId);
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error al desconectar: ${_connDioError(e)}'),
            backgroundColor: AppColors.ctDanger,
            duration: const Duration(seconds: 4),
          ));
          _loadMicrosoftStatus();
        }
      });
      return;
    }
    Future.delayed(const Duration(milliseconds: 260), () {
      if (mounted) setState(() => _connectedIds = Set.from(_connectedIds)..remove(item.id));
    });
  }

  void _showOAuth(Integration item) {
    showDialog(
      context: context,
      barrierColor: const Color(0x8C0B132B),
      builder: (ctx) => _OAuthDialog(
        item: item,
        onConnect: (i) {
          Navigator.of(ctx).pop();
          setState(() => _connectedIds = {..._connectedIds, i.id});
        },
        onCancel: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final showRecommended = _activeTab == 'apps' &&
        _activeCategory == IntegrationCategory.all &&
        _searchQuery.isEmpty;

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Hero header
            _ScreenHeader(connectedCount: _connectedIds.length),
            // ── Tabs
            _TabsBar(
              activeTab: _activeTab,
              onChanged: (t) => setState(() {
                _activeTab = t;
                _activeCategory = IntegrationCategory.all;
                _searchQuery = '';
                _searchCtrl.clear();
              }),
            ),
            // ── Body
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sidebar (solo en tab apps)
                  if (_activeTab == 'apps')
                    _CategoriesSidebar(
                      active: _activeCategory,
                      query: _searchQuery,
                      searchCtrl: _searchCtrl,
                      catCount: _catCount,
                      onCategory: (c) => setState(() => _activeCategory = c),
                      onSearch: (q) => setState(() => _searchQuery = q),
                    ),
                  // Content
                  Expanded(
                    child: _ContentArea(
                      activeTab: _activeTab,
                      filtered: filtered,
                      showRecommended: showRecommended,
                      query: _searchQuery,
                      searchCtrl: _searchCtrl,
                      activeCategory: _activeCategory,
                      onSearch: (q) => setState(() => _searchQuery = q),
                      onCardTap: _onCardTap,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // ── Drawer overlay
        if (_managingItem != null) ...[
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeManage,
              child: AnimatedBuilder(
                animation: _drawerCtrl,
                builder: (_, child) => ColoredBox(
                  color: Color.lerp(Colors.transparent, const Color(0x8C0B132B), _drawerCtrl.value)!,
                ),
              ),
            ),
          ),
          Positioned(
            right: 0, top: 0, bottom: 0, width: 520,
            child: SlideTransition(
              position: _drawerSlide,
              child: _ManageDrawer(
                item: _managingItem!,
                connectedIds: _connectedIds,
                onClose: _closeManage,
                onDisconnect: _disconnect,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Hero header ──────────────────────────────────────────────────────────────

class _ScreenHeader extends StatelessWidget {
  const _ScreenHeader({required this.connectedCount});
  final int connectedCount;

  @override
  Widget build(BuildContext context) {
    final total = _kApps.length + _kApiIntegrations.length;
    return Container(
      color: AppColors.ctSurface,
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Conexiones',
                  style: AppFonts.onest(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _teal400,
                    letterSpacing: -0.02 * 11,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Centro de aplicaciones',
                  style: AppFonts.onest(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ctNavy,
                    height: 1.1,
                    letterSpacing: -0.04 * 32,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Conecta Conectamos con las herramientas que ya usas.\nPlugins, SDKs y APIs externas para extender tu workspace.',
                  style: AppFonts.geist(
                    fontSize: 15,
                    color: AppColors.ctText2,
                    height: 1.5,
                    letterSpacing: -0.01 * 15,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 32),
          Row(
            children: [
              _StatWidget(value: '$connectedCount', label: 'conectadas'),
              const SizedBox(width: 32),
              _StatWidget(value: '$total', label: 'disponibles'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatWidget extends StatelessWidget {
  const _StatWidget({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: AppFonts.onest(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: AppColors.ctNavy,
            height: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppFonts.geist(
            fontSize: 12,
            color: _steel400,
          ),
        ),
      ],
    );
  }
}

// ─── Tab bar ──────────────────────────────────────────────────────────────────

class _TabsBar extends StatelessWidget {
  const _TabsBar({required this.activeTab, required this.onChanged});
  final String activeTab;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.ctSurface,
        border: Border(bottom: BorderSide(color: AppColors.ctBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        children: [
          _Tab(
            label: 'Aplicaciones',
            icon: Icons.grid_view_rounded,
            count: _kApps.length,
            active: activeTab == 'apps',
            onTap: () => onChanged('apps'),
          ),
          const SizedBox(width: 4),
          _Tab(
            label: 'Integraciones API',
            icon: Icons.code_rounded,
            count: _kApiIntegrations.length,
            active: activeTab == 'api',
            onTap: () => onChanged('api'),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    required this.label,
    required this.icon,
    required this.count,
    required this.active,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? AppColors.ctNavy : (_hovered ? AppColors.ctText : AppColors.ctText2);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: widget.active ? _teal400 : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: AppFonts.geist(
                  fontSize: 13,
                  fontWeight: widget.active ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: widget.active ? AppColors.ctNavy.withValues(alpha: 0.08) : _surface100,
                  borderRadius: BorderRadius.circular(1024),
                ),
                child: Text(
                  '${widget.count}',
                  style: AppFonts.geist(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: widget.active ? AppColors.ctNavy : _steel400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Sidebar de categorías ────────────────────────────────────────────────────

class _CategoriesSidebar extends StatelessWidget {
  const _CategoriesSidebar({
    required this.active,
    required this.query,
    required this.searchCtrl,
    required this.catCount,
    required this.onCategory,
    required this.onSearch,
  });
  final IntegrationCategory active;
  final String query;
  final TextEditingController searchCtrl;
  final int Function(IntegrationCategory) catCount;
  final ValueChanged<IntegrationCategory> onCategory;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: AppColors.ctSurface,
        border: Border(right: BorderSide(color: AppColors.ctBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Búsqueda
          _SidebarSearch(controller: searchCtrl, onChanged: onSearch),
          const SizedBox(height: 16),
          // Label
          Text(
            'Categorías',
            style: AppFonts.geist(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _steel400,
              letterSpacing: 0.04 * 11,
            ),
          ),
          const SizedBox(height: 6),
          // Items
          ..._kCategories.map((cat) => _CategoryItem(
            cat: cat,
            active: active == cat.id,
            count: catCount(cat.id),
            onTap: () => onCategory(cat.id),
          )),
        ],
      ),
    );
  }
}

class _SidebarSearch extends StatefulWidget {
  const _SidebarSearch({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<_SidebarSearch> createState() => _SidebarSearchState();
}

class _SidebarSearchState extends State<_SidebarSearch> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      child: TextField(
        controller: widget.controller,
        onChanged: widget.onChanged,
        style: AppFonts.geist(fontSize: 13, color: AppColors.ctText),
        decoration: InputDecoration(
          hintText: 'Buscar integración',
          hintStyle: AppFonts.geist(fontSize: 13, color: AppColors.ctText3),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 15,
            color: _focused ? _teal400 : AppColors.ctText3,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          filled: true,
          fillColor: _surface50,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          isDense: true,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.ctBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _teal400, width: 1.5),
          ),
        ),
      ),
    );
  }
}

class _CategoryItem extends StatefulWidget {
  const _CategoryItem({
    required this.cat,
    required this.active,
    required this.count,
    required this.onTap,
  });
  final ({IntegrationCategory id, String label, IconData icon}) cat;
  final bool active;
  final int count;
  final VoidCallback onTap;

  @override
  State<_CategoryItem> createState() => _CategoryItemState();
}

class _CategoryItemState extends State<_CategoryItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color iconColor;
    Color textColor;
    Color countColor;

    if (widget.active) {
      bg = AppColors.ctNavy;
      iconColor = AppColors.ctTealHover;
      textColor = Colors.white;
      countColor = Colors.white.withValues(alpha: 0.6);
    } else if (_hovered) {
      bg = _surface100;
      iconColor = AppColors.ctText2;
      textColor = AppColors.ctText;
      countColor = _steel400;
    } else {
      bg = Colors.transparent;
      iconColor = AppColors.ctText2;
      textColor = _text4;
      countColor = _steel400;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(widget.cat.icon, size: 15, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.cat.label,
                  style: AppFonts.geist(
                    fontSize: 13,
                    fontWeight: widget.active ? FontWeight.w500 : FontWeight.w400,
                    color: textColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${widget.count}',
                style: AppFonts.geist(fontSize: 12, color: countColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Área de contenido ────────────────────────────────────────────────────────

class _ContentArea extends StatelessWidget {
  const _ContentArea({
    required this.activeTab,
    required this.filtered,
    required this.showRecommended,
    required this.query,
    required this.searchCtrl,
    required this.activeCategory,
    required this.onSearch,
    required this.onCardTap,
  });
  final String activeTab;
  final List<Integration> filtered;
  final bool showRecommended;
  final String query;
  final TextEditingController searchCtrl;
  final IntegrationCategory activeCategory;
  final ValueChanged<String> onSearch;
  final ValueChanged<Integration> onCardTap;

  String get _sectionTitle {
    if (activeTab == 'api') return 'Integraciones de desarrollador';
    if (activeCategory == IntegrationCategory.all) return 'Todas las aplicaciones';
    return _kCategories.firstWhere((c) => c.id == activeCategory).label;
  }

  String get _sectionSub {
    if (activeTab == 'api') return 'APIs, SDKs y webhooks para construir sobre Conectamos';
    final n = filtered.length;
    return '$n ${n == 1 ? 'integración' : 'integraciones'}';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 24, 40, 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search (solo tab API)
          if (activeTab == 'api') ...[
            _WideSearch(controller: searchCtrl, onChanged: onSearch),
            const SizedBox(height: 24),
          ],
          // Recomendadas
          if (showRecommended) ...[
            _SectionBlock(
              title: 'Recomendadas para ti',
              subtitle: 'Las más usadas por equipos como el tuyo',
              items: filtered.take(3).toList(),
              onCardTap: onCardTap,
            ),
            const SizedBox(height: 32),
          ],
          // Grid principal
          if (filtered.isEmpty)
            _EmptyState(query: query)
          else
            _SectionBlock(
              title: _sectionTitle,
              subtitle: _sectionSub,
              items: filtered,
              onCardTap: onCardTap,
            ),
          const SizedBox(height: 40),
          const Divider(color: AppColors.ctBorder),
          const SizedBox(height: 32),
          const _CatalogsSection(),
        ],
      ),
    );
  }
}

// ── Catálogos conectados ──────────────────────────────────────────────────────

class _CatalogsSection extends ConsumerStatefulWidget {
  const _CatalogsSection();

  @override
  ConsumerState<_CatalogsSection> createState() => _CatalogsSectionState();
}

class _CatalogsSectionState extends ConsumerState<_CatalogsSection> {
  bool _loading = true;
  List<Map<String, dynamic>> _catalogs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final tenantId = ref.read(activeTenantIdProvider);
      final dio = ref.read(apiClientProvider).dio;
      final data = await CatalogsApi.listCatalogs(dio: dio, tenantId: tenantId);
      if (mounted) setState(() { _catalogs = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Catálogos conectados',
          style: AppFonts.onest(
              fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ctText),
        ),
        const SizedBox(height: 4),
        Text(
          'Fuentes de datos sincronizadas con tu operación.',
          style: AppFonts.geist(fontSize: 13, color: AppColors.ctText2),
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CircularProgressIndicator(
                  color: AppColors.ctTeal, strokeWidth: 2),
            ),
          )
        else if (_catalogs.isEmpty)
          _EmptyCatalogsState()
        else
          Column(
            children: _catalogs
                .map((cat) => _CatalogTile(catalog: cat))
                .toList(),
          ),
      ],
    );
  }
}

class _EmptyCatalogsState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open_outlined,
                size: 36, color: AppColors.ctText2),
            const SizedBox(height: 10),
            Text(
              'Sin catálogos configurados',
              style: AppFonts.onest(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ctText2),
            ),
            const SizedBox(height: 8),
            AppButton(
              label: 'Crear catálogo',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              onPressed: () => context.go('/catalogs'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogTile extends StatelessWidget {
  const _CatalogTile({required this.catalog});
  final Map<String, dynamic> catalog;

  static const _sourceIcons = <String, IconData>{
    'manual':          Icons.edit_note_rounded,
    'google_sheets':   Icons.table_chart_outlined,
    'onedrive_excel':  Icons.grid_on_outlined,
    'webhook_push':    Icons.webhook_outlined,
    'api_pull':        Icons.cloud_download_outlined,
  };

  static const _syncColors = <String, Color>{
    'synced':  AppColors.ctTeal,
    'failed':  AppColors.ctDanger,
    'running': _warn,
    'manual':  AppColors.ctText3,
  };

  @override
  Widget build(BuildContext context) {
    final label      = catalog['label'] as String? ?? catalog['name'] as String? ?? '—';
    final slug       = catalog['slug'] as String? ?? '';
    final sourceType = catalog['source_type'] as String? ?? '';
    final itemsCount = catalog['items_count'] as int? ?? 0;
    final syncStatus = catalog['sync_status'] as String? ?? 'manual';

    final sourceIcon = _sourceIcons[sourceType] ?? Icons.storage_rounded;
    final syncColor  = _syncColors[syncStatus] ?? AppColors.ctText3;
    final syncLabel  = switch (syncStatus) {
      'synced'  => 'Sincronizado',
      'failed'  => 'Error',
      'running' => 'Sincronizando',
      'manual'  => 'Manual',
      _         => syncStatus,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(sourceIcon, size: 18, color: AppColors.ctText2),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppFonts.geist(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ctText),
                ),
                if (slug.isNotEmpty)
                  Text(slug,
                      style: AppFonts.geist(
                          fontSize: 11, color: AppColors.ctText3)),
              ],
            ),
          ),
          Text(
            '$itemsCount items',
            style: AppFonts.geist(fontSize: 12, color: AppColors.ctText2),
          ),
          const SizedBox(width: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: syncColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: syncColor.withValues(alpha: 0.35)),
            ),
            child: Text(
              syncLabel,
              style: AppFonts.geist(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: syncColor),
            ),
          ),
          const SizedBox(width: 12),
          AppButton(
            label: 'Ver',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            isDisabled: slug.isEmpty,
            onPressed: () => context.go('/catalogs/$slug'),
          ),
        ],
      ),
    );
  }
}

class _WideSearch extends StatefulWidget {
  const _WideSearch({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<_WideSearch> createState() => _WideSearchState();
}

class _WideSearchState extends State<_WideSearch> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      child: TextField(
        controller: widget.controller,
        onChanged: widget.onChanged,
        style: AppFonts.geist(fontSize: 14, color: AppColors.ctText),
        decoration: InputDecoration(
          hintText: 'Buscar integración API',
          hintStyle: AppFonts.geist(fontSize: 14, color: AppColors.ctText3),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 16,
            color: _focused ? _teal400 : AppColors.ctText3,
          ),
          filled: true,
          fillColor: _surface50,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.ctBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _teal400, width: 1.5),
          ),
        ),
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.onCardTap,
  });
  final String title;
  final String subtitle;
  final List<Integration> items;
  final ValueChanged<Integration> onCardTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              title,
              style: AppFonts.onest(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.ctNavy,
                letterSpacing: -0.03 * 18,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              subtitle,
              style: AppFonts.geist(fontSize: 13, color: _steel400),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, constraints) {
          const cols = 3;
          const gap = 16.0;
          final colWidth = (constraints.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: items.map((item) => SizedBox(
              width: colWidth,
              child: _IntegrationCard(item: item, onTap: () => onCardTap(item)),
            )).toList(),
          );
        }),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 40, color: AppColors.ctBorder2),
            const SizedBox(height: 12),
            Text(
              query.isNotEmpty
                  ? 'No se encontraron integraciones para "$query"'
                  : 'No hay integraciones en esta categoría',
              style: AppFonts.geist(fontSize: 14, color: AppColors.ctText2),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Card de integración ──────────────────────────────────────────────────────

class _IntegrationCard extends StatefulWidget {
  const _IntegrationCard({required this.item, required this.onTap});
  final Integration item;
  final VoidCallback onTap;

  @override
  State<_IntegrationCard> createState() => _IntegrationCardState();
}

class _IntegrationCardState extends State<_IntegrationCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.item.state == IntegrationState.soon;
    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
      onEnter: (_) { if (!disabled) setState(() => _hovered = true); },
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: disabled ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.ctSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.ctBorder),
            boxShadow: _hovered
                ? [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
                    BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 1)),
                  ]
                : [],
          ),
          transform: _hovered
              ? Matrix4.translationValues(0.0, -2.0, 0.0)
              : Matrix4.identity(),
          child: Opacity(
            opacity: disabled ? 0.65 : 1.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IntegrationLogo(logoKey: widget.item.logoKey, size: 40),
                    const Spacer(),
                    if (widget.item.state == IntegrationState.connected)
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: _success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(1024),
                        ),
                        child: const Icon(Icons.check_rounded, size: 13, color: _success),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  widget.item.name,
                  style: AppFonts.onest(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ctNavy,
                    letterSpacing: -0.02 * 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.item.short,
                  style: AppFonts.geist(
                    fontSize: 13,
                    color: _text4,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 14),
                _StatusPill(state: widget.item.state),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Status pill ──────────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.state});
  final IntegrationState state;

  @override
  Widget build(BuildContext context) {
    final (bg, border, textColor, dotColor, label) = switch (state) {
      IntegrationState.available  => (_surface50, AppColors.ctBorder, _text4,     _steel300, 'Disponible'),
      IntegrationState.connected  => (_success.withValues(alpha: 0.08),  Colors.transparent, _success,  _success,  'Conectado'),
      IntegrationState.attention  => (_warn.withValues(alpha: 0.12),    Colors.transparent, _warnText, _warn,     'Requiere atención'),
      IntegrationState.soon       => (_surface100, Colors.transparent, _steel400, _dotMuted, 'Próximamente'),
      IntegrationState.newItem    => (_teal400.withValues(alpha: 0.16), Colors.transparent, _tealNewText, _teal400, 'Nuevo'),
      IntegrationState.beta       => (_teal500.withValues(alpha: 0.14), Colors.transparent, _tealBetaText, _teal500, 'Beta'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(1024),
        border: border != Colors.transparent ? Border.all(color: border) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppFonts.geist(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Logo de integración ──────────────────────────────────────────────────────

class _IntegrationLogo extends StatelessWidget {
  const _IntegrationLogo({required this.logoKey, required this.size});
  final String logoKey;
  final double size;

  static const _brandBg = {
    'gdrive':     Color(0xFF4285F4),
    'gcal':       Color(0xFF0F9D58),
    'gsheets':    Color(0xFF0F9D58),
    'onedrive':   Color(0xFF0078D4),
    'outlook':    Color(0xFF0078D4),
    'dropbox':    Color(0xFF0061FF),
    'n8n':        Color(0xFFEA4B71),
    'zapier':     Color(0xFFFF4A00),
    'make':       Color(0xFF6C00CC),
    'tableau':    Color(0xFFE8762D),
    'quickbooks': Color(0xFF2CA01C),
    'alegra':     Color(0xFFFF6A1A),
  };

  static const _brandInitials = {
    'gdrive':     'G',
    'gcal':       'G',
    'gsheets':    'S',
    'onedrive':   'O',
    'outlook':    'O',
    'dropbox':    'D',
    'n8n':        'n',
    'zapier':     'Z',
    'make':       'M',
    'tableau':    'T',
    'quickbooks': 'Q',
    'alegra':     'A',
    'gmail':      'G',
  };

  // Local asset paths — SVG, PNG, WEBP
  static const _assetPaths = {
    'gdrive':     'assets/logos/drive.png',
    'gcal':       'assets/logos/google_calendar.png',
    'gsheets':    'assets/logos/google-sheets',
    'onedrive':   'assets/logos/ondrive.svg',
    'outlook':    'assets/logos/outlook.png',
    'dropbox':    'assets/logos/dropbox.svg',
    'n8n':        'assets/logos/n8n.webp',
    'zapier':     'assets/logos/zapier.png',
    'make':       'assets/logos/make.png',
    'tableau':    'assets/logos/tableau.svg',
    'quickbooks': 'assets/logos/quickbooks.svg',
    'alegra':     'assets/logos/alegra.png',
    'gmail':      'assets/logos/gmail.png',
  };

  static const _apiIcons = {
    'code':    Icons.code_rounded,
    'webhook': Icons.webhook_rounded,
    'key':     Icons.vpn_key_rounded,
    'globe':   Icons.language_rounded,
  };

  Widget _buildAsset(String path) {
    final fallback = Text(
      _brandInitials[logoKey] ?? logoKey[0].toUpperCase(),
      style: AppFonts.onest(
        fontSize: size * 0.35,
        fontWeight: FontWeight.w700,
        color: _brandBg[logoKey] ?? AppColors.ctTeal,
      ),
    );
    if (path.endsWith('.svg')) {
      return SvgPicture.asset(
        path,
        width: size * 0.58,
        height: size * 0.58,
        placeholderBuilder: (_) => fallback,
      );
    }
    return Image.asset(
      path,
      width: size * 0.58,
      height: size * 0.58,
      errorBuilder: (_, error, stack) => fallback,
    );
  }

  @override
  Widget build(BuildContext context) {
    final assetPath = _assetPaths[logoKey];
    final apiIcon = _apiIcons[logoKey];
    final radius = BorderRadius.circular(size * 0.22);

    if (assetPath != null) {
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: radius,
        ),
        alignment: Alignment.center,
        child: _buildAsset(assetPath),
      );
    }

    // API icon (code, webhook, key, globe) — teal gradient
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.ctTealHover, _teal500],
        ),
        borderRadius: radius,
      ),
      alignment: Alignment.center,
      child: Icon(
        apiIcon ?? Icons.extension_rounded,
        size: size * 0.48,
        color: AppColors.ctNavy,
      ),
    );
  }
}

// ─── OAuth dialog (3 pasos) ───────────────────────────────────────────────────

enum _OAuthStep { review, authorizing, success }

class _OAuthDialog extends StatefulWidget {
  const _OAuthDialog({
    required this.item,
    required this.onConnect,
    required this.onCancel,
  });
  final Integration item;
  final ValueChanged<Integration> onConnect;
  final VoidCallback onCancel;

  @override
  State<_OAuthDialog> createState() => _OAuthDialogState();
}

class _OAuthDialogState extends State<_OAuthDialog> {
  _OAuthStep _step = _OAuthStep.review;
  Timer? _timer;

  void _authorize() {
    setState(() => _step = _OAuthStep.authorizing);
    _timer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _step = _OAuthStep.success);
      _timer = Timer(const Duration(milliseconds: 800), () {
        if (mounted) widget.onConnect(widget.item);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: SizedBox(
        width: 460,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.ctSurface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 40, offset: const Offset(0, 16)),
            ],
          ),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Close
              if (_step == _OAuthStep.review)
                Align(
                  alignment: Alignment.topRight,
                  child: _IconButton(
                    icon: Icons.close_rounded,
                    onTap: widget.onCancel,
                  ),
                ),
              // Logos row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.ctNavy,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.bolt_rounded, color: _teal400, size: 22),
                  ),
                  const SizedBox(width: 12),
                  // Animating dots
                  Row(
                    children: List.generate(5, (i) => _PulseDot(delay: i * 150)),
                  ),
                  const SizedBox(width: 12),
                  _IntegrationLogo(logoKey: widget.item.logoKey, size: 40),
                ],
              ),
              const SizedBox(height: 24),
              if (_step == _OAuthStep.success) ...[
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    color: _success.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: _success.withValues(alpha: 0.3), width: 2),
                  ),
                  child: const Icon(Icons.check_rounded, size: 32, color: _success),
                ),
                const SizedBox(height: 16),
                Text(
                  '¡${widget.item.name} conectado!',
                  style: AppFonts.onest(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ctNavy),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Ya puedes empezar a usar la integración en tus operaciones.',
                  style: AppFonts.geist(fontSize: 14, color: AppColors.ctText2, height: 1.5),
                  textAlign: TextAlign.center,
                ),
              ] else if (_step == _OAuthStep.authorizing) ...[
                const SizedBox(
                  width: 36, height: 36,
                  child: CircularProgressIndicator(
                    color: _teal400,
                    strokeWidth: 3,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Autorizando con ${widget.item.name}…',
                  style: AppFonts.onest(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ctNavy),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Espera mientras se completa la autorización en una nueva ventana.',
                  style: AppFonts.geist(fontSize: 14, color: AppColors.ctText2, height: 1.5),
                  textAlign: TextAlign.center,
                ),
              ] else ...[
                Text(
                  'Conectar ${widget.item.name}',
                  style: AppFonts.onest(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ctNavy),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Conectamos solicitará los siguientes permisos a tu cuenta de ${widget.item.name}.',
                  style: AppFonts.geist(fontSize: 14, color: AppColors.ctText2, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                if ((widget.item.permissions ?? []).isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ...widget.item.permissions!.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 18, height: 18,
                          decoration: BoxDecoration(
                            color: _success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(Icons.check_rounded, size: 11, color: _success),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(p, style: AppFonts.geist(fontSize: 13, color: AppColors.ctText)),
                        ),
                      ],
                    ),
                  )),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: AppButton(
                      label: 'Cancelar',
                      variant: AppButtonVariant.outline,
                      size: AppButtonSize.sm,
                      expand: true,
                      onPressed: widget.onCancel,
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: AppButton(
                      label: 'Autorizar con ${widget.item.name}',
                      variant: AppButtonVariant.teal,
                      size: AppButtonSize.sm,
                      expand: true,
                      onPressed: _authorize,
                    )),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_outline_rounded, size: 12, color: _steel400),
                    const SizedBox(width: 6),
                    Text(
                      'Puedes revocar el acceso en cualquier momento desde Conexiones.',
                      style: AppFonts.geist(fontSize: 11, color: _steel400),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.delay});
  final int delay;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (_, child) => Opacity(
          opacity: _anim.value,
          child: Container(
            width: 5, height: 5,
            decoration: const BoxDecoration(color: _teal400, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

// ─── Manage drawer ────────────────────────────────────────────────────────────

class _ManageDrawer extends StatelessWidget {
  const _ManageDrawer({
    required this.item,
    required this.connectedIds,
    required this.onClose,
    required this.onDisconnect,
  });
  final Integration item;
  final Set<String> connectedIds;
  final VoidCallback onClose;
  final ValueChanged<Integration> onDisconnect;

  String get _authLabel => switch (item.auth) {
    'oauth'   => 'OAuth 2.0',
    'apikey'  => 'API Key',
    'webhook' => 'Webhook',
    _         => item.auth,
  };

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 0,
      color: AppColors.ctSurface,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: AppColors.ctBorder)),
        ),
        child: Column(
          children: [
            // ── Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.ctBorder)),
              ),
              child: Row(
                children: [
                  _IntegrationLogo(logoKey: item.logoKey, size: 52),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: AppFonts.onest(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ctNavy,
                            letterSpacing: -0.03 * 20,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(item.short, style: AppFonts.geist(fontSize: 13, color: _steel400)),
                        const SizedBox(height: 8),
                        _StatusPill(state: connectedIds.contains(item.id) ? IntegrationState.connected : item.state),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _IconButton(icon: Icons.close_rounded, onTap: onClose),
                ],
              ),
            ),
            // ── Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.desc,
                      style: AppFonts.geist(fontSize: 14, color: AppColors.ctText2, height: 1.55),
                    ),
                    // Alert
                    if (item.state == IntegrationState.attention) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _warn.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _warn.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 18, color: _warn),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Token expirado', style: AppFonts.geist(fontSize: 13, fontWeight: FontWeight.w600, color: _warnText)),
                                  const SizedBox(height: 2),
                                  Text('Vuelve a autorizar para continuar sincronizando.', style: AppFonts.geist(fontSize: 12, color: _warnText)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            AppButton(label: 'Reautorizar', variant: AppButtonVariant.teal, size: AppButtonSize.sm, onPressed: onClose),
                          ],
                        ),
                      ),
                    ],
                    // Cuenta conectada
                    if (item.accountLabel != null) ...[
                      const SizedBox(height: 20),
                      _DrawerSection(
                        title: 'Cuenta conectada',
                        children: [
                          _DrawerRow(label: 'Cuenta', value: item.accountLabel!),
                          if (item.lastSync != null)
                            _DrawerRow(label: 'Última sincronización', value: item.lastSync!),
                          _DrawerRow(label: 'Tipo de auth', value: _authLabel),
                        ],
                      ),
                    ],
                    // Permisos
                    if ((item.permissions ?? []).isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _DrawerSection(
                        title: 'Permisos otorgados',
                        children: item.permissions!.map((p) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 16, height: 16,
                                decoration: BoxDecoration(
                                  color: _success.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(Icons.check_rounded, size: 10, color: _success),
                              ),
                              const SizedBox(width: 8),
                              Text(p, style: AppFonts.geist(fontSize: 13, color: AppColors.ctText)),
                            ],
                          ),
                        )).toList(),
                      ),
                    ],
                    // Actividad reciente
                    const SizedBox(height: 20),
                    _DrawerSection(
                      title: 'Actividad reciente',
                      children: [
                        _ActivityRow(color: _success, text: 'Sincronización completada · ${item.lastSync ?? 'hace 4 min'}'),
                        const _ActivityRow(color: _success, text: '3 archivos nuevos importados · hace 1 h'),
                        const _ActivityRow(color: AppColors.ctInfo, text: 'Permisos actualizados · ayer'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // ── Footer
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.ctBorder)),
              ),
              child: Row(
                children: [
                  AppButton(
                    label: 'Sincronizar',
                    variant: AppButtonVariant.outline,
                    size: AppButtonSize.sm,
                    prefixIcon: const Icon(Icons.sync_rounded, size: 14, color: AppColors.ctInk700),
                    onPressed: () {},
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    label: 'Avanzado',
                    variant: AppButtonVariant.outline,
                    size: AppButtonSize.sm,
                    prefixIcon: const Icon(Icons.open_in_new_rounded, size: 14, color: AppColors.ctInk700),
                    onPressed: () {},
                  ),
                  const Spacer(),
                  AppButton(
                    label: 'Desconectar',
                    variant: AppButtonVariant.danger,
                    size: AppButtonSize.sm,
                    prefixIcon: const Icon(Icons.delete_outline_rounded, size: 14, color: Colors.white),
                    onPressed: () => onDisconnect(item),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerSection extends StatelessWidget {
  const _DrawerSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppFonts.geist(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _steel400,
            letterSpacing: 0.04 * 11,
          ),
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }
}

class _DrawerRow extends StatelessWidget {
  const _DrawerRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: AppFonts.geist(fontSize: 13, color: _steel400)),
          ),
          Expanded(
            child: Text(value, style: AppFonts.geist(fontSize: 13, color: AppColors.ctText, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 7, height: 7,
            margin: const EdgeInsets.only(right: 10, top: 1),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(child: Text(text, style: AppFonts.geist(fontSize: 13, color: AppColors.ctText2))),
        ],
      ),
    );
  }
}

class _IconButton extends StatefulWidget {
  const _IconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: _hovered ? AppColors.ctSurface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(widget.icon, size: 18, color: AppColors.ctText2),
        ),
      ),
    );
  }
}

// ─── Integraciones API — Management sheet ────────────────────────────────────

class _IntegrationsManagementSheet extends ConsumerStatefulWidget {
  const _IntegrationsManagementSheet({
    required this.item,
    required this.typeFilter,
  });
  final Integration item;
  final String typeFilter; // 'inbound' or 'outbound'

  @override
  ConsumerState<_IntegrationsManagementSheet> createState() =>
      _IntegrationsManagementSheetState();
}

class _IntegrationsManagementSheetState
    extends ConsumerState<_IntegrationsManagementSheet> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  bool _deleting = false;

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
      final all = await FlowsApi.listIntegrationsByTenant();
      if (!mounted) return;
      final filtered = all.where((i) {
        final t = (i['integration_type'] as String? ?? '').toLowerCase();
        if (widget.typeFilter == 'inbound') return t == 'api' || t == 'inbound';
        return t == 'outbound' || t == 'webhook' || t == 'webhook_out';
      }).toList();
      setState(() {
        _items = filtered;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _connDioError(e);
        _loading = false;
      });
    }
  }

  Future<void> _delete(String id) async {
    if (_deleting) return;
    setState(() => _deleting = true);
    try {
      await FlowsApi.deleteIntegrationById(integrationId: id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_connDioError(e)),
        backgroundColor: AppColors.ctDanger,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  void _confirmDelete(String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eliminar integración', style: AppTextStyles.pageTitle),
        content: Text(
          '¿Eliminar "$name"? Esta acción no se puede deshacer.',
          style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
        ),
        actions: [
          AppButton(
            label: 'Cancelar',
            variant: AppButtonVariant.outline,
            size: AppButtonSize.sm,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          AppButton(
            label: 'Eliminar',
            variant: AppButtonVariant.danger,
            size: AppButtonSize.sm,
            onPressed: () {
              Navigator.of(ctx).pop();
              _delete(id);
            },
          ),
        ],
      ),
    );
  }

  void _openCreate() {
    showDialog(
      context: context,
      builder: (_) => _CreateTenantIntegrationDialog(
        defaultType: widget.typeFilter == 'inbound' ? 'api' : 'webhook',
        onCreated: (integration) async {
          await _showSecretDialog(integration);
          await _load();
        },
      ),
    );
  }

  Future<void> _showSecretDialog(Map<String, dynamic> integration) async {
    final apiKeyPlain = integration['api_key_plain'] as String?;
    final hmacSecretPlain = integration['hmac_secret_plain'] as String?;
    final secret = apiKeyPlain ?? hmacSecretPlain;
    final label = apiKeyPlain != null ? 'API Key' : 'HMAC Secret';
    if (!mounted) return;
    if (secret == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Integración creada, pero no se pudo recuperar el secret. Contacta soporte.',
        ),
        duration: Duration(seconds: 5),
      ));
      return;
    }
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Copia tu $label ahora', style: AppTextStyles.pageTitle),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppColors.ctDanger, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Esta es la única vez que verás esta clave. Guárdala en un lugar seguro.',
                      style: AppTextStyles.body.copyWith(color: AppColors.ctDanger),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(label, style: AppTextStyles.formLabel),
              const SizedBox(height: 6),
              _SecretBox(secret: secret),
            ],
          ),
        ),
        actions: [
          AppButton(
            label: 'Entendido',
            variant: AppButtonVariant.teal,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isInbound = widget.typeFilter == 'inbound';
    final title = isInbound ? 'API REST de Conectamos' : 'Webhooks salientes';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: AppColors.ctSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              color: AppColors.ctBorder2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 0),
            child: Row(
              children: [
                _IntegrationLogo(logoKey: widget.item.logoKey, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppFonts.onest(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ctNavy,
                        ),
                      ),
                      Text(
                        widget.item.short,
                        style: AppFonts.geist(fontSize: 13, color: _steel400),
                      ),
                    ],
                  ),
                ),
                AppButton(
                  label: 'Nueva',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                  prefixIcon: const Icon(Icons.add_rounded, size: 16, color: _teal400),
                  onPressed: _openCreate,
                ),
              ],
            ),
          ),
          const Divider(height: 20),
          // Body
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _teal400),
                  )
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              style: AppFonts.geist(
                                  fontSize: 13, color: AppColors.ctDanger),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            AppButton(
                              label: 'Reintentar',
                              variant: AppButtonVariant.ghost,
                              size: AppButtonSize.sm,
                              onPressed: _load,
                            ),
                          ],
                        ),
                      )
                    : _items.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.electrical_services_outlined,
                                    size: 40, color: AppColors.ctBorder2),
                                const SizedBox(height: 10),
                                Text(
                                  'Sin integraciones',
                                  style: AppFonts.onest(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.ctText2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Crea una nueva para empezar.',
                                  style: AppFonts.geist(
                                      fontSize: 13, color: AppColors.ctText3),
                                ),
                                const SizedBox(height: 20),
                                AppButton(
                                  label: 'Nueva integración',
                                  variant: AppButtonVariant.teal,
                                  prefixIcon: const Icon(Icons.add, size: 16),
                                  onPressed: _openCreate,
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 8),
                            itemCount: _items.length,
                            separatorBuilder: (_, index) =>
                                const SizedBox(height: 8),
                            itemBuilder: (ctx, i) {
                              final intg = _items[i];
                              final id = intg['id'] as String? ?? '';
                              final name =
                                  intg['name'] as String? ?? '(sin nombre)';
                              final type =
                                  intg['integration_type'] as String? ?? '';
                              final isActive =
                                  intg['is_active'] as bool? ?? true;
                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppColors.ctSurface,
                                  border: Border.all(color: AppColors.ctBorder),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                name,
                                                style: AppFonts.geist(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.ctText,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: isActive
                                                      ? AppColors.ctOkBg
                                                      : AppColors.ctSurface2,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  isActive ? 'Activo' : 'Inactivo',
                                                  style: AppTextStyles.badge.copyWith(
                                                    color: isActive
                                                        ? AppColors.ctOkText
                                                        : AppColors.ctText3,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _connTypeLabel(type),
                                            style: AppFonts.geist(
                                                fontSize: 12, color: _steel400),
                                          ),
                                        ],
                                      ),
                                    ),
                                    _deleting
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: _teal400),
                                          )
                                        : IconButton(
                                            icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              size: 18,
                                              color: AppColors.ctText3,
                                            ),
                                            tooltip: 'Eliminar',
                                            onPressed: id.isNotEmpty
                                                ? () =>
                                                    _confirmDelete(id, name)
                                                : null,
                                          ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

// ─── Create tenant integration dialog ─────────────────────────────────────────

class _CreateTenantIntegrationDialog extends ConsumerStatefulWidget {
  const _CreateTenantIntegrationDialog({
    required this.defaultType,
    required this.onCreated,
  });
  final String defaultType;
  final Future<void> Function(Map<String, dynamic>) onCreated;

  @override
  ConsumerState<_CreateTenantIntegrationDialog> createState() =>
      _CreateTenantIntegrationDialogState();
}

class _CreateTenantIntegrationDialogState
    extends ConsumerState<_CreateTenantIntegrationDialog> {
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  late String _type;
  String? _workerId;
  List<Map<String, dynamic>> _workers = [];
  bool _workersLoading = true;
  bool _saving = false;
  String? _error;
  int _rateLimit = 60;

  static const _kTypes = [
    ('api', 'API Key'),
    ('webhook', 'Webhook'),
    ('n8n', 'n8n'),
    ('zapier', 'Zapier'),
    ('make', 'Make'),
  ];

  @override
  void initState() {
    super.initState();
    _type = widget.defaultType;
    _nameCtrl.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadWorkers());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadWorkers() async {
    try {
      final list = await AiWorkersApi.listWorkers();
      if (!mounted) return;
      setState(() {
        _workers = list;
        _workersLoading = false;
        if (list.isNotEmpty) _workerId = list.first['id'] as String?;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _workersLoading = false);
    }
  }

  Future<void> _submit() async {
    if (_saving || _workerId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await FlowsApi.createIntegrationForTenant(
        name: _nameCtrl.text.trim(),
        integrationType: _type,
        tenantWorkerId: _workerId!,
        endpointUrl: _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
        rateLimitPerMinute: _rateLimit,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onCreated(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _connDioError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsUrl = _type == 'webhook' || _type == 'n8n';
    final nameValid = _nameCtrl.text.trim().isNotEmpty;
    final canSubmit =
        nameValid && _workerId != null && !_workersLoading && !_saving;

    return AlertDialog(
      title: Text('Nueva integración', style: AppTextStyles.pageTitle),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name
            Text('Nombre', style: AppTextStyles.formLabel),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: AppFonts.geist(fontSize: 13, color: AppColors.ctText),
              decoration: InputDecoration(
                hintText: 'Ej: Mi sistema externo',
                hintStyle:
                    AppFonts.geist(fontSize: 13, color: AppColors.ctText3),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppColors.ctBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppColors.ctBorder),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Type
            Text('Tipo', style: AppTextStyles.formLabel),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.ctBorder),
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButton<String>(
                value: _type,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                style:
                    AppFonts.geist(fontSize: 13, color: AppColors.ctText),
                items: _kTypes
                    .map((t) =>
                        DropdownMenuItem(value: t.$1, child: Text(t.$2)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _type = v);
                },
              ),
            ),
            const SizedBox(height: 16),
            // Worker
            Text('Worker', style: AppTextStyles.formLabel),
            const SizedBox(height: 6),
            _workersLoading
                ? const SizedBox(
                    height: 36,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _teal400),
                      ),
                    ),
                  )
                : _workers.isEmpty
                    ? Text(
                        'No hay workers disponibles',
                        style: AppFonts.geist(
                            fontSize: 13, color: AppColors.ctText3),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.ctBorder),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        child: DropdownButton<String>(
                          value: _workerId,
                          isExpanded: true,
                          underline: const SizedBox.shrink(),
                          style: AppFonts.geist(
                              fontSize: 13, color: AppColors.ctText),
                          items: _workers
                              .map((w) => DropdownMenuItem<String>(
                                    value: w['id'] as String?,
                                    child: Text(
                                      w['display_name'] as String? ??
                                          w['name'] as String? ??
                                          'Worker',
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _workerId = v);
                          },
                        ),
                      ),
            if (needsUrl) ...[
              const SizedBox(height: 14),
              Text('URL del endpoint', style: AppTextStyles.formLabel),
              const SizedBox(height: 6),
              TextField(
                controller: _urlCtrl,
                style: AppFonts.geist(fontSize: 13, color: AppColors.ctText),
                decoration: InputDecoration(
                  hintText: 'https://...',
                  hintStyle:
                      AppFonts.geist(fontSize: 13, color: AppColors.ctText3),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: AppColors.ctBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: AppColors.ctBorder),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'Límite por minuto:',
                  style: AppFonts.geist(
                      fontSize: 13, color: AppColors.ctText),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 72,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    style:
                        AppFonts.geist(fontSize: 13, color: AppColors.ctText),
                    controller:
                        TextEditingController(text: _rateLimit.toString()),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            const BorderSide(color: AppColors.ctBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            const BorderSide(color: AppColors.ctBorder),
                      ),
                    ),
                    onChanged: (v) {
                      final n = int.tryParse(v);
                      if (n != null && n > 0) _rateLimit = n;
                    },
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctDanger),
              ),
            ],
          ],
        ),
      ),
      actions: [
        AppButton(
          label: 'Cancelar',
          variant: AppButtonVariant.outline,
          size: AppButtonSize.sm,
          isDisabled: _saving,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Crear',
          variant: AppButtonVariant.teal,
          size: AppButtonSize.sm,
          isLoading: _saving,
          isDisabled: !canSubmit,
          onPressed: _submit,
        ),
      ],
    );
  }
}

// ─── Secret box ───────────────────────────────────────────────────────────────

class _SecretBox extends StatefulWidget {
  const _SecretBox({required this.secret});
  final String secret;

  @override
  State<_SecretBox> createState() => _SecretBoxState();
}

class _SecretBoxState extends State<_SecretBox> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.ctSurface2,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              widget.secret,
              style: AppTextStyles.body,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              _copied ? Icons.check : Icons.copy_outlined,
              size: 16,
              color: _copied ? AppColors.ctOk : AppColors.ctText3,
            ),
            tooltip: 'Copiar',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.secret));
              setState(() => _copied = true);
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) setState(() => _copied = false);
              });
            },
          ),
        ],
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _connTypeLabel(String type) => switch (type) {
      'api' => 'API Key',
      'inbound' => 'Inbound',
      'outbound' => 'Outbound',
      'webhook' || 'webhook_out' => 'Webhook',
      'zapier' => 'Zapier',
      'make' => 'Make',
      'n8n' => 'n8n',
      _ => type,
    };

String _connDioError(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      final d = data['detail'];
      if (d != null) return 'Error: $d';
    }
    final s = e.response?.statusCode;
    if (s != null) return 'Error $s';
  }
  return e.toString();
}
