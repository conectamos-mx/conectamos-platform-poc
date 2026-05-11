import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/screen_header.dart';

// ── Color options ─────────────────────────────────────────────────────────────

const _kColorOptions = [
  '#59E0CC',
  '#F59E0B',
  '#8B5CF6',
  '#3B82F6',
  '#EF4444',
  '#10B981',
];

Color _hexColor(String hex) {
  final h = hex.replaceAll('#', '');
  return Color(int.parse('FF$h', radix: 16));
}

// ── Mock data ─────────────────────────────────────────────────────────────────

final _kInitialTypes = <Map<String, dynamic>>[
  {
    'slug': 'crum_daily',
    'label': 'CRUM diario',
    'scope': 'date',
    'color': '#59E0CC',
    'fields': [
      {'key': 'crum', 'label': 'CRUM', 'type': 'text'},
    ],
    'materializes': true,
  },
  {
    'slug': 'vehicle_daily',
    'label': 'Vehículo del día',
    'scope': 'date',
    'color': '#F59E0B',
    'fields': [
      {'key': 'vehicle_id', 'label': 'Vehículo', 'type': 'text'},
    ],
    'materializes': false,
  },
  {
    'slug': 'route_assignment',
    'label': 'Ruta asignada',
    'scope': 'window',
    'color': '#8B5CF6',
    'fields': [
      {'key': 'zone', 'label': 'Zona', 'type': 'text'},
    ],
    'materializes': false,
  },
];

// ── Screen ────────────────────────────────────────────────────────────────────

class AssignmentTypesScreen extends ConsumerStatefulWidget {
  const AssignmentTypesScreen({super.key});

  @override
  ConsumerState<AssignmentTypesScreen> createState() =>
      _AssignmentTypesScreenState();
}

class _AssignmentTypesScreenState
    extends ConsumerState<AssignmentTypesScreen> {
  late List<Map<String, dynamic>> _types;

  // Drawer state
  Map<String, dynamic>? _editingType;
  final _labelCtrl = TextEditingController();
  final _slugCtrl = TextEditingController();
  String _editScope = 'date';
  String _editColor = '#59E0CC';
  List<Map<String, dynamic>> _editFields = [];

  // Toast
  String? _toast;
  Timer? _toastTimer;

  bool get _showDrawer => _editingType != null;
  bool get _isNewType =>
      _editingType != null &&
      (_editingType!['slug'] == null ||
          (_editingType!['slug'] as String).isEmpty);

  @override
  void initState() {
    super.initState();
    _types =
        _kInitialTypes.map((t) => Map<String, dynamic>.from(t)).toList();
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _slugCtrl.dispose();
    _toastTimer?.cancel();
    super.dispose();
  }

  void _openNew() {
    setState(() {
      _editingType = <String, dynamic>{};
      _labelCtrl.text = '';
      _slugCtrl.text = '';
      _editScope = 'date';
      _editColor = '#59E0CC';
      _editFields = [];
    });
  }

  void _openEdit(Map<String, dynamic> type) {
    setState(() {
      _editingType = type;
      _labelCtrl.text = type['label'] as String? ?? '';
      _slugCtrl.text = type['slug'] as String? ?? '';
      _editScope = type['scope'] as String? ?? 'date';
      _editColor = type['color'] as String? ?? '#59E0CC';
      _editFields = ((type['fields'] as List?) ?? [])
          .map((f) => Map<String, dynamic>.from(f as Map))
          .toList();
    });
  }

  void _closeDrawer() => setState(() => _editingType = null);

  void _addField() => setState(() {
        _editFields.add({'key': '', 'label': '', 'type': 'text'});
      });

  void _removeField(int idx) => setState(() => _editFields.removeAt(idx));

  void _save() {
    final updated = <String, dynamic>{
      'slug': _slugCtrl.text.trim(),
      'label': _labelCtrl.text.trim(),
      'scope': _editScope,
      'color': _editColor,
      'fields': _editFields
          .where((f) => (f['key'] as String? ?? '').isNotEmpty)
          .toList(),
      'materializes': _editingType?['materializes'] ?? false,
    };
    setState(() {
      if (_isNewType) {
        _types.add(updated);
      } else {
        final idx = _types
            .indexWhere((t) => t['slug'] == _editingType!['slug']);
        if (idx >= 0) _types[idx] = updated;
      }
      _editingType = null;
      _toast = 'Tipo guardado';
    });
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ctBg,
      body: Stack(
        children: [
          // Main content
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ScreenHeader(
                title: 'Tipos de asignación',
                subtitle:
                    'Define qué tipos de asignación maneja el tenant y su schema de datos.',
                actions: [
                  GestureDetector(
                    onTap: () => context.go('/assignments'),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.arrow_back_rounded,
                              size: 14, color: AppColors.ctText2),
                          const SizedBox(width: 4),
                          Text(
                            'Asignaciones',
                            style: AppFonts.geist(
                                fontSize: 13, color: AppColors.ctText2),
                          ),
                          Text(
                            ' / Tipos',
                            style: AppFonts.geist(
                                fontSize: 13, color: AppColors.ctText3),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _PrimaryButton(label: '+ Nuevo tipo', onTap: _openNew),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: _types.isEmpty
                      ? _EmptyState(onNew: _openNew)
                      : _TypesTable(types: _types, onEdit: _openEdit),
                ),
              ),
            ],
          ),
          // Backdrop
          if (_showDrawer)
            GestureDetector(
              onTap: _closeDrawer,
              child: Container(
                color: const Color.fromRGBO(0, 0, 0, 0.3),
              ),
            ),
          // Sliding drawer
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            right: _showDrawer ? 0 : -520,
            top: 0,
            bottom: 0,
            width: 480,
            child: _buildDrawer(),
          ),
          // Toast
          if (_toast != null)
            Positioned(
              bottom: 28,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.ctText,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _toast!,
                    style: AppFonts.geist(
                        fontSize: 13,
                        color: AppColors.ctSurface,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.ctSurface,
        border: Border(left: BorderSide(color: AppColors.ctBorder)),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.08),
            blurRadius: 24,
            offset: Offset(-4, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: AppColors.ctBorder)),
            ),
            child: Row(
              children: [
                Text(
                  _isNewType
                      ? 'Nuevo tipo'
                      : 'Editar: ${_editingType?['label'] ?? ''}',
                  style: AppFonts.onest(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ctText),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _closeDrawer,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded,
                          size: 18, color: AppColors.ctText2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Scrollable form body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _FieldLabel('Label'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _labelCtrl,
                    decoration: const InputDecoration(
                        hintText: 'Ej. CRUM diario'),
                    style: AppFonts.geist(
                        fontSize: 13, color: AppColors.ctText),
                  ),
                  const SizedBox(height: 16),
                  const _FieldLabel('Slug'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _slugCtrl,
                    readOnly: !_isNewType,
                    decoration: InputDecoration(
                      hintText: 'Ej. crum_daily',
                      filled: true,
                      fillColor: !_isNewType
                          ? AppColors.ctSurface2
                          : AppColors.ctSurface,
                    ),
                    style: AppFonts.geist(
                        fontSize: 13, color: AppColors.ctText),
                  ),
                  const SizedBox(height: 16),
                  const _FieldLabel('Scope'),
                  const SizedBox(height: 6),
                  _ScopeDropdown(
                    value: _editScope,
                    onChanged: (v) =>
                        setState(() => _editScope = v ?? 'date'),
                  ),
                  const SizedBox(height: 16),
                  const _FieldLabel('Color'),
                  const SizedBox(height: 8),
                  Row(
                    children: _kColorOptions.map((hex) {
                      final selected = hex == _editColor;
                      return GestureDetector(
                        onTap: () => setState(() => _editColor = hex),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: _hexColor(hex),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: selected
                                    ? AppColors.ctText
                                    : Colors.transparent,
                                width: 2,
                              ),
                              boxShadow: selected
                                  ? const [
                                      BoxShadow(
                                        color:
                                            Color.fromRGBO(0, 0, 0, 0.15),
                                        blurRadius: 4,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  const _FieldLabel('Schema de datos'),
                  const SizedBox(height: 8),
                  _FieldsTable(
                    fields: _editFields,
                    onChanged: (idx, field) =>
                        setState(() => _editFields[idx] = field),
                    onRemove: _removeField,
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _addField,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add_rounded,
                              size: 14, color: AppColors.ctTeal),
                          const SizedBox(width: 4),
                          Text(
                            '+ Agregar campo',
                            style: AppFonts.geist(
                                fontSize: 12,
                                color: AppColors.ctTeal,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Footer buttons
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.ctBorder)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _SecondaryButton(
                    label: 'Cancelar', onTap: _closeDrawer),
                const SizedBox(width: 8),
                _PrimaryButton(label: 'Guardar', onTap: _save),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Types table ───────────────────────────────────────────────────────────────

class _TypesTable extends StatelessWidget {
  const _TypesTable({required this.types, required this.onEdit});

  final List<Map<String, dynamic>> types;
  final void Function(Map<String, dynamic>) onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Table header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: AppColors.ctBorder)),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: const Row(
              children: [
                _ColHeader('Slug', flex: 2),
                _ColHeader('Label', flex: 2),
                _ColHeader('Scope', flex: 1),
                _ColHeader('Schema', flex: 3),
                _ColHeader('Materializa', flex: 1),
                _ColHeader('', flex: 1),
              ],
            ),
          ),
          // Data rows
          ...types.map((t) => _TypeRow(type: t, onEdit: onEdit)),
        ],
      ),
    );
  }
}

class _ColHeader extends StatelessWidget {
  const _ColHeader(this.label, {required this.flex});

  final String label;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: AppFonts.geist(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.ctText3),
      ),
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.type, required this.onEdit});

  final Map<String, dynamic> type;
  final void Function(Map<String, dynamic>) onEdit;

  @override
  Widget build(BuildContext context) {
    final fields = (type['fields'] as List?) ?? [];
    final colorHex = type['color'] as String? ?? '#9CA3AF';
    final scope = type['scope'] as String? ?? 'date';
    final materializes = type['materializes'] as bool? ?? false;

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.ctBorder)),
      ),
      child: Row(
        children: [
          // Slug
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.ctSurface2,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                type['slug'] as String? ?? '',
                style: AppFonts.geist(
                    fontSize: 11, color: AppColors.ctText2),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Label with color dot
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _hexColor(colorHex),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    type['label'] as String? ?? '',
                    style: AppFonts.geist(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ctText),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Scope badge
          Expanded(flex: 1, child: _ScopeBadge(scope)),
          // Schema chips
          Expanded(
            flex: 3,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: fields.map<Widget>((f) {
                final fMap = f as Map;
                final key = fMap['key'] as String? ?? '';
                final ftype = fMap['type'] as String? ?? 'text';
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.ctSurface2,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$key ($ftype)',
                    style: AppFonts.geist(
                        fontSize: 11, color: AppColors.ctText2),
                  ),
                );
              }).toList(),
            ),
          ),
          // Materializa
          Expanded(
            flex: 1,
            child: materializes
                ? const _StatusChip(
                    label: 'Sí',
                    bg: Color(0xFFD1FAE5),
                    fg: Color(0xFF065F46),
                  )
                : const _StatusChip(
                    label: 'No',
                    bg: AppColors.ctSurface2,
                    fg: AppColors.ctText3,
                  ),
          ),
          // Edit action
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => onEdit(type),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Text(
                    'Editar',
                    style: AppFonts.geist(
                        fontSize: 12,
                        color: AppColors.ctTeal,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onNew});

  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_today_outlined,
              size: 40, color: AppColors.ctText3),
          const SizedBox(height: 12),
          Text(
            'Sin tipos configurados',
            style: AppFonts.onest(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.ctText),
          ),
          const SizedBox(height: 6),
          Text(
            'Crea el primer tipo de asignación para tu tenant.',
            style:
                AppFonts.geist(fontSize: 13, color: AppColors.ctText2),
          ),
          const SizedBox(height: 16),
          _PrimaryButton(label: '+ Nuevo tipo', onTap: onNew),
        ],
      ),
    );
  }
}

// ── Fields schema table ───────────────────────────────────────────────────────

class _FieldsTable extends StatelessWidget {
  const _FieldsTable({
    required this.fields,
    required this.onChanged,
    required this.onRemove,
  });

  final List<Map<String, dynamic>> fields;
  final void Function(int idx, Map<String, dynamic> field) onChanged;
  final void Function(int idx) onRemove;

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) {
      return Text(
        'Sin campos. Agrega al menos uno.',
        style: AppFonts.geist(fontSize: 12, color: AppColors.ctText3),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: AppColors.ctSurface2,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(7)),
              border: Border(
                  bottom: BorderSide(color: AppColors.ctBorder)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text('Key',
                      style: AppFonts.geist(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ctText3)),
                ),
                Expanded(
                  flex: 3,
                  child: Text('Label',
                      style: AppFonts.geist(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ctText3)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Tipo',
                      style: AppFonts.geist(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ctText3)),
                ),
                const SizedBox(width: 28),
              ],
            ),
          ),
          // Rows
          ...fields.asMap().entries.map((entry) {
            final idx = entry.key;
            final f = entry.value;
            final isLast = idx == fields.length - 1;
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : const Border(
                        bottom: BorderSide(color: AppColors.ctBorder)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      initialValue: f['key'] as String? ?? '',
                      onChanged: (v) =>
                          onChanged(idx, {...f, 'key': v}),
                      decoration: const InputDecoration(
                        hintText: 'key',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                      ),
                      style: AppFonts.geist(
                          fontSize: 12, color: AppColors.ctText),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      initialValue: f['label'] as String? ?? '',
                      onChanged: (v) =>
                          onChanged(idx, {...f, 'label': v}),
                      decoration: const InputDecoration(
                        hintText: 'Label',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                      ),
                      style: AppFonts.geist(
                          fontSize: 12, color: AppColors.ctText),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: f['type'] as String? ?? 'text',
                      isDense: true,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'text', child: Text('text')),
                        DropdownMenuItem(
                            value: 'number', child: Text('number')),
                        DropdownMenuItem(
                            value: 'date', child: Text('date')),
                      ],
                      onChanged: (v) =>
                          onChanged(idx, {...f, 'type': v ?? 'text'}),
                      style: AppFonts.geist(
                          fontSize: 12, color: AppColors.ctText),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => onRemove(idx),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: const Icon(Icons.close_rounded,
                          size: 16, color: AppColors.ctText3),
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

// ── Scope dropdown ────────────────────────────────────────────────────────────

class _ScopeDropdown extends StatelessWidget {
  const _ScopeDropdown(
      {required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String?> onChanged;

  static const _items = {
    'date': 'date — Un día completo',
    'window': 'window — Rango horario',
    'open': 'open — Sin scope',
  };

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: const InputDecoration(),
      items: _items.entries
          .map((e) =>
              DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: onChanged,
      style: AppFonts.geist(fontSize: 13, color: AppColors.ctText),
    );
  }
}

// ── Scope badge ───────────────────────────────────────────────────────────────

class _ScopeBadge extends StatelessWidget {
  const _ScopeBadge(this.scope);

  final String scope;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        scope,
        style: AppFonts.geist(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.ctText2),
      ),
    );
  }
}

// ── Status chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip(
      {required this.label, required this.bg, required this.fg});

  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: AppFonts.geist(
            fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

// ── Field label ───────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppFonts.geist(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.ctText),
    );
  }
}

// ── Buttons ───────────────────────────────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.ctTeal,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: AppFonts.geist(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ctNavy),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.ctSurface,
            border: Border.all(color: AppColors.ctBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: AppFonts.geist(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.ctText),
          ),
        ),
      ),
    );
  }
}
