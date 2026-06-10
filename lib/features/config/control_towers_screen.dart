import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/groups_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_badge.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/page_header.dart';

// ── Helpers ───────────────────────────────────────────────────────────────

String _dioError(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      final d = data['detail'];
      if (d != null) return 'Error: $d';
    }
    final s = e.response?.statusCode;
    if (s != null) return 'Error $s al procesar la solicitud';
  }
  return e.toString();
}

String _fmtDate(String? iso) {
  if (iso == null) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  } catch (_) {
    return '—';
  }
}

// ── Screen ────────────────────────────────────────────────────────────────

class ControlTowersScreen extends ConsumerStatefulWidget {
  const ControlTowersScreen({super.key});

  @override
  ConsumerState<ControlTowersScreen> createState() => _ControlTowersScreenState();
}

class _ControlTowersScreenState extends ConsumerState<ControlTowersScreen> {
  List<Map<String, dynamic>> _towers = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final data = await GroupsApi.listControlTowers(dio: ref.read(apiClientProvider).dio);
      if (!mounted) return;
      setState(() { _towers = data; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = _dioError(e); });
    }
  }


  void _openEdit(Map<String, dynamic> tower) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _EditTowerDialog(tower: tower, dio: ref.read(apiClientProvider).dio, onSaved: _load),
    );
    if (result == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> tower) async {
    final towerId = tower['id'] as String? ?? '';
    final displayName = tower['display_name'] as String? ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Torre de Control'),
        content: Text('¿Confirmas eliminar "$displayName"?\n\nEsta acción marcará la torre como inactiva.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          AppButton(
            label: 'Eliminar',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await GroupsApi.deleteControlTower(dio: ref.read(apiClientProvider).dio, towerId: towerId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Torre eliminada'), backgroundColor: AppColors.ctOk),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_dioError(e)), backgroundColor: AppColors.ctDanger),
      );
    }
  }

  void _openSendMessage(Map<String, dynamic> tower) async {
    await showDialog(
      context: context,
      builder: (_) => _SendMessageDialog(tower: tower, dio: ref.read(apiClientProvider).dio),
    );
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(userPermissionsProvider);
    final canManage = perms.value?.contains('integrations.manage') ?? false;

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.ctTeal)),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: AppColors.ctDanger)),
              const SizedBox(height: 16),
              AppButton(
                variant: AppButtonVariant.primary,label: 'Reintentar', onPressed: _load),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            eyebrow: 'Notificaciones',
            title: 'Torres de Control',
            description: 'Grupos push-only vía Whapi para notificaciones sin interacción bidireccional. Para crear nuevas torres, ve al detalle del Worker correspondiente.',
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _towers.isEmpty
                ? const Center(
                    child: Text(
                      'No hay torres de control configuradas',
                      style: TextStyle(color: AppColors.ctText2, fontSize: 14),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _towers.length,
                    itemBuilder: (ctx, i) => _TowerCard(
                      tower: _towers[i],
                      canManage: canManage,
                      onEdit: () => _openEdit(_towers[i]),
                      onDelete: () => _delete(_towers[i]),
                      onSendMessage: () => _openSendMessage(_towers[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Tower Card ────────────────────────────────────────────────────────────

class _TowerCard extends StatelessWidget {
  const _TowerCard({
    required this.tower,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
    required this.onSendMessage,
  });

  final Map<String, dynamic> tower;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSendMessage;

  @override
  Widget build(BuildContext context) {
    final displayName = tower['display_name'] as String? ?? '—';
    final description = tower['description'] as String? ?? '';
    final status = tower['status'] as String? ?? 'inactive';
    final createdAt = tower['created_at'] as String?;
    final externalGroupId = tower['external_group_id'] as String? ?? '';
    final channelType = tower['channel_type'] as String? ?? 'whatsapp';
    final config = tower['config'] as Map<String, dynamic>? ?? {};
    final inviteLink = config['invite_link'] as String?;

    final isActive = status == 'active';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: AppColors.ctSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppColors.ctBorder, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
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
                          Text(
                            displayName,
                            style: AppFonts.onest(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ctText,
                            ),
                          ),
                          const SizedBox(width: 8),
                          AppBadge(
                            label: isActive ? 'Activa' : 'Inactiva',
                            variant: isActive ? AppBadgeVariant.ok : AppBadgeVariant.neutral,
                          ),
                        ],
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: AppFonts.geist(
                            fontSize: 13,
                            color: AppColors.ctText2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (canManage) ...[
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    color: AppColors.ctTeal,
                    onPressed: onEdit,
                    tooltip: 'Editar',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: AppColors.ctDanger,
                    onPressed: onDelete,
                    tooltip: 'Eliminar',
                  ),
                ],
                if (isActive)
                  IconButton(
                    icon: const Icon(Icons.send, size: 18),
                    color: AppColors.ctTeal,
                    onPressed: onSendMessage,
                    tooltip: 'Enviar mensaje de prueba',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.ctBorder),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DetailRow(
                    label: 'Group ID',
                    value: externalGroupId.isEmpty ? '—' : externalGroupId,
                  ),
                ),
                Expanded(
                  child: _DetailRow(
                    label: 'Canal',
                    value: channelType == 'whatsapp' ? 'WhatsApp' : channelType,
                  ),
                ),
                Expanded(
                  child: _DetailRow(
                    label: 'Creada',
                    value: _fmtDate(createdAt),
                  ),
                ),
              ],
            ),
            if (inviteLink != null && inviteLink.isNotEmpty) ...[
              const SizedBox(height: 8),
              _DetailRow(
                label: 'Link de invitación',
                value: inviteLink,
                isLink: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.isLink = false,
  });

  final String label;
  final String value;
  final bool isLink;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppFonts.geist(
            fontSize: 11,
            color: AppColors.ctText2,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        isLink
            ? GestureDetector(
                onTap: () {
                  // Could open in browser
                },
                child: Text(
                  value,
                  style: AppFonts.geist(
                    fontSize: 12,
                    color: AppColors.ctTeal,
                  ).copyWith(decoration: TextDecoration.underline),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            : Text(
                value,
                style: AppFonts.geist(
                  fontSize: 12,
                  color: AppColors.ctText,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
      ],
    );
  }
}

// ── Edit Dialog ───────────────────────────────────────────────────────────

class _EditTowerDialog extends StatefulWidget {
  const _EditTowerDialog({
    required this.tower,
    required this.dio,
    required this.onSaved,
  });

  final Map<String, dynamic> tower;
  final Dio dio;
  final VoidCallback onSaved;

  @override
  State<_EditTowerDialog> createState() => _EditTowerDialogState();
}

class _EditTowerDialogState extends State<_EditTowerDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late String _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
      text: widget.tower['display_name'] as String? ?? '',
    );
    _descCtrl = TextEditingController(
      text: widget.tower['description'] as String? ?? '',
    );
    _status = widget.tower['status'] as String? ?? 'active';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { _saving = true; });

    try {
      await GroupsApi.updateControlTower(
        dio: widget.dio,
        towerId: widget.tower['id'] as String,
        displayName: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        status: _status,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Torre actualizada'),
          backgroundColor: AppColors.ctOk,
        ),
      );
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() { _saving = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_dioError(e)), backgroundColor: AppColors.ctDanger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar Torre de Control'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre *'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(labelText: 'Descripción'),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Estado'),
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Activa')),
                  DropdownMenuItem(value: 'inactive', child: Text('Inactiva')),
                ],
                onChanged: (v) => setState(() { _status = v ?? 'active'; }),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        AppButton(
                variant: AppButtonVariant.primary,
          label: _saving ? 'Guardando...' : 'Guardar',
          onPressed: _saving ? () {} : () => _submit(),
          isDisabled: _saving,
        ),
      ],
    );
  }
}

// ── Send Message Dialog ───────────────────────────────────────────────────

class _SendMessageDialog extends StatefulWidget {
  const _SendMessageDialog({required this.tower, required this.dio});

  final Map<String, dynamic> tower;
  final Dio dio;

  @override
  State<_SendMessageDialog> createState() => _SendMessageDialogState();
}

class _SendMessageDialogState extends State<_SendMessageDialog> {
  final _formKey = GlobalKey<FormState>();
  final _messageCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { _sending = true; });

    try {
      await GroupsApi.sendMessageToTower(
        dio: widget.dio,
        towerId: widget.tower['id'] as String,
        message: _messageCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mensaje enviado'),
          backgroundColor: AppColors.ctOk,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() { _sending = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_dioError(e)), backgroundColor: AppColors.ctDanger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.tower['display_name'] as String? ?? '—';

    return AlertDialog(
      title: Text('Enviar mensaje a "$displayName"'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _messageCtrl,
            decoration: const InputDecoration(
              labelText: 'Mensaje',
              hintText: 'Escribe el mensaje de prueba...',
            ),
            maxLines: 4,
            validator: (v) => (v ?? '').trim().isEmpty ? 'Requerido' : null,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        AppButton(
                variant: AppButtonVariant.primary,
          label: _sending ? 'Enviando...' : 'Enviar',
          onPressed: _sending ? () {} : () => _send(),
          isDisabled: _sending,
        ),
      ],
    );
  }
}
