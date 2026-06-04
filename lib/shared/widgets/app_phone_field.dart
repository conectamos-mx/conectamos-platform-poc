import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/phone_normalizer.dart';

// ── Country data ──────────────────────────────────────────────────────────────

/// (ISO2, Name, DialCode) tuples used by the country picker.
const List<(String, String, String)> kPhoneCountries = [
  ('MX', 'México', '+52'),
  ('US', 'Estados Unidos', '+1'),
  ('CO', 'Colombia', '+57'),
  ('GT', 'Guatemala', '+502'),
  ('HN', 'Honduras', '+504'),
  ('SV', 'El Salvador', '+503'),
  ('ES', 'España', '+34'),
  ('AR', 'Argentina', '+54'),
  ('CL', 'Chile', '+56'),
  ('PE', 'Perú', '+51'),
  ('VE', 'Venezuela', '+58'),
  ('EC', 'Ecuador', '+593'),
  ('BO', 'Bolivia', '+591'),
  ('PY', 'Paraguay', '+595'),
  ('UY', 'Uruguay', '+598'),
  ('BR', 'Brasil', '+55'),
  ('CA', 'Canadá', '+1'),
  ('FR', 'Francia', '+33'),
  ('DE', 'Alemania', '+49'),
  ('IT', 'Italia', '+39'),
  ('GB', 'Reino Unido', '+44'),
];

/// Unicode flag emoji for an ISO 3166-1 alpha-2 code.
String countryFlag(String iso) {
  const base = 0x1F1E6 - 0x41;
  return iso.toUpperCase().codeUnits
      .map((c) => String.fromCharCode(c + base))
      .join();
}

// ── PhoneFieldWidget ──────────────────────────────────────────────────────────

/// A phone input widget with a searchable country-code selector and real-time
/// E.164 preview. Calls [onChanged] with the current E.164 value on every
/// edit.
class PhoneFieldWidget extends StatefulWidget {
  const PhoneFieldWidget({
    super.key,
    this.initialLocalNumber,
    this.initialCountryIso = 'MX',
    this.label,
    this.errorText,
    required this.onChanged,
    this.enabled = true,
  });

  final String? initialLocalNumber;
  final String initialCountryIso;
  final String? label;
  final String? errorText;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  State<PhoneFieldWidget> createState() => _PhoneFieldWidgetState();
}

class _PhoneFieldWidgetState extends State<PhoneFieldWidget> {
  late String _iso;
  late String _dialCode;
  late final TextEditingController _ctrl;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _iso = widget.initialCountryIso;
    _dialCode = PhoneNormalizer.dialCode(_iso);
    _ctrl = TextEditingController(text: widget.initialLocalNumber ?? '');
    _ctrl.addListener(_emit);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(PhoneNormalizer.formatToE164(_ctrl.text, _iso));
  }

  String get _preview {
    if (_ctrl.text.trim().isEmpty) return '';
    return PhoneNormalizer.formatToE164(_ctrl.text, _iso);
  }

  Future<void> _pickCountry() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => CountryPickerDialog(
        countries: kPhoneCountries,
        selectedIso: _iso,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _iso = result.$1;
        _dialCode = result.$2;
        _localError = null;
      });
      _emit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _localError ?? widget.errorText;
    final preview = _preview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            // Country selector button
            GestureDetector(
              onTap: widget.enabled ? _pickCountry : null,
              child: MouseRegion(
                cursor: widget.enabled
                    ? SystemMouseCursors.click
                    : MouseCursor.defer,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppColors.ctSurface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: error != null
                          ? AppColors.ctDanger
                          : AppColors.ctBorder2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(countryFlag(_iso),
                          style: AppTextStyles.body.copyWith(fontSize: 18)),
                      const SizedBox(width: 6),
                      Text(
                        _dialCode,
                        style: AppTextStyles.body,
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down_rounded,
                          size: 14, color: AppColors.ctText3),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Number input
            Expanded(
              child: TextField(
                controller: _ctrl,
                enabled: widget.enabled,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'[\d\s\-\(\)\+]')),
                ],
                style: AppTextStyles.body,
                onEditingComplete: () => setState(() {
                  _localError =
                      PhoneNormalizer.validatePhone(_ctrl.text, _iso);
                }),
                decoration: InputDecoration(
                  hintText: 'Número local',
                  hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                  filled: true,
                  fillColor: AppColors.ctSurface2,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: error != null
                          ? AppColors.ctDanger
                          : AppColors.ctBorder2,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: error != null
                          ? AppColors.ctDanger
                          : AppColors.ctBorder2,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: error != null
                          ? AppColors.ctDanger
                          : AppColors.ctTeal,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (preview.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            preview,
            style: AppTextStyles.bodySmall,
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 3),
          Text(
            error,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctDanger),
          ),
        ],
      ],
    );
  }
}

// ── CountryPickerDialog ───────────────────────────────────────────────────────

/// Searchable dialog for selecting a country from [countries].
/// Pops with a (isoCode, dialCode) tuple on selection.
class CountryPickerDialog extends StatefulWidget {
  const CountryPickerDialog({
    super.key,
    required this.countries,
    required this.selectedIso,
  });

  final List<(String, String, String)> countries;
  final String selectedIso;

  @override
  State<CountryPickerDialog> createState() => _CountryPickerDialogState();
}

class _CountryPickerDialogState extends State<CountryPickerDialog> {
  String _q = '';

  List<(String, String, String)> get _filtered {
    if (_q.isEmpty) return widget.countries;
    final q = _q.toLowerCase();
    return widget.countries
        .where((c) =>
            c.$1.toLowerCase().contains(q) ||
            c.$2.toLowerCase().contains(q) ||
            c.$3.contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 320,
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                style: AppTextStyles.body,
                decoration: InputDecoration(
                  hintText: 'Buscar país...',
                  hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 16, color: AppColors.ctText3),
                  filled: true,
                  fillColor: AppColors.ctSurface2,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: AppColors.ctBorder2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: AppColors.ctBorder2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                        color: AppColors.ctTeal, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _filtered.length,
                itemBuilder: (ctx, i) {
                  final c = _filtered[i];
                  final selected = c.$1 == widget.selectedIso;
                  return InkWell(
                    onTap: () =>
                        Navigator.pop(context, (c.$1, c.$3)),
                    child: Container(
                      color: selected
                          ? AppColors.ctTealLight
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Text(countryFlag(c.$1),
                              style: AppTextStyles.body.copyWith(fontSize: 18)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              c.$2,
                              style: AppTextStyles.body,
                            ),
                          ),
                          Text(
                            c.$3,
                            style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
