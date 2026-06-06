# SKILL_DATE_UTILS.md — Funciones de fecha/hora centralizadas

> ADR-413 — Todas las funciones de formato/calculo de fecha viven en `lib/core/utils/`.
> Las screens en `lib/features/` NUNCA definen funciones `_formatX`/`_fmtX` locales de fecha.

---

## lib/core/utils/date_format.dart

Todas las funciones que reciben `String? iso` aplican `.toLocal()` internamente
(excepto `fmtDateLongEs` y `fmtDateIntl` que reciben `DateTime`).

| Funcion | Firma | Input | TZ | Formato salida | Ejemplo | Cuando usar |
|---|---|---|---|---|---|---|
| `fmtTime` | `String fmtTime(String? iso, {String fallback = '\u2014'})` | ISO string | `.toLocal()` | `HH:mm` | `"09:07"` | Hora sola en listas, chat bubbles, activity feed. Usa `fallback: ''` si no quieres placeholder visible en null. |
| `fmtDateShort` | `String fmtDateShort(String? iso)` | ISO string | `.toLocal()` | `dd MMM \u00b7 HH:mm` | `"05 ene \u00b7 09:07"` | Fechas cortas en timelines de ejecuciones, sidebars, export PDF. SIN segundos. |
| `fmtDateTimeSeconds` | `String fmtDateTimeSeconds(String? iso)` | ISO string | `.toLocal()` | `dd MMM \u00b7 HH:mm:ss` | `"05 ene \u00b7 09:07:03"` | Igual que `fmtDateShort` pero CON segundos. Usada en timeline de eventos de ejecucion. |
| `fmtDateSlash` | `String fmtDateSlash(String? iso)` | ISO string | `.toLocal()` | `dd/MM/yyyy HH:mm` | `"05/01/2026 09:07"` | Fecha completa con hora en fichas de detalle (operador, integraciones). |
| `fmtDateOnly` | `String fmtDateOnly(String? iso)` | ISO string | `.toLocal()` | `dd/MM/yyyy` | `"05/01/2026"` | Fecha sin hora (ej. fecha de baja de operador). |
| `fmtDateTimeCompact` | `String fmtDateTimeCompact(String? iso)` | ISO string | `.toLocal()` | `dd/MM HH:mm` | `"05/01 09:07"` | Fecha compacta sin anio (chips de filtro de rango). |
| `fmtDateLongEs` | `String fmtDateLongEs(DateTime d)` | DateTime | naive | `EEEE, d de MMMM de yyyy` | `"lunes, 5 de enero de 2026"` | Hero date en overview. Recibe `DateTime.now()` directamente. |
| `fmtDateIntl` | `String fmtDateIntl(DateTime dt)` | DateTime | `.toLocal()` | `d MMM yyyy \u00b7 HH:mm` | `"5 ene 2026 \u00b7 09:07"` | Datetime pickers en assignments. Recibe DateTime del picker. |
| `fmtExecutionDate` | `String fmtExecutionDate(String? iso)` | ISO string | `.toLocal()` | Hoy/Ayer/`dd/MM \u00b7 HH:mm` | `"Hoy 09:07"` | Lista de ejecuciones pendientes. Hibrido: muestra "Hoy"/"Ayer" si aplica. |
| `isToday` | `bool isToday(String? iso)` | ISO string | `.toLocal()` | `bool` | `true` | Predicado para badges "hoy" en lista de conversaciones. |

### Desambiguacion rapida

- Solo hora? -> `fmtTime`
- Dia + mes + hora (timeline)? -> `fmtDateShort` (sin segundos) o `fmtDateTimeSeconds` (con segundos)
- Fecha completa dd/MM/yyyy + hora? -> `fmtDateSlash`
- Fecha completa sin hora? -> `fmtDateOnly`
- Fecha compacta dd/MM + hora (chip)? -> `fmtDateTimeCompact`
- Fecha larga en espanol (hero)? -> `fmtDateLongEs`
- Fecha + hora con locale intl (picker)? -> `fmtDateIntl`
- "Hoy"/"Ayer"/fecha? -> `fmtExecutionDate`

---

## lib/core/utils/relative_time.dart

| Funcion | Firma | Input | TZ | Formato salida | Ejemplo | Cuando usar |
|---|---|---|---|---|---|---|
| `fmtRelative` | `String fmtRelative(String? iso, {String nullLabel = '\u2014', bool showSeconds = false})` | ISO string | `.toLocal()` | Ahora / Hace Xm / Hace Xh / Ayer / Hace X dias | `"Hace 5 min"` | Tiempo relativo en listas (operadores, catalogos). `nullLabel: 'Nunca'` para catalogos. `showSeconds: true` para granularidad de segundos. |
| `fmtElapsedSeconds` | `String fmtElapsedSeconds(int? seconds)` | int (segundos) | N/A | Xs / Xm Xs / Xh Xm | `"3m 20s"` | Duracion calculada por backend (campo `elapsed_seconds`). NO es un timestamp. |
| `elapsedSince` | `String elapsedSince(DateTime t)` | DateTime | naive | hace Xs / hace Xm / hace Xh | `"hace 5m"` | Tiempo desde ultimo fetch (ej. "Act. hace 2m" en header). Nota: "hace" en minuscula, solo hasta horas. |

### Desambiguacion rapida

- Tiempo relativo desde ISO string? -> `fmtRelative`
- Duracion en segundos (int del backend)? -> `fmtElapsedSeconds`
- Tiempo desde un DateTime local (ej. _lastFetch)? -> `elapsedSince`

---

## lib/core/utils/week_math.dart

| Funcion | Firma | Input | TZ | Formato salida | Ejemplo | Cuando usar |
|---|---|---|---|---|---|---|
| `mondayOf` | `DateTime mondayOf(DateTime d)` | DateTime | naive | DateTime | lunes de la semana | Calcular inicio de semana para vista de assignments. |
| `isoDate` | `String isoDate(DateTime d)` | DateTime | naive | `yyyy-MM-dd` | `"2026-01-05"` | Serializar fecha para query param `scopeDate` del API. |
| `weekRangeLabel` | `String weekRangeLabel(DateTime monday)` | DateTime | naive | `d\u2013d mes yyyy` | `"5\u201311 ene 2026"` | Label de la barra de navegacion semanal en assignments. |

---

## lib/core/utils/telegram.dart

| Funcion | Firma | Input | TZ | Formato salida | Ejemplo | Cuando usar |
|---|---|---|---|---|---|---|
| `isTelegramExpired` | `bool isTelegramExpired(String? expiresAt)` | ISO string | `.toUtc()` ambas partes | `bool` | `true` | Verificar si el link de vinculacion Telegram expiro. UNICA funcion con comparacion UTC. |

---

## NO consolidadas (y por que)

Estas funciones siguen como `_private` en sus features. NO las muevas a utils sin contexto:

| Funcion | Archivo | Razon |
|---|---|---|
| `_fmtCell` | `dashboard_screen.dart:1135` | Bug: usa UTC-6 hardcoded en vez de `.toLocal()`. Tiene PLA aparte para corregir. No consolidar hasta que se arregle. |
| `_chatFormatDate` | `conversations_screen.dart:1736` | Recibe `DateTime` ya convertido a local por el caller (linea 2929). Convencion de input divergente: la funcion es naive pero el caller hace `.toLocal()` antes. Fusionarla con `_dateGroupLabel` requiere unificar la convencion de input — sprint aparte. |
| `_dateGroupLabel` | `all_executions_screen.dart:51` | Recibe `DateTime` SIN `.toLocal()` y lo convierte internamente. Convencion opuesta a `_chatFormatDate`. Ambas producen "Hoy"/"Ayer"/fecha pero con flujo TZ distinto. |
