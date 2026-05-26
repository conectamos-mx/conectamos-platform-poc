import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/groups_api.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_badge.dart';
import '../../shared/widgets/app_button.dart';

// ── Pantalla ──────────────────────────────────────────────────────────────────

class WhatsAppGroupsScreen extends ConsumerStatefulWidget {
  const WhatsAppGroupsScreen({super.key, required this.channelId});
  final String channelId;

  @override
  ConsumerState<WhatsAppGroupsScreen> createState() =>
      _WhatsAppGroupsScreenState();
}

class _WhatsAppGroupsScreenState extends ConsumerState<WhatsAppGroupsScreen> {
  List<Map<String, dynamic>> _groups = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await GroupsApi.listGroups(channelId: widget.channelId);
      if (mounted) setState(() { _groups = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _deleteGroup(Map<String, dynamic> group) async {
    final groupId = group['id'] as String? ?? '';
    final displayName = group['display_name'] as String? ?? 'este grupo';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.ctSurface,
        title: Text(
          'Eliminar grupo',
          style: AppTextStyles.cardTitle.copyWith(fontSize: 15),
        ),
        content: Text(
          '¿Seguro que deseas eliminar "$displayName"? '
          'El grupo se desactivará y dejará de recibir mensajes.',
          style: AppTextStyles.pageSubtitle,
        ),
        actions: [
          AppButton(
            label: 'Cancelar',
            onPressed: () => Navigator.pop(ctx, false),
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
          ),
          AppButton(
            label: 'Eliminar',
            onPressed: () => Navigator.pop(ctx, true),
            variant: AppButtonVariant.danger,
            size: AppButtonSize.sm,
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await GroupsApi.deleteGroup(groupId: groupId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Grupo eliminado'),
            backgroundColor: AppColors.ctOk,
          ),
        );
        _loadGroups();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar: $e'),
          backgroundColor: AppColors.ctDanger,
        ),
      );
    }
  }

  ({String label, AppBadgeVariant variant}) _statusBadge(String? status) {
    switch (status) {
      case 'active':
        return (label: 'Activo', variant: AppBadgeVariant.ok);
      case 'pending':
        return (label: 'Creando...', variant: AppBadgeVariant.warn);
      case 'inactive':
        return (label: 'Inactivo', variant: AppBadgeVariant.neutral);
      default:
        return (label: status ?? '—', variant: AppBadgeVariant.neutral);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Action bar
        Container(
          height: 48,
          width: double.infinity,
          decoration: const BoxDecoration(
            color: AppColors.ctSurface,
            border: Border(bottom: BorderSide(color: AppColors.ctBorder)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Grupos WhatsApp',
                      style:
                          AppTextStyles.pageTitle.copyWith(fontFamily: 'Geist'),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${_groups.length} grupo${_groups.length == 1 ? '' : 's'}',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Body
        Expanded(
          child: _loading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.ctTeal))
              : _error != null
                  ? Center(
                      child: Text(_error!,
                          style: AppTextStyles.body
                              .copyWith(color: AppColors.ctDanger)),
                    )
                  : _groups.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.groups_outlined,
                                  size: 48, color: AppColors.ctText3),
                              const SizedBox(height: 12),
                              Text(
                                'Sin grupos registrados.',
                                style: AppTextStyles.body
                                    .copyWith(color: AppColors.ctText2),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(22),
                          itemCount: _groups.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final g = _groups[i];
                            final displayName =
                                g['display_name'] as String? ?? '—';
                            final externalName =
                                g['external_name'] as String?;
                            final externalId =
                                g['external_group_id'] as String?;
                            final status = g['status'] as String?;
                            final badge = _statusBadge(status);
                            final meta =
                                g['metadata'] as Map<String, dynamic>? ??
                                    {};
                            final participantCount =
                                meta['participant_count'] as int?;

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.ctSurface,
                                border:
                                    Border.all(color: AppColors.ctBorder),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: AppColors.ctOkBg,
                                      borderRadius:
                                          BorderRadius.circular(18),
                                    ),
                                    child: const Icon(Icons.groups,
                                        size: 18,
                                        color: AppColors.ctOkText),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(displayName,
                                            style: AppTextStyles.body
                                                .copyWith(
                                                    fontWeight:
                                                        FontWeight.w600)),
                                        if (externalName != null &&
                                            externalName !=
                                                displayName) ...[
                                          const SizedBox(height: 2),
                                          Text(externalName,
                                              style: AppTextStyles
                                                  .bodySmall
                                                  .copyWith(
                                                      color: AppColors
                                                          .ctText3)),
                                        ],
                                        if (externalId != null) ...[
                                          const SizedBox(height: 2),
                                          Text(externalId,
                                              style: AppTextStyles.caption
                                                  .copyWith(
                                                      color: AppColors
                                                          .ctText3)),
                                        ],
                                        if (participantCount != null) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(Icons.people_outline,
                                                  size: 12,
                                                  color:
                                                      AppColors.ctText3),
                                              const SizedBox(width: 4),
                                              Text(
                                                  '$participantCount participantes',
                                                  style: AppTextStyles
                                                      .caption
                                                      .copyWith(
                                                          color: AppColors
                                                              .ctText3)),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  AppBadge(
                                    label: badge.label,
                                    variant: badge.variant,
                                  ),
                                  const SizedBox(width: 8),
                                  MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: GestureDetector(
                                      onTap: () => _deleteGroup(g),
                                      child: Icon(Icons.delete_outline,
                                          size: 18,
                                          color: AppColors.ctDanger),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}
