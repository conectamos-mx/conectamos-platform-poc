# FLUTTER_CONVENTIONS — conectamos-platform

> **Propósito:** Convenciones extraídas del código real del repo. Claude Code debe seguir
> estos patrones en toda pantalla nueva o modificación existente. No inventar patrones
> alternativos sin justificación explícita.
> **Fuente:** Auditoría 2026-04-27 sobre commit post-Fase C.
> **Mantenimiento:** Actualizar cuando se introduzca un patrón nuevo deliberadamente.

---

## 1. Estructura de directorios

```
lib/
  core/
    api/          — clases de API estáticas (un archivo por dominio)
    router/
      app_router.dart   — router único go_router
  features/
    config/       — pantallas de configuración (canales, flows, operadores)
    settings/     — ajustes del tenant
    [módulo]/     — una carpeta por feature
```

**Convención de naming de archivos:**
- Pantallas: `[nombre]_screen.dart`
- Pantalla de detalle con tabs: `[nombre]_detail_screen.dart`
- API: `[dominio]_api.dart` en `lib/core/api/`

---

## 2. Router (go_router)

**Archivo:** `lib/core/router/app_router.dart`

**Patrón de ruta con parámetro de id:**
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

**Reglas:**
- Todas las rutas con parámetros van dentro del `ShellRoute`.
- Usar `NoTransitionPage` — sin animaciones de transición.
- El id se extrae con `state.pathParameters['key'] ?? ''`.
- Rutas nuevas se agregan junto a las de su mismo dominio (flows junto a `/flows`).

---

## 3. Pantallas de detalle con tabs

**Patrón canónico** (extraído de `OperatorDetailScreen` y `ChannelDetailScreen`):

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

**AppBar con TabBar:**
```dart
appBar: AppBar(
  bottom: TabBar(
    controller: _tabCtrl,
    labelColor: AppColors.ctTeal,
    unselectedLabelColor: AppColors.ctText2,
    indicatorColor: AppColors.ctTeal,
    labelStyle: AppTextStyles.formLabel,
    unselectedLabelStyle: AppTextStyles.navItem,
    tabs: const [
      Tab(text: 'INFO'),
      Tab(text: 'CAMPOS'),
      Tab(text: 'COMPORTAMIENTO'),
      Tab(text: 'AL CERRAR'),
    ],
  ),
),
```

**Body:**
```dart
body: Column(
  children: [
    _FlowHeader(flow: _flow),
    Expanded(
      child: TabBarView(
        controller: _tabCtrl,
        children: [
          _InfoTab(...),
          _CamposTab(...),
          _ComportamientoTab(...),
          _AlCerrarTab(...),
        ],
      ),
    ),
  ],
),
```

**Regla:** Si el número de tabs varía según condición (ej. tipo de canal), crear el
`TabController` dentro del callback de `_load()` en lugar de `initState()`.

---

## 4. Clases de API

**Archivo de referencia:** `lib/core/api/flows_api.dart`

**Patrón de método:**
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

**Reglas:**
- Métodos estáticos — no instanciar la clase.
- `tenant_id` siempre como query parameter (`queryParameters:`), nunca en el body.
- Usar `ApiClient.dio` — no crear instancias de Dio directamente.
- `listFlows` → `List<Map<String, dynamic>>`
- `getFlow`, `createFlow`, `updateFlow` → `Map<String, dynamic>`
- `deleteFlow` → `void`

**Métodos existentes en FlowsApi:**
```dart
static Future<List<Map<String, dynamic>>> listFlows({required String tenantId})
static Future<Map<String, dynamic>> createFlow({required String tenantId, required String tenantWorkerId, required String name, String? description, List<Map<String, dynamic>> fields, Map<String, dynamic> behavior})
static Future<Map<String, dynamic>> updateFlow({required String flowId, String? name, String? description, bool? isActive, List<Map<String, dynamic>>? fields, Map<String, dynamic>? behavior})
static Future<void> deleteFlow({required String flowId})
// getFlow — PENDIENTE DE AGREGAR
```

---

## 5. Drag-to-reorder

**Widget:** `SliverReorderableList` (no `ReorderableListView`).
**Archivo de referencia:** `lib/features/settings/operator_fields_screen.dart:502`

```dart
SliverReorderableList(
  itemCount: _fields.length,
  onReorder: canManage ? _onReorder : (oldIndex, newIndex) {},
  itemBuilder: (context, i) {
    final field = _fields[i];
    final id = field['id'] as String? ?? i.toString();
    return _FieldCard(
      key: ValueKey(id),   // ← OBLIGATORIO
      field: field,
      index: i,
      canManage: canManage,
      onEdit: () => _openEdit(field),
    );
  },
),
```

**Handle de drag** dentro del item:
```dart
ReorderableDragStartListener(
  index: index,
  child: Icon(Icons.drag_handle),
)
```

**Reglas:**
- Cada item **debe** tener `key: ValueKey(id)` único y estable.
- `onReorder` recibe `(oldIndex, newIndex)` — aplicar la lógica estándar de Flutter:
  ```dart
  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _fields.removeAt(oldIndex);
      _fields.insert(newIndex, item);
    });
  }
  ```
- Cuando `canManage` es false, pasar `(_, __) {}` al `onReorder` para deshabilitar sin romper el widget.

---

## 6. Pantalla de lista con cards expandibles

**Archivo de referencia:** `lib/features/config/workflows_screen.dart`

- Clase de card: `_FlowCard` (línea 279)
- Expansión con `setState(() => _expanded = !_expanded)` — sin `ExpansionTile`.
- El edit abre un `Dialog` con `showDialog(...)` — **este patrón se reemplaza** en la nueva
  pantalla de detalle: el tap en la card navegará a `/flows/:flowId` vía `context.go(...)`.

**Cómo agregar navegación a una card existente:**
```dart
onTap: () => context.go('/flows/${flow['id']}'),
```

---

## 7. Colores y tipografía

**Clase de colores:** `AppColors` (importar desde el barrel del proyecto).

| Token | Uso |
|---|---|
| `AppColors.ctTeal` | Acento primario, tab activo, botones primarios |
| `AppColors.ctText2` | Labels secundarios, tabs inactivos |
| `AppColors.ctNavy` | AppBar, topbar |
| `AppColors.ctSurface` | Fondo de cards |
| `AppColors.ctBorder` | Bordes de contenedores |
| `AppColors.ctDanger` | Errores, destructivos |

**Fuentes:**
- Títulos / labels de sección: `Onest`
- Cuerpo / datos / código: `Geist`

---

## 8. Permisos y guards

**Provider:** `userPermissionsProvider` (Riverpod).

**Patrón de lectura:**
```dart
final perms = ref.watch(userPermissionsProvider);
final canManage = perms.contains('flows.manage');
```

**Permisos relevantes para Flows v2:**
- `flows.view` — ver lista y detalle
- `flows.manage` — crear, editar, eliminar
- `flow_executions.execute_dashboard` — ver y actuar sobre "Tareas"
- `flow_integrations.manage` — gestionar integraciones de flows

---

## 9. Convenciones de state en pantallas con carga asíncrona

```dart
bool _loading = true;
String? _error;
Map<String, dynamic>? _flow;

Future<void> _load() async {
  setState(() { _loading = true; _error = null; });
  try {
    final tenantId = ref.read(currentTenantProvider)!.id;
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

## 10. Notas de migración (workflows_screen.dart)

La pantalla actual `lib/features/config/workflows_screen.dart` maneja lista + form dialog en un
solo archivo. Al introducir `FlowDetailScreen`:

1. El `onEdit` de `_FlowCard` se reemplaza por navegación: `context.go('/flows/${flow['id']}')`.
2. El dialog de creación (`_openForm(flow: null)`) se mantiene para flujo de alta rápida.
3. El dialog de edición (`_openForm(flow: entry.value)`) se elimina — edición vive en la pantalla de detalle.
4. `_FlowCard` pierde el parámetro `onEdit` cuando el detalle esté disponible.

---

## 11. TextField sin doble borde (ADR 2026-05-25)

**PROHIBIDO:** `Container(border: Border.all()) + TextField(border: InputBorder.none)`
Este patrón produce doble borde en Flutter Web cuando el campo se enfoca.

**CORRECTO:** TextField con borders inline:
```dart
TextField(
  controller: _ctrl,
  style: AppTextStyles.body,
  decoration: InputDecoration(
    hintText: 'placeholder',
    hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
    filled: true,
    fillColor: AppColors.ctSurface2,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: AppColors.ctBorder2),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: AppColors.ctTeal, width: 1.5),
    ),
  ),
)
```

**Preferencia:** usar `AppTextField` siempre que sea posible. El patrón inline
solo aplica para widgets internos de Capa 3 que necesitan control fino
(ej. `_ColMappingField`, condition value TextField).

---

## 12. Tipos de campo en formularios dinámicos (2026-05-25)

El backend declara tipos de campo via endpoints como `/flows/precondition-types`
y `/flows/action-types`. Flutter los lee y renderiza dinámicamente:

| type               | Widget Flutter                        | Notas                                      |
|--------------------|---------------------------------------|---------------------------------------------|
| `text`             | TextField (con routing especial)      | flow slugs → AppDropdown; timezone → dropdown; window → DurationSelector |
| `select`           | AppDropdown (si display_as != radio)  | options del backend                         |
| `select` + radio   | `_AppRadioGroup`                      | cuando `field['display_as'] == 'radio'`     |
| `bool`             | SwitchListTile                        |                                             |
| `role_multi_select`| Wrap de chips toggle                  | fuente: `widget.availableRoles`             |
| `catalog_multi_select` | Wrap de chips toggle              | fuente: `_availableCatalogs`                |
| `flow_field_key`   | AppDropdown de field keys             | lazy-load vía `FlowsApi.getFlow()`          |
| `time`             | TextField + `showTimePicker`          | `AbsorbPointer` + `GestureDetector`         |
| `timezone`         | AppDropdown con `_kTimezones`         |                                             |

### Props adicionales en `flow_field_key`:

- `source_flow_field`: `'self'` → usa `widget.currentFlowFields`.
  Otro key → busca slug en `_textCtrls[key]`, carga flow via `FlowsApi.getFlow()`.
- `field_type_filter`: `List<String>` de tipos permitidos. Ej `['number']` filtra
  solo campos numéricos. Si `filteredFields.isEmpty` → `_SemanticWarning`.

---

## 13. Lazy-load de recursos externos con caché en dialogs (2026-05-25)

Para cargar recursos por demanda (ej. campos de un flow padre, preview de Google Sheet):

```dart
// Estado
Map<String, List<Map<String, dynamic>>> _cache = {};
Set<String> _loading = {};

// Método (fire-and-forget desde build)
void _loadResource(String key) {
  if (_cache.containsKey(key) || _loading.contains(key)) return;
  _loading.add(key);
  Api.fetch(key).then((data) {
    if (!mounted) return;
    setState(() { _cache[key] = data; _loading.remove(key); });
  }).catchError((_) {
    if (!mounted) return;
    setState(() { _cache[key] = []; _loading.remove(key); });
  });
}

// En build:
// Si _loading.contains(key): CircularProgressIndicator
// Si _cache[key] tiene items: AppDropdown
// Si _cache[key] vacío: Text explicativo o fallback TextField
```

Ejemplo real: `_fetchFlowFields(slug)` en `_AddRuleDialog` para
precondiciones con `source_flow_field != 'self'`.

---

## 14. Estándar flutter analyze antes de commit (2026-05-25)

`flutter analyze` en los archivos modificados debe retornar
**0 infos, 0 warnings, 0 errors** antes de cualquier commit.
No se acepta código nuevo que introduzca issues de analyzer.

Verificación obligatoria:
```bash
flutter analyze lib/features/flows/flow_detail_screen.dart 2>&1 | tail -5
# → "No issues found" o equivalente con 0 issues
```

Patrones frecuentes a evitar:
- `print()` → usar `debugPrint()`
- `activeColor` en SwitchListTile → usar `activeThumbColor`
- `if (mounted)` en callbacks de widgets hijos → usar `if (!context.mounted) return;`
- `(_, __)` en separatorBuilder → usar `(context, index)`

---

## 15. Wizards multi-paso (ADR-262, ADR-337)

Todo wizard multi-paso en la plataforma usa `AppWizardShell`
(`lib/shared/widgets/app_wizard_shell.dart`).
**NUNCA** crear steppers ad-hoc con Column + indicadores visuales en features.

```dart
await AppWizardShell.show(
  context: context,
  sidebarTitle: 'Nuevo flujo',
  steps: [
    AppWizardStep(title: 'Identidad', builder: (_) => _Step1()),
    AppWizardStep(title: 'Acceso',    builder: (_) => _Step2()),
    AppWizardStep(title: 'Confirmar', builder: (_) => _Step3()),
  ],
  onCancel: () => Navigator.of(context).pop(),
  onConfirm: _submit,
  confirmLabel: 'Crear flujo',
  canAdvance: _isValid,
);
```

**Layout:** sidebar 200px (lista de pasos numerados con circulos ctTeal/ctOk/ctBorder2)
+ contenido derecho (header del paso + SingleChildScrollView + footer con botones).

**Reglas de contenido por paso:**
- Cada paso recibe un `WidgetBuilder` — puede ser StatefulWidget propio
- No usar `DropdownButton` dentro del builder (ADR-263) — usar `AppDropdown`
- `canAdvance` se evalua en el padre — pasar `false` deshabilita Siguiente/Confirmar
- `onConfirm` es `Future<void>` — el shell maneja el loading state

**Wizards existentes pendientes de migracion (WIZARD-002):**

| Wizard actual | Archivo | Estado |
|---|---|---|
| `_NewFlowDialog` | `workflows_screen.dart` | Migrado a AppWizardShell |
| `_NewAssignmentDialog` | `assignments_screen.dart` | Pendiente |
| `_AddRuleDialog` | `flow_detail_screen.dart` | Wizard custom (2 pasos) — evaluar migracion |
| `_ActionDialog` | `flow_detail_screen.dart` | Wizard custom (catalogo + form) — evaluar migracion |
| Canal nuevo (inline) | `channels_screen.dart` | Stepper custom sidebar — evaluar migracion |
