# SKILL_DATE_UTILS.md — Funciones de fecha/hora centralizadas

> ADR-413 — Todas las funciones de formato/calculo de fecha viven en `lib/core/utils/`.
> ADR-414 — Todas las funciones delegan al global de zona activa en `tz_format.dart`.
> ADR-415 — Fallback IANA invalido → UTC + "(UTC)" visible. NUNCA silencioso. NUNCA CDMX.
> Las screens en `lib/features/` NUNCA definen funciones `_formatX`/`_fmtX` locales de fecha.

---

## lib/core/utils/tz_format.dart — Punto canonico de conversion TZ

### Global de zona activa

La zona activa se almacena en un global privado `_activeLocation` dentro de `tz_format.dart`.
Es un espejo read-only de `activeTenantZoneProvider` (Riverpod), sincronizado via
`tenantZoneSyncProvider` (watch en `AppShell`).

**Arranque:** antes de resolver tenant, `_activeLocation` es null → todas las funciones
formatean en UTC con sufijo visible "(UTC)". Tras resolver tenant, `setActiveZone` actualiza
el global y las funciones formatean en la zona del tenant.

| Funcion | Firma | Descripcion |
|---|---|---|
| `initTz` | `void initTz()` | Inicializa la base de datos de zonas horarias. Llamar una vez en `main()`. Idempotente. |
| `setActiveZone` | `void setActiveZone(String iana)` | Actualiza la zona activa. Si IANA invalido → null (UTC fallback). Llamado por `tenantZoneSyncProvider`. |
| `formatInTimeZone` | `({String text, bool utcFallback}) formatInTimeZone(DateTime utcInstant, DateFormat fmt)` | Formatea `utcInstant` en zona activa. Fallback: UTC + " (UTC)". |
| `nowInZone` | `({DateTime now, bool utcFallback}) nowInZone()` | `DateTime.now()` en zona activa. Fallback: UTC. |
| `toZone` | `({DateTime dt, bool utcFallback}) toZone(DateTime instant)` | Convierte cualquier DateTime a zona activa. Fallback: UTC. |
| `startOfDay` | `({DateTime dt, bool utcFallback}) startOfDay(DateTime instant)` | 00:00:00.000 del dia calendario del instante en zona activa. DST-aware. Fallback: UTC. |
| `endOfDay` | `({DateTime dt, bool utcFallback}) endOfDay(DateTime instant)` | 23:59:59.999 del dia calendario del instante en zona activa. DST-aware. Fallback: UTC. |

### Contrato de fallback (ADR-415)

- Si la zona activa es invalida o no ha sido configurada: formatea en **UTC** + `utcFallback: true`.
- El texto incluye sufijo visible `" (UTC)"` — NUNCA silencioso.
- **NUNCA** usar CDMX como fallback en las funciones de formato.

### Sincronizacion con Riverpod

```dart
// tenant_provider.dart
final tenantZoneSyncProvider = Provider<void>((ref) {
  final zone = ref.watch(activeTenantZoneProvider);
  tzf.setActiveZone(zone);
});

// app_shell.dart — build()
ref.watch(tenantZoneSyncProvider);
```

---

## lib/core/utils/date_format.dart

Todas las funciones delegan al global de zona activa. **Sin parametro `zone:`.**

| Funcion | Firma | Input | Formato salida | Ejemplo | Cuando usar |
|---|---|---|---|---|---|
| `fmtTime` | `String fmtTime(String? iso, {String fallback = '—'})` | ISO string | `HH:mm` | `"09:07"` | Hora sola en listas, chat bubbles, activity feed. |
| `fmtDateShort` | `String fmtDateShort(String? iso)` | ISO string | `dd MMM · HH:mm` | `"05 ene · 09:07"` | Fechas cortas en timelines, sidebars, export PDF. |
| `fmtDateTimeSeconds` | `String fmtDateTimeSeconds(String? iso)` | ISO string | `dd MMM · HH:mm:ss` | `"05 ene · 09:07:03"` | Timeline de eventos con segundos. |
| `fmtDateSlash` | `String fmtDateSlash(String? iso)` | ISO string | `dd/MM/yyyy HH:mm` | `"05/01/2026 09:07"` | Fecha completa con hora en fichas de detalle. |
| `fmtDateOnly` | `String fmtDateOnly(String? iso)` | ISO string | `dd/MM/yyyy` | `"05/01/2026"` | Fecha sin hora (ej. fecha de baja). |
| `fmtDateTimeCompact` | `String fmtDateTimeCompact(String? iso)` | ISO string | `dd/MM HH:mm` | `"05/01 09:07"` | Fecha compacta sin año (chips, celdas de tabla). |
| `fmtDateLongEs` | `String fmtDateLongEs(DateTime d)` | DateTime | `EEEE, d de MMMM de yyyy` | `"lunes, 5 de enero de 2026"` | Hero date en overview. |
| `fmtWeekdayEs` | `String fmtWeekdayEs(DateTime dt)` | DateTime (ya en zona) | `EEEE` capitalizado | `"Jueves"` | Nombre del dia en espanol, primera letra mayuscula. Usado por `resolveFreeText` en broadcast_helpers.dart. |
| `fmtDateIntl` | `String fmtDateIntl(DateTime dt)` | DateTime | `d MMM yyyy · HH:mm` | `"5 ene 2026 · 09:07"` | Datetime pickers en assignments. |
| `fmtExecutionDate` | `String fmtExecutionDate(String? iso)` | ISO string | Hoy/Ayer/`dd/MM · HH:mm` | `"Hoy 09:07"` | Lista de ejecuciones pendientes. |
| `isToday` | `bool isToday(String? iso)` | ISO string | `bool` | `true` | Predicado para badges "hoy". |
| `fmtDateGroupLabel` | `String fmtDateGroupLabel(DateTime utcInstant)` | DateTime | Hoy/Ayer/`d mmm yyyy` | `"Hoy"`, `"5 ene 2026"` | Separadores de grupo por fecha (chat, ejecuciones). |
| `fmtCreatedCell` | `({String dateLine, String relativeLine}) fmtCreatedCell(String? iso)` | ISO string | `Hoy, HH:mm` + `Ahora` | `("Hoy, 09:07", "Ahora")` | Celda de tabla con fecha+hora y tiempo relativo. Delega relativeLine a fmtRelative. |

### Desambiguacion rapida

- Solo hora? -> `fmtTime`
- Dia + mes + hora (timeline)? -> `fmtDateShort` (sin segundos) o `fmtDateTimeSeconds` (con segundos)
- Fecha completa dd/MM/yyyy + hora? -> `fmtDateSlash`
- Fecha completa sin hora? -> `fmtDateOnly`
- Fecha compacta dd/MM + hora (chip)? -> `fmtDateTimeCompact`
- Fecha larga en espanol (hero)? -> `fmtDateLongEs`
- Solo nombre del dia en espanol? -> `fmtWeekdayEs`
- Separador Hoy/Ayer/fecha (grupo)? -> `fmtDateGroupLabel`
- Fecha + hora con locale intl (picker)? -> `fmtDateIntl`
- "Hoy"/"Ayer"/fecha? -> `fmtExecutionDate`
- Celda fecha+relativo (tabla)? -> `fmtCreatedCell`

---

## lib/core/utils/relative_time.dart

| Funcion | Firma | Input | Formato salida | Ejemplo | Cuando usar |
|---|---|---|---|---|---|
| `fmtRelative` | `String fmtRelative(String? iso, {String nullLabel, bool showSeconds, bool compact, int? absoluteAfterDays})` | ISO string | Default: Ahora/Hace X min/Hace Xh/Ayer/Hace X días. compact: ahora/hace Xm/hace Xh/ayer/hace Xd. absoluteAfterDays: dd/MM/yyyy si > N días | `"Hace 5 min"`, `"hace 5m"`, `"05/01/2026"` | Tiempo relativo canonico. `compact: true` para indicadores "Act.". `absoluteAfterDays: 7` para escalaciones. |
| `fmtElapsedSeconds` | `String fmtElapsedSeconds(int? seconds)` | int (segundos) | Xs / Xm Xs / Xh Xm | `"3m 20s"` | Duracion calculada por backend. NO es un timestamp. Sin TZ. |

> `elapsedSince` fue eliminada en PLA-86. Usar `fmtRelative(dt.toUtc().toIso8601String(), compact: true, showSeconds: true)` en su lugar.

---

## lib/core/utils/week_math.dart

| Funcion | Firma | Input | Formato salida | Ejemplo | Cuando usar |
|---|---|---|---|---|---|
| `mondayOf` | `DateTime mondayOf(DateTime d)` | DateTime | DateTime | lunes de la semana | Inicio de semana para assignments. |
| `isoDate` | `String isoDate(DateTime d)` | DateTime | `yyyy-MM-dd` | `"2026-01-05"` | Serializar fecha para query param `scopeDate`. |
| `weekRangeLabel` | `String weekRangeLabel(DateTime monday)` | DateTime | `d–d mes yyyy` | `"5–11 ene 2026"` | Label de navegacion semanal. |

---

## lib/core/utils/telegram.dart

| Funcion | Firma | Input | TZ | Formato salida | Ejemplo | Cuando usar |
|---|---|---|---|---|---|---|
| `isTelegramExpired` | `bool isTelegramExpired(String? expiresAt)` | ISO string | `.toUtc()` ambas partes | `bool` | `true` | Verificar si link de Telegram expiro. UNICA funcion con comparacion UTC directa. |

---

## Patron de uso en call-sites

```dart
// Sin parametro zone: — la zona activa se lee del global interno
final text = fmtDateShort(item['created_at'] as String?);
```

El global se sincroniza automaticamente via `tenantZoneSyncProvider` en `AppShell`.
Los call-sites NO necesitan acceso a `ref` ni a `activeTenantZoneProvider`.

---

## NO consolidadas (y por que)

Ninguna pendiente en este momento. `_chatFormatDate`, `_formatDate` y `_dateGroupLabel` fueron
consolidadas en `fmtDateGroupLabel` (PLA-65).
