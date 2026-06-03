import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/phone_normalizer.dart';
import 'phone_field_widget.dart';

/// Widget para gestionar participantes de torres de control.
/// Permite agregar/remover números de teléfono con código de país.
class ParticipantsWidget extends StatefulWidget {
  const ParticipantsWidget({
    super.key,
    this.initial,
    required this.onChanged,
  });

  final List<String>? initial; // Lista de números E.164
  final ValueChanged<List<String>> onChanged;

  @override
  State<ParticipantsWidget> createState() => _ParticipantsWidgetState();
}

class _ParticipantsWidgetState extends State<ParticipantsWidget> {
  late final List<_ParticipantEntry> _entries;

  @override
  void initState() {
    super.initState();
    _entries = (widget.initial ?? []).map((phone) {
      final (iso, local) = PhoneNormalizer.parsePhone(phone);
      return _ParticipantEntry(
        localNumber: local,
        countryIso: iso,
        e164: phone,
      );
    }).toList();
  }

  void _emit() {
    widget.onChanged(_entries.map((e) => e.e164).where((p) => p.isNotEmpty).toList());
  }

  void _addEntry() {
    setState(() {
      _entries.add(_ParticipantEntry(
        localNumber: '',
        countryIso: 'MX',
        e164: '',
      ));
    });
    _emit();
  }

  void _removeEntry(int idx) {
    setState(() {
      _entries.removeAt(idx);
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Participantes del grupo',
          style: AppTextStyles.body.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.ctText,
          ),
        ),
        const SizedBox(height: 10),
        if (_entries.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.ctSurface2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.ctBorder),
            ),
            child: Center(
              child: Text(
                'Sin participantes',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
              ),
            ),
          )
        else
          ...List.generate(_entries.length, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ParticipantCard(
                entry: _entries[i],
                onRemove: () => _removeEntry(i),
                onChanged: () => setState(_emit),
              ),
            );
          }),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _addEntry,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              height: 36,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.ctSurface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.ctBorder2),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded, size: 14, color: AppColors.ctTeal),
                  const SizedBox(width: 6),
                  Text(
                    'Agregar participante',
                    style: AppTextStyles.bodySmall.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ctTeal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Card por participante ─────────────────────────────────────────────────

class _ParticipantCard extends StatefulWidget {
  const _ParticipantCard({
    required this.entry,
    required this.onRemove,
    required this.onChanged,
  });

  final _ParticipantEntry entry;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  State<_ParticipantCard> createState() => _ParticipantCardState();
}

class _ParticipantCardState extends State<_ParticipantCard> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.ctSurface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: PhoneFieldWidget(
              initialLocalNumber: widget.entry.localNumber,
              initialCountryIso: widget.entry.countryIso,
              onChanged: (e164) {
                widget.entry.e164 = e164;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.onRemove,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.ctDanger.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: AppColors.ctDanger,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Entry model ───────────────────────────────────────────────────────────

class _ParticipantEntry {
  _ParticipantEntry({
    required this.localNumber,
    required this.countryIso,
    required this.e164,
  });

  final String localNumber;
  final String countryIso;
  String e164;
}
