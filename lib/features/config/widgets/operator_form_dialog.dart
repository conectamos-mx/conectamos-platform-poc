import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/api/operator_fields_api.dart';
import '../../../core/api/operator_roles_api.dart';
import '../../../core/api/operators_api.dart';
import '../../../core/theme/colors.dart';
import '../../../core/utils/identity_config.dart';
import '../../../core/utils/phone_normalizer.dart';
import 'nationality_identity_widget.dart';
import 'phone_field_widget.dart';
import 'phone_secondary_widget.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

bool _isTelegramExpired(String? expiresAt) {
  if (expiresAt == null) return false;
  try {
    return DateTime.now().toUtc()
        .isAfter(DateTime.parse(expiresAt).toUtc());
  } catch (_) {
    return false;
  }
}

String _formatTelegramExpiry(String iso) {
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.day}/${dt.month}/${dt.year} '
        '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return iso;
  }
}

Color _avatarColor(String name) {
  const palette = [
    AppColors.ctTeal,
    Color(0xFF818CF8),
    Color(0xFFFB923C),
    Color(0xFFF472B6),
    Color(0xFF34D399),
    Color(0xFF60A5FA),
  ];
  if (name.isEmpty) return palette[0];
  final hash = name.codeUnits.fold(0, (a, b) => a + b);
  return palette[hash % palette.length];
}

String _initials(String name) {
  final parts =
      name.trim().split(' ').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
}

// ── OperatorFormDialog ────────────────────────────────────────────────────────

class OperatorFormDialog extends ConsumerStatefulWidget {
  const OperatorFormDialog({
    super.key,
    this.operatorId,
    this.initialName,
    this.initialPhone,
    this.initialRoleIds,
    this.initialTelegramChatId,
    this.initialMetadata,
    this.initialEmail,
    this.initialNationality,
    this.initialIdentityNumber,
    this.initialProfilePictureUrl,
    this.initialCustomFields,
    required this.onSaved,
    this.onOperatorMetadataUpdated,
  });

  final String? operatorId;
  final String? initialName;
  final String? initialPhone;
  final List<String>? initialRoleIds;
  final String? initialTelegramChatId;
  final Map<String, dynamic>? initialMetadata;
  final String? initialEmail;
  final String? initialNationality;
  final String? initialIdentityNumber;
  final String? initialProfilePictureUrl;
  final List<Map<String, dynamic>>? initialCustomFields;
  final VoidCallback onSaved;
  final void Function(String id, Map<String, dynamic> metadata)?
      onOperatorMetadataUpdated;

  bool get isEdit => operatorId != null;

  @override
  ConsumerState<OperatorFormDialog> createState() =>
      _OperatorFormDialogState();
}

class _OperatorFormDialogState extends ConsumerState<OperatorFormDialog> {
  // ── Basic fields ──────────────────────────────────────────────────────────
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _telegramCtrl;

  // Phone (WhatsApp primary)
  String _phoneCountryIso = 'MX';
  String _phoneLocalNumber = '';
  String _phoneE164 = '';

  // Identification
  String _nationalityIso = '';
  String _identityNumber = '';

  // Secondary phones
  List<Map<String, dynamic>> _phoneSecondary = [];

  // Profile photo
  Uint8List? _profileBytes;
  String? _profilePictureUrl;
  bool _uploadingPhoto = false;

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _saving = false;
  String? _errorMsg;
  Map<String, String> _fieldErrors = {};
  bool _secondaryExpanded = false;

  // Telegram invite
  bool _sendingInvite = false;
  List<String> _inviteResults = [];

  // Telegram linking state
  String _telegramLinkStatus = 'none';
  String? _telegramLinkExpiresAt;
  String? _telegramChannelId;

  // Realtime subscription
  RealtimeChannel? _realtimeChannel;

  // Roles
  String? _selectedRoleId;
  List<Map<String, dynamic>> _availableRoles = [];
  bool _rolesLoading = false;

  // Custom fields
  List<Map<String, dynamic>> _customFieldDefs = [];
  Map<String, dynamic> _customFieldValues = {};
  Map<String, TextEditingController> _customFieldControllers = {};
  final Map<String, bool> _customFieldUploading = {};
  bool _customFieldsLoading = false;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
    // email: prefer dedicated param (top-level column), fall back to metadata
    _emailCtrl = TextEditingController(
      text: widget.initialEmail ??
          (widget.initialMetadata?['email'] as String?) ??
          '',
    );
    _telegramCtrl =
        TextEditingController(text: widget.initialTelegramChatId ?? '');
    _selectedRoleId = widget.initialRoleIds?.isNotEmpty == true
        ? widget.initialRoleIds!.first
        : null;

    // Parse initial phone
    final rawPhone = widget.initialPhone ?? '';
    if (rawPhone.isNotEmpty) {
      final (iso, local) = PhoneNormalizer.parsePhone(rawPhone);
      _phoneCountryIso = iso;
      _phoneLocalNumber = local;
      _phoneE164 = PhoneNormalizer.formatToE164(local, iso);
    }

    // Identity / nationality: prefer dedicated params (top-level columns),
    // fall back to metadata for backward compatibility.
    final meta = widget.initialMetadata ?? {};
    _telegramLinkStatus =
        (meta['telegram_link_status'] as String?) ?? 'none';
    _telegramLinkExpiresAt =
        meta['telegram_link_expires_at'] as String?;
    _nationalityIso = widget.initialNationality ??
        (meta['nationality'] as String? ?? '');
    _identityNumber = widget.initialIdentityNumber ??
        (meta['identity_number'] as String? ?? '');
    _profilePictureUrl = widget.initialProfilePictureUrl ??
        (meta['profile_picture_url'] as String?);
    _phoneSecondary = ((meta['phone_secondary'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRoles();
      _loadCustomFields();
    });

    // Realtime subscription — DO NOT MODIFY THIS BLOCK
    if (widget.isEdit && widget.operatorId != null) {
      try {
        _realtimeChannel = Supabase.instance.client
            .channel('op_${widget.operatorId}')
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'operators',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'id',
                value: widget.operatorId!,
              ),
              callback: _handleRealtimeUpdate,
            )
            .subscribe();
      } catch (e) {
        debugPrint('[Realtime] subscribe error: $e');
        _realtimeChannel = null;
      }
    }
  }

  // ── _handleRealtimeUpdate — DO NOT MODIFY ────────────────────────────────

  void _handleRealtimeUpdate(PostgresChangePayload payload) {
    if (!mounted) return;
    final row = payload.newRecord;
    final rawMeta = row['metadata'];
    Map<String, dynamic> meta;
    if (rawMeta is Map) {
      meta = Map<String, dynamic>.from(rawMeta);
    } else if (rawMeta is String) {
      try {
        meta = Map<String, dynamic>.from(json.decode(rawMeta) as Map);
      } catch (_) {
        meta = {};
      }
    } else {
      meta = {};
    }

    final newChatId = meta['telegram_chat_id'] as String?;
    final newStatus = (meta['telegram_link_status'] as String?) ?? 'none';
    final newExpiresAt = meta['telegram_link_expires_at'] as String?;

    setState(() {
      if (newChatId != null && newChatId.isNotEmpty) {
        _telegramCtrl.text = newChatId;
        _telegramLinkStatus = 'linked';
        _telegramLinkExpiresAt = null;
      } else {
        _telegramLinkStatus = newStatus;
        _telegramLinkExpiresAt = newExpiresAt;
      }
    });

    widget.onOperatorMetadataUpdated?.call(widget.operatorId!, meta);
  }

  // ── Roles ─────────────────────────────────────────────────────────────────

  Future<void> _loadRoles() async {
    if (!mounted) return;
    setState(() => _rolesLoading = true);
    try {
      final roles = await OperatorRolesApi.listRoles(tenantId: '');
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

  // ── Custom fields ─────────────────────────────────────────────────────────

  Future<void> _loadCustomFields() async {
    if (!mounted) return;
    setState(() => _customFieldsLoading = true);
    try {
      final defs = await OperatorFieldsApi.getOperatorFields();
      if (!mounted) return;

      // Build initial values from initialCustomFields list
      final initMap = <String, dynamic>{};
      if (widget.initialCustomFields != null) {
        for (final cf in widget.initialCustomFields!) {
          final key = cf['field_key'] as String? ?? '';
          if (key.isNotEmpty) initMap[key] = cf['value'];
        }
      }

      // Create controllers for text / number / date fields
      final controllers = <String, TextEditingController>{};
      for (final def in defs) {
        final key = def['field_key'] as String? ?? '';
        final type = def['field_type'] as String? ?? 'text';
        if (['text', 'number', 'date'].contains(type)) {
          String displayVal = '';
          final initVal = initMap[key];
          if (initVal != null) {
            if (type == 'date') {
              try {
                final parts = initVal.toString().split('-');
                if (parts.length == 3) {
                  displayVal =
                      '${parts[2].padLeft(2, '0')}/${parts[1].padLeft(2, '0')}/${parts[0]}';
                }
              } catch (_) {
                displayVal = initVal.toString();
              }
            } else {
              displayVal = initVal.toString();
            }
          }
          controllers[key] = TextEditingController(text: displayVal);
        }
      }

      setState(() {
        _customFieldDefs = defs;
        _customFieldValues = Map<String, dynamic>.from(initMap);
        _customFieldControllers = controllers;
        _customFieldsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _customFieldsLoading = false);
    }
  }

  List<String> _getFieldChoices(Map<String, dynamic> def) {
    final raw = def['options'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is Map) {
      final choices = raw['choices'];
      if (choices is List) return choices.map((e) => e.toString()).toList();
    }
    return [];
  }

  Future<void> _pickCustomFile(String fieldKey,
      {required bool isPhoto}) async {
    if (_customFieldUploading[fieldKey] == true) return;
    FilePickerResult? result;
    if (isPhoto) {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
        withData: true,
      );
    } else {
      result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
    }
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    if (bytes.lengthInBytes > 10 * 1024 * 1024) {
      if (mounted) {
        setState(() =>
            _fieldErrors['cf_$fieldKey'] = 'El archivo excede 10MB');
      }
      return;
    }

    setState(() {
      _customFieldUploading[fieldKey] = true;
      _fieldErrors.remove('cf_$fieldKey');
    });

    try {
      final folder = widget.operatorId ?? _generateUuid();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = file.extension ?? 'bin';
      final path = 'operators/$folder/fields/$fieldKey/$ts.$ext';
      final contentType = isPhoto
          ? (ext == 'png' ? 'image/png' : 'image/jpeg')
          : 'application/octet-stream';

      await Supabase.instance.client.storage
          .from('wa-media')
          .uploadBinary(path, bytes,
              fileOptions: FileOptions(contentType: contentType));

      final url = Supabase.instance.client.storage
          .from('wa-media')
          .getPublicUrl(path);

      if (mounted) {
        setState(() {
          _customFieldValues[fieldKey] = url;
          _customFieldUploading[fieldKey] = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _customFieldUploading[fieldKey] = false;
          _fieldErrors['cf_$fieldKey'] =
              'No se pudo subir el archivo. Intenta de nuevo.';
        });
      }
    }
  }

  Widget _buildCustomField(Map<String, dynamic> def) {
    final key = def['field_key'] as String? ?? '';
    final label = def['label'] as String? ?? key;
    final type = def['field_type'] as String? ?? 'text';
    final isRequired = def['required'] as bool? ?? false;
    final displayLabel = '$label${isRequired ? ' *' : ''}';
    final errorKey = 'cf_$key';

    Widget input;
    switch (type) {
      case 'boolean':
        final boolVal =
            _customFieldValues[key] == true ||
            _customFieldValues[key].toString() == 'true';
        input = Switch(
          value: boolVal,
          activeTrackColor: AppColors.ctTeal,
          activeThumbColor: AppColors.ctNavy,
          onChanged: (v) => setState(() => _customFieldValues[key] = v),
        );
      case 'select':
        final choices = _getFieldChoices(def);
        final current = _customFieldValues[key] as String?;
        input = DropdownButtonFormField<String>(
          initialValue: choices.contains(current) ? current : null,
          hint: const Text('Seleccionar',
              style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  color: AppColors.ctText3)),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.ctSurface2,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: _fieldErrors.containsKey(errorKey)
                    ? AppColors.ctDanger
                    : AppColors.ctBorder2,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: _fieldErrors.containsKey(errorKey)
                    ? AppColors.ctDanger
                    : AppColors.ctBorder2,
              ),
            ),
            errorText: _fieldErrors[errorKey],
            errorStyle:
                const TextStyle(fontFamily: 'Geist', fontSize: 11),
          ),
          items: choices
              .map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(c,
                        style: const TextStyle(
                            fontFamily: 'Geist',
                            fontSize: 13,
                            color: AppColors.ctText)),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _customFieldValues[key] = v),
          style: const TextStyle(
              fontFamily: 'Geist', fontSize: 13, color: AppColors.ctText),
          dropdownColor: AppColors.ctSurface,
        );
      case 'date':
        final ctrl = _customFieldControllers[key]!;
        input = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () async {
                DateTime? initial;
                try {
                  final parts = ctrl.text.split('/');
                  if (parts.length == 3) {
                    initial = DateTime(int.parse(parts[2]),
                        int.parse(parts[1]), int.parse(parts[0]));
                  }
                } catch (_) {}
                final picked = await showDatePicker(
                  context: context,
                  initialDate: initial ?? DateTime.now(),
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2100),
                );
                if (picked != null && mounted) {
                  setState(() {
                    ctrl.text =
                        '${picked.day.toString().padLeft(2, '0')}/'
                        '${picked.month.toString().padLeft(2, '0')}/'
                        '${picked.year}';
                  });
                }
              },
              child: AbsorbPointer(
                child: TextField(
                  controller: ctrl,
                  readOnly: true,
                  style: const TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 13,
                      color: AppColors.ctText),
                  decoration: InputDecoration(
                    hintText: 'dd/mm/aaaa',
                    hintStyle: const TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 13,
                        color: AppColors.ctText3),
                    filled: true,
                    fillColor: AppColors.ctSurface2,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: _fieldErrors.containsKey(errorKey)
                              ? AppColors.ctDanger
                              : AppColors.ctBorder2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: _fieldErrors.containsKey(errorKey)
                              ? AppColors.ctDanger
                              : AppColors.ctBorder2),
                    ),
                    suffixIcon: const Icon(
                        Icons.calendar_today_outlined,
                        size: 16,
                        color: AppColors.ctText2),
                  ),
                ),
              ),
            ),
            if (_fieldErrors.containsKey(errorKey)) ...[
              const SizedBox(height: 3),
              Text(_fieldErrors[errorKey]!,
                  style: const TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 11,
                      color: AppColors.ctDanger)),
            ],
          ],
        );
      case 'photo':
        final url = _customFieldValues[key] as String?;
        final uploading = _customFieldUploading[key] ?? false;
        input = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: uploading
                  ? null
                  : () => _pickCustomFile(key, isPhoto: true),
              child: MouseRegion(
                cursor: uploading
                    ? MouseCursor.defer
                    : SystemMouseCursors.click,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.ctSurface2,
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: AppColors.ctBorder2),
                  ),
                  child: uploading
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          ),
                        )
                      : (url != null && url.isNotEmpty)
                          ? ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(7),
                              child: Image.network(url,
                                  fit: BoxFit.cover),
                            )
                          : const Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 28,
                              color: AppColors.ctText3),
                ),
              ),
            ),
            if (_fieldErrors.containsKey(errorKey)) ...[
              const SizedBox(height: 4),
              Text(_fieldErrors[errorKey]!,
                  style: const TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 11,
                      color: AppColors.ctDanger)),
            ],
          ],
        );
      case 'document':
        final docUrl = _customFieldValues[key] as String?;
        final uploading = _customFieldUploading[key] ?? false;
        final hasDoc = docUrl != null && docUrl.isNotEmpty;
        input = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasDoc) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.ctSurface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.ctBorder2),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.insert_drive_file_outlined,
                        size: 14, color: AppColors.ctTeal),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text('Documento subido',
                          style: TextStyle(
                              fontFamily: 'Geist',
                              fontSize: 12,
                              color: AppColors.ctText2)),
                    ),
                    GestureDetector(
                      onTap: () => setState(
                          () => _customFieldValues[key] = null),
                      child: const Icon(Icons.close,
                          size: 14, color: AppColors.ctText3),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              height: 36,
              child: uploading
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: () =>
                          _pickCustomFile(key, isPhoto: false),
                      icon: const Icon(Icons.upload_file_outlined,
                          size: 16),
                      label: Text(
                          hasDoc
                              ? 'Cambiar documento'
                              : 'Subir documento',
                          style: const TextStyle(
                              fontFamily: 'Geist', fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ctText2,
                        side: const BorderSide(
                            color: AppColors.ctBorder2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
            ),
            if (_fieldErrors.containsKey(errorKey)) ...[
              const SizedBox(height: 4),
              Text(_fieldErrors[errorKey]!,
                  style: const TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 11,
                      color: AppColors.ctDanger)),
            ],
          ],
        );
      default:
        // 'text' and 'number'
        input = _FormField(
          controller: _customFieldControllers[key]!,
          placeholder: label,
          keyboardType:
              type == 'number' ? TextInputType.number : null,
          errorText: _fieldErrors[errorKey],
        );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(displayLabel),
          const SizedBox(height: 6),
          input,
        ],
      ),
    );
  }

  // ── Profile photo ─────────────────────────────────────────────────────────

  static String _generateUuid() {
    final rng = Random.secure();
    final b = List.generate(16, (_) => rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  Future<void> _pickProfilePhoto() async {
    if (_uploadingPhoto) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    // OP_E008: size > 2 MB
    if (bytes.lengthInBytes > 2 * 1024 * 1024) {
      if (mounted) {
        setState(() => _fieldErrors['profile_picture'] =
            'OP_E008: La imagen excede 2MB');
      }
      return;
    }

    // OP_E009: format check
    final ext = (file.extension ?? '').toLowerCase();
    if (ext != 'jpg' && ext != 'jpeg' && ext != 'png') {
      if (mounted) {
        setState(() => _fieldErrors['profile_picture'] =
            'OP_E009: Solo se aceptan JPG y PNG');
      }
      return;
    }

    // Show preview + start upload
    if (mounted) {
      setState(() {
        _profileBytes = bytes;
        _profilePictureUrl = null;
        _uploadingPhoto = true;
        _fieldErrors.remove('profile_picture');
      });
    }

    try {
      final folder =
          widget.operatorId ?? _generateUuid();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = 'operators/$folder/$ts.$ext';
      final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';

      await Supabase.instance.client.storage
          .from('wa-media')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType),
          );

      final url = Supabase.instance.client.storage
          .from('wa-media')
          .getPublicUrl(path);

      if (mounted) {
        setState(() {
          _profilePictureUrl = url;
          _uploadingPhoto = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _profileBytes = null;
          _profilePictureUrl = null;
          _uploadingPhoto = false;
          _fieldErrors['profile_picture'] =
              'OP_E015: No se pudo subir la imagen. Intenta de nuevo.';
        });
      }
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneE164.isNotEmpty ? _phoneE164 : _phoneLocalNumber;

    setState(() {
      _fieldErrors = {};
      _errorMsg = null;
    });

    // Required field validation
    bool hasErrors = false;
    if (name.isEmpty) {
      _fieldErrors['display_name'] = 'Nombre obligatorio';
      hasErrors = true;
    }
    if (phone.isEmpty) {
      _fieldErrors['phone'] = 'Teléfono obligatorio';
      hasErrors = true;
    }
    for (final def in _customFieldDefs) {
      final key = def['field_key'] as String? ?? '';
      final label = def['label'] as String? ?? key;
      final isRequired = def['required'] as bool? ?? false;
      final type = def['field_type'] as String? ?? 'text';
      if (!isRequired || type == 'boolean') continue;
      final dynamic val;
      if (['text', 'number', 'date'].contains(type)) {
        val = _customFieldControllers[key]?.text.trim();
      } else {
        val = _customFieldValues[key];
      }
      if (val == null || val.toString().isEmpty) {
        _fieldErrors['cf_$key'] = '$label es requerido';
        hasErrors = true;
      }
    }
    if (hasErrors) {
      setState(() {});
      return;
    }

    setState(() => _saving = true);

    try {
      final roleIds = _selectedRoleId != null ? [_selectedRoleId!] : <String>[];
      final tgId = _telegramCtrl.text.trim();
      final metadata = <String, dynamic>{};
      if (_phoneSecondary.isNotEmpty) {
        metadata['phone_secondary'] = _phoneSecondary;
      }

      final bothPresent =
          _nationalityIso.isNotEmpty && _identityNumber.isNotEmpty;
      final identityType = bothPresent
          ? (getIdentityConfig(_nationalityIso)?.type ?? 'other')
          : null;
      final identityNumber = bothPresent ? _identityNumber : null;

      // Collect custom field values
      final customFieldValues = <String, dynamic>{};
      for (final def in _customFieldDefs) {
        final key = def['field_key'] as String? ?? '';
        final type = def['field_type'] as String? ?? 'text';
        dynamic val;
        if (type == 'date') {
          final text =
              _customFieldControllers[key]?.text.trim() ?? '';
          if (text.isNotEmpty) {
            try {
              final parts = text.split('/');
              if (parts.length == 3) {
                val = '${parts[2]}-'
                    '${parts[1].padLeft(2, '0')}-'
                    '${parts[0].padLeft(2, '0')}';
              }
            } catch (_) {}
          }
        } else if (type == 'text' || type == 'number') {
          final text =
              _customFieldControllers[key]?.text.trim() ?? '';
          if (text.isNotEmpty) val = text;
        } else {
          val = _customFieldValues[key];
        }
        if (val != null) customFieldValues[key] = val;
      }

      if (widget.isEdit) {
        await OperatorsApi.updateOperator(
          id: widget.operatorId!,
          displayName: name,
          phone: phone,
          roleIds: roleIds,
          telegramChatId: tgId,
          email: email.isNotEmpty ? email : null,
          nationality:
              _nationalityIso.isNotEmpty ? _nationalityIso : null,
          identityType: identityType,
          identityNumber: identityNumber,
          phoneSecondary:
              _phoneSecondary.isNotEmpty ? _phoneSecondary : null,
          profilePictureUrl: _profilePictureUrl,
          customFieldValues:
              customFieldValues.isNotEmpty ? customFieldValues : null,
        );
      } else {
        await OperatorsApi.createOperator(
          displayName: name,
          phone: phone,
          roleIds: roleIds,
          telegramChatId: tgId.isNotEmpty ? tgId : null,
          email: email.isNotEmpty ? email : null,
          nationality:
              _nationalityIso.isNotEmpty ? _nationalityIso : null,
          identityType: identityType,
          identityNumber: identityNumber,
          phoneSecondary:
              _phoneSecondary.isNotEmpty ? _phoneSecondary : null,
          profilePictureUrl: _profilePictureUrl,
          customFieldValues:
              customFieldValues.isNotEmpty ? customFieldValues : null,
        );
      }
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isEdit
                  ? 'Operador actualizado.'
                  : 'Operador creado. Mensaje de bienvenida enviado.',
              style:
                  const TextStyle(fontFamily: 'Geist', fontSize: 13),
            ),
            backgroundColor: AppColors.ctNavy,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map) {
        final message =
            data['message'] as String? ?? 'Error al guardar';
        final field = data['field'] as String?;

        if (field != null && field.isNotEmpty) {
          setState(() {
            _saving = false;
            _fieldErrors[field] = message;
          });
        } else {
          setState(() {
            _saving = false;
            _errorMsg = message;
          });
        }
      } else {
        final statusCode = e.response?.statusCode;
        setState(() {
          _saving = false;
          _errorMsg = statusCode == 409
              ? 'Ya existe un operador con ese número de teléfono.'
              : 'Error al guardar. Intenta de nuevo.';
        });
      }
    } catch (_) {
      setState(() {
        _saving = false;
        _errorMsg = 'Error inesperado. Intenta de nuevo.';
      });
    }
  }

  // ── Telegram invite — DO NOT MODIFY LOGIC ────────────────────────────────

  Future<void> _sendInvite() async {
    if (_sendingInvite || widget.operatorId == null) return;
    if (_telegramChannelId == null) {
      setState(() => _inviteResults = [
            '⚠ No se encontraron canales Telegram en los flujos seleccionados.'
          ]);
      return;
    }
    setState(() {
      _sendingInvite = true;
      _inviteResults = [];
    });
    try {
      final result = await OperatorsApi.sendTelegramInvite(
        operatorId: widget.operatorId!,
        channelId: _telegramChannelId!,
        phone: _phoneE164.isNotEmpty ? _phoneE164 : _phoneLocalNumber,
      );
      final expiresAt = result['expires_at'] as String?;
      if (mounted) {
        setState(() {
          _sendingInvite = false;
          _telegramLinkStatus = 'pending';
          if (expiresAt != null) _telegramLinkExpiresAt = expiresAt;
          _inviteResults = ['✓ Invitación enviada'];
        });
      }
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final String errorMsg;
      if (statusCode == 409) {
        errorMsg =
            'Este operador ya tiene Telegram vinculado. '
            'Borra el Chat ID actual y guarda para poder reenviar.';
      } else {
        errorMsg = 'No se pudo enviar la invitación. Intenta de nuevo.';
      }
      if (mounted) {
        setState(() {
          _sendingInvite = false;
          _inviteResults = ['✗ $errorMsg'];
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _sendingInvite = false;
          _inviteResults = [
            '✗ No se pudo enviar la invitación. Intenta de nuevo.'
          ];
        });
      }
    }
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _telegramCtrl.dispose();
    for (final ctrl in _customFieldControllers.values) {
      ctrl.dispose();
    }
    if (_realtimeChannel != null) {
      Supabase.instance.client
          .removeChannel(_realtimeChannel!)
          .catchError((e) {
        debugPrint('[Realtime] removeChannel error: $e');
        return 'error';
      });
    }
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.ctBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.isEdit
                          ? 'Editar operador'
                          : 'Agregar operador',
                      style: const TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ctText,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: const Icon(Icons.close_rounded,
                          size: 18, color: AppColors.ctText3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppColors.ctBorder),

            // ── Scrollable body ──────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Error banner ─────────────────────────────────────
                    if (_errorMsg != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.ctRedBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.ctDanger
                                  .withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                size: 14, color: AppColors.ctDanger),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMsg!,
                                style: const TextStyle(
                                  fontFamily: 'Geist',
                                  fontSize: 12,
                                  color: AppColors.ctRedText,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── SECCIÓN 1: Datos básicos ─────────────────────────
                    _SectionHeader(label: 'Datos básicos'),
                    const SizedBox(height: 14),

                    // Profile photo
                    Center(
                      child: Column(
                        children: [
                          GestureDetector(
                        onTap: _uploadingPhoto ? null : _pickProfilePhoto,
                        child: MouseRegion(
                          cursor: _uploadingPhoto
                              ? MouseCursor.defer
                              : SystemMouseCursors.click,
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              CircleAvatar(
                                radius: 36,
                                backgroundColor: (_profileBytes != null ||
                                        (_profilePictureUrl != null &&
                                            _profilePictureUrl!.isNotEmpty))
                                    ? AppColors.ctSurface2
                                    : _avatarColor(
                                        _nameCtrl.text.trim()),
                                backgroundImage: _profileBytes != null
                                    ? MemoryImage(_profileBytes!)
                                        as ImageProvider
                                    : (_profilePictureUrl != null &&
                                            _profilePictureUrl!.isNotEmpty)
                                        ? NetworkImage(_profilePictureUrl!)
                                        : null,
                                child: _uploadingPhoto
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : (_profileBytes == null &&
                                            (_profilePictureUrl == null ||
                                                _profilePictureUrl!.isEmpty))
                                        ? ListenableBuilder(
                                            listenable: _nameCtrl,
                                            builder: (context, child) =>
                                                Text(
                                              _initials(_nameCtrl.text),
                                              style: const TextStyle(
                                                fontFamily: 'Onest',
                                                fontSize: 18,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                            ),
                                          )
                                        : null,
                              ),
                              if (!_uploadingPhoto)
                              Container(
                                width: 22,
                                height: 22,
                                decoration: const BoxDecoration(
                                  color: AppColors.ctTeal,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                    Icons.camera_alt_rounded,
                                    size: 12,
                                    color: AppColors.ctNavy),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_fieldErrors.containsKey('profile_picture')) ...[
                        const SizedBox(height: 6),
                        Text(
                          _fieldErrors['profile_picture']!,
                          style: const TextStyle(
                            fontFamily: 'Geist',
                            fontSize: 11,
                            color: AppColors.ctDanger,
                          ),
                        ),
                      ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Nombre
                    _FieldLabel('Nombre completo *'),
                    const SizedBox(height: 6),
                    _FormField(
                      controller: _nameCtrl,
                      placeholder: 'Ej: Roberto Medina',
                      errorText: _fieldErrors['display_name'],
                    ),
                    const SizedBox(height: 14),

                    // Teléfono WhatsApp (PhoneFieldWidget)
                    PhoneFieldWidget(
                      label: 'Número de WhatsApp *',
                      initialCountryIso: _phoneCountryIso,
                      initialLocalNumber: _phoneLocalNumber,
                      errorText: _fieldErrors['phone'],
                      onChanged: (e164) =>
                          setState(() => _phoneE164 = e164),
                    ),
                    const SizedBox(height: 14),

                    // Email
                    _FieldLabel('Email (opcional)'),
                    const SizedBox(height: 6),
                    _FormField(
                      controller: _emailCtrl,
                      placeholder: 'correo@ejemplo.com',
                      keyboardType: TextInputType.emailAddress,
                      errorText: _fieldErrors['email'],
                    ),

                    const SizedBox(height: 20),

                    // ── SECCIÓN 2: Identificación ─────────────────────────
                    _SectionHeader(label: 'Identificación'),
                    const SizedBox(height: 14),
                    NationalityIdentityWidget(
                      initialNationality: _nationalityIso.isNotEmpty
                          ? _nationalityIso
                          : null,
                      initialIdentityNumber: _identityNumber.isNotEmpty
                          ? _identityNumber
                          : null,
                      onNationalityChanged: (iso) =>
                          setState(() => _nationalityIso = iso),
                      onIdentityChanged: (v) =>
                          setState(() => _identityNumber = v),
                    ),

                    const SizedBox(height: 20),

                    // ── SECCIÓN 3: Contacto adicional (collapsible) ───────
                    GestureDetector(
                      onTap: () => setState(
                          () => _secondaryExpanded = !_secondaryExpanded),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Row(
                          children: [
                            _SectionHeader(
                                label: 'Contacto adicional'),
                            const Spacer(),
                            Icon(
                              _secondaryExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: AppColors.ctText2,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _secondaryExpanded ? 'Colapsar' : 'Expandir',
                              style: const TextStyle(
                                  fontFamily: 'Geist',
                                  fontSize: 11,
                                  color: AppColors.ctText2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_secondaryExpanded) ...[
                      const SizedBox(height: 10),
                      PhoneSecondaryWidget(
                        initial: _phoneSecondary.isNotEmpty
                            ? _phoneSecondary
                            : null,
                        onChanged: (list) =>
                            setState(() => _phoneSecondary = list),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // ── SECCIÓN 4: Rol de operador ────────────────────────
                    _SectionHeader(label: 'Rol de operador'),
                    const SizedBox(height: 10),
                    if (_rolesLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.ctTeal),
                          ),
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        initialValue: _availableRoles.any(
                                (r) => r['id'] == _selectedRoleId)
                            ? _selectedRoleId
                            : null,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppColors.ctSurface2,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: AppColors.ctBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: AppColors.ctBorder),
                          ),
                        ),
                        hint: const Text('Sin rol asignado',
                            style: TextStyle(
                                fontFamily: 'Geist',
                                fontSize: 13,
                                color: AppColors.ctText2)),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('Sin rol asignado',
                                style: TextStyle(
                                    fontFamily: 'Geist',
                                    fontSize: 13,
                                    color: AppColors.ctText2)),
                          ),
                          ..._availableRoles.map((role) {
                            final id = role['id'] as String? ?? '';
                            final label =
                                role['label'] as String? ?? id;
                            final slug =
                                role['slug'] as String? ?? '';
                            return DropdownMenuItem<String>(
                              value: id,
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(label,
                                      style: const TextStyle(
                                          fontFamily: 'Geist',
                                          fontSize: 13,
                                          color: AppColors.ctText)),
                                  if (slug.isNotEmpty)
                                    Text(slug,
                                        style: const TextStyle(
                                            fontFamily: 'Geist',
                                            fontSize: 11,
                                            color: AppColors.ctText2)),
                                ],
                              ),
                            );
                          }),
                        ],
                        onChanged: (val) =>
                            setState(() => _selectedRoleId = val),
                      ),

                    // ── SECCIÓN 5: Telegram Chat ID ───────────────────────
                    const SizedBox(height: 20),
                    _SectionHeader(label: 'Vinculación Telegram'),
                    const SizedBox(height: 10),
                    if (_telegramLinkStatus == 'linked') ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.ctSurface2,
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: AppColors.ctBorder2),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _telegramCtrl.text,
                                style: const TextStyle(
                                  fontFamily: 'Geist',
                                  fontSize: 13,
                                  color: AppColors.ctText,
                                ),
                              ),
                            ),
                            const Icon(Icons.check_circle_rounded,
                                size: 16, color: AppColors.ctTeal),
                          ],
                        ),
                      ),
                    ] else ...[
                      _FieldLabel('Telegram Chat ID'),
                      const SizedBox(height: 6),
                      _FormField(
                        controller: _telegramCtrl,
                        placeholder: 'Ej: 123456789',
                        keyboardType: TextInputType.number,
                      ),
                    ],

                    // Vincular vía Telegram button
                    if (_telegramChannelId != null &&
                        _telegramLinkStatus != 'linked' &&
                        widget.isEdit) ...[
                      const SizedBox(height: 12),
                      Builder(builder: (ctx) {
                        final isExpired =
                            _telegramLinkStatus == 'expired' ||
                                (_telegramLinkStatus == 'pending' &&
                                    _isTelegramExpired(
                                        _telegramLinkExpiresAt));
                        final isPendingActive =
                            _telegramLinkStatus == 'pending' &&
                                !isExpired &&
                                _telegramLinkExpiresAt != null;
                        final btnLabel =
                            _telegramLinkStatus == 'none'
                                ? 'Vincular vía Telegram'
                                : 'Reenviar invitación';
                        return Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            if (isExpired)
                              const Padding(
                                padding:
                                    EdgeInsets.only(bottom: 6),
                                child: Text(
                                  'Invitación expirada',
                                  style: TextStyle(
                                    fontFamily: 'Geist',
                                    fontSize: 11,
                                    color: AppColors.ctDanger,
                                  ),
                                ),
                              )
                            else if (isPendingActive)
                              Padding(
                                padding: const EdgeInsets.only(
                                    bottom: 6),
                                child: Text(
                                  'Invitación enviada · expira ${_formatTelegramExpiry(_telegramLinkExpiresAt!)}',
                                  style: const TextStyle(
                                    fontFamily: 'Geist',
                                    fontSize: 11,
                                    color: AppColors.ctText2,
                                  ),
                                ),
                              ),
                            SizedBox(
                              width: double.infinity,
                              height: 36,
                              child: _sendingInvite
                                  ? const Center(
                                      child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child:
                                            CircularProgressIndicator(
                                                strokeWidth: 2),
                                      ),
                                    )
                                  : OutlinedButton.icon(
                                      onPressed: _sendInvite,
                                      icon: const Icon(
                                          Icons.telegram,
                                          size: 16),
                                      label: Text(btnLabel,
                                          style: const TextStyle(
                                              fontFamily: 'Geist',
                                              fontSize: 13)),
                                      style:
                                          OutlinedButton.styleFrom(
                                        foregroundColor:
                                            const Color(0xFF229ED9),
                                        side: const BorderSide(
                                            color:
                                                Color(0xFF229ED9)),
                                        shape:
                                            RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(
                                                  8),
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        );
                      }),
                      if (_inviteResults.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ..._inviteResults.map(
                          (r) => Padding(
                            padding:
                                const EdgeInsets.only(bottom: 4),
                            child: Text(
                              r,
                              style: const TextStyle(
                                  fontFamily: 'Geist',
                                  fontSize: 11,
                                  color: AppColors.ctText2),
                            ),
                          ),
                        ),
                      ],
                    ],

                    // ── SECCIÓN 6: Campos personalizados ─────────────────
                    if (_customFieldsLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.ctTeal),
                          ),
                        ),
                      )
                    else if (_customFieldDefs.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _SectionHeader(label: 'Campos personalizados'),
                      const SizedBox(height: 14),
                      ..._customFieldDefs.map(_buildCustomField),
                    ],

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // ── Footer with action buttons ─────────────────────────────
            const Divider(height: 1, color: AppColors.ctBorder),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _FormGhostButton(
                    label: 'Cancelar',
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  if (_saving)
                    const SizedBox(
                      width: 120,
                      height: 36,
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2),
                        ),
                      ),
                    )
                  else
                    _FormPrimaryButton(
                      label: 'Guardar operador',
                      onTap: _save,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Local widgets ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontFamily: 'Onest',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.ctText,
        letterSpacing: 0.1,
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Geist',
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.ctText,
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    required this.placeholder,
    this.keyboardType,
    this.errorText,
  });
  final TextEditingController controller;
  final String placeholder;
  final TextInputType? keyboardType;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(
            fontFamily: 'Geist',
            fontSize: 13,
            color: AppColors.ctText,
          ),
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 13,
              color: AppColors.ctText3,
            ),
            filled: true,
            fillColor: AppColors.ctSurface2,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: errorText != null
                    ? AppColors.ctDanger
                    : AppColors.ctBorder2,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: errorText != null
                    ? AppColors.ctDanger
                    : AppColors.ctBorder2,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: errorText != null
                    ? AppColors.ctDanger
                    : AppColors.ctTeal,
                width: 1.5,
              ),
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 3),
          Text(
            errorText!,
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 11,
              color: AppColors.ctDanger,
            ),
          ),
        ],
      ],
    );
  }
}

class _FormPrimaryButton extends StatefulWidget {
  const _FormPrimaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_FormPrimaryButton> createState() => _FormPrimaryButtonState();
}

class _FormPrimaryButtonState extends State<_FormPrimaryButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color:
                _hovered ? AppColors.ctTealDark : AppColors.ctTeal,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.ctNavy,
            ),
          ),
        ),
      ),
    );
  }
}

class _FormGhostButton extends StatefulWidget {
  const _FormGhostButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_FormGhostButton> createState() => _FormGhostButtonState();
}

class _FormGhostButtonState extends State<_FormGhostButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.ctSurface2
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.ctBorder2),
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.ctText2,
            ),
          ),
        ),
      ),
    );
  }
}
