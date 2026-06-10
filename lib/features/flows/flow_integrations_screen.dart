import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/flows_api.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_format.dart';
import '../../shared/widgets/app_button.dart';

// ── Screen ────────────────────────────────────────────────────────────────────

class FlowIntegrationsScreen extends ConsumerStatefulWidget {
  const FlowIntegrationsScreen({
    super.key,
    required this.flowId,
    required this.flowName,
    required this.tenantWorkerId,
  });

  final String flowId;
  final String flowName;
  final String tenantWorkerId;

  @override
  ConsumerState<FlowIntegrationsScreen> createState() =>
      _FlowIntegrationsScreenState();
}

class _FlowIntegrationsScreenState
    extends ConsumerState<FlowIntegrationsScreen> {
  List<Map<String, dynamic>> _integrations = [];
  bool _loading = true;
  String? _error;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await FlowsApi.listIntegrations(
        dio: ref.read(apiClientProvider).dio,
        flowId: widget.flowId,
      );
      if (!mounted) return;
      setState(() {
        _integrations = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _dioError(e);
        _loading = false;
      });
    }
  }

  Future<void> _delete(String integrationId) async {
    if (_deleting) return;
    setState(() => _deleting = true);
    try {
      await FlowsApi.deleteIntegration(
        dio: ref.read(apiClientProvider).dio,
        flowId: widget.flowId,
        integrationId: integrationId,
      );
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_dioError(e)),
        backgroundColor: AppColors.ctDanger,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  void _openEditUrlDialog(String integrationId, String currentUrl) {
    showDialog(
      context: context,
      builder: (_) => _EditEndpointDialog(
        currentUrl: currentUrl,
        onSave: (newUrl) async {
          final updated = await FlowsApi.patchIntegration(
            dio: ref.read(apiClientProvider).dio,
            flowId: widget.flowId,
            integrationId: integrationId,
            endpointUrl: newUrl,
          );
          if (!mounted) return;
          setState(() {
            final idx =
                _integrations.indexWhere((e) => e['id'] == integrationId);
            if (idx >= 0) _integrations[idx] = updated;
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('URL actualizada'),
            backgroundColor: AppColors.ctOk,
            duration: Duration(seconds: 2),
          ));
        },
      ),
    );
  }

  void _openCreateDialog() {
    showDialog(
      context: context,
      builder: (_) => _CreateIntegrationDialog(
        flowId: widget.flowId,
        onCreated: (integration) async {
          await _showSecretDialog(integration);
          await _load();
        },
      ),
    );
  }

  Future<void> _showSecretDialog(Map<String, dynamic> integration) async {
    final apiKeyPlain = integration['api_key_plain'] as String?;
    final hmacSecretPlain = integration['hmac_secret_plain'] as String?;
    final secret = apiKeyPlain ?? hmacSecretPlain;
    final label = apiKeyPlain != null ? 'API Key' : 'HMAC Secret';
    if (secret == null || !mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Copia tu $label ahora',
          style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist', fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppColors.ctDanger, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Esta es la única vez que verás esta clave. Guárdala en un lugar seguro.',
                      style: AppTextStyles.body.copyWith(color: AppColors.ctDanger),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              _SecretBox(secret: secret),
            ],
          ),
        ),
        actions: [
          AppButton(
            label: 'Entendido',
            variant: AppButtonVariant.teal,
            size: AppButtonSize.sm,
            onPressed: () => ctx.pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(activeTenantIdProvider, (prev, next) {
      if (next.isNotEmpty) _load();
    });

    final canManage = hasPermission(ref, 'flow_integrations', 'manage');

    return Scaffold(
      backgroundColor: AppColors.ctBg,
      appBar: AppBar(
        backgroundColor: AppColors.ctNavy,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/workers/${widget.tenantWorkerId}?selectedFlow=${widget.flowId}'),
        ),
        title: Text(
          'Integraciones — ${widget.flowName}',
          style: AppFonts.onest(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        actions: [
          if (canManage)
            AppButton(
              label: 'Nueva',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              isDisabled: _loading,
              prefixIcon: const Icon(Icons.add, size: 14, color: AppColors.ctTeal),
              onPressed: _openCreateDialog,
            ),
        ],
      ),
      body: _buildBody(canManage),
    );
  }

  Widget _buildBody(bool canManage) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.ctDanger),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            AppButton(label: 'Reintentar', variant: AppButtonVariant.ghost, size: AppButtonSize.sm, onPressed: _load),
          ],
        ),
      );
    }
    if (_integrations.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.electrical_services_outlined,
                size: 52, color: AppColors.ctText3),
            const SizedBox(height: 12),
            Text(
              'Sin integraciones',
              style: AppFonts.onest(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.ctText2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Crea una integración para conectar este flujo con sistemas externos.',
              style: AppFonts.geist(fontSize: 13, color: AppColors.ctText2),
              textAlign: TextAlign.center,
            ),
            if (canManage) ...[
              const SizedBox(height: 20),
              AppButton(
                label: 'Nueva integración',
                variant: AppButtonVariant.teal,
                size: AppButtonSize.sm,
                prefixIcon: const Icon(Icons.add, size: 14, color: AppColors.ctNavy),
                onPressed: _openCreateDialog,
              ),
            ],
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: _integrations.length,
      separatorBuilder: (ctx2, idx2) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final intg = _integrations[i];
        final id = intg['id'] as String? ?? '';
        final type = intg['integration_type'] as String? ?? '';
        final url = intg['endpoint_url'] as String? ?? '';
        return _IntegrationCard(
          integration: intg,
          canManage: canManage,
          deleting: _deleting,
          onDelete: () {
            if (id.isNotEmpty) _delete(id);
          },
          onEditEndpointUrl: (canManage && type == 'outbound' && id.isNotEmpty)
              ? () => _openEditUrlDialog(id, url)
              : null,
        );
      },
    );
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _IntegrationCard extends StatelessWidget {
  const _IntegrationCard({
    required this.integration,
    required this.canManage,
    required this.deleting,
    required this.onDelete,
    this.onEditEndpointUrl,
  });

  final Map<String, dynamic> integration;
  final bool canManage;
  final bool deleting;
  final VoidCallback onDelete;
  final VoidCallback? onEditEndpointUrl;

  @override
  Widget build(BuildContext context) {
    final type = integration['integration_type'] as String? ??
        integration['type'] as String? ??
        'api';
    final id = integration['id'] as String? ?? '';
    final isActive = integration['is_active'] as bool? ?? true;
    final createdAt = integration['created_at'] as String? ?? '';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _TypeIcon(type: type),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _typeLabel(type),
                      style: AppFonts.geist(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ctText,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusChip(active: isActive),
                  ],
                ),
                if (id.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'ID: $id',
                        style: AppFonts.geist(
                            fontSize: 11, color: AppColors.ctText3),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 14),
                        color: AppColors.ctText2,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: id));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('ID copiado'),
                              duration: Duration(milliseconds: 1500),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
                if (createdAt.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Creado: ${fmtDateSlash(createdAt)}',
                    style: AppFonts.geist(
                        fontSize: 11, color: AppColors.ctText3),
                  ),
                ],
                if (type == 'outbound' ||
                    type == 'webhook' ||
                    type == 'webhook_out') ...[
                  const SizedBox(height: 4),
                  _OutboundEndpointRow(
                    integration: integration,
                    onEdit: onEditEndpointUrl,
                  ),
                ],
              ],
            ),
          ),
          if (canManage)
            deleting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: AppColors.ctText3, size: 18),
                    tooltip: 'Eliminar',
                    onPressed: () => _confirmDelete(context),
                  ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Eliminar integración',
          style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist', fontWeight: FontWeight.w600),
        ),
        content: Text(
          '¿Estás seguro? Esta acción no se puede deshacer.',
          style: AppTextStyles.body.copyWith(color: AppColors.ctText2),
        ),
        actions: [
          AppButton(
            label: 'Cancelar',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: () => ctx.pop(),
          ),
          AppButton(
            label: 'Eliminar',
            variant: AppButtonVariant.danger,
            size: AppButtonSize.sm,
            onPressed: () { ctx.pop(); onDelete(); },
          ),
        ],
      ),
    );
  }
}

// ── Create dialog ─────────────────────────────────────────────────────────────

class _CreateIntegrationDialog extends ConsumerStatefulWidget {
  const _CreateIntegrationDialog({
    required this.flowId,
    required this.onCreated,
  });

  final String flowId;
  final Future<void> Function(Map<String, dynamic> integration) onCreated;

  @override
  ConsumerState<_CreateIntegrationDialog> createState() =>
      _CreateIntegrationDialogState();
}

class _CreateIntegrationDialogState extends ConsumerState<_CreateIntegrationDialog> {
  String _type = 'api';
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  bool _includeAncestors = false;
  int _rateLimit = 60;
  bool _saving = false;
  String? _error;

  static const _kTypes = [
    ('api', 'API Key'),
    ('webhook', 'Webhook'),
    ('zapier', 'Zapier'),
    ('make', 'Make (Integromat)'),
    ('n8n', 'n8n'),
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final integration = await FlowsApi.createIntegration(
        dio: ref.read(apiClientProvider).dio,
        flowId: widget.flowId,
        name: _nameCtrl.text.trim(),
        integrationType: _type,
        endpointUrl: _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
        includeAncestors: _includeAncestors,
        rateLimitPerMinute: _rateLimit,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onCreated(integration);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _dioError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsUrl = _type == 'webhook' || _type == 'n8n';
    final nameValid = _nameCtrl.text.trim().isNotEmpty;

    return AlertDialog(
      title: Text(
        'Nueva integración',
        style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist', fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nombre',
              style: AppTextStyles.bodySmall.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              style: AppFonts.geist(fontSize: 13, color: AppColors.ctText),
              decoration: InputDecoration(
                hintText: 'Ej: API Sistema Externo',
                hintStyle: AppFonts.geist(fontSize: 13, color: AppColors.ctText2),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppColors.ctBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppColors.ctBorder),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Tipo',
              style: AppTextStyles.bodySmall.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.ctBorder),
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButton<String>(
                value: _type,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                style: AppFonts.geist(fontSize: 13, color: AppColors.ctText),
                items: _kTypes
                    .map((t) => DropdownMenuItem(
                          value: t.$1,
                          child: Text(t.$2),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _type = v);
                },
              ),
            ),
            if (needsUrl) ...[
              const SizedBox(height: 14),
              Text(
                'URL del endpoint',
                style: AppTextStyles.bodySmall.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _urlCtrl,
                style: AppFonts.geist(fontSize: 13, color: AppColors.ctText),
                decoration: InputDecoration(
                  hintText: 'https://...',
                  hintStyle:
                      AppFonts.geist(fontSize: 13, color: AppColors.ctText3),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: AppColors.ctBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: AppColors.ctBorder),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Switch(
                  value: _includeAncestors,
                  activeThumbColor: Colors.white,
                  activeTrackColor: AppColors.ctTeal,
                  onChanged: (v) => setState(() => _includeAncestors = v),
                ),
                const SizedBox(width: 8),
                Text(
                  'Incluir flujos anteriores',
                  style: AppTextStyles.body,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'Límite por minuto:',
                  style: AppTextStyles.body,
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 72,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    style:
                        AppFonts.geist(fontSize: 13, color: AppColors.ctText),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            const BorderSide(color: AppColors.ctBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            const BorderSide(color: AppColors.ctBorder),
                      ),
                    ),
                    controller:
                        TextEditingController(text: _rateLimit.toString()),
                    onChanged: (v) {
                      final n = int.tryParse(v);
                      if (n != null && n > 0) _rateLimit = n;
                    },
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: AppColors.ctDanger),
              ),
            ],
          ],
        ),
      ),
      actions: [
        AppButton(
          label: 'Cancelar',
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.sm,
          isDisabled: _saving,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Crear',
          variant: AppButtonVariant.teal,
          size: AppButtonSize.sm,
          isLoading: _saving,
          isDisabled: !nameValid,
          onPressed: _submit,
        ),
      ],
    );
  }
}

// ── Secret box ────────────────────────────────────────────────────────────────

class _SecretBox extends StatefulWidget {
  const _SecretBox({required this.secret});
  final String secret;

  @override
  State<_SecretBox> createState() => _SecretBoxState();
}

class _SecretBoxState extends State<_SecretBox> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.ctSurface2,
        border: Border.all(color: AppColors.ctBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              widget.secret,
              style: AppTextStyles.body,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              _copied ? Icons.check : Icons.copy_outlined,
              size: 16,
              color: _copied ? AppColors.ctOk : AppColors.ctText3,
            ),
            tooltip: 'Copiar',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.secret));
              setState(() => _copied = true);
              Future.delayed(const Duration(seconds: 2),
                  () {
                if (mounted) setState(() => _copied = false);
              });
            },
          ),
        ],
      ),
    );
  }
}

// ── Small widgets ─────────────────────────────────────────────────────────────

class _TypeIcon extends StatelessWidget {
  const _TypeIcon({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    switch (type) {
      case 'webhook':
      case 'webhook_out':
        icon = Icons.webhook_outlined;
        break;
      case 'zapier':
        icon = Icons.bolt_outlined;
        break;
      case 'make':
      case 'n8n':
        icon = Icons.device_hub_outlined;
        break;
      default:
        icon = Icons.key_outlined;
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.ctInfoBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 20, color: AppColors.ctInfo),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: active ? AppColors.ctOkBg : AppColors.ctSurface2,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        active ? 'Activo' : 'Inactivo',
        style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600, color: active ? AppColors.ctOkText : AppColors.ctText3),
      ),
    );
  }
}

class _OutboundEndpointRow extends StatelessWidget {
  const _OutboundEndpointRow({
    required this.integration,
    this.onEdit,
  });

  final Map<String, dynamic> integration;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final url = integration['endpoint_url'] as String? ??
        integration['url'] as String? ??
        '';
    final hasUrl = url.isNotEmpty;
    return Row(
      children: [
        Icon(Icons.link, size: 12,
            color: hasUrl ? AppColors.ctText3 : AppColors.ctText3),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            hasUrl ? url : 'Sin URL configurada',
            style: AppFonts.geist(fontSize: 11, color: AppColors.ctText3),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (onEdit != null) ...[
          const SizedBox(width: 4),
          InkWell(
            onTap: onEdit,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.edit_outlined,
                  size: 13, color: AppColors.ctText3),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Edit endpoint dialog ───────────────────────────────────────────────────────

class _EditEndpointDialog extends StatefulWidget {
  const _EditEndpointDialog({
    required this.currentUrl,
    required this.onSave,
  });

  final String currentUrl;
  final Future<void> Function(String url) onSave;

  @override
  State<_EditEndpointDialog> createState() => _EditEndpointDialogState();
}

class _EditEndpointDialogState extends State<_EditEndpointDialog> {
  late final TextEditingController _urlCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.currentUrl);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_urlCtrl.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _dioError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Editar URL del endpoint',
        style: AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist', fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'URL del endpoint',
              style: AppTextStyles.bodySmall.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _urlCtrl,
              autofocus: true,
              style: AppFonts.geist(fontSize: 13, color: AppColors.ctText),
              decoration: InputDecoration(
                hintText: 'https://...',
                hintStyle:
                    AppFonts.geist(fontSize: 13, color: AppColors.ctText3),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppColors.ctBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppColors.ctBorder),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: AppColors.ctDanger),
              ),
            ],
          ],
        ),
      ),
      actions: [
        AppButton(
          label: 'Cancelar',
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.sm,
          isDisabled: _saving,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Guardar',
          variant: AppButtonVariant.teal,
          size: AppButtonSize.sm,
          isLoading: _saving,
          onPressed: _submit,
        ),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _typeLabel(String type) {
  switch (type) {
    case 'api':
      return 'API Key';
    case 'webhook':
    case 'webhook_out':
      return 'Webhook';
    case 'zapier':
      return 'Zapier';
    case 'make':
      return 'Make';
    case 'n8n':
      return 'n8n';
    default:
      return type;
  }
}

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
