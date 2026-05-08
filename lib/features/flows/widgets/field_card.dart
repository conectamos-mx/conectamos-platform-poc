import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../conversations/widgets/media_preview_dialog.dart';

// ── Public widget ────────────────────────────────────────────────────────────

class FieldCard extends StatelessWidget {
  const FieldCard({
    super.key,
    required this.field,
    required this.value,
    required this.isPending,
    required this.isInherited,
    this.fv,
    this.operatorOptions = const [],
  });

  final Map<String, dynamic> field;
  final dynamic value;
  final bool isPending;
  final bool isInherited;
  final Map<String, dynamic>? fv;
  final List<Map<String, dynamic>> operatorOptions;

  bool get _isWide {
    final type = field['type'] as String? ?? 'text';
    return type == 'photo' ||
        type == 'media' ||
        type == 'location' ||
        (type == 'text' && field['multiline'] == true);
  }

  bool get isWide => _isWide;

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
          _FieldHeader(
              field: field, value: value, isPending: isPending, isInherited: isInherited),
          const SizedBox(height: 10),
          _FieldValue(field: field, value: value, fv: fv, operatorOptions: operatorOptions),
        ],
      ),
    );
  }
}

// ── Field Header ─────────────────────────────────────────────────────────────

class _FieldHeader extends StatelessWidget {
  const _FieldHeader({
    required this.field,
    required this.value,
    required this.isPending,
    required this.isInherited,
  });

  final Map<String, dynamic> field;
  final dynamic value;
  final bool isPending;
  final bool isInherited;

  static IconData _typeIcon(String type) => switch (type) {
        'number'   => Icons.pin_rounded,
        'date'     => Icons.calendar_month_rounded,
        'yesno'    => Icons.toggle_on_rounded,
        'select'   => Icons.checklist_rounded,
        'photo' || 'media' => Icons.camera_alt_rounded,
        'location' => Icons.location_on_rounded,
        _          => Icons.notes_rounded,
      };

  static String _typeLabel(String type) => switch (type) {
        'number'   => 'Número',
        'date'     => 'Fecha',
        'yesno'    => 'Sí / No',
        'select'   => 'Selección',
        'photo'    => 'Foto',
        'media'    => 'Foto/Media',
        'location' => 'Ubicación',
        _          => 'Texto',
      };

  @override
  Widget build(BuildContext context) {
    final type = field['type'] as String? ?? 'text';
    final label = field['label'] as String? ?? field['key'] as String? ?? '—';
    final slug = field['key'] as String? ?? '';
    final required = field['required'] == true;

    final (tileBg, tileFg, tileBd) = isPending
        ? (AppColors.ctWarnBg, AppColors.ctWarnText, const Color(0xFFFDE68A))
        : isInherited
            ? (const Color(0xFFEEF2FF), const Color(0xFF4338CA), const Color(0xFFC7D2FE))
            : (AppColors.ctTealLight, AppColors.ctTealText, const Color(0xFF99F6E4));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: tileBg,
            border: Border.all(color: tileBd),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(_typeIcon(type), size: 14, color: tileFg),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(label,
                      style: AppFonts.geist(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ctNavy,
                          letterSpacing: -0.01)),
                  if (required) _SmallBadge(label: 'Requerido', tone: 'teal'),
                  if (isInherited) _SmallBadge(label: 'Heredado', tone: 'info'),
                  if (isPending) _SmallBadge(label: 'Pendiente', tone: 'warn', dot: true),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(_typeLabel(type),
                      style: AppFonts.geist(fontSize: 11, color: const Color(0xFF94A3B8))),
                  const Text(' · ',
                      style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                  Text(slug,
                      style: const TextStyle(
                          fontFamily: 'Geist', fontSize: 10, color: Color(0xFF94A3B8))),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.label, required this.tone, this.dot = false});
  final String label;
  final String tone;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, bd) = switch (tone) {
      'teal'  => (AppColors.ctTealLight, AppColors.ctTealText, const Color(0xFF99F6E4)),
      'info'  => (AppColors.ctInfoBg, AppColors.ctInfoText, const Color(0xFFBFDBFE)),
      'warn'  => (AppColors.ctWarnBg, AppColors.ctWarnText, const Color(0xFFFDE68A)),
      _       => (AppColors.ctSurface2, AppColors.ctText2, AppColors.ctBorder),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: bd),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
                width: 5, height: 5,
                decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: AppFonts.geist(
                  fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

// ── Field Value Dispatcher ────────────────────────────────────────────────────

class _FieldValue extends StatelessWidget {
  const _FieldValue({
    required this.field,
    required this.value,
    this.fv,
    this.operatorOptions = const [],
  });
  final Map<String, dynamic> field;
  final dynamic value;
  final Map<String, dynamic>? fv;
  final List<Map<String, dynamic>> operatorOptions;

  Widget _buildValue(BuildContext context) {
    final type = field['type'] as String? ?? 'text';

    // When resolved value is null, try to recover directly from raw fv row
    dynamic effectiveValue = value;
    String? rawMediaUrl;
    final fvLocal = fv;
    if (effectiveValue == null && fvLocal != null) {
      final vText  = fvLocal['value_text'] as String?;
      final vNum   = fvLocal['value_numeric'];
      final vJsonb = fvLocal['value_jsonb'];
      final vMedia = fvLocal['value_media_url'] as String?;
      if (vText != null && vText.isNotEmpty) {
        effectiveValue = vText;
      } else if (vNum != null) {
        effectiveValue = vNum;
      } else if (vJsonb is Map) {
        effectiveValue = vJsonb;
      } else if (vMedia != null && vMedia.isNotEmpty) {
        rawMediaUrl = vMedia;
      }
    }

    final bool hasAnyValue = fvLocal != null && (
      (fvLocal['value_text'] as String?)?.isNotEmpty == true ||
      fvLocal['value_numeric'] != null ||
      fvLocal['value_jsonb'] != null ||
      (fvLocal['value_media_url'] as String?)?.isNotEmpty == true
    );

    if (effectiveValue == null && rawMediaUrl == null) {
      return hasAnyValue
          ? _CapturedRawSlot(
              rawValue: fvLocal['value_text'] as String? ??
                  fvLocal['value_media_url'] as String?)
          : const _PendingSlot();
    }

    // URL-only fallback: raw media URL without structured value
    if (rawMediaUrl != null && effectiveValue == null) {
      return switch (type) {
        'photo' || 'media' => _PhotoGallery(photos: [rawMediaUrl]),
        'location'         => _LocationUrlLink(url: rawMediaUrl),
        _                  => _UrlLink(url: rawMediaUrl),
      };
    }

    return switch (type) {
      'text'             => _TextValue(value: effectiveValue, multiline: field['multiline'] == true),
      'number'           => _NumberValue(value: effectiveValue, unit: field['unit'] as String?),
      'date'             => _DateValue(value: effectiveValue),
      'yesno'            => _YesNoValue(value: effectiveValue),
      'select'           => _SelectValue(value: effectiveValue, options: field['options'] as List? ?? [], operatorOptions: operatorOptions),
      'photo' || 'media' => _PhotoGallery(photos: _toPhotoList(effectiveValue)),
      'location'         => effectiveValue is String && effectiveValue.trim().startsWith('http')
          ? _LocationUrlLink(url: effectiveValue.trim())
          : _toLocation(effectiveValue) != null
              ? _LocationMap(value: _toLocation(effectiveValue))
              : hasAnyValue
                  ? _CapturedRawSlot(
                      rawValue: fvLocal['value_text'] as String? ??
                          fvLocal['value_media_url'] as String?)
                  : const _PendingSlot(),
      _                  => effectiveValue != null
          ? _TextValue(value: effectiveValue.toString(), multiline: false)
          : hasAnyValue
              ? _CapturedRawSlot(
                  rawValue: fvLocal['value_text'] as String? ??
                      fvLocal['value_media_url'] as String?)
              : const _PendingSlot(),
    };
  }

  @override
  Widget build(BuildContext context) {
    try {
      return _buildValue(context);
    } catch (_) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.ctSurface2,
          border: Border.all(color: AppColors.ctBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                size: 14, color: Color(0xFFF59E0B)),
            const SizedBox(width: 8),
            Text('Valor capturado · no se puede mostrar',
                style: AppFonts.geist(
                    fontSize: 12, color: AppColors.ctText3)),
          ],
        ),
      );
    }
  }

  static String? _extractPhotoUrl(Map<String, dynamic> fv) {
    final fromJsonb = (fv['value_jsonb'] as Map?)?['url'] as String?;
    final fromUrl = fv['value_media_url'] as String?;
    return fromJsonb ?? fromUrl;
  }

  static List<String> _toPhotoList(dynamic v) {
    if (v == null) return [];
    if (v is List) {
      return v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    if (v is Map) {
      // Raw fv row: has value_jsonb / value_media_url keys
      if (v.containsKey('value_jsonb') || v.containsKey('value_media_url')) {
        final url = _extractPhotoUrl(Map<String, dynamic>.from(v));
        return url != null ? [url] : [];
      }
      // value_jsonb Map: {"url": "https://..."}
      final url = v['url'] as String?;
      return url != null ? [url] : [];
    }
    final s = v.toString();
    return s.isNotEmpty ? [s] : [];
  }

  static Map<String, dynamic>? _toLocation(dynamic v) {
    if (v == null) return null;
    if (v is Map) return v.cast<String, dynamic>();
    return null;
  }
}

// ── Text ─────────────────────────────────────────────────────────────────────

class _TextValue extends StatelessWidget {
  const _TextValue({required this.value, required this.multiline});
  final dynamic value;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    final text = value?.toString() ?? '';
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F3F5),
            border: Border.all(color: AppColors.ctBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text.isEmpty ? '—' : text,
            style: AppFonts.geist(fontSize: 14, color: const Color(0xFF0F172A), height: 1.55),
            softWrap: true,
            maxLines: multiline ? null : 4,
          ),
        ),
        if (text.isNotEmpty)
          Positioned(
            bottom: 6,
            right: 6,
            child: SizedBox(
              width: 24,
              height: 24,
              child: IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copiado'),
                      duration: Duration(milliseconds: 1500),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded,
                    size: 13, color: AppColors.ctText3),
                padding: EdgeInsets.zero,
                tooltip: 'Copiar valor',
              ),
            ),
          ),
      ],
    );
  }
}

// ── Number ────────────────────────────────────────────────────────────────────

class _NumberValue extends StatelessWidget {
  const _NumberValue({required this.value, required this.unit});
  final dynamic value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    if (value == null) return const _PendingSlot();
    final num n = value is num ? value : num.tryParse(value.toString()) ?? 0;
    final isMoney = unit == 'MXN';
    final formatted = isMoney
        ? NumberFormat.currency(locale: 'es_MX', symbol: r'$', decimalDigits: 0)
            .format(n)
        : n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 2);

    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.ctNavy,
            border: Border.all(color: AppColors.ctBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(formatted,
                  style: AppFonts.geist(
                    fontSize: 14,
                    color: AppColors.ctTeal,
                    height: 1.55,
                  )),
              if (unit != null && !isMoney) ...[
                const SizedBox(width: 6),
                Text(unit!,
                    style: AppFonts.geist(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.6))),
              ],
            ],
          ),
        ),
        Positioned(
          bottom: 6,
          right: 6,
          child: SizedBox(
            width: 24,
            height: 24,
            child: IconButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: formatted));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copiado'),
                    duration: Duration(milliseconds: 1500),
                  ),
                );
              },
              icon: const Icon(Icons.copy_rounded,
                  size: 13, color: AppColors.ctText3),
              padding: EdgeInsets.zero,
              tooltip: 'Copiar valor',
            ),
          ),
        ),
      ],
    );
  }
}

// ── Date ─────────────────────────────────────────────────────────────────────

class _DateValue extends StatelessWidget {
  const _DateValue({required this.value});
  final dynamic value;

  static const _shortMonths = [
    'ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN',
    'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC'
  ];
  static const _longMonths = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
  ];

  @override
  Widget build(BuildContext context) {
    if (value == null) return const _PendingSlot();
    DateTime d;
    try {
      d = DateTime.parse(value.toString()).toLocal();
    } catch (_) {
      return _TextValue(value: value, multiline: false);
    }
    final mon = _shortMonths[d.month - 1];
    final monLong = _longMonths[d.month - 1];
    final day = d.day;
    final year = d.year;
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F5),
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.ctBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(mon,
                    style: AppFonts.geist(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ctDanger,
                        letterSpacing: 0.05)),
                Text(day.toString(),
                    style: AppFonts.onest(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ctNavy)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$day de $monLong de $year',
                  style: AppFonts.geist(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ctNavy)),
              Text('$h:$m',
                  style:
                      AppFonts.geist(fontSize: 12, color: const Color(0xFF475569))),
            ],
          ),
        ],
      ),
    );
  }
}

// ── YesNo ─────────────────────────────────────────────────────────────────────

class _YesNoValue extends StatelessWidget {
  const _YesNoValue({required this.value});
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    if (value == null) return const _PendingSlot();
    final yes = value == true || value == 'true' || value == 1;

    return Row(
      children: [
        Expanded(child: _YesNoOption(label: 'Sí', active: yes, isYes: true)),
        const SizedBox(width: 8),
        Expanded(child: _YesNoOption(label: 'No', active: !yes, isYes: false)),
      ],
    );
  }
}

class _YesNoOption extends StatelessWidget {
  const _YesNoOption(
      {required this.label, required this.active, required this.isYes});
  final String label;
  final bool active;
  final bool isYes;

  @override
  Widget build(BuildContext context) {
    final (bg, bd, fg) = active
        ? isYes
            ? (AppColors.ctOkBg, AppColors.ctOk, AppColors.ctOkText)
            : (AppColors.ctRedBg, AppColors.ctDanger, AppColors.ctRedText)
        : (Colors.white, AppColors.ctBorder, const Color(0xFF94A3B8));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: bd, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(
              color: active ? (isYes ? AppColors.ctOk : AppColors.ctDanger) : Colors.transparent,
              border: active
                  ? null
                  : Border.all(color: AppColors.ctBorder2, width: 1.5),
              shape: BoxShape.circle,
            ),
            child: active
                ? Icon(isYes ? Icons.check_rounded : Icons.close_rounded,
                    size: 12, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 10),
          Text(label,
              style: AppFonts.geist(
                  fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

// ── Select ────────────────────────────────────────────────────────────────────

class _SelectValue extends StatelessWidget {
  const _SelectValue({
    required this.value,
    required this.options,
    this.operatorOptions = const [],
  });
  final dynamic value;
  final List options;
  final List<Map<String, dynamic>> operatorOptions;

  String _resolve(String raw) {
    if (operatorOptions.isEmpty) return raw;
    final match = operatorOptions.firstWhere(
      (o) => (o['id'] as String?) == raw,
      orElse: () => const {},
    );
    return (match['name'] as String?) ?? raw;
  }

  Widget _selectedChip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.ctTealLight,
          border: Border.all(color: AppColors.ctTeal),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_rounded, size: 12, color: AppColors.ctTealText),
            const SizedBox(width: 6),
            Text(label,
                style: AppFonts.geist(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ctTealText,
                )),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    // Normalize to List<String>
    final selected = value is List
        ? (value as List).map((e) => e.toString()).toList()
        : value != null
            ? [value.toString()]
            : <String>[];

    // ≥ 5 options: show only selected chip(s)
    if (options.length >= 5) {
      if (selected.isEmpty) {
        return Text('Sin selección',
            style: AppFonts.geist(fontSize: 12, color: AppColors.ctText3));
      }
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: selected
            .map((val) => _selectedChip(_resolve(val)))
            .toList(),
      );
    }

    // < 5 options: show all chips, selected highlighted with resolver
    if (options.isEmpty && selected.isNotEmpty) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: selected
            .map((val) => _selectedChip(_resolve(val)))
            .toList(),
      );
    }
    if (options.isEmpty) return const _PendingSlot();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options.map<Widget>((opt) {
        final raw = opt.toString();
        final label = _resolve(raw);
        final isSel = selected.contains(raw);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSel ? AppColors.ctTealLight : Colors.white,
            border: Border.all(
                color: isSel ? AppColors.ctTeal : AppColors.ctBorder),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSel) ...[
                const Icon(Icons.check_rounded,
                    size: 12, color: AppColors.ctTealText),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: AppFonts.geist(
                    fontSize: 12,
                    fontWeight: isSel ? FontWeight.w600 : FontWeight.w500,
                    color: isSel ? AppColors.ctTealText : const Color(0xFF94A3B8),
                  )),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Photo Gallery ─────────────────────────────────────────────────────────────

class _PhotoGallery extends StatelessWidget {
  const _PhotoGallery({required this.photos});
  final List<String> photos;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) return const _PendingSlot();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        childAspectRatio: 4 / 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: photos.length,
      itemBuilder: (ctx, i) => _PhotoThumb(
        src: photos[i],
        index: i,
        total: photos.length,
        onTap: () => showDialog(
          context: context,
          barrierColor: Colors.black87,
          builder: (_) => MediaPreviewDialog(url: photos[i]),
        ),
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({
    required this.src,
    required this.index,
    required this.total,
    required this.onTap,
  });
  final String src;
  final int index;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final num = '${(index + 1).toString().padLeft(2, '0')} / ${total.toString().padLeft(2, '0')}';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(src,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) => _MediaErrorSlot(url: src)),
              // Top-left numerator
              Positioned(
                top: 6, left: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xB20B132B),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(num,
                      style: const TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: 0.03)),
                ),
              ),
              // Bottom gradient + timestamp
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  height: 48,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0x73000000)],
                    ),
                  ),
                  alignment: Alignment.bottomLeft,
                  padding: const EdgeInsets.all(8),
                  child: Text('Evidencia',
                      style: const TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                          letterSpacing: 0.02)),
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
                    onPressed: () => Clipboard.setData(ClipboardData(text: src)),
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
      ),
    );
  }
}

// ── Location Map ──────────────────────────────────────────────────────────────

class _LocationMap extends StatelessWidget {
  const _LocationMap({required this.value});
  final Map<String, dynamic>? value;

  @override
  Widget build(BuildContext context) {
    if (value == null) return const _PendingSlot();
    final lat = ((value!['lat'] ?? value!['latitude']) as num?)?.toDouble() ?? 0;
    final lng = ((value!['lng'] ?? value!['longitude']) as num?)?.toDouble() ?? 0;
    final address = value!['address'] as String? ?? '';
    if (lat == 0 && lng == 0) return const _PendingSlot();

    final point = LatLng(lat, lng);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 200,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: point,
                initialZoom: 15,
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.none),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}@2x.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.conectamos.platform',
                ),
                CircleLayer(circles: [
                  CircleMarker(
                    point: point,
                    radius: 60,
                    useRadiusInMeter: true,
                    color: const Color(0x2659E0CC),
                    borderColor: AppColors.ctTeal,
                    borderStrokeWidth: 1.5,
                  ),
                ]),
                MarkerLayer(markers: [
                  Marker(
                    point: point,
                    width: 36,
                    height: 46,
                    alignment: Alignment.topCenter,
                    child: const _LocationMarkerWidget(),
                  ),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F3F5),
            border: Border.all(color: AppColors.ctBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_rounded,
                  size: 16, color: AppColors.ctTeal),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(address,
                        style: AppFonts.geist(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.ctNavy,
                            height: 1.45)),
                    const SizedBox(height: 3),
                    Text(
                        '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                        style: const TextStyle(
                            fontFamily: 'Geist',
                            fontSize: 11,
                            color: Color(0xFF475569),
                            letterSpacing: -0.005)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () async {
                  final uri = Uri.parse(
                      'https://www.google.com/maps?q=$lat,$lng');
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 11),
                label: const Text('Abrir'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.ctText2,
                  textStyle:
                      AppFonts.geist(fontSize: 11, fontWeight: FontWeight.w500),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LocationMarkerWidget extends StatelessWidget {
  const _LocationMarkerWidget();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36, height: 46,
      child: Stack(
        children: [
          Positioned(
            top: 0, left: 2,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppColors.ctTeal,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.ctNavy, width: 3),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x660B132B),
                      offset: Offset(0, 4),
                      blurRadius: 12),
                ],
              ),
              child: const Icon(Icons.location_on_rounded,
                  size: 16, color: AppColors.ctNavy),
            ),
          ),
          Positioned(
            bottom: 0, left: 12,
            child: CustomPaint(
              size: const Size(12, 6),
              painter: _TrianglePainter(color: AppColors.ctNavy),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}

// ── Location URL Link (fallback when only value_media_url is available) ───────

class _LocationUrlLink extends StatelessWidget {
  const _LocationUrlLink({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final uri = Uri.tryParse(url);
        if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F5),
          border: Border.all(color: AppColors.ctBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on_rounded, size: 16, color: AppColors.ctTeal),
            const SizedBox(width: 8),
            Text('Ver ubicación',
                style: AppFonts.geist(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ctTeal)),
            const SizedBox(width: 4),
            const Icon(Icons.open_in_new_rounded, size: 13, color: AppColors.ctTeal),
          ],
        ),
      ),
    );
  }
}

// ── Generic URL Link ──────────────────────────────────────────────────────────

class _UrlLink extends StatelessWidget {
  const _UrlLink({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final uri = Uri.tryParse(url);
        if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F5),
          border: Border.all(color: AppColors.ctBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.link_rounded, size: 14, color: AppColors.ctTeal),
            const SizedBox(width: 8),
            Expanded(
              child: Text(url,
                  style: AppFonts.geist(fontSize: 12, color: AppColors.ctTeal),
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.open_in_new_rounded, size: 13, color: AppColors.ctTeal),
          ],
        ),
      ),
    );
  }
}

// ── Media Error Slot ──────────────────────────────────────────────────────────

class _MediaErrorSlot extends StatelessWidget {
  const _MediaErrorSlot({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.ctSurface2,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.broken_image_rounded,
            color: AppColors.ctText3,
            size: 22,
          ),
          const SizedBox(height: 6),
          const Text(
            'No se pudo cargar',
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 11,
              color: AppColors.ctText3,
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () async {
              final uri = Uri.tryParse(url);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text(
              'Abrir en navegador',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.ctTeal,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Captured Raw Slot ─────────────────────────────────────────────────────────

class _CapturedRawSlot extends StatelessWidget {
  const _CapturedRawSlot({this.rawValue});
  final String? rawValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 16, color: Color(0xFFD97706)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Capturado · no se puede visualizar',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFD97706),
                  ),
                ),
                if (rawValue != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    rawValue!,
                    style: const TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 11,
                      color: Color(0xFF92400E),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pending Slot ──────────────────────────────────────────────────────────────

class _PendingSlot extends StatefulWidget {
  const _PendingSlot();

  @override
  State<_PendingSlot> createState() => _PendingSlotState();
}

class _PendingSlotState extends State<_PendingSlot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border.all(
            color: const Color(0xFFFCD34D), width: 1.5,
            style: BorderStyle.solid),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _opacity,
            builder: (context2, child2) => Opacity(
              opacity: _opacity.value,
              child: Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.ctWarn,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text('Pendiente de captura',
              style: AppFonts.geist(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ctWarnText)),
        ],
      ),
    );
  }
}
