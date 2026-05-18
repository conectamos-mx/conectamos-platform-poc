import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/flows_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_button.dart';
import '../conversations/conversations_screen.dart' show selectedChannelIdProvider;
import 'widgets/execution_header_block.dart';
import 'widgets/execution_metadata_sidebar.dart';
import 'widgets/field_card.dart';
import 'widgets/lineage_breadcrumb.dart';
import 'widgets/messages_thread.dart';

class ExecutionDetailScreen extends ConsumerStatefulWidget {
  const ExecutionDetailScreen({super.key, required this.executionId});
  final String executionId;

  @override
  ConsumerState<ExecutionDetailScreen> createState() =>
      _ExecutionDetailScreenState();
}

class _ExecutionDetailScreenState
    extends ConsumerState<ExecutionDetailScreen> {
  bool _loading = true;
  DateTime? _lastFetch;
  Timer? _ticker;
  Timer? _refreshTimer;
  String? _error;
  Map<String, dynamic>? _exec;
  Map<String, dynamic>? _flow;

  String _elapsedSince(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'hace ${d.inSeconds}s';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes}m';
    return 'hace ${d.inHours}h';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tenantId = ref.read(activeTenantIdProvider);
      if (tenantId.isNotEmpty) {
        _load();
        _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
          if (mounted) _load();
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _exec == null;
      _error = null;
    });
    try {
      final raw = await FlowsApi.getExecution(
          executionId: widget.executionId);
      final snapshot =
          (raw['flow_definition_snapshot'] as Map?)?.cast<String, dynamic>() ??
              {};
      setState(() {
        _exec = raw;
        _flow = snapshot;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    } finally {
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      setState(() { _lastFetch = DateTime.now(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Permission guard
    final perms = ref.watch(userPermissionsProvider);
    if (perms.valueOrNull != null &&
        !perms.valueOrNull!.contains('flows.view')) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => context.go('/overview'));
      return const SizedBox.shrink();
    }

    ref.listen<String>(activeTenantIdProvider, (prev, next) {
      if (next.isNotEmpty && prev != next) {
        _load();
        if (_refreshTimer == null || !_refreshTimer!.isActive) {
          _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
            if (mounted) _load();
          });
        }
      }
    });

    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.ctBg,
        appBar: _buildAppBar(context),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.ctTeal),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.ctBg,
        appBar: _buildAppBar(context),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  style: AppFonts.geist(
                      fontSize: 14, color: AppColors.ctDanger)),
              const SizedBox(height: 12),
              AppButton(
                label: 'Reintentar',
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.sm,
                onPressed: _load,
              ),
            ],
          ),
        ),
      );
    }

    final exec = _exec!;
    final flow = _flow!;

    final execStatus = exec['status'] as String? ?? '';
    const abandonableStatuses = {
      'active', 'paused', 'pending_completion',
      'pending_dashboard', 'pending_input', 'created',
    };
    final canManageExecutions =
        hasPermission(ref, 'flow_executions', 'execute_dashboard');
    final showAbandon =
        canManageExecutions && abandonableStatuses.contains(execStatus);

    return Scaffold(
      backgroundColor: AppColors.ctBg,
      appBar: _buildAppBar(context),
      body: SelectionArea(child: Column(
        children: [
          ExecutionHeaderBlock(
            exec: exec,
            flow: flow,
            showAbandon: showAbandon,
            onAbandon: () => _abandon(context, exec['id'] as String? ?? ''),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1280),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (_lastFetch != null)
                              Text(
                                'Act. ${_elapsedSince(_lastFetch!)}',
                                style: AppFonts.geist(fontSize: 11, color: AppColors.ctText3),
                              ),
                            const SizedBox(width: 4),
                            SizedBox(
                              width: 32,
                              height: 32,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                icon: _loading
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.ctTeal,
                                        ),
                                      )
                                    : const Icon(Icons.refresh_rounded,
                                        size: 16, color: AppColors.ctText3),
                                onPressed: _loading ? null : _load,
                              ),
                            ),
                          ],
                        ),
                        LineageBreadcrumb(exec: exec),
                        LayoutBuilder(
                          builder: (ctx, constraints) {
                            final wide = constraints.maxWidth >= 900;
                            final rawEvents = exec['events'] as List? ?? [];
                            final events = rawEvents
                                .whereType<Map>()
                                .map((e) => e.cast<String, dynamic>())
                                .toList();
final content = _MainContent(exec: exec, flow: flow);
                            final sidebar = ExecutionMetadataSidebar(
                                exec: exec, flow: flow, events: events);

                            if (wide) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: content),
                                  const SizedBox(width: 22),
                                  sidebar,
                                ],
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                content,
                                const SizedBox(height: 22),
                                sidebar,
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      )),
    );
  }

  Future<void> _abandon(BuildContext context, String executionId) async {
    final messenger = ScaffoldMessenger.of(context);
    bool loading = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('¿Abandonar ejecución?',
              style: AppFonts.onest(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ctNavy)),
          content: Text(
            'Esta acción marcará la ejecución como abandonada y no se podrá revertir.',
            style: AppFonts.geist(fontSize: 14, color: AppColors.ctText2),
          ),
          actions: [
            AppButton(
              label: 'Cancelar',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              isDisabled: loading,
              onPressed: () => Navigator.pop(ctx),
            ),
            AppButton(
              label: 'Sí, abandonar',
              variant: AppButtonVariant.danger,
              size: AppButtonSize.sm,
              isLoading: loading,
              onPressed: () async {
                setDialogState(() => loading = true);
                try {
                  await FlowsApi.abandonExecution(
                      executionId: executionId);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Ejecución abandonada'),
                        duration: Duration(milliseconds: 2000),
                      ),
                    );
                    await _load();
                  }
                } on DioException catch (e) {
                  final data = e.response?.data;
                  final code =
                      data is Map ? data['code'] as String? : null;
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    final msg = code == 'execution_not_abandonable'
                        ? 'Esta ejecución no se puede abandonar (estado: ${data['current_status'] ?? '—'})'
                        : 'Error al abandonar la ejecución';
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(msg),
                        duration: const Duration(milliseconds: 3000),
                      ),
                    );
                  }
                } catch (_) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Error al abandonar la ejecución'),
                        duration: Duration(milliseconds: 2000),
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.ctBg,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: AppColors.ctText),
        onPressed: () => context.go('/executions'),
      ),
    );
  }
}

// ── Main content (fields + messages) ─────────────────────────────────────────

class _MainContent extends StatelessWidget {
  const _MainContent({required this.exec, required this.flow});
  final Map<String, dynamic> exec;
  final Map<String, dynamic> flow;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldsBlock(exec: exec, flow: flow),
        const SizedBox(height: 22),
        _MessagesBlock(exec: exec),
      ],
    );
  }
}

// ── Fields Block ──────────────────────────────────────────────────────────────

class _FieldsBlock extends StatefulWidget {
  const _FieldsBlock({required this.exec, required this.flow});
  final Map<String, dynamic> exec;
  final Map<String, dynamic> flow;

  @override
  State<_FieldsBlock> createState() => _FieldsBlockState();
}

class _FieldsBlockState extends State<_FieldsBlock> {
  final Set<String> _hiddenTypes = {};

  static const List<(String, IconData, String)> _typeOrder = [
    ('text',     Icons.notes_rounded,          'Texto'),
    ('number',   Icons.tag_rounded,            'Número'),
    ('date',     Icons.calendar_month_rounded, 'Fecha'),
    ('yesno',    Icons.toggle_on_rounded,      'Sí/No'),
    ('select',   Icons.checklist_rounded,      'Selección'),
    ('location', Icons.location_on_rounded,    'Ubicación'),
  ];

  static String _normalizeType(String t) => t == 'photo' ? 'media' : t;

  static bool _fvHasValue(Map<String, dynamic> fv) =>
      fv['value_text'] != null ||
      fv['value_numeric'] != null ||
      fv['value_media_url'] != null ||
      fv['value_jsonb'] != null;

  static dynamic _resolveValue(
    String type,
    Map<String, dynamic> fv, {
    Map<String, dynamic>? assetsAttached,
    String? fieldKey,
  }) {
    if (type == 'asset_ref') {
      if (assetsAttached != null && fieldKey != null) {
        final asset = assetsAttached[fieldKey];
        if (asset is Map) {
          return (asset['display_text'] as String?) ??
              (asset['item_id'] as String?);
        }
      }
      // Fallback: value_jsonb → item_id, or value_text
      final jsonb = fv['value_jsonb'];
      if (jsonb is Map) return jsonb['item_id'] as String?;
      return fv['value_text'];
    }
    return switch (type) {
      'number'             => fv['value_numeric'],
      'media' || 'photo'   => _resolveMedia(fv),
      'location'           => _resolveLocation(fv),
      _                    => fv['value_text'],
    };
  }

  static List<String> _resolveMedia(Map<String, dynamic> fv) {
    // 1. Intentar value_jsonb como Map (caso ideal)
    final jsonb = fv['value_jsonb'];
    if (jsonb is Map) {
      final url = jsonb['url'] as String?;
      if (url != null) return [url];
    }

    // 2. value_media_url puede ser una URL limpia o un JSON serializado
    final rawMediaUrl = fv['value_media_url'];
    if (rawMediaUrl is String && rawMediaUrl.isNotEmpty) {
      final trimmed = rawMediaUrl.trim();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          // Normalizar comillas simples a dobles para parsear
          final normalized = trimmed.replaceAll("'", '"');
          final decoded = jsonDecode(normalized);
          if (decoded is Map) {
            final url = decoded['url'] as String?;
            if (url != null) return [url];
          }
        } catch (_) {
          // Si falla el parse, extraer URL con regex
          final match = RegExp(r'https?://[^ \t\n"]+').firstMatch(trimmed);
          if (match != null) return [match.group(0)!];
        }
      }
      // Es una URL directa
      return [trimmed];
    }

    return [];
  }

  static Map<String, dynamic>? _resolveLocation(Map<String, dynamic> fv) {
    // 1. Fuente ideal: value_jsonb como Map
    final jsonb = fv['value_jsonb'];
    if (jsonb is Map) {
      final result = Map<String, dynamic>.from(jsonb.cast<String, dynamic>());
      final address = fv['value_text'] as String?;
      if (address != null && !address.trim().startsWith('{') &&
          !address.trim().startsWith('http')) {
        result['address'] = address;
      }
      return result;
    }

    // 2. Intentar parsear value_text como coordenadas
    final vText = fv['value_text'] as String?;
    if (vText != null && vText.isNotEmpty) {
      final fromText = _parseLocationString(vText);
      if (fromText != null) return fromText;
    }

    // 3. Intentar parsear value_media_url como coordenadas
    final vMedia = fv['value_media_url'] as String?;
    if (vMedia != null && vMedia.isNotEmpty) {
      final fromMedia = _parseLocationString(vMedia);
      if (fromMedia != null) return fromMedia;
    }

    // 4. Sin coordenadas extraíbles → null (field_card usará _LocationUrlLink o _PendingSlot)
    return null;
  }

  static Map<String, dynamic>? _parseLocationString(String raw) {
    final s = raw.trim();

    // Caso A: JSON o dict Python con lat/lng o latitude/longitude
    if (s.startsWith('{')) {
      try {
        final normalized = s.replaceAll("'", '"');
        final decoded = jsonDecode(normalized) as Map<String, dynamic>;
        final lat = (decoded['lat'] ?? decoded['latitude']) as num?;
        final lng = (decoded['lng'] ?? decoded['longitude']) as num?;
        if (lat != null && lng != null) {
          return {
            'lat': lat.toDouble(),
            'lng': lng.toDouble(),
            if (decoded['address'] != null) 'address': decoded['address'],
            if (decoded['name'] != null && decoded['address'] == null)
              'address': decoded['name'],
          };
        }
      } catch (_) {}
    }

    // Caso B: URL de Google Maps con ?q=lat,lng
    final urlMatch = RegExp(r'https?://[^\s]+').firstMatch(s);
    if (urlMatch != null) {
      final url = urlMatch.group(0)!;
      final coordMatch = RegExp(
        r'[?&]q=([+-]?\d+\.?\d*),([+-]?\d+\.?\d*)',
      ).firstMatch(url);
      if (coordMatch != null) {
        return {
          'lat': double.parse(coordMatch.group(1)!),
          'lng': double.parse(coordMatch.group(2)!),
          'address': url,
        };
      }
    }

    // Caso C: coordenadas crudas "lat,lng"
    final rawCoord = RegExp(
      r'^([+-]?\d+\.?\d*),\s*([+-]?\d+\.?\d*)$',
    ).firstMatch(s);
    if (rawCoord != null) {
      return {
        'lat': double.parse(rawCoord.group(1)!),
        'lng': double.parse(rawCoord.group(2)!),
      };
    }

    // Caso D: formato "lat=X, lng=Y"
    final latLngNamed = RegExp(
      r'lat=([+-]?\d+\.?\d*)[,\s]+lng=([+-]?\d+\.?\d*)',
    ).firstMatch(s);
    if (latLngNamed != null) {
      final lat = double.tryParse(latLngNamed.group(1) ?? '');
      final lng = double.tryParse(latLngNamed.group(2) ?? '');
      if (lat != null && lng != null) return {'lat': lat, 'lng': lng};
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final rawFields = widget.flow['fields'] as List? ?? [];
    final fields = rawFields
        .whereType<Map>()
        .map((f) => f.cast<String, dynamic>())
        .toList();

    // Extract operator_options for select fields with UUID values
    final operatorOptions = (widget.exec['operator_options'] as List? ?? [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();

    // Build field_values lookup keyed by field_key
    final rawFvList = widget.exec['field_values'] as List? ?? [];
    final fvMap = <String, Map>{};
    for (final item in rawFvList.whereType<Map>()) {
      final k = item['field_key'];
      if (k is String && k.isNotEmpty) fvMap[k] = item;
    }

    // Types present in this flow (normalized)
    final presentTypes = fields
        .map((f) => _normalizeType(f['type'] as String? ?? 'text'))
        .toSet();

    // Progress
    final total = fields.length;
    final filled = fields.where((f) {
      final key = f['key'];
      if (key is! String) return false;
      final fv = fvMap[key];
      return fv != null && _fvHasValue(fv.cast<String, dynamic>());
    }).length;

    // assets_attached keyed by field_key
    final assetsAttached = (widget.exec['assets_attached'] as Map?)
        ?.cast<String, dynamic>();

    // Resolve values and pending list
    final values = <String, dynamic>{};
    final pending = <String>[];
    for (final field in fields) {
      final key = field['key'] as String? ?? '';
      final fvRaw = fvMap[key];
      final fv = fvRaw?.cast<String, dynamic>();
      if (fv == null || !_fvHasValue(fv)) {
        pending.add(key);
      } else {
        values[key] = _resolveValue(
          field['type'] as String? ?? 'text',
          fv,
          assetsAttached: assetsAttached,
          fieldKey: key,
        );
      }
    }

    // Build evidence photos list from photo/media fields
    final evidencePhotos = <({String url, String fieldLabel, String fieldKey})>[];
    for (final field in fields) {
      final type = field['type'] as String? ?? 'text';
      if (type != 'photo' && type != 'media') continue;
      final key = field['key'] as String? ?? '';
      final label = field['label'] as String? ?? key;
      final fvRaw = fvMap[key];
      if (fvRaw == null) continue;
      final fv = fvRaw.cast<String, dynamic>();
      if (!_fvHasValue(fv)) continue;
      final urls = _resolveMedia(fv);
      for (final url in urls) {
        if (url.isNotEmpty) {
          evidencePhotos.add((url: url, fieldLabel: label, fieldKey: key));
        }
      }
    }

    // Visible fields after type filter, sorted by type priority (stable)
    // Photo/media fields are excluded — rendered separately in EvidencesSection
    const typePriority = <String, int>{
      'text': 0, 'number': 1, 'date': 2,
      'boolean': 3, 'yesno': 3,
      'select': 4, 'asset_ref': 5, 'location': 6,
    };
    final visibleFields = (fields
        .where((f) {
          final type = f['type'] as String? ?? 'text';
          if (type == 'photo' || type == 'media') return false;
          return !_hiddenTypes.contains(_normalizeType(type));
        })
        .toList()
        .asMap()
        .entries
        .toList()
      ..sort((a, b) {
        final ta = _normalizeType(a.value['type'] as String? ?? 'text');
        final tb = _normalizeType(b.value['type'] as String? ?? 'text');
        final pa = typePriority[ta] ?? 99;
        final pb = typePriority[tb] ?? 99;
        return pa != pb ? pa.compareTo(pb) : a.key.compareTo(b.key);
      }))
        .map((e) => e.value)
        .toList();

    // Legacy field_values not in snapshot
    final knownKeys = fields.map((f) => f['key'] as String? ?? '').toSet();
    final legacyKeys = fvMap.keys.where((k) => !knownKeys.contains(k)).toList();
    final legacyValues = <String, dynamic>{
      for (final k in legacyKeys)
        k: fvMap[k]!['value_text'] ?? fvMap[k]!['value_numeric'] ?? '—',
    };

    if (fields.isEmpty && fvMap.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.workspaces_outline,
              size: 32, color: Color(0xFF94A3B8)),
          const SizedBox(height: 8),
          Text('Este flujo no tiene campos definidos',
              style: AppFonts.geist(
                      fontSize: 14, color: const Color(0xFF94A3B8))
                  .copyWith(fontStyle: FontStyle.italic)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Title + type filter icons ───────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Campos capturados',
                    style: AppFonts.onest(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ctNavy,
                      letterSpacing: -0.02,
                    )),
                const SizedBox(height: 2),
                Text('$filled de $total campos con valor',
                    style: AppFonts.geist(
                        fontSize: 12, color: AppColors.ctText2)),
              ],
            ),
            Row(
              children: [
                for (final (type, icon, label) in _typeOrder)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: _TypeFilterIcon(
                      icon: icon,
                      label: label,
                      exists: presentTypes.contains(type),
                      active: !_hiddenTypes.contains(type),
                      onToggle: () => setState(() {
                        if (_hiddenTypes.contains(type)) {
                          _hiddenTypes.remove(type);
                        } else {
                          _hiddenTypes.add(type);
                        }
                      }),
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (ctx, constraints) {
            final totalWidth = constraints.maxWidth;
            const gap = 14.0;
            return _WrapGrid(
              fields: visibleFields,
              values: values,
              pending: pending,
              totalWidth: totalWidth,
              gap: gap,
              fvMap: fvMap,
              operatorOptions: operatorOptions,
            );
          },
        ),
        if (evidencePhotos.isNotEmpty) ...[
          const SizedBox(height: 22),
          _EvidencesSection(photos: evidencePhotos),
        ],
        if (legacyKeys.isNotEmpty) ...[
          const SizedBox(height: 22),
          _LegacyFieldsCard(slugs: legacyKeys, values: legacyValues),
        ],
        if (assetsAttached != null && assetsAttached.isNotEmpty) ...[
          const SizedBox(height: 22),
          _AssetsAttachedCard(
            assetsAttached: assetsAttached,
            fields: fields,
          ),
        ],
      ],
    );
  }
}

// ── Type Filter Icon ───────────────────────────────────────────────────────────

class _TypeFilterIcon extends StatelessWidget {
  const _TypeFilterIcon({
    required this.icon,
    required this.label,
    required this.exists,
    required this.active,
    required this.onToggle,
  });

  final IconData icon;
  final String label;
  final bool exists;
  final bool active;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color border;
    final Color iconColor;

    if (!exists) {
      bg = const Color(0xFFF1F3F5);
      border = AppColors.ctBorder;
      iconColor = const Color(0xFFCBD5E1);
    } else if (active) {
      bg = AppColors.ctTealLight;
      border = AppColors.ctTeal;
      iconColor = AppColors.ctTealText;
    } else {
      bg = Colors.white;
      border = AppColors.ctBorder;
      iconColor = const Color(0xFF94A3B8);
    }

    final tile = Tooltip(
      message: label,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 13, color: iconColor),
      ),
    );

    if (!exists) {
      return MouseRegion(cursor: SystemMouseCursors.forbidden, child: tile);
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onToggle, child: tile),
    );
  }
}

class _WrapGrid extends StatelessWidget {
  const _WrapGrid({
    required this.fields,
    required this.values,
    required this.pending,
    required this.totalWidth,
    required this.gap,
    this.fvMap = const {},
    this.operatorOptions = const [],
  });

  final List<Map<String, dynamic>> fields;
  final Map<String, dynamic> values;
  final List<String> pending;
  final double totalWidth;
  final double gap;
  final Map<String, Map> fvMap;
  final List<Map<String, dynamic>> operatorOptions;

  @override
  Widget build(BuildContext context) {
    final halfWidth = (totalWidth - gap) / 2;

    final List<Widget> items = fields.map((field) {
      final key = field['key'] as String? ?? '';
      final value = values[key];
      final isPending = pending.contains(key);
      final card = FieldCard(
        field: field,
        value: value,
        isPending: isPending,
        isInherited: false,
        fv: fvMap[key]?.cast<String, dynamic>(),
        operatorOptions: operatorOptions,
      );
      final isWide = card.isWide;
      return SizedBox(
        width: isWide ? totalWidth : halfWidth,
        child: card,
      );
    }).toList();

    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: items,
    );
  }
}

// ── Evidences Section ─────────────────────────────────────────────────────────

class _EvidencesSection extends StatelessWidget {
  const _EvidencesSection({required this.photos});
  final List<({String url, String fieldLabel, String fieldKey})> photos;

  @override
  Widget build(BuildContext context) {
    final photoCount = photos.length;
    final fieldCount = photos.map((p) => p.fieldKey).toSet().length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Evidencias',
                style: AppFonts.onest(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ctNavy,
                  letterSpacing: -0.02,
                )),
            const SizedBox(width: 10),
            Text(
              '$photoCount foto${photoCount == 1 ? '' : 's'} en $fieldCount campo${fieldCount == 1 ? '' : 's'}',
              style: AppFonts.geist(fontSize: 12, color: AppColors.ctText3),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < photos.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                _EvidenceThumb(photo: photos[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _EvidenceThumb extends StatelessWidget {
  const _EvidenceThumb({required this.photo});
  final ({String url, String fieldLabel, String fieldKey}) photo;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      height: 180,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              photo.url,
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, stack) => Container(
                color: AppColors.ctSurface2,
                child: const Icon(Icons.broken_image_rounded,
                    size: 28, color: AppColors.ctText3),
              ),
            ),
            // Label overlay at bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: Colors.black.withValues(alpha: 0.55),
                child: Text(
                  photo.fieldLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
                ),
              ),
            ),
            // Copy URL button
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: IconButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: photo.url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('URL copiada'),
                        duration: Duration(milliseconds: 1500),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded,
                      size: 13, color: Colors.white),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  tooltip: 'Copiar URL',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Legacy Fields Card ────────────────────────────────────────────────────────

class _LegacyFieldsCard extends StatelessWidget {
  const _LegacyFieldsCard(
      {required this.slugs, required this.values});
  final List<String> slugs;
  final Map<String, dynamic> values;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A0F172A), offset: Offset(0, 1), blurRadius: 2),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Campos legacy',
                  style: AppFonts.geist(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ctNavy)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.ctSurface2,
                  border: Border.all(color: AppColors.ctBorder),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text('Deprecado',
                    style: AppFonts.geist(
                        fontSize: 10,
                        color: AppColors.ctText2)
                      .copyWith(
                        fontStyle: FontStyle.italic,
                        decoration: TextDecoration.lineThrough)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...slugs.map((slug) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 160,
                      child: Text(slug,
                          style: AppTextStyles.formLabel.copyWith(color: AppColors.ctInk700)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(values[slug]?.toString() ?? '—',
                          style: AppFonts.geist(
                              fontSize: 12, color: AppColors.ctNavy)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ── Assets Attached Card ──────────────────────────────────────────────────────

class _AssetsAttachedCard extends StatelessWidget {
  const _AssetsAttachedCard({
    required this.assetsAttached,
    required this.fields,
  });

  final Map<String, dynamic> assetsAttached;
  final List<Map<String, dynamic>> fields;

  @override
  Widget build(BuildContext context) {
    // Build label lookup from flow fields
    final labelByKey = <String, String>{
      for (final f in fields)
        if (f['key'] is String) f['key'] as String: (f['label'] as String?) ?? f['key'] as String,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A0F172A), offset: Offset(0, 1), blurRadius: 2),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined,
                  size: 15, color: AppColors.ctTeal),
              const SizedBox(width: 6),
              Text(
                'Assets referenciados',
                style: AppFonts.geist(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ctNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...assetsAttached.entries.map((entry) {
            final fieldKey = entry.key;
            final asset = entry.value is Map
                ? (entry.value as Map).cast<String, dynamic>()
                : <String, dynamic>{};
            final label = labelByKey[fieldKey] ?? fieldKey;
            final displayText = asset['display_text'] as String? ??
                asset['item_id'] as String? ??
                '—';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 160,
                    child: Text(
                      label,
                      style: AppFonts.geist(
                        fontSize: 12,
                        color: const Color(0xFF475569),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Ver detalle de catálogo no disponible aún'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.ctTeal.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.ctTeal.withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.link_rounded,
                                  size: 12, color: AppColors.ctTeal),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  displayText,
                                  style: AppFonts.geist(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.ctTeal,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Timeline Block ────────────────────────────────────────────────────────────

class _TimelineBlock extends StatelessWidget {
  const _TimelineBlock({required this.events});
  final List<Map<String, dynamic>> events;

  static const _months = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];

  static String _fmt(String? iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso).toLocal();
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      final ss = d.second.toString().padLeft(2, '0');
      return '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} · $hh:$mm:$ss';
    } catch (_) {
      return iso;
    }
  }

  static ({Color color, String label}) _cfg(String type) =>
      switch (type) {
        'flujo_iniciado'       => (color: AppColors.ctTeal,            label: 'Flujo iniciado'),
        'campo_capturado'      => (color: const Color(0xFF10B981),     label: 'Campo capturado'),
        'campo_rechazado'      => (color: const Color(0xFFF59E0B),     label: 'Campo rechazado'),
        'flujo_completado'     => (color: AppColors.ctTeal,            label: 'Flujo completado'),
        'flujo_abandonado'     => (color: const Color(0xFFEF4444),     label: 'Flujo abandonado'),
        'supervisor_intervino' => (color: const Color(0xFF3B82F6),     label: 'Supervisor intervino'),
        'worker_escaló'        => (color: const Color(0xFFF59E0B),     label: 'Worker escaló'),
        'flujo_pausado'        => (color: AppColors.ctText2,           label: 'Flujo pausado'),
        'flujo_retomado'       => (color: AppColors.ctTeal,            label: 'Flujo retomado'),
        _                      => (color: AppColors.ctText2,           label: type),
      };

  @override
  Widget build(BuildContext context) {
    final sorted = [...events];
    sorted.sort((a, b) {
      final ta = a['timestamp'] as String? ?? a['created_at'] as String? ?? '';
      final tb = b['timestamp'] as String? ?? b['created_at'] as String? ?? '';
      return ta.compareTo(tb);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cronología',
            style: AppFonts.onest(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.ctNavy,
              letterSpacing: -0.02,
            )),
        const SizedBox(height: 2),
        Text('Registro de eventos del flujo',
            style: AppFonts.geist(fontSize: 12, color: AppColors.ctText2)),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.ctBorder),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x0A0F172A), offset: Offset(0, 1), blurRadius: 2),
            ],
          ),
          child: sorted.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.timeline_rounded,
                          size: 20, color: AppColors.ctText3),
                      const SizedBox(width: 8),
                      Text('Sin eventos registrados',
                          style: AppFonts.geist(
                              fontSize: 13, color: AppColors.ctText3)),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    children: [
                      for (var i = 0; i < sorted.length; i++)
                        _EventRow(
                          event: sorted[i],
                          isLast: i == sorted.length - 1,
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.isLast});
  final Map<String, dynamic> event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final type =
        event['type'] as String? ?? event['event_type'] as String? ?? '';
    final ts = event['timestamp'] as String? ?? event['created_at'] as String?;
    final dataRaw = event['data'];
    String? dataStr;
    if (dataRaw is Map && dataRaw.isNotEmpty) {
      dataStr = dataRaw.entries.map((e) => '${e.key}: ${e.value}').join(' · ');
    } else if (dataRaw is String && (dataRaw).isNotEmpty) {
      dataStr = dataRaw;
    }
    final cfg = _TimelineBlock._cfg(type);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Track (dot + connector line) ─────────────────────────────────
        SizedBox(
          width: 20,
          child: Column(
            children: [
              const SizedBox(height: 4),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: cfg.color,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Container(
                  width: 1.5,
                  height: 24,
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  color: AppColors.ctBorder,
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // ── Content ──────────────────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0.0 : 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(cfg.label,
                          style: AppFonts.geist(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ctNavy)),
                    ),
                    const SizedBox(width: 8),
                    Text(_TimelineBlock._fmt(ts),
                        style: AppFonts.geist(
                            fontSize: 11, color: AppColors.ctText3)),
                  ],
                ),
                if (dataStr != null && dataStr.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(dataStr,
                      style: AppFonts.geist(
                          fontSize: 12, color: AppColors.ctText2)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Messages Block ────────────────────────────────────────────────────────────

class _MessagesBlock extends ConsumerWidget {
  const _MessagesBlock({required this.exec});
  final Map<String, dynamic> exec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rawMessages = exec['messages'] as List? ?? [];
    final messages = rawMessages
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();

    if (messages.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.chat_rounded,
                          size: 16, color: AppColors.ctWa),
                      const SizedBox(width: 8),
                      Text('Conversación relacionada',
                          style: AppFonts.onest(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ctNavy,
                            letterSpacing: -0.02,
                          )),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                      '${messages.length} mensajes · todos los archivos quedaron registrados',
                      style: AppFonts.geist(
                          fontSize: 12, color: AppColors.ctText2)),
                ],
              ),
            ),
            AppButton(
              label: 'Abrir hilo completo',
              variant: AppButtonVariant.outline,
              size: AppButtonSize.sm,
              prefixIcon: const Icon(Icons.arrow_outward_rounded, size: 14, color: AppColors.ctInk700),
              onPressed: () {
                final channelId = (exec['channel'] as Map?)?['id'] as String?;
                context.go('/conversations');
                if (channelId != null) {
                  Future.delayed(const Duration(milliseconds: 50), () {
                    ref.read(selectedChannelIdProvider.notifier).state = channelId;
                  });
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        MessagesThread(messages: messages),
      ],
    );
  }
}
