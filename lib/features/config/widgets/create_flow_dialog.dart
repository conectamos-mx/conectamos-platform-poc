import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/catalogs_api.dart';
import '../../../core/api/flows_api.dart';
import '../../../core/api/operator_roles_api.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/display_mappers.dart' as dm;
import '../../../shared/widgets/app_detail_row.dart';
import '../../../shared/widgets/app_dropdown.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/app_wizard_shell.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

const _kAccentMap = {
  '\u00E0': 'a', '\u00E1': 'a', '\u00E2': 'a', '\u00E3': 'a',
  '\u00E4': 'a', '\u00E5': 'a', '\u00E6': 'ae', '\u00E7': 'c',
  '\u00E8': 'e', '\u00E9': 'e', '\u00EA': 'e', '\u00EB': 'e',
  '\u00EC': 'i', '\u00ED': 'i', '\u00EE': 'i', '\u00EF': 'i',
  '\u00F0': 'd', '\u00F1': 'n',
  '\u00F2': 'o', '\u00F3': 'o', '\u00F4': 'o', '\u00F5': 'o',
  '\u00F6': 'o', '\u00F8': 'o',
  '\u00F9': 'u', '\u00FA': 'u', '\u00FB': 'u', '\u00FC': 'u',
  '\u00FD': 'y', '\u00FF': 'y', '\u00FE': 'th', '\u00DF': 'ss',
};

String _slugify(String input) {
  final lower = input.toLowerCase();
  final buf = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    buf.write(_kAccentMap[ch] ?? ch);
  }
  return buf
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

// ── CreateFlowDialog ─────────────────────────────────────────────────────────

class CreateFlowDialog extends ConsumerStatefulWidget {
  const CreateFlowDialog({
    super.key,
    required this.tenantId,
    required this.onCreated,
    this.workers = const [],
    this.fixedWorkerId,
  }) : assert(
         workers.length > 0 || fixedWorkerId != null,
         'Debe proveer workers o fixedWorkerId',
       );

  final String tenantId;
  final void Function(String flowId) onCreated;
  final List<Map<String, dynamic>> workers;
  final String? fixedWorkerId;

  @override
  ConsumerState<CreateFlowDialog> createState() => _CreateFlowDialogState();
}

class _CreateFlowDialogState extends ConsumerState<CreateFlowDialog> {
  // Step 1 — Identidad
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _selectedWorkerId;
  String? _slugError;

  // Step 2 — Acceso
  List<Map<String, dynamic>> _availableRoles = [];
  final List<String> _selectedRoleIds = [];
  final List<String> _selectedTriggers = [];
  bool _loadingRoles = false;

  // Flow type (query vs capture)
  bool _isQuery = false;
  List<Map<String, dynamic>> _catalogs = [];
  String? _selectedCatalogSlug;
  bool _loadingCatalogs = false;

  static const _triggerOptions = [
    ('conversational', 'Conversacional', 'El operador inicia el flujo por chat'),
    ('ingest',         'API / Ingesta',  'Se activa por carga de datos externa'),
    ('scheduled',      'Programado',     'Se ejecuta en horario autom\u00E1tico'),
    ('on_complete',    'Al completar otro flujo', 'Se abre como acci\u00F3n de cierre'),
  ];

  String get _slug => _slugify(_nameCtrl.text.trim());
  bool get _slugValid => _slug.length >= 3;

  bool get _showWorkerSelector => widget.workers.length > 1;

  bool get _canAdvance {
    if (_nameCtrl.text.trim().isEmpty || !_slugValid || _selectedWorkerId == null) return false;
    if (_isQuery && _selectedCatalogSlug == null) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    // R1: fixedWorkerId takes priority; then single-element list; then first of list
    if (widget.fixedWorkerId != null) {
      _selectedWorkerId = widget.fixedWorkerId;
    } else if (widget.workers.length == 1) {
      _selectedWorkerId = widget.workers.first['id'] as String?;
    } else if (widget.workers.isNotEmpty) {
      _selectedWorkerId = widget.workers.first['id'] as String?;
    }
    _nameCtrl.addListener(_onNameChanged);
    _loadRoles();
  }

  void _onNameChanged() {
    if (_slugError != null) {
      setState(() => _slugError = null);
    } else {
      setState(() {});
    }
  }

  Future<void> _loadRoles() async {
    setState(() => _loadingRoles = true);
    try {
      final roles = await OperatorRolesApi.listRoles(
        dio: ref.read(apiClientProvider).dio,
        tenantId: widget.tenantId,
      );
      if (mounted) {
        setState(() => _availableRoles = List<Map<String, dynamic>>.from(roles));
      }
    } catch (_) {}
    finally {
      if (mounted) setState(() => _loadingRoles = false);
    }
  }

  Future<void> _loadCatalogs() async {
    setState(() => _loadingCatalogs = true);
    try {
      final catalogs = await CatalogsApi.listCatalogs(
        dio: ref.read(apiClientProvider).dio,
        tenantId: widget.tenantId,
      );
      if (mounted) {
        setState(() => _catalogs = List<Map<String, dynamic>>.from(catalogs));
      }
    } catch (_) {}
    finally {
      if (mounted) setState(() => _loadingCatalogs = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_onNameChanged);
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String _workerName(String? id) {
    if (id == null) return '\u2014';
    final w = widget.workers.where((w) => w['id'] == id).firstOrNull;
    return w?['display_name'] as String? ?? w?['catalog_name'] as String? ?? '\u2014';
  }

  String _catalogName(String? slug) {
    if (slug == null) return '\u2014';
    return _catalogs
        .where((c) => c['slug'] == slug)
        .map((c) => c['name'] as String? ?? slug)
        .firstOrNull ?? slug;
  }

  // R2: return on 409, no rethrow
  Future<void> _submit() async {
    if (_selectedWorkerId == null) return;
    try {
      final result = await FlowsApi.createFlow(
        dio: ref.read(apiClientProvider).dio,
        tenantWorkerId: _selectedWorkerId!,
        name: _nameCtrl.text.trim(),
        slug: _slug,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        allowedRoleIds: _selectedRoleIds.isEmpty ? null : _selectedRoleIds,
        triggerSources: _selectedTriggers.isEmpty ? null : _selectedTriggers,
        behavior: _isQuery
            ? {
                'query_config': {
                  'catalog_slug': _selectedCatalogSlug,
                  'metrics': <Map<String, dynamic>>[],
                  'filter_fields': <String>[],
                  'group_by_fields': <String>[],
                },
              }
            : const {},
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onCreated(result['id'] as String);
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 409) {
        setState(() => _slugError = 'Ya existe un flujo con este nombre');
        return;
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppWizardShell(
      sidebarTitle: 'Nuevo flujo',
      confirmLabel: 'Crear flujo',
      canAdvance: _canAdvance,
      onCancel: () => Navigator.of(context).pop(),
      onConfirm: _submit,
      steps: [
        AppWizardStep(title: 'Identidad', builder: (_) => _buildStep1()),
        AppWizardStep(title: 'Acceso', builder: (_) => _buildStep2()),
        AppWizardStep(title: 'Confirmar', builder: (_) => _buildStep3()),
      ],
    );
  }

  // ── Step builders ──────────────────────────────────────────────────────────

  Widget _buildTypeTile({
    required String label,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.ctTeal.withValues(alpha: 0.08)
                : AppColors.ctSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.ctTeal : AppColors.ctBorder,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18,
                  color: selected ? AppColors.ctTeal : AppColors.ctText2),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: AppTextStyles.body.copyWith(
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        )),
                    Text(subtitle,
                        style: AppTextStyles.bodySmall
                            .copyWith(fontSize: 11, color: AppColors.ctText3)),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_rounded, size: 16, color: AppColors.ctTeal),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tipo de flujo',
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _buildTypeTile(
                label: 'Captura',
                subtitle: 'Recolecta datos en campo',
                icon: Icons.edit_note_outlined,
                selected: !_isQuery,
                onTap: () => setState(() {
                  _isQuery = false;
                  _selectedCatalogSlug = null;
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildTypeTile(
                label: 'Consulta',
                subtitle: 'Consulta datos de cat\u00E1logos',
                icon: Icons.search_outlined,
                selected: _isQuery,
                onTap: () {
                  setState(() => _isQuery = true);
                  if (_catalogs.isEmpty && !_loadingCatalogs) _loadCatalogs();
                },
              ),
            ),
          ],
        ),
        if (_isQuery) ...[
          const SizedBox(height: 16),
          AppDropdown<String>(
            label: 'Cat\u00E1logo a consultar',
            items: _catalogs
                .map((c) => AppDropdownItem<String>(
                      value: c['slug'] as String? ?? '',
                      label: c['name'] as String? ?? c['slug'] as String? ?? '',
                    ))
                .toList(),
            value: _selectedCatalogSlug,
            hint: _loadingCatalogs
                ? 'Cargando cat\u00E1logos...'
                : 'Selecciona un cat\u00E1logo',
            enabled: !_loadingCatalogs,
            onChanged: (v) => setState(() => _selectedCatalogSlug = v),
          ),
        ],
        const SizedBox(height: 16),
        AppTextField(
          controller: _nameCtrl,
          label: 'Nombre del flujo',
          hint: 'Ej: Entrega de paquete',
        ),
        if (_nameCtrl.text.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          _SlugIndicator(slug: _slug, error: _slugError),
        ],
        const SizedBox(height: 16),
        AppTextField(
          controller: _descCtrl,
          label: 'Descripci\u00F3n (opcional)',
          hint: 'Describe el prop\u00F3sito de este flujo...',
          maxLines: 3,
        ),
        // R1: worker selector only when >1 worker
        if (_showWorkerSelector) ...[
          const SizedBox(height: 16),
          Text('Worker',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          ...widget.workers.map((w) {
            final id = w['id'] as String? ?? '';
            final name = w['display_name'] as String? ??
                w['catalog_name'] as String? ?? '\u2014';
            final color = w['catalog_color'] as String?;
            final selected = _selectedWorkerId == id;
            return GestureDetector(
              onTap: () => setState(() => _selectedWorkerId = id),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.ctTeal.withValues(alpha: 0.08)
                        : AppColors.ctSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? AppColors.ctTeal : AppColors.ctBorder,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: dm.hexColor(color),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(name,
                            style: AppTextStyles.body.copyWith(
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                            )),
                      ),
                      if (selected)
                        const Icon(Icons.check_rounded,
                            size: 16, color: AppColors.ctTeal),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Roles con acceso',
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Selecciona qu\u00E9 roles pueden iniciar este flujo. Si no seleccionas ninguno, todos los roles tendr\u00E1n acceso.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2)),
        const SizedBox(height: 12),
        if (_loadingRoles)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ctTeal),
            )),
          )
        else if (_availableRoles.isEmpty)
          Text('No hay roles disponibles. Podr\u00E1s asignarlos despu\u00E9s.',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _availableRoles.map((role) {
              final id = role['id'] as String? ?? '';
              final name = role['label'] as String? ?? role['name'] as String? ?? id;
              final selected = _selectedRoleIds.contains(id);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (selected) {
                      _selectedRoleIds.remove(id);
                    } else {
                      _selectedRoleIds.add(id);
                    }
                  });
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.ctTeal.withValues(alpha: 0.1)
                          : AppColors.ctSurface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected ? AppColors.ctTeal : AppColors.ctBorder,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (selected) ...[
                          const Icon(Icons.check_rounded, size: 14, color: AppColors.ctTeal),
                          const SizedBox(width: 4),
                        ],
                        Text(name,
                            style: AppTextStyles.body.copyWith(
                              fontSize: 12,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                              color: selected ? AppColors.ctTealDark : AppColors.ctText2,
                            )),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        const SizedBox(height: 24),
        Text('Or\u00EDgenes de ejecuci\u00F3n',
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('\u00BFDesde d\u00F3nde puede iniciarse este flujo?',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2)),
        const SizedBox(height: 12),
        ..._triggerOptions.map((opt) {
          final selected = _selectedTriggers.contains(opt.$1);
          return GestureDetector(
            onTap: () {
              setState(() {
                if (selected) {
                  _selectedTriggers.remove(opt.$1);
                } else {
                  _selectedTriggers.add(opt.$1);
                }
              });
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.ctTeal.withValues(alpha: 0.06)
                      : AppColors.ctSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? AppColors.ctTeal : AppColors.ctBorder,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: selected ? AppColors.ctTeal : AppColors.ctBorder2,
                          width: selected ? 2 : 1.5,
                        ),
                        color: selected ? AppColors.ctTeal : Colors.transparent,
                      ),
                      child: selected
                          ? const Icon(Icons.check, size: 12, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(opt.$2, style: AppTextStyles.body.copyWith(
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
                          Text(opt.$3, style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.ctText3)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStep3() {
    final roleNames = _availableRoles
        .where((r) => _selectedRoleIds.contains(r['id'] as String))
        .map((r) => r['label'] as String? ?? r['name'] as String? ?? '')
        .join(', ');
    final triggerLabels = _triggerOptions
        .where((t) => _selectedTriggers.contains(t.$1))
        .map((t) => t.$2)
        .join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Revisa la configuraci\u00F3n antes de crear el flujo.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText2)),
        const SizedBox(height: 16),
        AppDetailRow(
          label: 'Tipo',
          value: Text(_isQuery ? 'Consulta' : 'Captura', style: AppTextStyles.body),
        ),
        const Divider(height: 1),
        if (_isQuery) ...[
          AppDetailRow(
            label: 'Cat\u00E1logo',
            value: Text(_catalogName(_selectedCatalogSlug), style: AppTextStyles.body),
          ),
          const Divider(height: 1),
        ],
        AppDetailRow(
          label: 'Nombre',
          value: Text(_nameCtrl.text.trim(), style: AppTextStyles.body),
        ),
        const Divider(height: 1),
        AppDetailRow(
          label: 'Slug',
          value: Text(_slug, style: AppTextStyles.body.copyWith(
              fontFamily: 'Geist', color: AppColors.ctText2)),
        ),
        const Divider(height: 1),
        if (_showWorkerSelector) ...[
          AppDetailRow(
            label: 'Worker',
            value: Text(_workerName(_selectedWorkerId), style: AppTextStyles.body),
          ),
          const Divider(height: 1),
        ],
        if (_descCtrl.text.trim().isNotEmpty) ...[
          AppDetailRow(
            label: 'Descripci\u00F3n',
            crossAxisAlignment: CrossAxisAlignment.start,
            value: Text(_descCtrl.text.trim(), style: AppTextStyles.bodySmall),
          ),
          const Divider(height: 1),
        ],
        AppDetailRow(
          label: 'Roles',
          value: Text(
            roleNames.isEmpty ? 'Todos los roles' : roleNames,
            style: AppTextStyles.body,
          ),
        ),
        const Divider(height: 1),
        AppDetailRow(
          label: 'Or\u00EDgenes',
          value: Text(
            triggerLabels.isEmpty ? 'Sin or\u00EDgenes seleccionados' : triggerLabels,
            style: AppTextStyles.body,
          ),
        ),
      ],
    );
  }
}

// ── _SlugIndicator ───────────────────────────────────────────────────────────

class _SlugIndicator extends StatelessWidget {
  const _SlugIndicator({required this.slug, this.error});
  final String slug;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Row(
        children: [
          const Icon(Icons.error_outline, size: 13, color: AppColors.ctDanger),
          const SizedBox(width: 4),
          Text(error!,
              style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 12, color: AppColors.ctDanger)),
        ],
      );
    }
    final valid = slug.length >= 3;
    return Row(
      children: [
        Icon(
          valid ? Icons.check_circle_outline : Icons.warning_amber_outlined,
          size: 13,
          color: valid ? AppColors.ctOk : AppColors.ctText3,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            valid ? slug : (slug.isEmpty ? 'Escribe un nombre' : 'Nombre muy corto'),
            style: AppTextStyles.bodySmall.copyWith(
                fontSize: 12,
                color: valid ? AppColors.ctOk : AppColors.ctText3),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
