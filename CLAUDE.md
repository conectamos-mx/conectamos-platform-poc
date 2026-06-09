# CLAUDE.md — conectamos-platform

This file is the single source of guidance for Claude Code working in this repository.
Read it fully before touching any file. Do not invent patterns not described here.

---

## Commands

```bash
# Install dependencies
flutter pub get

# Run in Chrome (only supported target — Flutter Web)
flutter run -d chrome

# Analyze (run before every commit — fix all warnings before delivering)
flutter analyze

# Build for production
flutter build web --release

# Deploy to Firebase Hosting
firebase deploy --only hosting

# Run code generation (Riverpod generators)
dart run build_runner build --delete-conflicting-outputs
```

Unit tests live in `test/unit/` — run with `flutter test test/unit/`.

---

## Architecture overview

**Flutter Web SPA** targeting Chrome only. No mobile/desktop targets.

### Data flow

```
Supabase Realtime (stream)  ──→  ConsumerStatefulWidget (setState)  ──→  ListView.builder
FastAPI backend (Dio)        ──→  fire-and-forget or await in handler
```

All authenticated requests go through `ApiClient` (Dio, `lib/core/api/api_client.dart`),
which injects `Authorization: Bearer {supabase_access_token}` via `InterceptorsWrapper`.
Backend base URL: `https://platform-api.conectamos.ai`.

Supabase is used directly for:
- Auth (email+password)
- Realtime message streams (`wa_messages` table via `.stream()`)
- Read receipts (`supabase_read_receipts.dart`)

### Multi-tenancy

Every screen and query is scoped by `activeTenantIdProvider` (Riverpod `Provider<String>`).
When it changes, all streams re-subscribe and all lists reload.
**Never hardcode tenant IDs** — always `ref.read(activeTenantIdProvider)`.

Superadmin (`miguel@conectamos.mx`) can switch tenants; other users see only their own.
Tenant selection persists in `localStorage` key `conectamos_active_tenant`.

### Shell layout

`AppShell` (`lib/shared/widgets/app_shell.dart`) wraps all authenticated routes via
`ShellRoute` in go_router. Collapsible sidebar + topbar. Screens inject title/subtitle/actions
via providers (`topbarTitleProvider`, etc.).
Auth screens (`/login`, `/forgot-password`, `/reset-password`, `/activate`) bypass the shell.

---

## Directory structure & file naming

```
lib/
  core/
    api/          — static API classes, one file per domain: [domain]_api.dart
    router/
      app_router.dart   — single go_router instance
    theme/
      colors.dart       — AppColors constants
  features/
    config/       — configuration screens (channels, flows, operators)
    settings/     — tenant settings
    [module]/     — one folder per feature
  shared/
    widgets/      — shared widgets (AppShell, etc.)
```

**Naming rules:**
- Screens: `[name]_screen.dart`
- Detail screens with tabs: `[name]_detail_screen.dart`
- API classes: `[domain]_api.dart` in `lib/core/api/`

---

## Routing (go_router)

**File:** `lib/core/router/app_router.dart`

```dart
GoRoute(
  path: '/flows/:flowId',
  pageBuilder: (context, state) {
    final flowId = state.pathParameters['flowId'] ?? '';
    return NoTransitionPage(
      child: FlowDetailScreen(flowId: flowId),
    );
  },
),
```

**Rules:**
- All parameterized routes go inside `ShellRoute`.
- Always use `NoTransitionPage` — no transition animations.
- Extract path params with `state.pathParameters['key'] ?? ''`.
- Add new routes next to others in the same domain.

`kMockMode = false` (in `lib/core/config.dart`) — when false, unauthenticated users redirect
to `/login`; authenticated users at `/login` go to `/overview`. Public auth routes skip guard.

---

## API classes

**Reference file:** `lib/core/api/flows_api.dart`

```dart
static Future<Map<String, dynamic>> getFlow({
  required String tenantId,
  required String flowId,
}) async {
  final resp = await ApiClient.dio.get(
    '/flows/$flowId',
    queryParameters: {'tenant_id': tenantId},
  );
  return resp.data as Map<String, dynamic>;
}
```

**Rules:**
- Methods are always static — never instantiate the class.
- `tenant_id` always as query parameter (`queryParameters:`), never in the body.
- Use `ApiClient.dio` — never create Dio instances directly.
- Return types by method type:
  - `list*` → `List<Map<String, dynamic>>`
  - `get*`, `create*`, `update*` → `Map<String, dynamic>`
  - `delete*` → `void`

---

## Detail screens with tabs (canonical pattern)

**Reference:** `OperatorDetailScreen`, `ChannelDetailScreen`

```dart
class FlowDetailScreen extends ConsumerStatefulWidget {
  const FlowDetailScreen({super.key, required this.flowId});
  final String flowId;

  @override
  ConsumerState<FlowDetailScreen> createState() => _FlowDetailScreenState();
}

class _FlowDetailScreenState extends ConsumerState<FlowDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }
}
```

**AppBar with TabBar:**
```dart
appBar: AppBar(
  bottom: TabBar(
    controller: _tabCtrl,
    labelColor: AppColors.ctTeal,
    unselectedLabelColor: AppColors.ctText2,
    indicatorColor: AppColors.ctTeal,
    labelStyle: const TextStyle(
      fontFamily: 'Geist',
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
    tabs: const [Tab(text: 'INFO'), Tab(text: 'CAMPOS'), ...],
  ),
),
```

**Body:**
```dart
body: Column(
  children: [
    _ScreenHeader(data: _data),
    Expanded(
      child: TabBarView(
        controller: _tabCtrl,
        children: [_InfoTab(...), _CamposTab(...), ...],
      ),
    ),
  ],
),
```

> If the number of tabs varies by condition, create `TabController` inside `_load()` instead of `initState()`.

---

## Async state pattern

Every screen with async data uses this exact pattern — no variations:

```dart
bool _loading = true;
String? _error;
Map<String, dynamic>? _flow; // replace type as needed

Future<void> _load() async {
  setState(() { _loading = true; _error = null; });
  try {
    final tenantId = ref.read(activeTenantIdProvider);
    final data = await FlowsApi.getFlow(tenantId: tenantId, flowId: widget.flowId);
    setState(() { _flow = data; _loading = false; });
  } catch (e) {
    setState(() { _error = e.toString(); _loading = false; });
  }
}
```

**Loading state:** `Center(child: CircularProgressIndicator(color: AppColors.ctTeal))`
**Error state:** `Center(child: Text(_error!, style: TextStyle(color: AppColors.ctDanger)))`

---

## Drag-to-reorder

Use `SliverReorderableList` — **never** `ReorderableListView`.
**Reference:** `lib/features/settings/operator_fields_screen.dart:502`

```dart
SliverReorderableList(
  itemCount: _fields.length,
  onReorder: canManage ? _onReorder : (oldIndex, newIndex) {},
  itemBuilder: (context, i) {
    final field = _fields[i];
    final id = field['id'] as String? ?? i.toString();
    return _FieldCard(
      key: ValueKey(id),  // REQUIRED — must be unique and stable
      field: field,
      index: i,
      canManage: canManage,
      onEdit: () => _openEdit(field),
    );
  },
),
```

**Drag handle inside item:**
```dart
ReorderableDragStartListener(
  index: index,
  child: Icon(Icons.drag_handle),
)
```

**onReorder logic:**
```dart
void _onReorder(int oldIndex, int newIndex) {
  setState(() {
    if (newIndex > oldIndex) newIndex--;
    final item = _fields.removeAt(oldIndex);
    _fields.insert(newIndex, item);
  });
}
```

When `canManage` is false, pass `(_, __) {}` to disable without breaking the widget.

---

## Theme & design tokens

Always use `AppColors` constants (`lib/core/theme/colors.dart`) — **never inline hex values**.

| Token | Use |
|---|---|
| `AppColors.ctTeal` | Primary accent, active tab, primary buttons |
| `AppColors.ctText2` | Secondary labels, inactive tabs |
| `AppColors.ctNavy` | AppBar, topbar |
| `AppColors.ctSurface` | Card backgrounds |
| `AppColors.ctBorder` | Container borders |
| `AppColors.ctDanger` | Errors, destructive actions |

**Typography:**
- Headings / buttons ≥ 15px or w600+: `Onest` → `AppFonts.onest(...)`
- Body / data / code: `Geist` → `AppFonts.geist(...)`
Both helpers live in `app_theme.dart`.

---

## Permissions & guards

```dart
final perms = ref.watch(userPermissionsProvider);
final canManage = perms.contains('flows.manage');
```

Relevant permission strings:
- `flows.view` — view list and detail
- `flows.manage` — create, edit, delete
- `flow_executions.execute_dashboard` — view and act on "Tareas"
- `flow_integrations.manage` — manage flow integrations

---

## Screen-specific notes

### Conversations (`lib/features/conversations/conversations_screen.dart`, ~3500 lines)

- `_TabOperador`: sidebar `_ConvoList` (240px fixed) + `_ChatPanel` (flexible). Outer `Row` uses `CrossAxisAlignment.stretch`.
- `_ChatPanelState` subscribes to `SupabaseMessages.streamMessages()`. On first emit: determines `_firstUnreadMessageId`, schedules two `addPostFrameCallback` jumps to scroll bottom. On subsequent emits: auto-scrolls only if `_atBottom` threshold ≤ 100px.
- `_windowOpen` (`bool?`): `null` = loading, `true` = last inbound < 24h, `false` = closed. Input disabled when `!= true`. Badge/banner hidden for non-WhatsApp channels.
- Read receipts sent sequentially (50ms delay) to avoid burst POSTs.
- `_pendingReactions`: optimistic emoji state keyed by `wa_message_id`. Updated before POST, reverted on catch.
- `selectedChannelIdProvider` / `selectedChannelTypeProvider` — global `StateProvider<String?>` in this file. `_ActionBar` passes them as query params to `/broadcast`.
- 422 errors from `/messages/send` surface the backend `detail` field in the UI snackbar.

### Broadcasts (`lib/features/broadcasts/broadcast_screen.dart`)

- Receives `channel_id` and `channel_type` via go_router query params.
- `isTelegram` flag (from `channel_type == 'telegram'`) hides mode toggle and template dropdown.
- `channel_id` required in POST body; submit blocked with snackbar if empty.

### Channels & WhatsApp Embedded Signup (`lib/features/config/channels_screen.dart`)

- FB SDK injected at runtime via `dart:html` in `_initFbSdk()` (once, guarded by `static bool _fbSdkInitialized`).
- `@JS('_fbLaunchSignup')` binding uses `dart:js_interop`; callbacks passed with `.toJS`.
- `FB.login()` **must** be called synchronously from the user gesture (`onTap`) — no `async` gap.
- Config: `appId: '4149613485350757'`, `config_id: '2145617199565998'`, `response_type: 'code'`, `override_default_response_type: true`.
- On success: `POST /channels/embedded-signup` with `{code, tenant_id}`.
- `_embeddedSignupInProgress` guards against duplicate calls.
- Credential flow stepper: `verify-credentials` → `activate-whatsapp` → save. Both must succeed.

### Operators (`lib/features/config/operators_screen.dart`)

- Flow pre-population handles both string IDs and map objects (`op['flows']` can be either).
- `metadata` key omitted entirely when `telegramChatId == null` — never send explicit null.
- "Vincular vía Telegram" button: appears when operator has Telegram flow but no chat ID (edit mode only). Calls `POST /operators/{id}/send-telegram-invite` per unique Telegram channel. Telegram validation is warning-only, not blocking.

### Flows list (`lib/features/config/workflows_screen.dart`)

Active migration in progress — do not revert these changes:
- `_FlowCard.onTap` navigates to `/flows/${flow['id']}` via `context.go(...)` — no more edit dialog.
- Create dialog (`_openForm(flow: null)`) is kept for quick creation.
- Edit dialog (`_openForm(flow: entry)`) is removed — editing lives in `FlowDetailScreen`.

### Control Towers (`lib/features/config/worker_detail_screen.dart`)

**Tab: Torres de Control** — worker-level configuration for push-only notification groups.

**Features:**
- CRUD dialogs: `_CreateTowerDialog`, `_EditTowerDialog`
- Name validation with spam-trigger detection (words: "torre", "test", "dev", "grupo", "control")
- `_NamingGuideDialog` — info modal with examples of good/bad names and anti-spam tips
- `ParticipantsWidget` — manages phone numbers with country code selector (E.164 format)
- 3 estados visuales:
  - `active`: Badge verde "Activo", botones habilitados
  - `inactive`: Badge gris "Inactivo", banner de advertencia, botón "Eliminar" deshabilitado
  - `deleted`: NO aparece en listado (filtrado en backend)

**Backend integration:** `GroupsApi.createControlTower()`, `updateControlTower()`, `deleteControlTower()`
- Creación con delays anti-spam (2.5s entre participantes)
- Actualización calcula diff de participantes en backend
- Delete es soft-delete (`status='deleted'`)

**Flow integration:** `flow_detail_screen.dart` action `notify_group`
- Selector de tipo: "Grupo (bidireccional)" o "Torre de Control"
- Solo torres `active` aparecen en selector
- Guarda `destination_type` ('group' o 'control_tower') + `group_id`

---

## CI/CD

Push to `main` → GitHub Actions → `flutter build web --release` → `firebase deploy --only hosting`.
Production URL: `https://conectamos-platform-poc.web.app`.
Requires `FIREBASE_TOKEN` secret in GitHub Actions.

---

## Formateo de fecha/hora — NUNCA crear funciones locales

Toda lógica de formato, cálculo relativo o aritmética de calendario de fechas vive en
`lib/core/utils/` (date_format.dart, relative_time.dart, week_math.dart, telegram.dart).

  cat SKILL_DATE_UTILS.md   ← catálogo completo de las 17 funciones públicas

**Regla:** NUNCA crees una función local `_formatX`/`_fmtX` de fecha en un feature.
Usa las funciones de `lib/core/utils/`. Si ninguna cubre tu caso, agrega una función
pública AHÍ + documéntala en SKILL_DATE_UTILS.md en el mismo commit.
Prohibido duplicar arrays de meses o lógica padLeft de fecha en features.

Antes de hacer commit en cualquier screen, ejecuta:

  grep -c "_fmt\|_format.*Date\|_format.*Time\|padLeft.*'0'" [archivo]  → debe ser 0 para fecha/hora

---

## Componentes UI — leer antes de cualquier pantalla nueva o modificación

Antes de escribir cualquier widget de presentación, botón, badge, chip, fila de detalle
o tarjeta de KPI, lee el archivo de convenciones de componentes compartidos:

  cat FLUTTER_CONVENTIONS.md   ← convenciones generales del repo
  cat SKILL_FLUTTER_SHARED_WIDGETS.md   ← catálogo de primitivos y reglas de uso

### Regla de oro
Las screens en lib/features/ son compositors — solo organizan widgets.
No crean presentación inline. Antes de hacer commit en cualquier screen, ejecuta:

  grep -c "ElevatedButton\|TextButton\|OutlinedButton\|FilledButton" [archivo]  → debe ser 0
  grep -c "Color(0x\|Color.fromARGB" [archivo]  → debe ser 0
  grep -c "TextStyle(" [archivo]  → debe ser 0
  flutter analyze [archivo]  → No issues found

Si alguno retorna > 0, aplicar los primitivos de lib/shared/widgets/ antes de continuar.

### Primitivos disponibles en lib/shared/widgets/
- app_button.dart     — todos los botones (reemplaza ElevatedButton, TextButton, OutlinedButton)
- app_badge.dart      — badges de estado, canal, tipo
- app_chip.dart       — chips de filtro interactivos
- app_detail_row.dart — filas label + valor para fichas de detalle
- app_kpi_card.dart   — tarjetas de métricas numéricas
- app_shell.dart      — shell de navegación principal
- operator_avatar.dart, page_header.dart, screen_header.dart — otros shared
