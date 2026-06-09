# Decisiones de Arquitectura (ADRs) — conectamos-platform

---

## ADR-344 — condition_parser: quoted "true" permanece string

**Fecha:** 2026-05-26
**Estado:** Implementado
**Contexto:** `condition_parser.py` convertia `"true"` (con comillas) a `bool True`, rompiendo comparaciones `==` contra `value_text` que almacena strings.
**Decision:** Quoted `"true"` y `"false"` permanecen como string. Solo bare `true`/`false` (sin comillas) se convierten a bool.
**Consecuencia:** Condiciones show_if con `value: "true"` ahora comparan correctamente contra `value_text="true"`.

---

## ADR-345 — on_complete flow selector filtrado por trigger_sources

**Fecha:** 2026-05-26
**Estado:** Implementado
**Contexto:** El dropdown de target_flow_slug en _ActionDialog (open_flow, open_flow_n_times) mostraba todos los flows del worker. Flows sin `on_complete` en `trigger_sources` fallaban con `child_execution_error` al intentar crear la ejecucion hija.
**Decision:** Filtrar `_availableFlows` por `_hasOnComplete()` — solo mostrar flows donde `trigger_sources` contiene `"on_complete"`. Si el valor actual apunta a un flow invalido preexistente, se muestra con sufijo "(sin permiso de encadenamiento)" y warning rojo.
**Consecuencia:** Imposible seleccionar un flow que no soporte encadenamiento. Configs invalidas preexistentes visibles con advertencia.

---

## ADR-346 — Boolean normalization: display + backend backfill

**Fecha:** 2026-05-26
**Estado:** Implementado
**Contexto:** Campos `type:"boolean"` almacenan `value_text` como `"true"`/`"false"` pero el frontend mostraba el string raw. Ademas, operadores capturan variantes como `"Si"`, `"si"`, `"Si"`, `"No"`.
**Decision:**
- Frontend `_YesNoValue`: normaliza con set `{'true','si','si','yes','1'}` → Si (green), resto → No (red).
- Frontend `_typeLabel`/`_typeIcon`: `'boolean'` mapeado al mismo branch que `'yesno'`.
- Backend: normaliza en escritura (`checkpoint_complete`) y backfill 579 filas existentes.
**Consecuencia:** Display consistente independientemente de la variante capturada.

---

## ADR-347 — show_if evaluation quirurgico en execution detail

**Fecha:** 2026-05-26
**Estado:** Implementado
**Contexto:** Campos con `show_if` se renderizan siempre en execution detail, incluyendo como "Pendiente" cuando la condicion no se cumple. Primer intento (c1d8538) uso `activeFields` en todos los consumers → causo regresiones en campos legacy y texto.
**Decision:** Approach quirurgico con 3 helpers estaticos:
- `_normalize(v)`: canonicaliza variantes Si/No → "true"/"false"
- `_evalShowIfOp(control, op, expected)`: eq/==/neq/!=, fail-open para ops desconocidos
- `_fieldVisibility(field, fvMap, execStatus)`: retorna `visible`/`hidden`/`visible_unknown`

Solo 3 consumers usan el filtro:
1. `presentTypes` — excluye hidden del set de tipos
2. `total`/`filled` (progress counter) — cuenta solo no-hidden
3. `visibleFields` filter — excluye hidden antes de renderizar

`knownKeys` SIEMPRE usa `fields` completo (snapshot sin filtrar) para detectar campos legacy.
**Consecuencia:** Campos ocultos por show_if no se renderizan ni cuentan en progreso. Campos legacy no contaminados.
