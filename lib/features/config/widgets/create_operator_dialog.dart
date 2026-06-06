import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error.dart';
import '../../../core/api/channels_api.dart';
import '../../../core/api/iam_api.dart';
import '../../../core/api/operator_roles_api.dart';
import '../../../core/api/operators_api.dart';
import '../../../core/providers/tenant_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_format.dart';
import '../../../shared/widgets/app_alert_banner.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_dropdown.dart';
import '../../../shared/widgets/app_multi_select.dart';
import 'phone_field_widget.dart';

// ── CreateOperatorDialog ──────────────────────────────────────────────────────

class CreateOperatorDialog extends ConsumerStatefulWidget {
  const CreateOperatorDialog({super.key, required this.onSaved});
  final VoidCallback onSaved;

  @override
  ConsumerState<CreateOperatorDialog> createState() =>
      _CreateOperatorDialogState();
}

class _CreateOperatorDialogState extends ConsumerState<CreateOperatorDialog> {
  // ── Fields ────────────────────────────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  final String _phoneCountryIso = 'MX';
  String _phoneE164 = '';
  List<String> _selectedRoleIds = [];

  // ── Roles ─────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _availableRoles = [];
  bool _rolesLoading = false;

  // ── Channel types ─────────────────────────────────────────────────────────
  List<String> _channelTypes = [];
  bool _channelTypesLoading = false;

  // ── Channel types ──────────────────────────────────────────────────────────

  Future<void> _loadChannelTypes() async {
    setState(() => _channelTypesLoading = true);
    try {
      final channels = await ChannelsApi.listChannels();
      final types = channels
          .map((ch) => ch['channel_type'] as String? ?? '')
          .where((t) => t.isNotEmpty)
          .toSet()
          .toList();
      // Default order: whatsapp first, then alphabetical
      types.sort((a, b) {
        if (a == 'whatsapp') return -1;
        if (b == 'whatsapp') return 1;
        return a.compareTo(b);
      });
      if (mounted) {
        setState(() {
          _channelTypes = types;
          _channelTypesLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _channelTypesLoading = false);
    }
  }

  void _reorderChannelType(int from, int delta) {
    final to = from + delta;
    if (to < 0 || to >= _channelTypes.length) return;
    setState(() {
      final item = _channelTypes.removeAt(from);
      _channelTypes.insert(to, item);
    });
  }

  // ── Phone lookup ──────────────────────────────────────────────────────────
  Timer? _lookupDebounce;
  Map<String, dynamic>? _lookupResult;
  bool _lookupLoading = false;
  String _lastLookedUpPhone = '';

  // ── Tenant-user link ──────────────────────────────────────────────────────
  bool _linkToUser = false;
  String? _linkTenantUserId;
  List<Map<String, dynamic>> _unlinkTenantUsers = [];
  bool _tenantUsersLoading = false;
  bool _manualLinkMode = false;

  // ── Conflict resolution ──────────────────────────────────────────────────
  bool _sdConflictResolved = false;

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _saving = false;
  String? _errorMsg;
  Map<String, String> _fieldErrors = {};

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_clearNameError);
    _loadRoles();
    _loadChannelTypes();
    _loadTenantUsers();
  }

  void _clearNameError() {
    if (_fieldErrors.containsKey('name') && _nameCtrl.text.trim().isNotEmpty) {
      setState(() => _fieldErrors.remove('name'));
    }
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_clearNameError);
    _nameCtrl.dispose();
    _lookupDebounce?.cancel();
    super.dispose();
  }

  // ── Roles ─────────────────────────────────────────────────────────────────

  Future<void> _loadRoles() async {
    setState(() => _rolesLoading = true);
    try {
      final tenantId = ref.read(activeTenantIdProvider);
      final roles = await OperatorRolesApi.listRoles(tenantId: tenantId);
      if (mounted) {
        setState(() {
          _availableRoles = roles;
          _rolesLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _rolesLoading = false);
    }
  }

  // ── Tenant users (for manual link dropdown) ───────────────────────────────

  Future<void> _loadTenantUsers() async {
    setState(() => _tenantUsersLoading = true);
    try {
      final users = await IamApi.getUsers();
      if (mounted) {
        setState(() {
          _unlinkTenantUsers = users
              .where((u) => u['operator_id'] == null)
              .toList();
          _tenantUsersLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _tenantUsersLoading = false);
    }
  }

  void _onManualUserSelected(String? userId) {
    if (userId == null) {
      setState(() {
        _linkTenantUserId = null;
        _linkToUser = false;
        _manualLinkMode = false;
      });
      return;
    }
    final user = _unlinkTenantUsers.firstWhere(
      (u) => u['id'] == userId,
      orElse: () => {},
    );
    if (user.isEmpty) return;

    final userPhone = user['telefono'] as String?;
    setState(() {
      _linkTenantUserId = userId;
      _linkToUser = true;
      if (userPhone != null && userPhone.isNotEmpty) {
        _phoneE164 = userPhone;
      }
    });
  }

  // ── Phone lookup ──────────────────────────────────────────────────────────

  void _onPhoneChanged(String e164) {
    setState(() {
      _phoneE164 = e164;
      _fieldErrors.remove('phone');
    });
    _lookupDebounce?.cancel();

    // Reset lookup state when phone changes
    if (e164 != _lastLookedUpPhone) {
      setState(() {
        _lookupResult = null;
        _linkToUser = false;
        _linkTenantUserId = null;
        _manualLinkMode = false;
        _sdConflictResolved = false;
      });
    }

    // Validate: need at least country code + 7 digits
    final digits = e164.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return;

    _lookupDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted && e164 == _phoneE164) _doLookup(e164);
    });
  }

  Future<void> _doLookup(String phone) async {
    if (phone == _lastLookedUpPhone && _lookupResult != null) return;
    setState(() => _lookupLoading = true);
    try {
      final result = await OperatorsApi.lookupByPhone(phone: phone);
      if (mounted && phone == _phoneE164) {
        setState(() {
          _lookupResult = result;
          _lastLookedUpPhone = phone;
          _lookupLoading = false;

          final match = result['match'] as String?;

          // Auto-link if tenant_user match (D-10: obligatorio)
          if (match == 'tenant_user') {
            final tu = result['tenant_user'] as Map<String, dynamic>? ?? {};
            _linkTenantUserId = tu['id'] as String?;
            _linkToUser = true;
            // D-13: autofill name only if empty
            final nombre = tu['nombre'] as String?;
            if (nombre != null &&
                nombre.isNotEmpty &&
                _nameCtrl.text.trim().isEmpty) {
              _nameCtrl.text = nombre;
            }
          }

          // SD: show modal immediately instead of inline banner
          if (match == 'operator_deleted') {
            final op = result['operator'] as Map<String, dynamic>? ?? {};
            final tu = result['tenant_user'] as Map<String, dynamic>?;
            // Schedule after setState completes
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showSoftDeleteModal(op, tenantUser: tu);
            });
          }
        });
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final status = e.response?.statusCode;
      if (status == 422) {
        // Phone format invalid per backend — show inline error
        setState(() {
          _lookupLoading = false;
          _fieldErrors['phone'] =
              'Número con formato inválido. Usá formato internacional (ej: +5215555111111).';
        });
      } else {
        setState(() => _lookupLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _lookupLoading = false);
    }
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save({bool createDespiteSoftDeleted = false}) async {
    final name = _nameCtrl.text.trim();
    setState(() {
      _fieldErrors = {};
      _errorMsg = null;
    });

    // Client validation
    if (name.isEmpty) {
      _fieldErrors['name'] = 'Nombre obligatorio';
    }
    if (_phoneE164.isEmpty) {
      _fieldErrors['phone'] = 'Teléfono obligatorio';
    } else {
      final digits = _phoneE164.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 10) {
        _fieldErrors['phone'] =
            'Número con formato inválido. Usá formato internacional (ej: +5215555111111).';
      }
    }
    if (_selectedRoleIds.isEmpty) {
      _fieldErrors['roles'] = 'Selecciona al menos un rol';
    }
    if (_fieldErrors.isNotEmpty) {
      setState(() {});
      return;
    }

    // Block if lookup shows blocking state
    final match = _lookupResult?['match'] as String?;
    if (match == 'operator_active' || match == 'exists_no_permission') {
      return; // UI already shows the block message
    }

    // Block if no channel types configured
    if (_channelTypes.isEmpty && !_channelTypesLoading) {
      setState(() => _errorMsg = 'Este tenant no tiene canales configurados.');
      return;
    }

    setState(() => _saving = true);

    try {
      final effectiveLinkId = _linkToUser && (_linkTenantUserId ?? '').isNotEmpty
          ? _linkTenantUserId
          : null;
      await OperatorsApi.createOperatorV2(
        displayName: name,
        phone: _phoneE164,
        roleIds: _selectedRoleIds,
        linkToTenantUserId: effectiveLinkId,
        preferredChannelTypes: _channelTypes,
        createDespiteSoftDeleted: createDespiteSoftDeleted,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Operador creado.', style: AppTextStyles.body),
            backgroundColor: AppColors.ctNavy,
          ),
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final apiErr = ApiError.from(e);
      if (apiErr != null) {
        _handleApiError(apiErr);
      } else {
        // Fallback: try to read detail/message from unstructured error body
        final data = e.response?.data;
        String msg = 'Error al crear el operador. Intenta de nuevo.';
        if (data is Map) {
          final detail = data['detail'] ?? data['message'];
          if (detail is String && detail.isNotEmpty) {
            msg = detail;
          } else if (detail is Map && detail['message'] is String) {
            msg = detail['message'] as String;
          } else if (detail is List) {
            // FastAPI 422 validation: [{"loc": ["body","role_ids"], ...}]
            for (final err in detail) {
              if (err is Map) {
                final loc = err['loc'] as List?;
                if (loc != null && loc.contains('role_ids')) {
                  setState(() {
                    _saving = false;
                    _fieldErrors['roles'] = 'Selecciona al menos un rol';
                  });
                  return;
                }
              }
            }
          }
        }
        setState(() {
          _saving = false;
          _errorMsg = msg;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorMsg = 'Error inesperado. Intenta de nuevo.';
        });
      }
    }
  }

  void _handleApiError(ApiError err) {
    switch (err.errorCode) {
      case 'OPERATOR_PHONE_IN_USE':
        final op = err.meta['operator'] as Map<String, dynamic>? ?? {};
        final opName = op['name'] as String? ?? 'otro operador';
        setState(() {
          _saving = false;
          _errorMsg = 'Este número ya pertenece al operador $opName.';
        });

      case 'OPERATOR_SOFT_DELETED_EXISTS':
        setState(() => _saving = false);
        final op = err.meta['operator'] as Map<String, dynamic>? ?? {};
        final tu = err.meta['tenant_user'] as Map<String, dynamic>?;
        _showSoftDeleteModal(op, tenantUser: tu);

      case 'PHONE_BELONGS_TO_USER':
        setState(() {
          _saving = false;
          _errorMsg =
              'Este teléfono pertenece a un usuario del dashboard. Usa el lookup de teléfono para vincular.';
        });

      case 'TENANT_USER_ALREADY_LINKED':
        setState(() {
          _saving = false;
          _errorMsg = 'Este usuario ya está vinculado a otro operador.';
        });

      case 'PHONE_MISMATCH_WITH_USER':
        setState(() {
          _saving = false;
          _errorMsg =
              'El teléfono no coincide con el del usuario. Verificá el número.';
        });

      default:
        setState(() {
          _saving = false;
          _errorMsg = err.message.isNotEmpty
              ? err.message
              : 'Error al crear el operador.';
        });
    }
  }

  // ── Soft-delete modal (D-6) ───────────────────────────────────────────────

  Future<void> _showSoftDeleteModal(
    Map<String, dynamic> op, {
    Map<String, dynamic>? tenantUser,
  }) async {
    final opName = op['name'] as String? ?? 'operador';
    final opId = op['id'] as String? ?? '';
    final deletedAt = op['deleted_at'] as String?;
    final deletedLabel = deletedAt != null
        ? fmtDateOnly(deletedAt)
        : 'fecha desconocida';
    final tuId = tenantUser?['id'] as String?;
    final tuName = tenantUser?['nombre'] as String?;
    final hasTu = tuId != null && tuId.isNotEmpty;

    final bannerTitle = hasTu
        ? 'Existe un operador borrado ($opName, eliminado el $deletedLabel); '
          'el número pertenece a $tuName (usuario del dashboard). '
          'Al restaurar o crear se vinculará a su cuenta.'
        : 'Existe un operador eliminado con este número: $opName (eliminado el $deletedLabel).';

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.ctSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.ctBorder),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Operador eliminado encontrado',
                  style: AppTextStyles.body
                      .copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                AppAlertBanner(
                  variant: AppAlertBannerVariant.warning,
                  title: bannerTitle,
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children: [
                    AppButton(
                      label: hasTu ? 'Crear nuevo' : 'Crear nuevo (no relacionado)',
                      variant: AppButtonVariant.ghost,
                      size: AppButtonSize.sm,
                      onPressed: () => Navigator.pop(ctx, 'create_new'),
                    ),
                    AppButton(
                      label: 'Restaurar $opName',
                      variant: AppButtonVariant.teal,
                      size: AppButtonSize.sm,
                      onPressed: () => Navigator.pop(ctx, 'restore'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!mounted) return;

    if (action == 'restore' && opId.isNotEmpty) {
      await _restoreOperator(opId, linkToTenantUserId: hasTu ? tuId : null);
    } else if (action == 'create_new') {
      if (hasTu) {
        _linkTenantUserId = tuId;
        _linkToUser = true;
      }
      setState(() => _sdConflictResolved = true);
      await _save(createDespiteSoftDeleted: true);
    }
  }

  Future<void> _restoreOperator(String id, {String? linkToTenantUserId}) async {
    setState(() => _saving = true);
    final effectiveLinkId = (linkToTenantUserId ?? '').isNotEmpty
        ? linkToTenantUserId
        : null;
    try {
      await OperatorsApi.restoreOperator(
        id: id,
        linkToTenantUserId: effectiveLinkId,
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Operador restaurado.', style: AppTextStyles.body),
            backgroundColor: AppColors.ctNavy,
          ),
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final apiErr = ApiError.from(e);
      setState(() {
        _saving = false;
        _errorMsg = apiErr?.message ?? 'Error al restaurar el operador.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorMsg = 'Error al restaurar. Intenta de nuevo.';
        });
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final match = _lookupResult?['match'] as String?;
    final isBlocked =
        match == 'operator_active' ||
        match == 'exists_no_permission' ||
        (match == 'operator_deleted' && !_sdConflictResolved) ||
        (!_channelTypesLoading && _channelTypes.isEmpty);

    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.ctBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Agregar operador',
                      style: AppTextStyles.body
                          .copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Icon(Icons.close_rounded,
                          size: 18, color: AppColors.ctText3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppColors.ctBorder),

            // ── Body ──────────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Error banner
                    if (_errorMsg != null) ...[
                      AppAlertBanner(
                        variant: AppAlertBannerVariant.danger,
                        title: _errorMsg!,
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Name ─────────────────────────────────────────────
                    _FieldLabel('Nombre completo *'),
                    const SizedBox(height: 6),
                    _FormInput(
                      controller: _nameCtrl,
                      placeholder: 'Ej: Roberto Medina',
                      errorText: _fieldErrors['name'],
                    ),
                    const SizedBox(height: 14),

                    // ── Phone ────────────────────────────────────────────
                    PhoneFieldWidget(
                      label: 'Número de WhatsApp *',
                      initialCountryIso: _phoneCountryIso,
                      errorText: _fieldErrors['phone'],
                      onChanged: _onPhoneChanged,
                    ),
                    const SizedBox(height: 4),

                    // ── Lookup status ────────────────────────────────────
                    if (_lookupLoading)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.ctTeal),
                            ),
                            const SizedBox(width: 8),
                            Text('Verificando número...',
                                style: AppTextStyles.bodySmall
                                    .copyWith(color: AppColors.ctText3)),
                          ],
                        ),
                      )
                    else
                      _buildLookupBanner(),

                    // ── Manual link dropdown ─────────────────────────────
                    _buildLinkSection(),

                    const SizedBox(height: 10),

                    // ── Roles (multi-select) ─────────────────────────────
                    _FieldLabel('Roles *'),
                    const SizedBox(height: 6),
                    if (_rolesLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.ctTeal),
                          ),
                        ),
                      )
                    else
                      AppMultiSelect<String>(
                        items: _availableRoles
                            .map((r) => AppMultiSelectItem(
                                  value: r['id'] as String? ?? '',
                                  label: r['label'] as String? ?? '—',
                                ))
                            .toList(),
                        selectedValues: _selectedRoleIds,
                        placeholder: 'Seleccionar roles...',
                        searchable: true,
                        onChanged: (vals) => setState(() {
                          _selectedRoleIds = vals;
                          _fieldErrors.remove('roles');
                        }),
                      ),
                    if (_fieldErrors.containsKey('roles')) ...[
                      const SizedBox(height: 4),
                      Text(
                        _fieldErrors['roles']!,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.ctDanger),
                      ),
                    ],

                    // ── Channel type priority ─────────────────────────
                    if (!_channelTypesLoading && _channelTypes.length > 1) ...[
                      const SizedBox(height: 6),
                      _FieldLabel('Canal preferido'),
                      const SizedBox(height: 6),
                      _ChannelTypeOrder(
                        types: _channelTypes,
                        onMove: _reorderChannelType,
                      ),
                    ] else if (!_channelTypesLoading && _channelTypes.length == 1) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.check_circle_outline,
                              size: 14, color: AppColors.ctOk),
                          const SizedBox(width: 6),
                          Text(
                            'Canal: ${_channelTypeLabel(_channelTypes.first)}',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.ctOkText),
                          ),
                        ],
                      ),
                    ] else if (_channelTypesLoading) ...[
                      const SizedBox(height: 6),
                      const SizedBox(
                        height: 24,
                        child: Center(
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.ctTeal),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // ── Footer ────────────────────────────────────────────────────
            const Divider(height: 1, color: AppColors.ctBorder),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancelar',
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.sm,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    label: 'Crear operador',
                    variant: AppButtonVariant.teal,
                    size: AppButtonSize.sm,
                    isLoading: _saving,
                    isDisabled: isBlocked,
                    onPressed: _saving || isBlocked ? () {} : _save,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Lookup banner builder ─────────────────────────────────────────────────

  // ── Link section builder ───────────────────────────────────────────────────

  Widget _buildLinkSection() {
    final match = _lookupResult?['match'] as String?;

    // Don't show link section if blocked states
    if (match == 'operator_active' ||
        match == 'exists_no_permission' ||
        match == 'operator_deleted') {
      return const SizedBox.shrink();
    }

    // If B1 auto-detected a tenant_user, show that info (already handled in banner)
    // but also allow switching to manual mode
    final hasAutoLink = match == 'tenant_user';

    // Show manual dropdown if: auto-link active OR user toggled manual mode
    if (!hasAutoLink && !_manualLinkMode) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: GestureDetector(
          onTap: () => setState(() => _manualLinkMode = true),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Row(
              children: [
                const Icon(Icons.link, size: 14, color: AppColors.ctTeal),
                const SizedBox(width: 6),
                Text(
                  'Vincular a usuario del dashboard',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.ctTeal),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Manual dropdown
    if (_manualLinkMode && !hasAutoLink) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _FieldLabel('Vincular a usuario'),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() {
                    _manualLinkMode = false;
                    _linkToUser = false;
                    _linkTenantUserId = null;
                  }),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text('Cancelar',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.ctText3)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_tenantUsersLoading)
              const SizedBox(
                height: 36,
                child: Center(
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.ctTeal),
                  ),
                ),
              )
            else
              AppDropdown<String>(
                value: _linkTenantUserId,
                hint: 'Seleccionar usuario...',
                items: _unlinkTenantUsers.map((u) {
                  final id = u['id'] as String? ?? '';
                  final nombre = u['nombre'] as String? ?? '—';
                  final tel = u['telefono'] as String? ?? '';
                  final label = tel.isNotEmpty
                      ? '$nombre ($tel)'
                      : nombre;
                  return AppDropdownItem(value: id, label: label);
                }).toList(),
                onChanged: _onManualUserSelected,
              ),
            if (_linkToUser && _linkTenantUserId != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      size: 14, color: AppColors.ctOk),
                  const SizedBox(width: 6),
                  Text('Se vinculará al crear',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.ctOkText)),
                ],
              ),
            ],
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // ── Lookup banner builder ─────────────────────────────────────────────────

  Widget _buildLookupBanner() {
    final result = _lookupResult;
    if (result == null) return const SizedBox.shrink();

    final match = result['match'] as String?;

    switch (match) {
      // B1: tenant_user match — vínculo obligatorio (D-10)
      case 'tenant_user':
        final tu = result['tenant_user'] as Map<String, dynamic>? ?? {};
        final nombre = tu['nombre'] as String? ?? 'usuario';
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppAlertBanner(
            variant: AppAlertBannerVariant.info,
            title:
                'Este número pertenece a $nombre (usuario del dashboard). El operador se vinculará a su cuenta.',
          ),
        );

      // B2: exists_no_permission
      case 'exists_no_permission':
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppAlertBanner(
            variant: AppAlertBannerVariant.danger,
            title:
                'Este número ya está registrado en el sistema. Contactá a un administrador.',
          ),
        );

      // C: operator_active
      case 'operator_active':
        final op = result['operator'] as Map<String, dynamic>? ?? {};
        final opName = op['name'] as String? ?? 'otro operador';
        final opId = op['id'] as String?;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppAlertBanner(
            variant: AppAlertBannerVariant.danger,
            title: 'Este número ya pertenece al operador $opName.',
            actions: [
              if (opId != null)
                AppButton(
                  label: 'Ir a $opName',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                  onPressed: () {
                    Navigator.pop(context);
                    // Navigate via go_router — caller's context
                  },
                ),
            ],
          ),
        );

      // SD: operator_deleted — handled via modal in _doLookup, not inline banner
      case 'operator_deleted':
        return const SizedBox.shrink();

      // none: no conflict
      case 'none':
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 14, color: AppColors.ctOk),
              const SizedBox(width: 6),
              Text('Número disponible',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.ctOkText)),
            ],
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }
}

// ── Private helpers ──────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppTextStyles.formLabel);
  }
}

class _FormInput extends StatelessWidget {
  const _FormInput({
    required this.controller,
    this.placeholder,
    this.errorText,
  });
  final TextEditingController controller;
  final String? placeholder;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          style: AppTextStyles.body,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.ctSurface2,
            hintText: placeholder,
            hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: errorText != null
                    ? AppColors.ctDanger
                    : AppColors.ctBorder,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: errorText != null
                    ? AppColors.ctDanger
                    : AppColors.ctBorder,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.ctTeal),
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 4),
          Text(errorText!,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctDanger)),
        ],
      ],
    );
  }
}

// ── Channel type helpers ─────────────────────────────────────────────────────

String _channelTypeLabel(String t) => switch (t) {
      'whatsapp' => 'WhatsApp',
      'telegram' => 'Telegram',
      'sms' => 'SMS',
      _ => t,
    };

Color _channelTypeColor(String t) => switch (t) {
      'whatsapp' => AppColors.ctWa,
      'telegram' => AppColors.ctTg,
      'sms' => AppColors.ctText2,
      _ => AppColors.ctText3,
    };

IconData _channelTypeIcon(String t) => switch (t) {
      'whatsapp' => Icons.chat_bubble_outline,
      'telegram' => Icons.telegram,
      'sms' => Icons.sms_outlined,
      _ => Icons.router_rounded,
    };

class _ChannelTypeOrder extends StatelessWidget {
  const _ChannelTypeOrder({
    required this.types,
    required this.onMove,
  });
  final List<String> types;
  final void Function(int from, int delta) onMove;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: types.asMap().entries.map((entry) {
        final i = entry.key;
        final type = entry.value;
        final color = _channelTypeColor(type);

        return Container(
          key: ValueKey(type),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.ctSurface,
            border: Border.all(color: AppColors.ctBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${i + 1}',
                  style: AppTextStyles.bodySmall
                      .copyWith(fontWeight: FontWeight.w700, color: color),
                ),
              ),
              const SizedBox(width: 10),
              Icon(_channelTypeIcon(type), size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _channelTypeLabel(type),
                  style: AppTextStyles.body
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              _OrderArrow(
                icon: Icons.keyboard_arrow_up_rounded,
                onPressed: i > 0 ? () => onMove(i, -1) : null,
              ),
              _OrderArrow(
                icon: Icons.keyboard_arrow_down_rounded,
                onPressed:
                    i < types.length - 1 ? () => onMove(i, 1) : null,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _OrderArrow extends StatelessWidget {
  const _OrderArrow({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          icon,
          size: 20,
          color: onPressed != null ? AppColors.ctText2 : AppColors.ctBorder,
        ),
      ),
    );
  }
}
