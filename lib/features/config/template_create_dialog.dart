import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/templates_api.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../shared/widgets/app_button.dart';

// ── Tipos de encabezado ────────────────────────────────────────────────────────

enum _HeaderType { none, text, image, video, file }

// ── Dialog principal ───────────────────────────────────────────────────────────

class TemplateCreateDialog extends ConsumerStatefulWidget {
  const TemplateCreateDialog({
    super.key,
    required this.channelId,
    required this.tenantId,
  });

  final String channelId;
  final String tenantId;

  @override
  ConsumerState<TemplateCreateDialog> createState() => _TemplateCreateDialogState();
}

class _TemplateCreateDialogState extends ConsumerState<TemplateCreateDialog> {
  final _nameCtrl        = TextEditingController();
  final _headerTextCtrl  = TextEditingController();
  final _headerUrlCtrl   = TextEditingController();
  final _bodyCtrl        = TextEditingController();
  final _footerCtrl      = TextEditingController();
  final _bodyFocus       = FocusNode();

  final Map<int, TextEditingController> _varExampleCtrls = {};

  String      _category   = 'MARKETING';
  String      _language   = 'es_MX';
  _HeaderType _headerType = _HeaderType.none;
  bool        _submitting = false;
  String?     _nameError;
  String?     _varError;
  int         _varCount   = 0;
  final List<TextEditingController> _buttonCtrls = [];

  static const _categories = [
    (value: 'MARKETING',      label: 'Marketing'),
    (value: 'UTILITY',        label: 'Utilidad'),
    (value: 'AUTHENTICATION', label: 'Autenticación'),
  ];

  static const _languages = [
    (value: 'es_MX', label: 'Español México (es_MX)'),
    (value: 'es_ES', label: 'Español España (es_ES)'),
    (value: 'es_AR', label: 'Español Argentina (es_AR)'),
    (value: 'en_US', label: 'Inglés US (en_US)'),
    (value: 'en_GB', label: 'Inglés UK (en_GB)'),
    (value: 'pt_BR', label: 'Portugués BR (pt_BR)'),
    (value: 'pt_PT', label: 'Portugués PT (pt_PT)'),
    (value: 'fr',    label: 'Francés (fr)'),
    (value: 'de',    label: 'Alemán (de)'),
    (value: 'it',    label: 'Italiano (it)'),
  ];


  @override
  void initState() {
    super.initState();
    _bodyCtrl.addListener(_refresh);
    _headerTextCtrl.addListener(_refresh);
    _headerUrlCtrl.addListener(_refresh);
    _footerCtrl.addListener(_refresh);
  }

  void _refresh() {
    _syncVarControllers();
    setState(() {});
  }

  void _syncVarControllers() {
    final re = RegExp(r'\{\{(\d+)\}\}');
    final detected = re
        .allMatches(_bodyCtrl.text)
        .map((m) => int.parse(m.group(1)!))
        .toSet();

    // Add controllers for newly detected variables
    for (final n in detected) {
      _varExampleCtrls.putIfAbsent(n, () => TextEditingController());
    }

    // Dispose and remove controllers for variables no longer in body
    final toRemove =
        _varExampleCtrls.keys.where((k) => !detected.contains(k)).toList();
    for (final k in toRemove) {
      _varExampleCtrls.remove(k)!.dispose();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _headerTextCtrl.dispose();
    _headerUrlCtrl.dispose();
    _bodyCtrl.dispose();
    _footerCtrl.dispose();
    _bodyFocus.dispose();
    for (final c in _varExampleCtrls.values) {
      c.dispose();
    }
    for (final c in _buttonCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  // ── helpers ─────────────────────────────────────────────────────────────────

  void _insertVariable() {
    _varCount++;
    final txt = _bodyCtrl.text;
    final sel = _bodyCtrl.selection;
    final tag = '{{$_varCount}}';
    final pos = (sel.isValid && sel.baseOffset >= 0) ? sel.baseOffset : txt.length;
    final next = txt.substring(0, pos) + tag + txt.substring(pos);
    _bodyCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: pos + tag.length),
    );
    _bodyFocus.requestFocus();
  }

  List<Map<String, dynamic>> _buildVariables() {
    final re = RegExp(r'\{\{(\d+)\}\}');
    final seen = <int>{};
    final result = <Map<String, dynamic>>[];
    for (final m in re.allMatches(_bodyCtrl.text)) {
      final n = int.parse(m.group(1)!);
      if (seen.add(n)) {
        result.add({
          'index': n,
          'example': _varExampleCtrls[n]?.text.trim().isNotEmpty == true
              ? _varExampleCtrls[n]!.text.trim()
              : 'Ejemplo $n',
        });
      }
    }
    return result;
  }

  static String _normalizeTemplateName(String input) {
    const accents = '\u00E1\u00E0\u00E4\u00E2\u00E3\u00E9\u00E8\u00EB\u00EA\u00ED\u00EC\u00EF\u00EE\u00F3\u00F2\u00F6\u00F4\u00F5\u00FA\u00F9\u00FC\u00FB\u00F1\u00C1\u00C0\u00C4\u00C2\u00C3\u00C9\u00C8\u00CB\u00CA\u00CD\u00CC\u00CF\u00CE\u00D3\u00D2\u00D6\u00D4\u00D5\u00DA\u00D9\u00DC\u00DB\u00D1';
    const replacements = 'aaaaaeeeeiiiioooooouuuunAAAAAEEEEIIIIOOOOOUUUUN';
    var result = input;
    for (var i = 0; i < accents.length; i++) {
      result = result.replaceAll(accents[i], replacements[i].toLowerCase());
    }
    result = result.toLowerCase();
    result = result.replaceAll(' ', '_');
    result = result.replaceAll(RegExp(r'[^a-z0-9_]'), '');
    return result;
  }

  static const _varHints = {
    1: 'Ej: Juan García',
    2: 'Ej: TMR-Prixz',
  };

  Widget _buildVarExamples() {
    if (_varExampleCtrls.isEmpty) return const SizedBox.shrink();

    final indices = _varExampleCtrls.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _sectionLabel('Ejemplos de variables *'),
        if (_varError != null) ...[
          const SizedBox(height: 4),
          Text(
            _varError!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctDanger),
          ),
        ],
        const SizedBox(height: 8),
        for (final n in indices) ...[
          Text(
            'Ejemplo para {{$n}}',
            style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _varExampleCtrls[n],
            decoration: InputDecoration(
              hintText: _varHints[n] ?? 'Ej: Valor $n',
              hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            style: AppTextStyles.body,
            onChanged: (_) {
              if (_varError != null) setState(() => _varError = null);
            },
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'El nombre es requerido.');
      return;
    }
    if (_bodyCtrl.text.trim().isEmpty) return;

    // Validate var examples before submitting
    if (_varExampleCtrls.isNotEmpty) {
      final missing = _varExampleCtrls.entries
          .where((e) => e.value.text.trim().isEmpty)
          .map((e) => '{{${e.key}}}')
          .toList();
      if (missing.isNotEmpty) {
        setState(() =>
            _varError = 'Completa los ejemplos de todas las variables.');
        return;
      }
    }

    setState(() { _submitting = true; _nameError = null; _varError = null; });
    try {
      final headerTypeStr = switch (_headerType) {
        _HeaderType.none  => null,
        _HeaderType.text  => 'TEXT',
        _HeaderType.image => 'IMAGE',
        _HeaderType.video => 'VIDEO',
        _HeaderType.file  => 'DOCUMENT',
      };
      final headerText = _headerType == _HeaderType.text
          ? _headerTextCtrl.text.trim()
          : null;
      final headerUrl = (_headerType != _HeaderType.none &&
              _headerType != _HeaderType.text)
          ? _headerUrlCtrl.text.trim()
          : null;

      if (_headerType != _HeaderType.none &&
          _headerType != _HeaderType.text &&
          (headerUrl == null || headerUrl.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La URL de ejemplo del encabezado es requerida por Meta.'),
            backgroundColor: AppColors.ctDanger,
          ),
        );
        setState(() => _submitting = false);
        return;
      }

      final footerText = _footerCtrl.text.trim();

      final buttons = _buttonCtrls
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .map((t) => {'type': 'QUICK_REPLY', 'text': t})
          .toList();

      await TemplatesApi.createTemplate(
        dio:              ref.read(apiClientProvider).dio,
        name:             name,
        category:         _category,
        language:         _language,
        bodyText:         _bodyCtrl.text.trim(),
        variables:        _buildVariables(),
        channelId:        widget.channelId,
        headerType:       headerTypeStr,
        headerText:       headerText,
        headerExampleUrl: headerUrl,
        footerText:       footerText.isEmpty ? null : footerText,
        buttons:          buttons.isEmpty ? null : buttons,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al crear la plantilla: $e'),
            backgroundColor: AppColors.ctDanger,
          ),
        );
      }
    }
  }

  // ── build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(32),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 860,
          height: 620,
          child: ColoredBox(
            color: AppColors.ctSurface,
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 520, child: _buildForm()),
                      const VerticalDivider(
                          width: 1, thickness: 1, color: AppColors.ctBorder),
                      Expanded(child: _buildPreview()),
                    ],
                  ),
                ),
                _buildFooterBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── header bar ──────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: AppColors.ctNavy,
      child: Row(
        children: [
          Text(
            'Nueva plantilla',
            style: AppTextStyles.pageTitle.copyWith(color: Colors.white),
          ),
          const Spacer(),
          IconButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white70),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // ── form panel ──────────────────────────────────────────────────────────────

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1 ── Nombre
          _sectionLabel('Nombre de plantilla *'),
          const SizedBox(height: 6),
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              hintText: 'nombre_en_snake_case',
              hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
              errorText: _nameError,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            style: AppTextStyles.body,
            onChanged: (v) {
              final normalized = _normalizeTemplateName(v);
              if (normalized != v) {
                _nameCtrl.value = _nameCtrl.value.copyWith(
                  text: normalized,
                  selection: TextSelection.collapsed(offset: normalized.length),
                );
              }
              if (_nameError != null) {
                setState(() => _nameError = null);
              } else {
                setState(() {});
              }
            },
          ),
          const SizedBox(height: 4),
          Text(
            'Solo min\u00FAsculas, n\u00FAmeros y _. Los espacios se convierten autom\u00E1ticamente.',
            style: AppTextStyles.caption.copyWith(color: AppColors.ctText3),
          ),
          const SizedBox(height: 12),

          // 2 ── Categoría + Idioma (row)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel('Categoría *'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _category,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        isDense: true,
                      ),
                      style: AppTextStyles.body,
                      items: _categories
                          .map((c) => DropdownMenuItem(
                              value: c.value, child: Text(c.label)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _category = v);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel('Idioma *'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _language,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        isDense: true,
                      ),
                      style: AppTextStyles.body,
                      items: _languages
                          .map((l) => DropdownMenuItem(
                              value: l.value, child: Text(l.label)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _language = v);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 3 ── Encabezado (opcional)
          _sectionLabel('Encabezado · Opcional'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _HeaderType.values
                .map((t) => _HeaderChip(
                      label: _headerTypeLabel(t),
                      selected: _headerType == t,
                      onTap: () => setState(() {
                        _headerType = t;
                        _headerTextCtrl.clear();
                        _headerUrlCtrl.clear();
                      }),
                    ))
                .toList(),
          ),
          if (_headerType == _HeaderType.text) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _headerTextCtrl,
              maxLength: 60,
              decoration: InputDecoration(
                hintText: 'Texto del encabezado',
                hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
              style: AppTextStyles.body,
            ),
          ] else if (_headerType != _HeaderType.none) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _headerUrlCtrl,
              decoration: InputDecoration(
                hintText: 'URL de ejemplo (requerido por Meta)',
                hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
              style: AppTextStyles.body,
            ),
          ],
          const SizedBox(height: 16),

          // 4 ── Mensaje (body)
          _sectionLabel('Mensaje *'),
          const SizedBox(height: 6),
          TextField(
            controller: _bodyCtrl,
            focusNode: _bodyFocus,
            minLines: 4,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: 'Escribe el cuerpo del mensaje…',
              hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.all(12),
            ),
            style: AppTextStyles.body,
          ),
          const SizedBox(height: 6),
          AppButton(
            label: '+ Agregar variable',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            prefixIcon: const Icon(Icons.add_circle_outline_rounded, size: 14, color: AppColors.ctTeal),
            onPressed: _insertVariable,
          ),
          // 4b ── Ejemplos de variables (condicional)
          _buildVarExamples(),
          const SizedBox(height: 16),

          // 5 ── Pie de página (opcional)
          _sectionLabel('Pie de página · Opcional'),
          const SizedBox(height: 6),
          TextField(
            controller: _footerCtrl,
            maxLength: 60,
            decoration: InputDecoration(
              hintText: 'Texto del pie de página',
              hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            style: AppTextStyles.body,
          ),

          // 6 ── Botones QUICK_REPLY (opcional, máx 3)
          const SizedBox(height: 16),
          Row(
            children: [
              _sectionLabel('Botones · Opcional'),
              const Spacer(),
              if (_buttonCtrls.length < 3)
                AppButton(
                  label: '+ Agregar botón',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                  prefixIcon: const Icon(Icons.add_circle_outline_rounded, size: 14, color: AppColors.ctTeal),
                  onPressed: () {
                    setState(() {
                      _buttonCtrls.add(TextEditingController());
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < _buttonCtrls.length; i++) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _buttonCtrls[i],
                    maxLength: 25,
                    decoration: InputDecoration(
                      hintText: 'Texto del botón ${i + 1}',
                      hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      isDense: true,
                      counterText: '',
                    ),
                    style: AppTextStyles.body,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _buttonCtrls.removeAt(i).dispose();
                    });
                  },
                  icon: const Icon(Icons.remove_circle_outline_rounded,
                      size: 18, color: AppColors.ctDanger),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  // ── preview panel ────────────────────────────────────────────────────────────

  Widget _buildPreview() {
    final headerTxt   = _headerType == _HeaderType.text ? _headerTextCtrl.text : null;
    final headerMedia = _headerType != _HeaderType.none && _headerType != _HeaderType.text;
    final body        = _bodyCtrl.text;
    final footer      = _footerCtrl.text;
    final now         = TimeOfDay.now();
    final time = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    return Container(
      color: const Color(0xFFEBEBE9),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vista previa',
            style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Align(
              alignment: Alignment.topRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.waBubbleAi,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(2),
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header media placeholder
                      if (headerMedia)
                        Container(
                          height: 90,
                          decoration: BoxDecoration(
                            color: AppColors.ctSurface2,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(12),
                              topRight: Radius.circular(2),
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              _headerTypeIcon(_headerType),
                              size: 28,
                              color: AppColors.ctText3,
                            ),
                          ),
                        ),
                      // Header text
                      if (headerTxt != null && headerTxt.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                          child: Text(
                            headerTxt,
                            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      // Body
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                            12,
                            (headerTxt != null && headerTxt.isNotEmpty) ||
                                    headerMedia
                                ? 6
                                : 10,
                            12,
                            0),
                        child: Text(
                          body.isEmpty ? 'El mensaje aparecerá aquí…' : body,
                          style: AppTextStyles.body.copyWith(
                            color: body.isEmpty ? AppColors.ctText3 : AppColors.ctText,
                          ),
                        ),
                      ),
                      // Footer
                      if (footer.isNotEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(12, 4, 12, 0),
                          child: Text(
                            footer,
                            style: AppTextStyles.bodySmall,
                          ),
                        ),
                      // Buttons preview
                      if (_buttonCtrls.any((c) => c.text.trim().isNotEmpty)) ...[
                        const Divider(height: 1, color: AppColors.ctBorder),
                        for (final ctrl in _buttonCtrls
                            .where((c) => c.text.trim().isNotEmpty))
                          InkWell(
                            onTap: null,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
                              child: Center(
                                child: Text(
                                  ctrl.text.trim(),
                                  style: const TextStyle(
                                    fontFamily: 'Geist',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0093FF),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                      // Timestamp row
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              time,
                              style: AppTextStyles.caption.copyWith(color: AppColors.ctText2),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.done_all_rounded,
                                size: 13, color: AppColors.ctTeal),
                          ],
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
  }

  // ── footer action bar ────────────────────────────────────────────────────────

  Widget _buildFooterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.ctBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: 'Cancelar',
            variant: AppButtonVariant.outline,
            size: AppButtonSize.sm,
            isDisabled: _submitting,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          const SizedBox(width: 10),
          AppButton(
            label: 'Enviar a revisión',
            variant: AppButtonVariant.teal,
            size: AppButtonSize.sm,
            isLoading: _submitting,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }

  // ── utility ──────────────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Text(
        text,
        style: AppTextStyles.bodySmall.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
      );

  String _headerTypeLabel(_HeaderType t) {
    switch (t) {
      case _HeaderType.none:  return 'Ninguno';
      case _HeaderType.text:  return 'Texto';
      case _HeaderType.image: return 'Imagen';
      case _HeaderType.video: return 'Video';
      case _HeaderType.file:  return 'Archivo';
    }
  }

  IconData _headerTypeIcon(_HeaderType t) {
    switch (t) {
      case _HeaderType.image: return Icons.image_outlined;
      case _HeaderType.video: return Icons.videocam_outlined;
      case _HeaderType.file:  return Icons.attach_file_rounded;
      default:                return Icons.image_outlined;
    }
  }
}

// ── Chip de tipo de encabezado ─────────────────────────────────────────────────

class _HeaderChip extends StatefulWidget {
  const _HeaderChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_HeaderChip> createState() => _HeaderChipState();
}

class _HeaderChipState extends State<_HeaderChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.ctTeal
                : (_hovered ? AppColors.ctSurface2 : AppColors.ctSurface),
            border: Border.all(
              color: widget.selected ? AppColors.ctTeal : AppColors.ctBorder,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            widget.label,
            style: AppTextStyles.bodySmall.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: widget.selected ? Colors.white : AppColors.ctText2,
            ),
          ),
        ),
      ),
    );
  }
}
