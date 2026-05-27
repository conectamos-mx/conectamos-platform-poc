# Backlog — conectamos-platform

## Resueltos (2026-05-26)

- [x] Boolean field display — type label muestra "Texto" en lugar de "Si/No" → ADR-346
- [x] show_if en execution detail — campos ocultos aparecen como "Pendiente" → ADR-347
- [x] Canal en listado de ejecuciones — ejecuciones encadenadas muestran "—" → resolved_channels
- [x] on_complete flow selector — dropdown muestra flows sin trigger correcto → ADR-345
- [x] Rutas standalone /flows y /channels — renderizan sin AppShell → eliminadas, nav redirigida a /workers/:id
- [x] DS tokens — btnPrimary con color hardcodeado, chipLabel faltante, colores inline → corregidos

## Pendientes

### [P-001] show_if en execution detail — operadores in/not_in
Severidad: Baja. Area: Frontend.
`_evalShowIfOp` soporta eq/neq pero no in/not_in. El backend los usa en show_if con listas.
Fix: agregar cases para in/not_in al switch en `_evalShowIfOp`.

### [P-002] Endpoint GET /executions/{id}/messages
Severidad: Alta. Area: Backend.
Frontend ya consume el endpoint (executions_api.dart + execution_detail_screen.dart).
Backend debe crear el endpoint en conectamos_meta_api. Ver prompt de backend en sesion 2026-05-26.

### [P-003] catalog_detail_screen — tap en _UsageRow deshabilitado
Severidad: Baja. Area: Frontend.
`onTap: null` en _UsageRow porque no hay workerId disponible en contexto de catalogo.
Fix: el endpoint `/catalogs/{id}/usages` debe retornar `tenant_worker_id` por cada usage,
o navegar a un buscador de flows por slug.

### [P-004] Guard eliminacion de campo — referencias huerfanas en preconditions y on_complete
Severidad: Media. Area: Frontend.
El guard de _FieldDialog detecta show_if de otros campos pero NO escanea
preconditions[].params ni on_complete.actions[].condition. Si un campo
referenciado en esas zonas se elimina, las referencias quedan huerfanas
y fallan silenciosamente en runtime. Fix: extender guard para escanear
las 3 zonas y mostrar modal de advertencia con referencias encontradas.
