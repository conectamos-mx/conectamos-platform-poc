# Estado del Proyecto — conectamos-platform

## Historial de sesiones

| Fecha | Resumen |
|---|---|
| 2026-05-26 | Sprint bugs Gustavo V2. Backend: condition_parser fix (ADR-344), boolean normalization en escritura + backfill 579 filas (ADR-346), resolved_channels en endpoints de ejecuciones, endpoint GET /executions/{id}/messages. Frontend: boolean display completo label+valor+normalizacion (ADR-346), show_if evaluation quirurgico en execution detail — 3 helpers _normalize/_evalShowIfOp/_fieldVisibility, 3 consumers tocados (ADR-347), on_complete flow selector filtrado por trigger_sources (ADR-345), canal resuelto desde resolved_channels en listado y sidebar, mensajes en execution detail via _MessagesBlock existente, rutas standalone /flows y /channels eliminadas, DS tokens corregidos (btnPrimary sin color, chipLabel, 3 colores nuevos). PRs #14 #15 mergeados. PR #16 (feat/channel-from-messages) pendiente. |
