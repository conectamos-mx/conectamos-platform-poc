import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sticky_headers/sticky_headers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/api/flows_api.dart';
import '../broadcasts/broadcast_screen.dart';
import '../../core/api/channels_api.dart';
import '../../core/api/conversations_api.dart';
import '../../core/api/messages_api.dart';
import '../../core/api/operators_api.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/phone_normalizer.dart';
import '../../core/api/sessions_api.dart';
import '../../core/api/supabase_messages.dart';
import '../../core/api/supabase_read_receipts.dart';
import '../../core/providers/permissions_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/operator_avatar.dart';
import '../../shared/widgets/screen_header.dart';
import 'widgets/media_preview_dialog.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final selectedChannelIdProvider  = StateProvider<String?>((ref) => null);
final selectedChannelTabProvider = StateProvider<int>((ref) => 0);
final selectedChatIdProvider     = StateProvider<String?>((ref) => null);
final selectedChatNameProvider = StateProvider<String?>((ref) => null);
final selectedOperatorChannelsProvider =
    StateProvider<List<Map<String, dynamic>>>((ref) => []);
final selectedChannelIndexProvider = StateProvider<int>((ref) => 0);
final replyingToProvider =
    StateProvider<Map<String, dynamic>?>((ref) => null);
final selectedConvOperatorIdProvider = StateProvider<String?>((ref) => null);
final selectedChannelTypeProvider    = StateProvider<String?>((ref) => null);
final selectedChannelWorkerTypeProvider = StateProvider<String?>((ref) => null);
final selectedConvPhotoUrlProvider   = StateProvider<String?>((ref) => null);
final channelUnreadProvider = StateProvider<Map<String, int>>((ref) => const {});
// chat_id → 0 override set when user opens a chat; read by _loadAllChannelUnreads
// to avoid overwriting local-zeroed counts with stale backend values.
final _chatReadOverrideProvider = StateProvider<Map<String, int>>((ref) => const {});

// ── Pantalla ──────────────────────────────────────────────────────────────────

class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        const ScreenHeader(
          title: 'Conversaciones',
          subtitle: 'Mensajes activos por canal y operador',
        ),
        const Expanded(child: _ConversationsBody()),
      ],
    );
  }
}

// ── Broadcast modal ───────────────────────────────────────────────────────────

void _showBroadcastModal(
    BuildContext context, String channelId, String channelType) {
  showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) {
      final sw = MediaQuery.of(ctx).size.width;
      final sh = MediaQuery.of(ctx).size.height;
      final w  = sw * 0.9 < 900 ? sw * 0.9 : 900.0;
      final h  = sh * 0.85 < 700 ? sh * 0.85 : 700.0;
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: w,
            height: h,
            child: BroadcastScreen(
              channelId:   channelId,
              channelType: channelType,
            ),
          ),
        ),
      );
    },
  );
}

// ── Cuerpo con tabs ───────────────────────────────────────────────────────────

class _ConversationsBody extends ConsumerStatefulWidget {
  const _ConversationsBody();

  @override
  ConsumerState<_ConversationsBody> createState() => _ConversationsBodyState();
}

class _ConversationsBodyState extends ConsumerState<_ConversationsBody> {
  List<Map<String, dynamic>> _channels = [];
  bool _loadingChannels = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadChannels());
  }

  Future<void> _loadChannels() async {
    if (!mounted) return;
    setState(() => _loadingChannels = true);
    final tenantId = ref.read(activeTenantIdProvider);
    try {
      final all = await ChannelsApi.listChannels();
      final active = all
          .where((c) => c['is_active'] as bool? ?? false)
          .toList()
        ..sort((a, b) => (a['created_at'] as String? ?? '')
            .compareTo(b['created_at'] as String? ?? ''));
      if (!mounted) return;
      setState(() { _channels = active; _loadingChannels = false; });
      if (active.isNotEmpty && ref.read(selectedChannelIdProvider) == null) {
        // Set worker type and channel type BEFORE channel ID,
        // because the channel ID change triggers _fetchConversations
        // which needs worker type to be already set.
        ref.read(selectedChannelTypeProvider.notifier).state =
            active.first['channel_type'] as String?;
        ref.read(selectedChannelWorkerTypeProvider.notifier).state =
            active.first['worker_type'] as String?;
        ref.read(selectedChannelIdProvider.notifier).state =
            active.first['id'] as String?;
      }
      _loadAllChannelUnreads(active, tenantId);
    } catch (_) {
      if (mounted) setState(() => _loadingChannels = false);
    }
  }

  Future<void> _loadAllChannelUnreads(
      List<Map<String, dynamic>> channels, String tenantId) async {
    final activeChannelId = ref.read(selectedChannelIdProvider);
    final otherChannels = channels
        .where((ch) => ch['id'] != activeChannelId)
        .toList();
    if (otherChannels.isEmpty) return;
    debugPrint('[_loadAllChannelUnreads] loading ${otherChannels.length} other channels');
    try {
      final results = await Future.wait(
        otherChannels.map((ch) => ConversationsApi.listConversations(
          channelId: ch['id'] as String,
        )),
      );
      if (!mounted) return;
      final chatReadOverride = ref.read(_chatReadOverrideProvider);
      final current = ref.read(channelUnreadProvider);
      final Map<String, int> updated = Map.from(current);
      for (int i = 0; i < otherChannels.length; i++) {
        final channelId = otherChannels[i]['id'] as String;
        final convs = results[i];
        // Diagnostic: detect chat_id mismatch between backend and session overrides
        if (chatReadOverride.isNotEmpty) {
          final backendIds = convs.map((c) => c['chat_id'] as String? ?? '').toSet();
          final overrideOnly = chatReadOverride.keys.toSet().difference(backendIds);
          if (overrideOnly.isNotEmpty) {
            debugPrint('[_loadAllChannelUnreads] MISMATCH — override keys not in backend: $overrideOnly');
            debugPrint('[_loadAllChannelUnreads] backend chat_ids sample: ${backendIds.take(3).toList()}');
          }
        }
        updated[channelId] = convs.fold<int>(
            0, (sum, c) {
              final chatId = c['chat_id'] as String? ?? '';
              // Respect session-level read override — user already cleared this chat
              final count = chatReadOverride.containsKey(chatId)
                  ? chatReadOverride[chatId]!
                  : ((c['unread_count'] as int?) ?? 0);
              return sum + count;
            });
      }
      debugPrint('[_loadAllChannelUnreads] done — totals: $updated');
      ref.read(channelUnreadProvider.notifier).state = updated;
    } catch (e) {
      debugPrint('[_loadAllChannelUnreads] error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(activeTenantIdProvider, (prev, next) {
      if (prev != null && prev != next) {
        ref.read(selectedChannelIdProvider.notifier).state = null;
        ref.read(selectedChannelTabProvider.notifier).state = 0;
        ref.read(selectedChatIdProvider.notifier).state = null;
        ref.read(selectedChatNameProvider.notifier).state = null;
        ref.read(selectedOperatorChannelsProvider.notifier).state = [];
        ref.read(replyingToProvider.notifier).state = null;
        setState(() { _channels = []; _loadingChannels = true; });
        _loadChannels();
      }
    });

    ref.listen<int>(channelStateVersionProvider, (prev, next) {
      if (prev != null && prev != next) _loadChannels();
    });

    final tab = ref.watch(selectedChannelTabProvider);
    final selectedChannelId = ref.watch(selectedChannelIdProvider);
    final channelUnread = ref.watch(channelUnreadProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Nivel 1 — Canal selector (solo si hay más de 1 canal)
        if (!_loadingChannels && _channels.length > 1)
          _ChannelSelectorBar(
            channels: _channels,
            selectedChannelId: selectedChannelId,
            channelUnread: channelUnread,
            onChannelSelected: (id) {
              final ch = _channels.firstWhere(
                (c) => (c['id'] as String?) == id,
                orElse: () => {},
              );
              ref.read(selectedChannelTypeProvider.notifier).state =
                  ch['channel_type'] as String?;
              ref.read(selectedChannelWorkerTypeProvider.notifier).state =
                  ch['worker_type'] as String?;
              ref.read(selectedChannelIdProvider.notifier).state = id;
              ref.read(selectedChannelTabProvider.notifier).state = 0;
              ref.read(selectedChatIdProvider.notifier).state = null;
              ref.read(selectedChatNameProvider.notifier).state = null;
              ref.read(selectedOperatorChannelsProvider.notifier).state = [];
              ref.read(selectedConvOperatorIdProvider.notifier).state = null;
              ref.read(replyingToProvider.notifier).state = null;
            },
          ),

        // Nivel 2 — Pill tab bar (Conversaciones / Feed global) + action buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
          child: Row(
            children: [
              _TabBar(selectedIndex: tab),
              const Spacer(),
              AppButton(
                label: '📢  Broadcast a todos',
                onPressed: () {
                  final channelId   = ref.read(selectedChannelIdProvider)   ?? '';
                  final channelType = ref.read(selectedChannelTypeProvider) ?? 'whatsapp';
                  _showBroadcastModal(context, channelId, channelType);
                },
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.sm,
              ),
              const SizedBox(width: 8),
              AppButton(
                label: '+ Nuevo mensaje',
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const _NewMessageDialog(),
                ),
                variant: AppButtonVariant.teal,
                size: AppButtonSize.sm,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Tab content
        Expanded(
          child: IndexedStack(
            index: tab,
            children: const [
              _TabOperador(),
              _TabFeed(),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Pill tab bar ──────────────────────────────────────────────────────────────

class _TabBar extends ConsumerWidget {
  const _TabBar({required this.selectedIndex});
  final int selectedIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.ctSurface2,
        borderRadius: BorderRadius.circular(9),
      ),
      child: IntrinsicWidth(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TabPill(
              label: 'Conversaciones',
              selected: selectedIndex == 0,
              onTap: () =>
                  ref.read(selectedChannelTabProvider.notifier).state = 0,
            ),
            const SizedBox(width: 2),
            _TabPill(
              label: 'Feed global',
              selected: selectedIndex == 1,
              onTap: () =>
                  ref.read(selectedChannelTabProvider.notifier).state = 1,
            ),
          ],
        ),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.ctSurface : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: AppTextStyles.body.copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? AppColors.ctText : AppColors.ctText2),
          ),
        ),
      ),
    );
  }
}

// ── Platform icon helper ───────────────────────────────────────────────────────

Widget _platformIcon(String? channelType) {
  final color = channelType == 'whatsapp'
      ? AppColors.ctWa
      : channelType == 'telegram'
          ? AppColors.ctTg
          : Colors.grey;
  final label = channelType == 'whatsapp'
      ? 'W'
      : channelType == 'telegram'
          ? 'T'
          : '?';
  return Container(
    width: 16,
    height: 16,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    alignment: Alignment.center,
    child: Text(
      label,
      style: AppTextStyles.caption.copyWith(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
    ),
  );
}

// ── Channel selector bar (Nivel 1) ────────────────────────────────────────────

class _ChannelSelectorBar extends StatelessWidget {
  const _ChannelSelectorBar({
    required this.channels,
    required this.selectedChannelId,
    required this.onChannelSelected,
    this.channelUnread = const {},
  });
  final List<Map<String, dynamic>> channels;
  final String? selectedChannelId;
  final ValueChanged<String> onChannelSelected;
  final Map<String, int> channelUnread;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: AppColors.ctSurface,
        border: Border(bottom: BorderSide(color: AppColors.ctBorder)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: channels.length,
        itemBuilder: (context, i) {
          final ch = channels[i];
          final chId = ch['id'] as String?;
          final isSelected = chId == selectedChannelId;
          final color = _hexColor(ch['color'] as String?);
          final label = ch['display_name'] as String? ?? 'Canal ${i + 1}';
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () { if (chId != null) onChannelSelected(chId); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.ctSurface : Colors.transparent,
                  border: isSelected
                      ? Border(bottom: BorderSide(color: color, width: 2))
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _platformIcon(ch['channel_type'] as String?),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: AppTextStyles.navItem.copyWith(fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500, color: isSelected ? AppColors.ctText : AppColors.ctText2),
                    ),
                    if (chId != null && (channelUnread[chId] ?? 0) > 0) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.ctTeal,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          (channelUnread[chId]! > 99)
                              ? '99+'
                              : '${channelUnread[chId]}',
                          style: AppTextStyles.badge.copyWith(color: AppColors.ctNavy),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Tab 1: Por operador ───────────────────────────────────────────────────────

class _TabOperador extends ConsumerWidget {
  const _TabOperador();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        _ConvoList(),
        VerticalDivider(width: 1, color: AppColors.ctBorder),
        Expanded(child: _ChatPanel()),
      ],
    );
  }
}

// ── Helpers de formato ────────────────────────────────────────────────────────


String _mediaFallback(String type) {
  switch (type) {
    case 'image': return '[📷 Imagen]';
    case 'audio': return '[🎤 Nota de voz]';
    case 'video': return '[🎥 Video]';
    case 'document': return '[📄 Documento]';
    case 'sticker': return '[😊 Sticker]';
    case 'location': return '[📍 Ubicación]';
    default: return '[📎 Archivo]';
  }
}


String _msgBody(Map<String, dynamic> msg) {
  final raw = msg['raw_body'] as String?;
  if (raw != null && raw.isNotEmpty) return raw;
  return _mediaFallback(msg['message_type'] as String? ?? '');
}

/// Resuelve el nombre a mostrar para mensajes outbound.
/// Usa from_name si está disponible; luego deriva del origin o sent_by_user_id.
String _outboundSenderName(Map<String, dynamic> msg) {
  final fromName = msg['from_name'] as String?;
  if (fromName != null && fromName.isNotEmpty) return fromName;
  final origin = msg['origin'] as String?;
  if (origin == 'ai_worker') return 'AI Worker';
  final sentByUserId = msg['sent_by_user_id'] as String?;
  if (sentByUserId != null && sentByUserId.isNotEmpty) return 'Agente';
  return 'Supervisor';
}

/// Devuelve el color del nombre y el badge de origen para mensajes outbound.
({Color nameColor, Widget? badge}) _outboundOriginStyle(
    Map<String, dynamic> msg) {
  final origin = msg['origin'] as String?;
  switch (origin) {
    case 'ai_worker':
      return (
        nameColor: AppColors.ctInfoText,
        badge: _OriginBadge(
          label: 'IA',
          bg: AppColors.ctInfoBg,
          fg: AppColors.ctInfoText,
        ),
      );
    case 'human':
      return (nameColor: AppColors.ctTealHover, badge: null);
    case 'external':
      return (
        nameColor: AppColors.ctText2,
        badge: _OriginBadge(
          label: 'Externo',
          bg: AppColors.ctSurface2,
          fg: AppColors.ctText2,
        ),
      );
    default:
      return (
        nameColor: AppColors.ctText2,
        badge: _OriginBadge(
          label: 'Sistema',
          bg: AppColors.ctSurface2,
          fg: AppColors.ctText2,
        ),
      );
  }
}

class _OriginBadge extends StatelessWidget {
  const _OriginBadge({required this.label, required this.bg, required this.fg});
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(fontSize: 9, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

Color _hexColor(String? hex) {
  try {
    final h = (hex ?? '#9CA3AF').replaceAll('#', '');
    if (h.length != 6) return AppColors.ctText3;
    return Color(int.parse('FF$h', radix: 16));
  } catch (_) {
    return AppColors.ctText3;
  }
}

IconData _mediaIcon(String mediaType) {
  switch (mediaType) {
    case 'image':    return Icons.image_outlined;
    case 'video':    return Icons.videocam_outlined;
    case 'audio':    return Icons.mic_outlined;
    case 'document': return Icons.attach_file_rounded;
    default:         return Icons.attach_file_rounded;
  }
}

String _mediaLabel(String mediaType) {
  switch (mediaType) {
    case 'image':    return 'Imagen';
    case 'video':    return 'Video';
    case 'audio':    return 'Audio';
    case 'document': return 'Archivo';
    default:         return 'Adjunto';
  }
}

// ── Avatar de operador con fallback a iniciales ───────────────────────────────

class _OperatorAvatar extends StatelessWidget {
  const _OperatorAvatar({
    required this.name,
    this.photoUrl,
    this.size = 40,
    // ignore: unused_element_parameter
    this.bgColor = AppColors.ctTealLight,
  });
  final String name;
  final String? photoUrl;
  final double size;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          photoUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildFallback(),
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : _buildFallback(),
        ),
      );
    }
    return _buildFallback();
  }

  Widget _buildFallback() {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : parts.isNotEmpty
            ? parts[0][0].toUpperCase()
            : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: AppTextStyles.body.copyWith(fontSize: size * 0.35, fontWeight: FontWeight.w600, color: AppColors.ctTealText),
      ),
    );
  }
}

// ── Lista de conversaciones (240px) ───────────────────────────────────────────

class _ConvoList extends ConsumerStatefulWidget {
  const _ConvoList();

  @override
  ConsumerState<_ConvoList> createState() => _ConvoListState();
}

class _ConvoListState extends ConsumerState<_ConvoList> {
  static final Map<String, DateTime> _lastReadAtCache = {};
  static final Map<String, DateTime> _preOpenLastRead = {};

  String _search = '';
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _archivedConvs = [];
  bool _showArchived = false;
  final Map<String, int> _unreadOverride = {};
  bool _loading = false;
  // TODO: consolidar streams — ConvoList y ChatPanel suscriben por separado
  StreamSubscription<Map<String, dynamic>>? _feedSub;
  DateTime? _feedHighWater;

  static DateTime? getLastReadSync(String chatId) => _lastReadAtCache[chatId];

  static Future<void> setLastRead(
      String chatId, DateTime time, String tenantId) async {
    _lastReadAtCache[chatId] = time;
    SupabaseReadReceipts.setLastRead(chatId, time, tenantId);
  }

  Future<void> _loadLastReadCache() async {
    final userId =
        Supabase.instance.client.auth.currentUser?.id ?? '';
    final tenantId = ref.read(activeTenantIdProvider);
    if (userId.isEmpty || tenantId.isEmpty) return;
    final data = await SupabaseReadReceipts.loadAll(
        userId: userId, tenantId: tenantId);
    _lastReadAtCache.addAll(data);
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _loadLastReadCache().then((_) {
      if (mounted) _fetchConversations();
    });
  }

  @override
  void dispose() {
    _feedSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchConversations({bool resubscribe = true}) async {
    final channelId = ref.read(selectedChannelIdProvider);
    if (channelId == null) return;
    setState(() => _loading = true);
    try {
      final tenantId = ref.read(activeTenantIdProvider);
      final wt = ref.read(selectedChannelWorkerTypeProvider);
      final isSales = wt == 'sales' || wt == 'custom';
      final convs = await ConversationsApi.listConversations(
        channelId: channelId,
        includeUnregistered: isSales,
      );
      if (mounted) {
        setState(() { _conversations = convs; _loading = false; });
        _updateChannelUnread();
        if (resubscribe) _subscribeToFeed(channelId, tenantId);
        _loadArchivedConvs();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadArchivedConvs() async {
    final channelId = ref.read(selectedChannelIdProvider);
    if (channelId == null) return;
    try {
      final all = await ConversationsApi.listConversations(
        channelId: channelId,
        includeUnregistered: true,
      );
      if (mounted) {
        setState(() {
          _archivedConvs =
              all.where((c) => c['operator_id'] == null && c['is_group'] != true).toList();
        });
      }
    } catch (_) {}
  }

  void _subscribeToFeed(String channelId, String tenantId) {
    _feedSub?.cancel();
    _feedHighWater = null;
    _feedSub = SupabaseMessages.streamIncomingMessages(
      channelId: channelId,
      tenantId: tenantId,
    ).listen(_onNewMessage);
  }

  void _onNewMessage(Map<String, dynamic> msg) {
    if (!mounted) return;

    final chatId = msg['chat_id'] as String?;
    if (chatId == null) return;

    // Guard against re-emitted old messages on WebSocket reconnect
    final receivedAt = DateTime.tryParse(msg['received_at'] as String? ?? '');
    if (receivedAt != null) {
      if (_feedHighWater != null && !receivedAt.isAfter(_feedHighWater!)) return;
      _feedHighWater = receivedAt;
    }

    final idx = _conversations.indexWhere((c) => c['chat_id'] == chatId);
    if (idx == -1) {
      // Conversation not yet in list — only case where refetch is allowed
      _fetchConversations(resubscribe: false);
      return;
    }

    final updated = Map<String, dynamic>.from(_conversations[idx]);

    // Build last_message in the shape _ApiConvoItem expects
    final msgType = msg['message_type'] as String? ?? 'text';
    final isMedia = msgType != 'text' && msgType.isNotEmpty;
    updated['last_message'] = {
      'body': isMedia ? null : (msg['raw_body'] as String? ?? ''),
      'media_type': isMedia ? msgType : null,
      'created_at': msg['received_at'],
    };

    final selectedChatId = ref.read(selectedChatIdProvider);
    final activeChannelId = ref.read(selectedChannelIdProvider);
    final msgChannelId = msg['channel_id'] as String?;

    // Message from a different channel (defensive — stream is scoped to active channel)
    if (msgChannelId != null && msgChannelId != activeChannelId) {
      final current = ref.read(channelUnreadProvider);
      ref.read(channelUnreadProvider.notifier).state = {
        ...current,
        msgChannelId: (current[msgChannelId] ?? 0) + 1,
      };
      return;
    }

    setState(() {
      if (selectedChatId != chatId) {
        final current = _unreadOverride[chatId]
            ?? (updated['unread_count'] as int? ?? 0);
        _unreadOverride[chatId] = current + 1;
      }
      _conversations.removeAt(idx);
      _conversations.insert(0, updated);
    });
    _updateChannelUnread();
  }

  void _updateChannelUnread() {
    final channelId = ref.read(selectedChannelIdProvider);
    if (channelId == null) return;
    int total = 0;
    for (final conv in _conversations) {
      final chatId = conv['chat_id'] as String? ?? '';
      total += _unreadOverride[chatId] ?? (conv['unread_count'] as int? ?? 0);
    }
    final current = ref.read(channelUnreadProvider);
    if (current[channelId] != total) {
      ref.read(channelUnreadProvider.notifier).state = {
        ...current,
        channelId: total,
      };
    }
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: TextField(
        onChanged: (v) => setState(() => _search = v),
        style: AppTextStyles.body,
        decoration: InputDecoration(
          hintText: 'Buscar conversación…',
          hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 16,
            color: AppColors.ctText3,
          ),
          filled: true,
          fillColor: AppColors.ctSurface2,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.ctBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.ctBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:
                const BorderSide(color: AppColors.ctTeal, width: 1.5),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Reinicia conversaciones cuando cambia el tenant
    ref.listen<String>(activeTenantIdProvider, (prev, next) {
      if (prev != null && prev != next) {
        setState(() {
          _conversations = [];
          _archivedConvs = [];
          _showArchived = false;
          _unreadOverride.clear();
        });
        _fetchConversations();
        ref.read(selectedChatIdProvider.notifier).state = null;
        ref.read(selectedChatNameProvider.notifier).state = null;
        ref.read(selectedConvPhotoUrlProvider.notifier).state = null;
        ref.read(channelUnreadProvider.notifier).state = const {};
        ref.read(selectedOperatorChannelsProvider.notifier).state = [];
        ref.read(selectedConvOperatorIdProvider.notifier).state = null;
        ref.read(selectedChannelIndexProvider.notifier).state = 0;
        ref.read(selectedChannelIdProvider.notifier).state = null;
        ref.read(replyingToProvider.notifier).state = null;
      }
    });
    // Recarga cuando cambia el estado de canales (activar/desactivar)
    ref.listen<int>(channelStateVersionProvider, (prev, next) {
      if (prev != null && prev != next) _fetchConversations();
    });
    // Recarga cuando cambia el canal seleccionado
    ref.listen<String?>(selectedChannelIdProvider, (prev, next) {
      if (prev != next) _fetchConversations();
    });

    final selectedChatId = ref.watch(selectedChatIdProvider);
    final workerType = ref.watch(selectedChannelWorkerTypeProvider);
    final isSalesChannel = workerType == 'sales' || workerType == 'custom';
    final filtered = _conversations.where((conv) {
      final chatIdVal = conv['chat_id'] as String?;
      if (chatIdVal == null || chatIdVal.isEmpty) return false;
      // Exclude unregistered — shown in archived panel below (only for operative channels)
      // Groups (is_group == true) are kept in the main list as normal conversations
      if (!isSalesChannel && conv['operator_id'] == null && conv['is_group'] != true) return false;
      final name = conv['display_name'] as String? ?? '';
      return name.toLowerCase().contains(_search.toLowerCase());
    }).toList();

    final channelId = ref.read(selectedChannelIdProvider) ?? '';

    return SizedBox(
      width: 240,
      child: Column(
        children: [
          _searchBar(),
          if (!isSalesChannel && _archivedConvs.isNotEmpty)
            _ArchivedEntryButton(
              count: _archivedConvs.length,
              expanded: _showArchived,
              onTap: () => setState(() => _showArchived = !_showArchived),
            ),
          if (!isSalesChannel && _showArchived && _archivedConvs.isNotEmpty)
            _ArchivedPanel(
              convs: _archivedConvs,
              channelId: channelId,
              onRefresh: _fetchConversations,
            ),
          if (_loading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_conversations.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'Sin conversaciones',
                  style: AppTextStyles.navItem.copyWith(color: AppColors.ctText3),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final conv       = filtered[i];
                  final chatId     = conv['chat_id'] as String? ?? '';
                  final isGroup    = conv['is_group'] as bool? ?? false;
                  final groupName  = conv['group_display_name'] as String?;
                  final name       = (isGroup && groupName != null)
                      ? groupName
                      : (conv['display_name'] as String? ?? chatId);
                  final photoUrl   = conv['profile_picture_url'] as String?;
                  final lastMsg    = conv['last_message'] as Map<String, dynamic>?;
                  final body       = lastMsg?['body'] as String?;
                  final mediaType  = lastMsg?['media_type'] as String?;
                  final createdAt  = lastMsg?['created_at'] as String?;
                  final unread     = _unreadOverride[chatId]
                      ?? (conv['unread_count'] as int? ?? 0);
                  // Use backend-provided window_open; fallback true is
                  // conservative (non-WA channels have no 24h restriction).
                  final windowOpen = conv['window_open'] as bool? ?? true;
                  return _ApiConvoItem(
                    name: name,
                    isGroup: isGroup,
                    photoUrl: photoUrl,
                    preview: mediaType != null
                        ? null
                        : (body?.isNotEmpty == true ? body! : 'Sin mensajes'),
                    mediaType: mediaType,
                    time: fmtTime(createdAt, fallback: ''),
                    isToday: isToday(createdAt),
                    isSelected: chatId == selectedChatId,
                    unreadCount: unread,
                    isWindowOpen: windowOpen,
                    onTap: () {
                      final prev = getLastReadSync(chatId);
                      if (prev != null) {
                        _preOpenLastRead[chatId] = prev;
                      } else {
                        _preOpenLastRead.remove(chatId);
                      }
                      setLastRead(chatId, DateTime.now().toUtc(),
                          ref.read(activeTenantIdProvider));
                      setState(() { _unreadOverride[chatId] = 0; });
                      final chatOverrides = Map<String, int>.from(
                          ref.read(_chatReadOverrideProvider));
                      chatOverrides[chatId] = 0;
                      ref.read(_chatReadOverrideProvider.notifier).state =
                          chatOverrides;
                      _updateChannelUnread();
                      // Mark all inbound messages as panel-read on the server
                      final channelId = ref.read(selectedChannelIdProvider) ?? '';
                      if (channelId.isNotEmpty) {
                        ConversationsApi.markChatRead(
                          chatId: chatId,
                          channelId: channelId,
                        );
                      }
                      // read-receipts dispatched in _ChatPanelState._sendReadReceipts
                      ref.read(selectedChatIdProvider.notifier).state = chatId;
                      ref.read(selectedChatNameProvider.notifier).state = name;
                      ref.read(selectedConvPhotoUrlProvider.notifier).state = photoUrl;
                      ref.read(selectedOperatorChannelsProvider.notifier).state = [];
                      ref.read(selectedConvOperatorIdProvider.notifier).state =
                          conv['operator_id'] as String?;
                      ref.read(selectedChannelIndexProvider.notifier).state = 0;
                      ref.read(replyingToProvider.notifier).state = null;
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── Botón entrada a archivadas ────────────────────────────────────────────────

class _ArchivedEntryButton extends StatelessWidget {
  const _ArchivedEntryButton({
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 14,
              color: AppColors.ctText3,
            ),
            const SizedBox(width: 4),
            Text(
              '$count archivada${count == 1 ? '' : 's'}',
              style: AppTextStyles.navItem.copyWith(color: AppColors.ctText3),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Panel de conversaciones archivadas (inline colapsable) ────────────────────

class _ArchivedPanel extends ConsumerStatefulWidget {
  const _ArchivedPanel({
    required this.convs,
    required this.channelId,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> convs;
  final String channelId;
  final VoidCallback onRefresh;

  @override
  ConsumerState<_ArchivedPanel> createState() => _ArchivedPanelState();
}

class _ArchivedPanelState extends ConsumerState<_ArchivedPanel> {
  List<Map<String, dynamic>> _operators = [];
  bool _loadingOps = false;

  Future<void> _ensureOperators() async {
    if (_operators.isNotEmpty || _loadingOps) return;
    setState(() => _loadingOps = true);
    try {
      final ops = await OperatorsApi.listOperators();
      if (mounted) setState(() { _operators = ops; _loadingOps = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingOps = false);
    }
  }

  Future<void> _assignOperator(Map<String, dynamic> conv) async {
    await _ensureOperators();
    if (!mounted) return;
    final chatId = conv['chat_id'] as String? ?? '';
    final operatorId = await showDialog<String>(
      context: context,
      builder: (_) => _AssignOperatorDialog(operators: _operators),
    );
    if (operatorId == null || !mounted) return;
    try {
      await ConversationsApi.assignConversationOperator(
        chatId: chatId,
        channelId: widget.channelId,
        operatorId: operatorId,
      );
      if (mounted) widget.onRefresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al asignar: $e')),
      );
    }
  }

  Future<void> _deleteConversation(Map<String, dynamic> conv) async {
    final chatId = conv['chat_id'] as String? ?? '';
    final name   = conv['display_name'] as String? ?? chatId;

    final confirm1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.ctSurface,
        title: Text(
          '¿Eliminar conversación?',
          style: AppTextStyles.cardTitle.copyWith(fontSize: 15),
        ),
        content: Text(
          'Se eliminarán permanentemente todos los mensajes de "$name" '
          'en este canal. Esta acción no se puede deshacer.',
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
            label: 'Continuar',
            onPressed: () => Navigator.pop(ctx, true),
            variant: AppButtonVariant.danger,
            size: AppButtonSize.sm,
          ),
        ],
      ),
    );
    if (confirm1 != true || !mounted) return;

    final confirm2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.ctSurface,
        title: Text(
          'Confirmar eliminación definitiva',
          style: AppTextStyles.cardTitle.copyWith(fontSize: 15),
        ),
        content: Text(
          '¿Seguro que deseas eliminar todos los mensajes de "$name"? '
          'Esta operación es irreversible.',
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
            label: 'Eliminar definitivamente',
            onPressed: () => Navigator.pop(ctx, true),
            variant: AppButtonVariant.danger,
            size: AppButtonSize.sm,
          ),
        ],
      ),
    );
    if (confirm2 != true || !mounted) return;

    try {
      await ConversationsApi.deleteUnregisteredConversation(
        fromPhone: chatId,
        channelId: widget.channelId,
      );
      if (mounted) widget.onRefresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al eliminar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(userRoleProvider).valueOrNull?.toLowerCase();
    final isAdmin = role == 'admin' || role == 'super_admin';
    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: const BoxDecoration(
        color: AppColors.ctSurface2,
        border: Border.symmetric(
          horizontal: BorderSide(color: AppColors.ctBorder),
        ),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: widget.convs.length,
        separatorBuilder: (context, i) =>
            const Divider(color: AppColors.ctBorder, height: 1),
        itemBuilder: (context, i) {
          final conv    = widget.convs[i];
          final chatId  = conv['chat_id']      as String? ?? '';
          final name    = conv['display_name'] as String? ?? chatId;
          final lastMsg = conv['last_message'] as Map<String, dynamic>?;
          final body    = lastMsg?['body']      as String?;
          final at      = lastMsg?['created_at'] as String?;
          return Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: AppTextStyles.formLabel,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      fmtTime(at, fallback: ''),
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
                if (body != null && body.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    body,
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    _ArchivedAction(
                      label: 'Asignar',
                      color: AppColors.ctTeal,
                      onTap: () => _assignOperator(conv),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(width: 8),
                      _ArchivedAction(
                        label: 'Eliminar',
                        color: AppColors.ctDanger,
                        onTap: () => _deleteConversation(conv),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ArchivedAction extends StatelessWidget {
  const _ArchivedAction({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w500, color: color),
        ),
      ),
    );
  }
}

// ── Diálogo selector de operador ──────────────────────────────────────────────

class _AssignOperatorDialog extends StatefulWidget {
  const _AssignOperatorDialog({required this.operators});

  final List<Map<String, dynamic>> operators;

  @override
  State<_AssignOperatorDialog> createState() => _AssignOperatorDialogState();
}

class _AssignOperatorDialogState extends State<_AssignOperatorDialog> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.operators.where((op) {
      final name = (op['display_name'] ?? op['name'] ?? '').toString().toLowerCase();
      return name.contains(_search.toLowerCase());
    }).toList();

    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Asignar operador',
                style: AppFonts.onest(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ctText,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _search = v),
                style: AppTextStyles.body,
                decoration: InputDecoration(
                  hintText: 'Buscar operador…',
                  hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                  prefixIcon: const Icon(
                    Icons.search_rounded, size: 16, color: AppColors.ctText3,
                  ),
                  filled: true,
                  fillColor: AppColors.ctSurface2,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.ctBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.ctBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: AppColors.ctTeal, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Sin operadores',
                        style: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final op   = filtered[i];
                        final id   = op['id']            as String? ?? '';
                        final name = (op['display_name'] ?? op['name'] ?? id).toString();
                        final photoUrl = op['photo_url'] as String?;
                        return ListTile(
                          dense: true,
                          leading: OperatorAvatar(
                            name: name,
                            photoUrl: photoUrl,
                            size: 36,
                          ),
                          title: Text(
                            name,
                            style: AppTextStyles.body,
                          ),
                          onTap: () => Navigator.pop(context, id),
                        );
                      },
                    ),
            ),
            const Divider(color: AppColors.ctBorder, height: 1),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: AppButton(
                  label: 'Cancelar',
                  onPressed: () => Navigator.pop(context),
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Item de conversación (modo API) ───────────────────────────────────────────

class _ApiConvoItem extends StatefulWidget {
  const _ApiConvoItem({
    required this.name,
    required this.time,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
    this.photoUrl,
    this.preview,
    this.mediaType,
    this.unreadCount = 0,
    this.isWindowOpen = true,
    this.isGroup = false,
  });
  final String name;
  final String? photoUrl;
  final String? preview;
  final String? mediaType;
  final String time;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;
  final int unreadCount;
  final bool isWindowOpen;
  final bool isGroup;

  @override
  State<_ApiConvoItem> createState() => _ApiConvoItemState();
}

class _ApiConvoItemState extends State<_ApiConvoItem> {
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
          duration: const Duration(milliseconds: 100),
          height: 64,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? AppColors.ctTealLight
                : _hovered
                    ? AppColors.ctSurface2
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: widget.isSelected
                ? const Border(
                    left: BorderSide(color: AppColors.ctTeal, width: 2),
                  )
                : null,
          ),
          child: Row(
            children: [
              // Avatar + status dot
              Stack(
                children: [
                  if (widget.isGroup)
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.ctNavy.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.groups, size: 16, color: AppColors.ctNavy),
                    )
                  else
                    _OperatorAvatar(name: widget.name, photoUrl: widget.photoUrl, size: 32),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: widget.isWindowOpen
                            ? AppColors.ctOk
                            : AppColors.ctText3,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 9),
              // Nombre + preview
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.name,
                            style: AppTextStyles.navItem.copyWith(fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w500, color: AppColors.ctText),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          widget.time,
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: widget.mediaType != null
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _mediaIcon(widget.mediaType!),
                                      size: 11,
                                      color: AppColors.ctText2,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      _mediaLabel(widget.mediaType!),
                                      style: AppTextStyles.bodySmall,
                                    ),
                                  ],
                                )
                              : Text(
                                  widget.preview ?? 'Sin mensajes',
                                  style: AppTextStyles.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                        ),
                        const SizedBox(width: 4),
                        if (widget.unreadCount > 0)
                          Container(
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(
                                minWidth: 18, minHeight: 18),
                            decoration: const BoxDecoration(
                              color: AppColors.ctTeal,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              widget.unreadCount > 99
                                  ? '99+'
                                  : '${widget.unreadCount}',
                              style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ctNavy),
                              textAlign: TextAlign.center,
                            ),
                          )
                        else
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: widget.isToday
                                  ? const Color(0xFF22C55E)
                                  : AppColors.ctText3,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Panel de chat ─────────────────────────────────────────────────────────────

class _ChatPanel extends ConsumerStatefulWidget {
  const _ChatPanel();

  @override
  ConsumerState<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends ConsumerState<_ChatPanel>
    with WidgetsBindingObserver {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<Map<String, dynamic>> _apiMessages = [];
  bool _msgLoading = false;
  bool? _windowOpen; // null = cargando, true = abierta, false = cerrada
  bool _streamError = false;
  bool _sending = false;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  String? _firstUnreadMessageId;
  final _firstUnreadKey = GlobalKey();
  final Set<String> _processedReadIds = {};
  // Optimistic reactions keyed by wa_message_id of the target message
  final Map<String, List<String>> _pendingReactions = {};

  // Pagination state
  bool _isLoadingOlder = false;
  bool _hasMoreMessages = true;
  DateTime? _oldestLoadedAt;

  // Multimedia
  bool _isDragOver = false;
  StreamSubscription? _pasteSub;

  // Voice recording
  bool _isRecording = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  html.MediaRecorder? _mediaRecorder;
  html.MediaStream? _micStream;
  final List<html.Blob> _recordingChunks = [];
  String _recordingMimeType = 'audio/webm';

  // Track current subscribed chatId to avoid re-subscribing on web tab focus
  String? _subscribedChatId;

  // Supervisor mode — true after user explicitly taps "Intervenir"
  bool _isSupervisorMode = false;

  // Auto-scroll state
  bool _atBottom = true;       // true mientras el usuario esté cerca del fondo
  bool _hasNewMessage = false; // badge "↓ Nuevo mensaje" visible


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pasteSub = html.document.onPaste.listen(_handleDocumentPaste);
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    // reverse: true → pixels == 0 is the visual bottom (most recent messages).
    final nearBottom = pos.pixels <= 100;
    if (nearBottom != _atBottom) setState(() => _atBottom = nearBottom);
    if (nearBottom && _hasNewMessage) setState(() => _hasNewMessage = false);
    // reverse: true → maxScrollExtent == visual top (oldest messages).
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _loadOlderMessages();
    }
  }

  String _chatFormatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(dt.year, dt.month, dt.day);
    if (d == today) return 'Hoy';
    if (d == yesterday) return 'Ayer';
    const months = [
      '', 'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    return '${dt.day} ${months[dt.month]} ${dt.year}';
  }

  Widget _chatDateSepChip(String label) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.ctSurface2,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: AppTextStyles.bodySmall,
          ),
        ),
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chatId = ref.read(selectedChatIdProvider);
    final tenantId = ref.read(activeTenantIdProvider);
    // Require tenantId to be loaded before subscribing; otherwise the
    // stream would have no tenant filter and deliver cross-tenant messages.
    if (chatId != null && tenantId.isNotEmpty && _apiMessages.isEmpty && !_msgLoading) {
      _subscribeToMessages(chatId);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final chatId = ref.read(selectedChatIdProvider);
      // Only re-subscribe if chatId changed — on web, 'resumed' fires on every
      // tab focus/blur which would spam read receipts if we always re-subscribe.
      if (chatId != null && chatId != _subscribedChatId) {
        _subscribeToMessages(chatId);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _pasteSub?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToFirstUnread() {
    // With reverse: true, position 0 == visual bottom (most recent).
    // No unread → the list already opens at position 0 (bottom), nothing to do.
    if (_firstUnreadMessageId == null) return;

    if (!_scrollCtrl.hasClients) return;

    // Try to scroll to the separator via GlobalKey.
    // Called from inside a postFrameCallback, so the widget should already be
    // in the tree — ensureVisible is instantaneous (Duration.zero).
    final ctx = _firstUnreadKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.0,
        duration: Duration.zero,
      );
    }
  }

  String? _activeChannelId() {
    return ref.read(selectedChannelIdProvider);
  }

  Future<void> _sendReadReceipts(List<Map<String, dynamic>> messages) async {
    final tenantId = ref.read(activeTenantIdProvider);
    if (tenantId.isEmpty) {
      debugPrint('[markRead] SKIP — tenantId empty');
      return;
    }
    // Find the last inbound message that is valid and not yet processed.
    // WhatsApp marks all prior messages as read when the latest one is marked.
    // messages is ordered ascending by received_at from the stream.
    ({String waId, String channelId})? last;
    for (final msg in messages) {
      if ((msg['direction'] as String?) == 'outbound') continue;

      // Only process messages that belong to the active tenant.
      final msgTenantId = msg['tenant_id'] as String?;
      if (msgTenantId != tenantId) continue;

      final waId = msg['wa_message_id'] as String?;
      if (waId == null || waId.isEmpty || waId == 'null') continue;
      if (!waId.startsWith('wamid.')) continue;
      if (_processedReadIds.contains(waId)) continue;

      final channelId = msg['channel_id'] as String? ?? '';
      if (channelId.isEmpty) continue;

      last = (waId: waId, channelId: channelId);
    }

    if (last == null) return;

    // Mark the single most-recent unread inbound; add before the await to
    // block any concurrent emit from enqueuing the same wamid.
    _processedReadIds.add(last.waId);
    if (!mounted) return;
    await MessagesApi.markRead(last.waId, tenantId: tenantId, channelId: last.channelId);
  }

  void _handleTyping() {
    final tenantId = ref.read(activeTenantIdProvider);
    if (tenantId.isEmpty) return;
    final lastInbound = _apiMessages
        .lastWhere(
          (m) => (m['direction'] as String?) != 'outbound' &&
              (m['wa_message_id'] as String?) != null &&
              (m['wa_message_id'] as String?)!.isNotEmpty,
          orElse: () => {},
        );
    final waId = lastInbound['wa_message_id'] as String?;
    if (waId == null || waId.isEmpty || waId == 'null') return;
    final channelId = lastInbound['channel_id'] as String? ?? '';
    if (channelId.isEmpty) {
      debugPrint('[_handleTyping] SKIP — no channel_id');
      return;
    }
    MessagesApi.sendTyping(waId, tenantId: tenantId, channelId: channelId); // fire-and-forget
  }

  Future<void> _sendReaction(
      Map<String, dynamic> msg, String emoji) async {
    final chatId = ref.read(selectedChatIdProvider) ?? '';
    final channelId = msg['channel_id'] as String? ?? '';
    if (channelId.isEmpty) {
      debugPrint('[_sendReaction] SKIP — no channel_id');
      return;
    }
    final sentByUserId = Supabase.instance.client.auth.currentUser?.id;
    final channelType = ref.read(selectedChannelTypeProvider) ?? 'whatsapp';

    // Optimistic key: wa_message_id for WA, msg id for Telegram
    final waId = msg['wa_message_id'] as String?;
    final optimisticKey = waId?.isNotEmpty == true
        ? waId!
        : (msg['id'] as String? ?? '');
    if (optimisticKey.isNotEmpty && mounted) {
      setState(() {
        final existing = _pendingReactions.putIfAbsent(optimisticKey, () => []);
        if (!existing.contains(emoji)) existing.add(emoji);
      });
    }

    try {
      if (channelType == 'telegram') {
        final rawPayload = msg['raw_payload'];
        Map<String, dynamic> payload = {};
        if (rawPayload is String) {
          try { payload = json.decode(rawPayload) as Map<String, dynamic>; } catch (_) {}
        } else if (rawPayload is Map) {
          payload = Map<String, dynamic>.from(rawPayload);
        }
        final tgMessageId = payload['message_id'];
        if (tgMessageId == null) {
          debugPrint('[_sendReaction] SKIP — no message_id in raw_payload');
          if (mounted) setState(() => _pendingReactions[optimisticKey]?.remove(emoji));
          return;
        }
        final toChatId = int.tryParse(chatId);
        if (toChatId == null) {
          debugPrint('[_sendReaction] SKIP — chatId not parseable as int: $chatId');
          if (mounted) setState(() => _pendingReactions[optimisticKey]?.remove(emoji));
          return;
        }
        await MessagesApi.sendTelegramReaction(
          channelId: channelId,
          toChatId: toChatId,
          messageId: tgMessageId is int
              ? tgMessageId
              : int.parse(tgMessageId.toString()),
          emoji: emoji,
          sentByUserId: sentByUserId,
        );
      } else {
        // WhatsApp — comportamiento original
        if (waId == null || waId.isEmpty) {
          if (mounted) setState(() => _pendingReactions[optimisticKey]?.remove(emoji));
          return;
        }
        await MessagesApi.sendReaction(
          messageId: waId,
          emoji: emoji,
          toPhone: chatId,
          channelId: channelId,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _pendingReactions[optimisticKey]?.remove(emoji));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al enviar reacción: $e'),
          backgroundColor: AppColors.ctDanger,
          duration: const Duration(seconds: 3),
        ));
      }
    }
  }

  // ── Multimedia ──────────────────────────────────────────────────────────────

  void _handleDocumentPaste(html.ClipboardEvent event) {
    try {
      final items = event.clipboardData?.items;
      if (items == null) return;
      final len = items.length ?? 0;
      for (var i = 0; i < len; i++) {
        final item = items[i];
        final type = item.type ?? '';
        if (type.startsWith('image/')) {
          final file = item.getAsFile();
          if (file == null) return;
          event.preventDefault();
          final reader = html.FileReader();
          reader.readAsArrayBuffer(file);
          reader.onLoadEnd.listen((_) {
            try {
              final result = reader.result;
              Uint8List? bytes;
              if (result is Uint8List) {
                bytes = result;
              } else if (result is ByteBuffer) {
                bytes = result.asUint8List();
              }
              if (bytes != null && mounted) {
                final name = 'clipboard_image_${DateTime.now().millisecondsSinceEpoch}.png';
                _openPreviewModal(bytes, name);
              }
            } catch (_) {}
          });
          break;
        }
      }
    } catch (_) {}
  }

  Future<void> _pickFile(String type) async {
    try {
      FilePickerResult? result;
      if (type == 'image') {
        result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      } else if (type == 'audio') {
        result = await FilePicker.platform.pickFiles(type: FileType.audio, withData: true);
      } else {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt'],
          withData: true,
        );
      }
      if (result == null) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return;
      if (mounted) _openPreviewModal(bytes, file.name);
    } catch (_) {}
  }

  void _openPreviewModal(Uint8List bytes, String filename, {int? audioDuration}) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) => _MediaPreviewDialog(
        bytes: bytes,
        filename: filename,
        audioDuration: audioDuration,
        onSend: (caption) {
          // Use dialog's own context so the barrier closes immediately
          Navigator.of(dialogContext).pop();
          _sendMedia(bytes, filename, caption);
        },
      ),
    );
  }

  Future<void> _sendMedia(Uint8List bytes, String filename, String? caption) async {
    final chatId = ref.read(selectedChatIdProvider) ?? '';
    if (chatId.isEmpty) return;
    final channelId = _activeChannelId() ?? '';
    if (channelId.isEmpty) {
      debugPrint('[_sendMedia] SKIP — no channelId');
      return;
    }
    final userId = Supabase.instance.client.auth.currentUser?.id;

    final replyTo = ref.read(replyingToProvider);
    ref.read(replyingToProvider.notifier).state = null;
    final isTelegram = ref.read(selectedChannelTypeProvider) == 'telegram';
    final replyId = (replyTo != null && isTelegram)
        ? replyTo['id'] as String?
        : null;

    if (mounted) setState(() { _sending = true; _isDragOver = false; });
    try {
      await MessagesApi.sendMedia(
        to: chatId,
        fileBytes: bytes,
        filename: filename,
        channelId: channelId,
        caption: caption,
        sentByUserId: userId,
        replyToMessageId: replyId,
      );
      if (mounted) setState(() { _sending = false; _isDragOver = false; });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() { _sending = false; _isDragOver = false; });
      final String errorMsg = _dioErrorMessage(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(errorMsg),
        backgroundColor: AppColors.ctDanger,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() { _sending = false; _isDragOver = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error al enviar archivo: $e'),
        backgroundColor: AppColors.ctDanger,
      ));
    }
  }

  /// Extrae un mensaje legible de un [DioException] sin usar ! en datos opcionales.
  String _dioErrorMessage(DioException e) {
    final response = e.response;
    if (response == null) {
      // Timeout, sin conexión, etc.
      return 'Error de conexión al enviar archivo';
    }
    final data = response.data;
    if (data is Map) {
      final detail = data['detail'];
      if (detail != null) return 'Error: $detail';
    }
    final status = response.statusCode;
    if (status == 415) return 'Formato de archivo no soportado por WhatsApp';
    if (status != null) return 'Error $status al enviar archivo';
    return 'Error desconocido al enviar archivo';
  }

  void _handleAttach(String type) {
    switch (type) {
      case 'image':
      case 'doc':
        _pickFile(type);
        break;
      case 'location-request':
        _sendLocationRequest();
        break;
    }
  }

  Future<void> _sendLocationRequest() async {
    final chatId = ref.read(selectedChatIdProvider) ?? '';
    if (chatId.isEmpty) return;
    final channelId = _activeChannelId() ?? '';
    if (channelId.isEmpty) {
      debugPrint('[_sendLocationRequest] SKIP — no channelId');
      return;
    }
    final userId = Supabase.instance.client.auth.currentUser?.id;
    try {
      await MessagesApi.sendLocationRequest(
        to: chatId,
        channelId: channelId,
        sentByUserId: userId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Solicitud de ubicación enviada'),
          backgroundColor: AppColors.ctOk,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('❌ Error al enviar solicitud'),
          backgroundColor: AppColors.ctDanger,
        ));
      }
    }
  }

  /// Picks the first MIME type the browser's MediaRecorder actually accepts.
  /// The MediaRecorder constructor throws NotSupportedError for unsupported
  /// types, so we probe by construction and discard the test instance.
  String _pickRecorderMimeType(html.MediaStream stream) {
    for (final mime in const [
      'audio/ogg;codecs=opus',       // Firefox — Meta acepta
      'audio/mp4;codecs=mp4a.40.2',  // Chrome AAC — Meta acepta
      'audio/mp4',                    // mp4 genérico
      'audio/webm;codecs=opus',       // último recurso — Meta no acepta webm
    ]) {
      try {
        html.MediaRecorder(stream, {'mimeType': mime}); // throws if unsupported
        return mime;
      } catch (_) {}
    }
    return 'audio/mp4'; // fallback: mp4 sobre webm
  }

  Future<void> _startVoiceRecording() async {
    try {
      final stream = await html.window.navigator.mediaDevices!
          .getUserMedia({'audio': true, 'video': false});
      _micStream = stream;
      _recordingChunks.clear();
      final mimeType = _pickRecorderMimeType(stream);
      _recordingMimeType = mimeType;
      final recorder = html.MediaRecorder(stream, {'mimeType': mimeType});
      _mediaRecorder = recorder;
      recorder.addEventListener('dataavailable', (html.Event event) {
        try {
          // ignore: avoid_dynamic_calls
          final data = (event as dynamic).data;
          if (data == null) return;
          final blob = data as html.Blob;
          if (blob.size > 0) _recordingChunks.add(blob);
        } catch (_) {}
      });
      recorder.start();
      if (mounted) {
        setState(() {
          _isRecording = true;
          _recordingSeconds = 0;
        });
      }
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordingSeconds++);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo acceder al micrófono: $e'),
          backgroundColor: AppColors.ctDanger,
        ));
      }
    }
  }

  Future<void> _stopVoiceRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    final recorder = _mediaRecorder;
    if (recorder == null) return;

    final stopCompleter = Completer<void>();
    recorder.addEventListener('stop', (html.Event _) {
      if (!stopCompleter.isCompleted) stopCompleter.complete();
    });
    recorder.stop();
    _micStream?.getTracks().forEach((t) => t.stop());
    if (mounted) setState(() => _isRecording = false);

    await stopCompleter.future;

    if (_recordingChunks.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se capturó audio. Intenta de nuevo.'),
          backgroundColor: AppColors.ctDanger,
        ));
      }
      return;
    }

    try {
      final mimeType = _recordingMimeType;
      final blob = html.Blob(_recordingChunks, mimeType);

      if (blob.size == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se capturó audio. Intenta de nuevo.'),
            backgroundColor: AppColors.ctDanger,
          ));
        }
        return;
      }

      final fileReader = html.FileReader();
      final readCompleter = Completer<Uint8List>();

      fileReader.onLoad.listen((_) {
        try {
          final result = fileReader.result;
          Uint8List bytes;
          if (result is ByteBuffer) {
            bytes = result.asUint8List();
          } else if (result is Uint8List) {
            bytes = result;
          } else {
            // Last resort for environments where result wraps a raw JS ArrayBuffer
            // ignore: avoid_dynamic_calls
            bytes = (result as dynamic).asUint8List() as Uint8List;
          }
          if (!readCompleter.isCompleted) readCompleter.complete(bytes);
        } catch (e) {
          if (!readCompleter.isCompleted) readCompleter.completeError(e);
        }
      });
      fileReader.onError.listen((_) {
        if (!readCompleter.isCompleted) {
          readCompleter.completeError('FileReader error');
        }
      });

      fileReader.readAsArrayBuffer(blob);
      final bytes = await readCompleter.future;

      if (bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se capturó audio. Intenta de nuevo.'),
            backgroundColor: AppColors.ctDanger,
          ));
        }
        return;
      }

      final ext = mimeType.contains('ogg') ? 'ogg' : mimeType.contains('mp4') ? 'mp4' : 'webm';
      await _sendMedia(bytes, 'voice_note.$ext', null);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al procesar audio: $e'),
          backgroundColor: AppColors.ctDanger,
        ));
      }
    }
  }

  void _cancelVoiceRecording() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _mediaRecorder?.stop();
    _micStream?.getTracks().forEach((t) => t.stop());
    _recordingChunks.clear();
    if (mounted) setState(() => _isRecording = false);
  }

  Widget _buildDragOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: AppColors.ctTeal.withValues(alpha: 0.2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.arrow_downward_rounded, size: 52, color: AppColors.ctTeal),
              const SizedBox(height: 12),
              Text(
                'Suelta para adjuntar',
                style: AppTextStyles.body.copyWith(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ctTeal),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _subscribeToMessages(String chatId) async {
    _subscription?.cancel();
    _subscribedChatId = chatId;
    _processedReadIds.clear();
    _pendingReactions.clear();
    setState(() {
      _msgLoading = true;
      _apiMessages = [];
      _firstUnreadMessageId = null;
      _windowOpen = null;
      _isSupervisorMode = false;
      _atBottom = true;
      _hasNewMessage = false;
      _streamError = false;
      _isLoadingOlder = false;
      _hasMoreMessages = true;
      _oldestLoadedAt = null;
    });

    final tenantId = ref.read(activeTenantIdProvider);
    final effectiveTenantId = tenantId.isNotEmpty ? tenantId : null;

    // ── Fetch inicial: 50 mensajes más recientes ──
    try {
      final recent = await SupabaseMessages.getMessages(
        chatId,
        limit: 50,
        tenantId: effectiveTenantId,
        ascending: false, // DESC → most recent first
      );
      if (!mounted) return;
      // Reverse to ASC (oldest → newest) for display
      final messages = recent.reversed.toList();

      // Determine first unread
      final lastRead = _ConvoListState._preOpenLastRead[chatId];
      if (lastRead != null) {
        for (final msg in messages) {
          if ((msg['direction'] as String?) == 'outbound') continue;
          final receivedAt =
              DateTime.tryParse(msg['received_at'] as String? ?? '');
          if (receivedAt != null && receivedAt.isAfter(lastRead)) {
            _firstUnreadMessageId = msg['id'] as String?;
            break;
          }
        }
      }

      // Track oldest loaded timestamp for pagination
      if (messages.isNotEmpty) {
        _oldestLoadedAt = DateTime.tryParse(
            messages.first['received_at'] as String? ?? '');
      }
      if (recent.length < 50) _hasMoreMessages = false;

      // Compute window state
      final lastInbound = messages
          .where((m) => (m['direction'] as String?) != 'outbound')
          .lastOrNull;
      final receivedAt = lastInbound != null
          ? DateTime.tryParse(lastInbound['received_at'] as String? ?? '')
          : null;
      final channelType = ref.read(selectedChannelTypeProvider);
      final operatorId  = ref.read(selectedConvOperatorIdProvider);
      final hasRecentInbound = receivedAt != null &&
          DateTime.now().toUtc().difference(receivedAt.toUtc()).inHours < 24;
      final computed = operatorId == null
          ? true
          : (channelType != 'whatsapp') || hasRecentInbound;

      _ConvoListState.setLastRead(
          chatId, DateTime.now().toUtc(), ref.read(activeTenantIdProvider));

      setState(() {
        _apiMessages = messages;
        _msgLoading = false;
        _windowOpen = computed;
        _streamError = false;
      });
      _sendReadReceipts(messages);

      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToFirstUnread());
    } catch (_) {
      if (!mounted) return;
      setState(() { _msgLoading = false; _streamError = true; });
      return;
    }

    // ── Suscripción a inserts en tiempo real ──
    _subscription = SupabaseMessages.streamNewMessages(
      chatId,
      tenantId: effectiveTenantId,
    ).listen((newMsg) {
      if (!mounted) return;
      final id = newMsg['id'] as String?;
      // Dedup: skip if already in list
      if (id != null && _apiMessages.any((m) => m['id'] == id)) return;

      // Update window state
      if ((newMsg['direction'] as String?) != 'outbound') {
        final ra = DateTime.tryParse(newMsg['received_at'] as String? ?? '');
        if (ra != null) {
          final channelType = ref.read(selectedChannelTypeProvider);
          final operatorId  = ref.read(selectedConvOperatorIdProvider);
          final fresh = DateTime.now().toUtc().difference(ra.toUtc()).inHours < 24;
          final computed = operatorId == null
              ? true
              : (channelType != 'whatsapp') || fresh;
          _windowOpen = computed;
        }
      }

      _ConvoListState.setLastRead(
          chatId, DateTime.now().toUtc(), ref.read(activeTenantIdProvider));

      setState(() {
        _apiMessages = [..._apiMessages, newMsg];
      });
      _sendReadReceipts([newMsg]);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollCtrl.hasClients) return;
        if (_atBottom) {
          _scrollCtrl.jumpTo(0);
        } else {
          setState(() => _hasNewMessage = true);
        }
      });
    }, onError: (_) {
      // Stream error doesn't affect already-loaded messages
    });
  }

  Future<void> _loadOlderMessages() async {
    if (_isLoadingOlder || !_hasMoreMessages) return;
    final chatId = _subscribedChatId;
    if (chatId == null || _oldestLoadedAt == null) return;

    setState(() => _isLoadingOlder = true);
    try {
      final tenantId = ref.read(activeTenantIdProvider);
      final older = await SupabaseMessages.getMessages(
        chatId,
        limit: 50,
        tenantId: tenantId.isNotEmpty ? tenantId : null,
        before: _oldestLoadedAt,
        ascending: false, // DESC → most recent of the older batch first
      );
      if (!mounted) return;
      if (older.isEmpty) {
        setState(() {
          _hasMoreMessages = false;
          _isLoadingOlder = false;
        });
        return;
      }
      // Reverse to ASC, then prepend
      final batch = older.reversed.toList();
      // Dedup by id
      final existingIds = _apiMessages.map((m) => m['id']).toSet();
      final unique = batch.where((m) => !existingIds.contains(m['id'])).toList();

      if (unique.isNotEmpty) {
        _oldestLoadedAt = DateTime.tryParse(
            unique.first['received_at'] as String? ?? '');
      }
      if (older.length < 50) _hasMoreMessages = false;

      setState(() {
        _apiMessages = [...unique, ..._apiMessages];
        _isLoadingOlder = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingOlder = false);
    }
  }

  bool _isGoogleMapsUrl(String text) {
    final lower = text.toLowerCase();
    return lower.contains('maps.google.com') ||
        lower.contains('google.com/maps') ||
        lower.contains('goo.gl/maps') ||
        lower.contains('maps.app.goo.gl');
  }

  Color _channelSendColor(String? channelType) {
    if (channelType == 'whatsapp') return AppColors.ctWa;
    if (channelType == 'telegram') return AppColors.ctTg;
    return AppColors.ctTeal;
  }

  Future<void> _intervene() async {
    final chatId = ref.read(selectedChatIdProvider);
    if (chatId == null) return;
    setState(() => _isSupervisorMode = true);
    try {
      final sessionId = await SessionsApi.findActiveSessionId(chatId: chatId);
      if (sessionId != null) {
        await SessionsApi.patchStatus(sessionId: sessionId, status: 'supervisor');
      }
    } catch (_) {
      // best-effort — supervisor mode is already enabled locally
    }
  }

  Future<void> _stopIntervening() async {
    final chatId = ref.read(selectedChatIdProvider);
    if (chatId == null) return;
    setState(() => _isSupervisorMode = false);
    try {
      final sessionId = await SessionsApi.findActiveSessionId(chatId: chatId);
      if (sessionId != null) {
        await SessionsApi.patchStatus(sessionId: sessionId, status: 'worker');
      }
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;

    final chatId = ref.read(selectedChatIdProvider) ?? '';
    if (chatId.isEmpty) return;

    final tenantId = ref.read(activeTenantIdProvider);
    if (tenantId.isEmpty) return;

    final channelId = _activeChannelId() ?? '';
    if (channelId.isEmpty) {
      debugPrint('[_sendMessage] SKIP — no channelId');
      return;
    }

    // Auto-detect Google Maps URLs
    if (_isGoogleMapsUrl(text)) {
      _msgCtrl.clear();
      setState(() => _sending = true);
      try {
        await MessagesApi.sendLocation(
          to: chatId,
          channelId: channelId,
          googleMapsUrl: text,
          sentByUserId: Supabase.instance.client.auth.currentUser?.id,
        );
        if (mounted) {
          setState(() => _sending = false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scrollCtrl.hasClients) return;
            _scrollCtrl.jumpTo(0); // reverse: true → 0 == visual bottom
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ Ubicación enviada'),
            backgroundColor: AppColors.ctOk,
          ));
        }
      } on DioException catch (e) {
        if (mounted) {
          setState(() => _sending = false);
          final isInvalid = e.response?.statusCode == 400;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(isInvalid ? '❌ URL de Google Maps no válida' : '❌ Error al enviar ubicación'),
            backgroundColor: AppColors.ctDanger,
          ));
        }
      } catch (e) {
        if (mounted) {
          setState(() => _sending = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('❌ Error al enviar ubicación'),
            backgroundColor: AppColors.ctDanger,
          ));
        }
      }
      return;
    }

    final replyTo = ref.read(replyingToProvider);
    ref.read(replyingToProvider.notifier).state = null;

    _msgCtrl.clear();
    setState(() => _sending = true);

    final isTelegram = ref.read(selectedChannelTypeProvider) == 'telegram';
    final replyId = replyTo == null
        ? null
        : isTelegram
            ? replyTo['id'] as String?
            : replyTo['wa_message_id'] as String?;

    try {
      await MessagesApi.sendWhatsAppMessage(
          to: chatId,
          text: text,
          channelId: channelId,
          sentByUserId: Supabase.instance.client.auth.currentUser?.id,
          replyToMessageId: replyId);
      if (mounted) {
        setState(() => _sending = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollCtrl.hasClients) return;
          _scrollCtrl.jumpTo(0); // reverse: true → 0 == visual bottom
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        final String msg;
        if (e.response?.statusCode == 422) {
          final data = e.response?.data;
          final detail = data is Map ? data['detail']?.toString() : null;
          msg = detail?.isNotEmpty == true
              ? detail!
              : 'No se pudo enviar el mensaje. Verifica la configuración del canal.';
        } else {
          msg = 'Error al enviar: ${e.message ?? e.toString()}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.ctDanger,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar: $e'),
            backgroundColor: AppColors.ctDanger,
          ),
        );
      }
    }
  }

  Widget _buildMessageBubble(
    Map<String, dynamic> msg, {
    required Map<String, List<String>> reactionsMap,
  }) {
    final direction = msg['direction'] as String? ?? 'inbound';
    final isOutbound = direction == 'outbound';
    final msgId = msg['id'] as String? ?? '';
    final msgWaId = msg['wa_message_id'] as String?;

    // Resolve reply context
    final contextMsgId = msg['context_message_id'] as String?;
    String? contextFrom;
    String? contextBody;
    if (contextMsgId != null && contextMsgId.isNotEmpty) {
      final ref_ = _apiMessages.cast<Map<String, dynamic>?>().firstWhere(
            (m) =>
                (m!['wa_message_id'] as String?) == contextMsgId ||
                (m['id'] as String?) == contextMsgId,
            orElse: () => null,
          );
      if (ref_ != null) {
        // Bug 2 fix: resolve display name from original message
        final refIsOutbound = (ref_['direction'] as String?) == 'outbound';
        contextFrom = refIsOutbound
            ? _outboundSenderName(ref_)
            : (ref_['from_name'] as String? ??
                ref_['from_phone'] as String? ?? '');
        // Bug 3 & 4 fix: media-aware preview
        final refType = ref_['message_type'] as String?;
        final refBody = ref_['raw_body'] as String? ?? '';
        if (refBody.isNotEmpty) {
          contextBody = refBody;
        } else {
          contextBody = switch (refType) {
            'image'    => '📷 Imagen',
            'video'    => '🎥 Video',
            'document' => '📄 Documento',
            'audio'    => '🎵 Audio',
            'location' => '📍 Ubicación',
            _          => null,
          };
        }
      } else {
        // Original not found: fall back to raw context_from (phone) as name
        contextFrom = msg['context_from'] as String?;
        contextBody = null; // → "Mensaje citado"
      }
    }

    // Reactions for this message: keyed by wa_message_id or id
    final msgReactions = reactionsMap[msgWaId ?? msgId] ??
        reactionsMap[msgId] ??
        const <String>[];

    final originStyle = isOutbound ? _outboundOriginStyle(msg) : null;

    // "Sin operador" badge for unregistered inbound with no assigned operator
    final isUnregisteredNoOp = !isOutbound &&
        (msg['unregistered'] as bool? ?? false) &&
        msg['operator_id'] == null;
    final inboundBadge = isUnregisteredNoOp
        ? _OriginBadge(label: 'Sin operador', bg: AppColors.ctSurface2, fg: AppColors.ctText2)
        : null;

    return _ApiMessageBubble(
      key: ValueKey(msgId),
      body: _msgBody(msg),
      time: fmtTime(msg['received_at'] as String?, fallback: ''),
      senderName: isOutbound
          ? _outboundSenderName(msg)
          : (msg['from_name'] as String? ??
              msg['from_phone'] as String? ?? ''),
      isOutbound: isOutbound,
      origin: msg['origin'] as String?,
      channelType: ref.read(selectedChannelTypeProvider),
      waStatus: msg['wa_status'] as String?,
      messageType: msg['message_type'] as String?,
      mediaUrl: msg['media_url'] as String?,
      hasContext: contextMsgId != null && contextMsgId.isNotEmpty,
      contextFrom: contextFrom,
      contextBody: contextBody,
      reactions: msgReactions,
      onReply: () =>
          ref.read(replyingToProvider.notifier).state = msg,
      onReact: (emoji) => _sendReaction(msg, emoji),
      senderNameColor: originStyle?.nameColor,
      senderBadge: originStyle?.badge ?? inboundBadge,
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.chat_bubble_outline_rounded,
            size: 48,
            color: AppColors.ctText3,
          ),
          const SizedBox(height: 12),
          Text(
            'Selecciona una conversación',
            style: AppTextStyles.body.copyWith(color: AppColors.ctText3),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatId = ref.watch(selectedChatIdProvider);
    final chatName = ref.watch(selectedChatNameProvider);

    ref.listen<String?>(selectedChatIdProvider, (prev, next) {
      if (next != null && next != prev) _subscribeToMessages(next);
    });

    // If the tenant was not loaded when didChangeDependencies first ran,
    // subscribe now that we have a valid tenantId.
    ref.listen<String>(activeTenantIdProvider, (prev, next) {
      if (next.isNotEmpty && prev != next) {
        final cid = ref.read(selectedChatIdProvider);
        // Re-subscribe only if we have no active subscription yet (or the
        // existing one was created without tenant filtering).
        if (cid != null && cid != _subscribedChatId) {
          _subscribeToMessages(cid);
        }
      }
    });

    if (chatId == null) return _emptyState();

    final channels       = ref.watch(selectedOperatorChannelsProvider);
    final activeChannelId = ref.watch(selectedChannelIdProvider);
    final activeChannel   = channels
        .where((c) => (c['channel_id'] as String?) == activeChannelId)
        .firstOrNull;

    final channelFiltered = activeChannelId != null
        ? _apiMessages.where((m) {
            final msgChannelId = m['channel_id'] as String?;
            return msgChannelId == null || msgChannelId == activeChannelId;
          }).toList()
        : List<Map<String, dynamic>>.from(_apiMessages);

    // Build reactions map (keyed by reaction_message_id) and filter out
    // reaction-type messages from the display list.
    final reactionsMap = <String, List<String>>{};
    for (final m in channelFiltered) {
      if ((m['message_type'] as String?) == 'reaction') {
        final targetId = m['reaction_message_id'] as String?;
        final emoji = m['reaction_emoji'] as String?;
        if (targetId != null && targetId.isNotEmpty &&
            emoji != null && emoji.isNotEmpty) {
          (reactionsMap[targetId] ??= []).add(emoji);
        }
      }
    }
    // Merge pending (optimistic) reactions, avoiding duplicates.
    for (final entry in _pendingReactions.entries) {
      final existing = reactionsMap.putIfAbsent(entry.key, () => []);
      for (final e in entry.value) {
        if (!existing.contains(e)) existing.add(e);
      }
    }
    final visibleMessages = channelFiltered
        .where((m) => (m['message_type'] as String?) != 'reaction')
        .toList();

    final replyingTo = ref.watch(replyingToProvider);

    final channelType = ref.read(selectedChannelTypeProvider);
    final isWhatsapp = (channelType ?? 'whatsapp') == 'whatsapp';
    final String inputHint;
    if (!_isSupervisorMode) {
      inputHint = 'Toca "Intervenir" para escribir';
    } else if (isWhatsapp && _windowOpen == false) {
      inputHint = 'Ventana de 24h cerrada · Usa una plantilla';
    } else {
      inputHint = 'Escribe un mensaje…';
    }

    final body = Column(
      children: [
        // Header
        _ApiChatHeader(
          name: chatName ?? chatId,
          windowOpen: _windowOpen,
          photoUrl: ref.watch(selectedConvPhotoUrlProvider),
          channelType: channelType,
          channelName: activeChannel?['name'] as String?,
          workerName: activeChannel?['worker_name'] as String?,
          channelColor: activeChannel?['color'] as String?,
          onIntervene: hasPermission(ref, 'conversations', 'send')
              ? (!_isSupervisorMode ? _intervene : _stopIntervening)
              : null,
          isSupervisorMode: _isSupervisorMode,
          operatorId: ref.watch(selectedConvOperatorIdProvider),
          tenantId: ref.read(activeTenantIdProvider),
        ),

        // Mensajes
        if (_msgLoading)
          const Expanded(
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_streamError)
          Expanded(
            child: ColoredBox(
              color: const Color(0xFFEBEBE9),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded,
                        size: 40, color: AppColors.ctText3),
                    const SizedBox(height: 12),
                    Text(
                      'No se pudieron cargar los mensajes',
                      style: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      label: 'Reintentar',
                      onPressed: () => _subscribeToMessages(chatId),
                      variant: AppButtonVariant.outline,
                      size: AppButtonSize.sm,
                      prefixIcon: const Icon(Icons.refresh_rounded, size: 14, color: AppColors.ctTeal),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ColoredBox(
              color: const Color(0xFFEBEBE9),
              child: Builder(builder: (context) {
                // Group messages by day for StickyHeader (ascending order).
                final groups =
                    <({String label, List<Map<String, dynamic>> msgs})>[];
                DateTime? lastDay;
                for (final msg in visibleMessages) {
                  final iso = msg['received_at'] as String?;
                  DateTime? dt;
                  if (iso != null) dt = DateTime.tryParse(iso)?.toLocal();
                  if (dt != null) {
                    final day = DateTime(dt.year, dt.month, dt.day);
                    if (lastDay == null || day != lastDay) {
                      groups.add((label: _chatFormatDate(dt), msgs: []));
                      lastDay = day;
                    }
                  } else if (groups.isEmpty) {
                    groups.add((label: '', msgs: []));
                  }
                  if (groups.isNotEmpty) groups.last.msgs.add(msg);
                }
                // With reverse: true, index 0 == visual bottom. Reverse the
                // groups so the most-recent day group is at index 0 (bottom).
                final displayGroups = groups.reversed.toList();

                // Extra item at visual top for loading spinner
                final hasLoader = _isLoadingOlder || _hasMoreMessages;
                final totalItems = displayGroups.length + (hasLoader ? 1 : 0);

                return ListView.builder(
                  controller: _scrollCtrl,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  itemCount: totalItems,
                  itemBuilder: (context, i) {
                    // Last index in reverse == visual top → loading indicator
                    if (i == displayGroups.length && hasLoader) {
                      return _isLoadingOlder
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.ctTeal,
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink();
                    }
                    final group = displayGroups[i];
                    return StickyHeader(
                      header: _chatDateSepChip(group.label),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: group.msgs.map((msg) {
                          final msgId = msg['id'] as String?;
                          final isFirstUnread = msgId != null &&
                              msgId == _firstUnreadMessageId;

                          if (isFirstUnread) {
                            return Column(
                              key: _firstUnreadKey,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12),
                                  child: Row(
                                    children: [
                                      const Expanded(
                                        child: Divider(
                                          color: AppColors.ctTeal,
                                          thickness: 0.5,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10),
                                        child: Text(
                                          'Mensajes nuevos',
                                          style: AppTextStyles.badge.copyWith(color: AppColors.ctTeal),
                                        ),
                                      ),
                                      const Expanded(
                                        child: Divider(
                                          color: AppColors.ctTeal,
                                          thickness: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _buildMessageBubble(msg,
                                    reactionsMap: reactionsMap),
                              ],
                            );
                          }
                          return _buildMessageBubble(msg,
                              reactionsMap: reactionsMap);
                        }).toList(),
                      ),
                    );
                  },
                );
              }),
            ),
          ),

        // Banner ventana cerrada (solo WhatsApp, supervisor mode activo)
        if (_isSupervisorMode && isWhatsapp && _windowOpen == false)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppColors.ctWarnBg,
            child: Row(
              children: [
                const Icon(Icons.timer_outlined,
                    size: 18, color: AppColors.ctWarnText),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Ventana de 24h cerrada. Solo puedes enviar mensajes con plantilla aprobada.',
                    style: AppTextStyles.navItem.copyWith(color: AppColors.ctWarnText),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () {
                    final chId  = ref.read(selectedChannelIdProvider)   ?? '';
                    final chTyp = ref.read(selectedChannelTypeProvider) ?? 'whatsapp';
                    _showBroadcastModal(context, chId, chTyp);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.ctWarnText,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Usar plantilla →',
                      style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Reply bar (shown when replying to a message)
        if (replyingTo != null)
          _ReplyBar(
            message: replyingTo,
            onDismiss: () =>
                ref.read(replyingToProvider.notifier).state = null,
          ),

        // Badge "Nuevo mensaje"
        if (_hasNewMessage)
          GestureDetector(
            onTap: () {
              if (_scrollCtrl.hasClients) {
                // reverse: true → 0 == visual bottom (most recent messages)
                _scrollCtrl.animateTo(
                  0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              }
              setState(() => _hasNewMessage = false);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              color: AppColors.ctTeal.withValues(alpha: 0.12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.arrow_downward_rounded,
                      size: 13, color: AppColors.ctTealDark),
                  const SizedBox(width: 6),
                  Text(
                    'Nuevo mensaje',
                    style: AppTextStyles.formLabel.copyWith(color: AppColors.ctTealDark),
                  ),
                ],
              ),
            ),
          ),

        // Input (hidden when WA window is closed and supervisor is active — banner shown instead)
        if (!(_isSupervisorMode && isWhatsapp && _windowOpen == false))
          _ChatInput(
            controller: _msgCtrl,
            onSend: (_windowOpen == true && _isSupervisorMode) ? _sendMessage : null,
            onTyping: (_windowOpen == true && _isSupervisorMode) ? _handleTyping : null,
            sending: _sending,
            enabled: _windowOpen == true && _isSupervisorMode,
            hintText: inputHint,
            onAttach: _handleAttach,
            onMic: (_windowOpen == true && _isSupervisorMode) ? _startVoiceRecording : null,
            isRecording: _isRecording,
            recordingSeconds: _recordingSeconds,
            onStop: _stopVoiceRecording,
            onCancel: _cancelVoiceRecording,
            sendColor: _channelSendColor(channelType),
          ),
      ],
    );

    return DropTarget(
      onDragDone: (details) {
        if (details.files.isEmpty) return;
        final file = details.files.first;
        file.readAsBytes().then((bytes) {
          if (mounted) _openPreviewModal(bytes, file.name);
        });
        setState(() => _isDragOver = false);
      },
      onDragEntered: (_) => setState(() => _isDragOver = true),
      onDragExited: (_) => setState(() => _isDragOver = false),
      child: Stack(
        children: [
          body,
          if (_isDragOver) _buildDragOverlay(),
        ],
      ),
    );
  }
}

// ── Intervene button ──────────────────────────────────────────────────────────

class _InterveneButton extends StatefulWidget {
  const _InterveneButton({required this.onTap, this.isSupervisorMode = false});
  final VoidCallback onTap;
  final bool isSupervisorMode;

  @override
  State<_InterveneButton> createState() => _InterveneButtonState();
}

class _InterveneButtonState extends State<_InterveneButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isSupervisorMode;
    final borderColor = isActive ? AppColors.ctTeal : const Color(0xFFFB923C);
    final normalBg  = isActive ? AppColors.ctTealLight : const Color(0xFFFFF7ED);
    final hoverBg   = isActive
        ? AppColors.ctTeal.withValues(alpha: 0.2)
        : const Color(0xFFFED7AA);
    final iconColor = isActive ? AppColors.ctTealDark : const Color(0xFFEA580C);
    final label = isActive ? 'Dejar de intervenir' : 'Intervenir';
    final icon = isActive ? Icons.stop_circle_outlined : Icons.pan_tool_outlined;

    return Tooltip(
      message: isActive
          ? 'Devolver el control al AI Worker'
          : 'Tomar control de la conversación para responder manualmente',
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 600),
      decoration: BoxDecoration(
        color: AppColors.ctNavy,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: AppTextStyles.bodySmall.copyWith(color: Colors.white),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _hovered ? hoverBg : normalBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: iconColor),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppTextStyles.navItem.copyWith(fontWeight: FontWeight.w600, color: iconColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Header de chat (modo API) ─────────────────────────────────────────────────

class _ApiChatHeader extends StatelessWidget {
  const _ApiChatHeader({
    required this.name,
    required this.windowOpen,
    this.photoUrl,
    this.channelType,
    this.channelName,
    this.workerName,
    this.channelColor,
    this.onIntervene,
    this.isSupervisorMode = false,
    this.operatorId,
    this.tenantId,
  });
  final String name;
  final bool? windowOpen;
  final String? photoUrl;
  final String? channelType;
  final String? channelName;
  final String? workerName;
  final String? channelColor;
  final VoidCallback? onIntervene;
  final bool isSupervisorMode;
  final String? operatorId;
  final String? tenantId;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AppColors.ctSurface,
        border: Border(bottom: BorderSide(color: AppColors.ctBorder)),
      ),
      child: Row(
        children: [
          _OperatorAvatar(name: name, photoUrl: photoUrl, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (windowOpen != null && channelType == 'whatsapp')
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: windowOpen!
                              ? AppColors.ctOkBg
                              : AppColors.ctSurface2,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          windowOpen! ? 'Ventana abierta' : 'Ventana cerrada',
                          style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w500, color: windowOpen! ? AppColors.ctOkText : AppColors.ctText3),
                        ),
                      ),
                  ],
                ),
                Text(
                  channelName != null
                      ? '$channelName${workerName != null ? ' · $workerName' : ''}'
                      // TODO: show operator flow chips here when flows are
                      // available in the conversation object (currently not
                      // returned by /conversations — would require extra request).
                      : 'Sin flujos asignados',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
          if (operatorId != null &&
              operatorId!.isNotEmpty &&
              tenantId != null &&
              tenantId!.isNotEmpty) ...[
            const SizedBox(width: 8),
            _ActiveFlowPill(
              operatorId: operatorId!,
              tenantId: tenantId!,
            ),
          ],
          if (onIntervene != null) ...[
            const SizedBox(width: 12),
            _InterveneButton(onTap: onIntervene!, isSupervisorMode: isSupervisorMode),
          ],
        ],
      ),
    );
  }
}

// ── _ActiveFlowPill ───────────────────────────────────────────────────────────

class _ActiveFlowPill extends StatefulWidget {
  const _ActiveFlowPill({
    required this.operatorId,
    required this.tenantId,
  });
  final String operatorId;
  final String tenantId;

  @override
  State<_ActiveFlowPill> createState() => _ActiveFlowPillState();
}

class _ActiveFlowPillState extends State<_ActiveFlowPill> {
  Map<String, dynamic>? _activeFlow;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _fetch());
  }

  @override
  void didUpdateWidget(_ActiveFlowPill old) {
    super.didUpdateWidget(old);
    if (old.operatorId != widget.operatorId ||
        old.tenantId != widget.tenantId) {
      _fetch();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (!mounted) return;
    try {
      final flow = await FlowsApi.getActiveFlow(
        operatorId: widget.operatorId,
      );
      if (!mounted) return;
      setState(() => _activeFlow = flow);
    } catch (_) {
      // Silently ignore — pill simply stays hidden on error
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = _activeFlow;
    if (flow == null) return const SizedBox.shrink();

    final flowName = flow['flow_name'] as String? ??
        flow['flow_slug'] as String? ??
        'Flow activo';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.ctTealLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.ctTeal),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.ctTeal,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            flowName,
            style: AppTextStyles.formLabel.copyWith(color: AppColors.ctTeal),
          ),
        ],
      ),
    );
  }
}

// ── Burbuja de mensaje (modo API) ─────────────────────────────────────────────

class _ApiMessageBubble extends StatefulWidget {
  const _ApiMessageBubble({
    super.key,
    required this.body,
    required this.time,
    required this.senderName,
    required this.isOutbound,
    this.origin,
    this.channelType,
    this.waStatus,
    this.messageType,
    this.mediaUrl,
    this.hasContext = false,
    this.contextFrom,
    this.contextBody,
    this.reactions = const [],
    this.onReply,
    this.onReact,
    this.senderNameColor,
    this.senderBadge,
  });
  final String body;
  final String time;
  final String senderName;
  final bool isOutbound;
  final String? origin;
  final String? channelType;
  final Color? senderNameColor;
  final Widget? senderBadge;
  final String? waStatus;
  final String? messageType;
  final String? mediaUrl;
  // Reply context
  final bool hasContext;
  final String? contextFrom;
  final String? contextBody;
  // Reactions
  final List<String> reactions;
  final VoidCallback? onReply;
  final void Function(String emoji)? onReact;

  @override
  State<_ApiMessageBubble> createState() => _ApiMessageBubbleState();
}

class _ApiMessageBubbleState extends State<_ApiMessageBubble> {
  double _swipeDx = 0;

  static final Set<String> _registeredMediaViews = {};

  void _onDragUpdate(DragUpdateDetails d) {
    if (d.delta.dx > 0 && widget.onReply != null) {
      setState(() =>
          _swipeDx = (_swipeDx + d.delta.dx).clamp(0.0, 64.0));
    }
  }

  void _onDragEnd(DragEndDetails d) {
    final triggered = _swipeDx >= 50;
    setState(() => _swipeDx = 0);
    if (triggered) widget.onReply?.call();
  }

  void _showEmojiPicker() {
    if (widget.onReact == null && widget.onReply == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmojiPickerSheet(
        onEmoji: (emoji) {
          Navigator.pop(context);
          widget.onReact?.call(emoji);
        },
        onReply: widget.onReply != null
            ? () {
                Navigator.pop(context);
                widget.onReply!();
              }
            : null,
      ),
    );
  }

  Widget _buildQuote() {
    final isOut = widget.isOutbound;
    final name = (widget.contextFrom?.isNotEmpty == true)
        ? widget.contextFrom!
        : 'Mensaje citado';
    final raw = widget.contextBody ?? '';
    final preview = raw.isNotEmpty
        ? (raw.length > 80 ? '${raw.substring(0, 80)}…' : raw)
        : 'Mensaje citado';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isOut
            ? Colors.white.withValues(alpha: 0.5)
            : const Color(0xFFE4E8EA),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(
            width: 3,
            color: isOut
                ? AppColors.ctTeal
                : AppColors.ctText3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: AppTextStyles.badge.copyWith(color: AppColors.ctTeal),
          ),
          const SizedBox(height: 2),
          Text(
            preview,
            style: AppTextStyles.bodySmall.copyWith(color: const Color(0xFF667781)),
          ),
        ],
      ),
    );
  }

  Widget _buildReactionPills() {
    if (widget.reactions.isEmpty) return const SizedBox.shrink();
    final counts = <String, int>{};
    for (final e in widget.reactions) {
      counts[e] = (counts[e] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        children: counts.entries
            .map((entry) => Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    entry.value > 1
                        ? '${entry.key} ${entry.value}'
                        : entry.key,
                    style: AppTextStyles.body.copyWith(fontSize: 12),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _fallback(String label) => Text(
        label,
        style: AppTextStyles.body.copyWith(color: const Color(0xFF667781)),
      );

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildImageContent() {
    final mUrl = (widget.mediaUrl?.isNotEmpty == true) ? widget.mediaUrl! : null;
    if (mUrl == null) return _fallback('[Imagen]');
    final caption =
        (widget.body.isNotEmpty && !widget.body.startsWith('[')) ? widget.body : null;

    final thumbnail = GestureDetector(
      onTap: () => showDialog(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => MediaPreviewDialog(url: mUrl),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            Image.network(
              mUrl,
              width: 240,
              height: 180,
              fit: BoxFit.cover,
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                return Container(
                  width: 240,
                  height: 180,
                  color: AppColors.ctSurface2,
                );
              },
              errorBuilder: (ctx, e, s) => Container(
                width: 240,
                height: 180,
                color: AppColors.ctSurface2,
                child: const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 32,
                    color: AppColors.ctText3,
                  ),
                ),
              ),
            ),
            // Timestamp overlay — bottom-right corner
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(6),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.time,
                      style: AppTextStyles.caption.copyWith(color: Colors.white),
                    ),
                    if (widget.isOutbound) ...[
                      const SizedBox(width: 3),
                      _statusIcon(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        thumbnail,
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              caption,
              style: AppTextStyles.body.copyWith(color: const Color(0xFF111B21), height: 1.4),
            ),
          ),
      ],
    );
  }

  Widget _buildAudioContent() {
    final mUrl = (widget.mediaUrl?.isNotEmpty == true) ? widget.mediaUrl! : null;
    if (mUrl == null) return _fallback('[Audio]');
    final audioViewId = 'audio-${mUrl.hashCode}';
    if (!_registeredMediaViews.contains(audioViewId)) {
      _registeredMediaViews.add(audioViewId);
      ui_web.platformViewRegistry.registerViewFactory(
        audioViewId,
        (int id) {
          final audio = html.AudioElement()
            ..controls = true
            ..style.width = '220px'
            ..style.outline = 'none'
            ..style.display = 'block';
          audio.append(html.SourceElement()
            ..src = mUrl
            ..type = 'audio/ogg');
          audio.append(html.SourceElement()
            ..src = mUrl
            ..type = 'audio/mpeg');
          return audio;
        },
      );
    }
    return SizedBox(
      width: 220,
      height: 54,
      child: HtmlElementView(viewType: audioViewId),
    );
  }

  Widget _buildVideoContent() {
    final mUrl = (widget.mediaUrl?.isNotEmpty == true) ? widget.mediaUrl! : null;
    if (mUrl == null) return _fallback('[Video]');
    final videoViewId = 'video-${mUrl.hashCode}';
    if (!_registeredMediaViews.contains(videoViewId)) {
      _registeredMediaViews.add(videoViewId);
      ui_web.platformViewRegistry.registerViewFactory(
        videoViewId,
        (int id) {
          final video = html.VideoElement()
            ..controls = true
            ..style.width = '240px'
            ..style.height = '135px'
            ..style.borderRadius = '8px'
            ..style.background = '#000'
            ..style.outline = 'none'
            ..style.display = 'block';
          video.append(html.SourceElement()
            ..src = mUrl
            ..type = 'video/mp4');
          return video;
        },
      );
    }
    final caption =
        (widget.body.isNotEmpty && !widget.body.startsWith('[')) ? widget.body : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 240,
          height: 135,
          child: HtmlElementView(viewType: videoViewId),
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              caption,
              style: AppTextStyles.body.copyWith(color: const Color(0xFF111B21), height: 1.4),
            ),
          ),
      ],
    );
  }

  Widget _buildDocumentContent() {
    final mUrl = (widget.mediaUrl?.isNotEmpty == true) ? widget.mediaUrl! : null;
    if (mUrl == null) return _fallback('[Documento]');
    final fileName = Uri.parse(mUrl).pathSegments.lastOrNull ?? 'Documento';
    final caption =
        (widget.body.isNotEmpty && !widget.body.startsWith('[')) ? widget.body : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file, size: 24, color: Color(0xFF667781)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(fileName,
                  style: AppTextStyles.navItem.copyWith(color: const Color(0xFF111B21)),
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _openUrl(mUrl),
              child: Text('Abrir',
                  style: AppTextStyles.navItem.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFF53BDEB))),
            ),
          ],
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              caption,
              style: AppTextStyles.body.copyWith(color: const Color(0xFF111B21), height: 1.4),
            ),
          ),
      ],
    );
  }

  Widget _buildStickerContent() {
    final mUrl = (widget.mediaUrl?.isNotEmpty == true) ? widget.mediaUrl! : null;
    if (mUrl == null) return _fallback('[Sticker]');
    return Image.network(
      mUrl,
      width: 120,
      height: 120,
      fit: BoxFit.contain,
      errorBuilder: (ctx, e, s) => _fallback('[Sticker]'),
    );
  }

  Widget _buildLocationContent() {
    Map<String, dynamic>? locData;
    try {
      locData = jsonDecode(widget.body) as Map<String, dynamic>;
    } catch (_) {}
    final locName = locData?['name'] as String? ??
        locData?['address'] as String? ??
        'Ubicación compartida';
    final lat = locData?['latitude']?.toString() ?? '';
    final lng = locData?['longitude']?.toString() ?? '';
    final mapsUrl = (lat.isNotEmpty && lng.isNotEmpty)
        ? 'https://maps.google.com/?q=$lat,$lng'
        : 'https://maps.google.com/';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on, color: Colors.red, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(locName,
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFF111B21))),
            ),
          ],
        ),
        if (lat.isNotEmpty && lng.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 24),
            child: Text('$lat, $lng',
                style: AppTextStyles.bodySmall.copyWith(color: const Color(0xFF667781))),
          ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => _openUrl(mapsUrl),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF53BDEB).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('Ver en mapa',
                style: AppTextStyles.navItem.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFF53BDEB))),
          ),
        ),
      ],
    );
  }

  Widget _buildTextContent({Color textColor = const Color(0xFF111B21)}) {
    return Text(
      widget.body,
      style: AppTextStyles.body.copyWith(color: textColor, height: 1.4),
    );
  }

  Widget _statusIcon() {
    switch (widget.waStatus) {
      case 'read':
        return const Icon(Icons.done_all,
            size: 12, color: Color(0xFF53BDEB));
      case 'delivered':
        return const Icon(Icons.done_all,
            size: 12, color: Color(0xFF667781));
      case 'sent':
        return const Icon(Icons.check,
            size: 12, color: Color(0xFF667781));
      case 'failed':
        return const Icon(Icons.error_outline,
            size: 12, color: Colors.red);
      default:
        return const Icon(Icons.check,
            size: 12, color: Color(0xFF667781));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSticker = widget.messageType == 'sticker';
    final isOutbound = widget.isOutbound;
    final origin = widget.origin;
    final channelType = widget.channelType ?? 'whatsapp';
    final isHuman = origin == 'human';
    final Color bubbleBg;
    if (isSticker) {
      bubbleBg = Colors.transparent;
    } else if (!isOutbound) {
      bubbleBg = Colors.white;
    } else if (isHuman) {
      bubbleBg = AppColors.ctNavy;
    } else if (channelType == 'telegram') {
      bubbleBg = AppColors.ctInfoBg;
    } else {
      bubbleBg = AppColors.waBubbleAi;
    }
    final Color bubbleTextColor = (isOutbound && isHuman)
        ? Colors.white
        : const Color(0xFF111B21);
    final Color timeColor = (isOutbound && isHuman)
        ? Colors.white.withValues(alpha: 0.5)
        : const Color(0xFF667781);

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bubbleBg,
        borderRadius: isOutbound
            ? const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(2),
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              )
            : const BorderRadius.only(
                topLeft: Radius.circular(2),
                topRight: Radius.circular(12),
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
      ),
      child: Column(
        crossAxisAlignment: isOutbound
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (widget.hasContext) _buildQuote(),
          if (widget.senderName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.senderName,
                    style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600, color: widget.senderNameColor ?? timeColor),
                  ),
                  if (widget.senderBadge != null) ...[
                    const SizedBox(width: 4),
                    widget.senderBadge!,
                  ],
                ],
              ),
            ),
          if (widget.messageType == 'image')   _buildImageContent(),
          if (widget.messageType == 'video')   _buildVideoContent(),
          if (widget.messageType == 'audio')   _buildAudioContent(),
          if (widget.messageType == 'document') _buildDocumentContent(),
          if (widget.messageType == 'sticker') _buildStickerContent(),
          if (widget.messageType == 'location') _buildLocationContent(),
          if (!const ['image', 'video', 'audio', 'document', 'sticker', 'location']
              .contains(widget.messageType))
            _buildTextContent(textColor: bubbleTextColor),
          // Timestamp is rendered inside the image overlay for image messages
          // with a valid media_url; skip the bottom row in that case.
          if (!(widget.messageType == 'image' && widget.mediaUrl?.isNotEmpty == true)) ...[
            const SizedBox(height: 3),
            if (isOutbound)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.time,
                    style: AppTextStyles.caption.copyWith(color: timeColor),
                  ),
                  const SizedBox(width: 4),
                  _statusIcon(),
                ],
              )
            else
              Text(
                widget.time,
                style: AppTextStyles.caption.copyWith(color: timeColor),
              ),
          ],
        ],
      ),
    );

    final bubbleWithReactions = Column(
      crossAxisAlignment:
          isOutbound ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        bubble,
        _buildReactionPills(),
      ],
    );

    // Reply icon that appears during swipe
    final replyHint = _swipeDx > 8
        ? Positioned(
            left: isOutbound ? null : 0,
            right: isOutbound ? 0 : null,
            top: 0,
            bottom: 0,
            child: Center(
              child: Opacity(
                opacity: (_swipeDx / 50).clamp(0.0, 1.0),
                child: const Icon(
                  Icons.reply_rounded,
                  color: Color(0xFF667781),
                  size: 20,
                ),
              ),
            ),
          )
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onLongPress: _showEmojiPicker,
        child: Row(
          mainAxisAlignment:
              isOutbound ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (isOutbound) const SizedBox(width: 60),
            Flexible(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Transform.translate(
                    offset: Offset(_swipeDx, 0),
                    child: bubbleWithReactions,
                  ),
                  ?replyHint,
                ],
              ),
            ),
            if (!isOutbound) const SizedBox(width: 60),
          ],
        ),
      ),
    );
  }
}

// ── Reply bar ─────────────────────────────────────────────────────────────────

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.message, required this.onDismiss});
  final Map<String, dynamic> message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final isOutbound = (message['direction'] as String?) == 'outbound';
    final name = isOutbound
        ? _outboundSenderName(message)
        : (message['from_name'] as String? ??
            message['from_phone'] as String? ?? '');
    final raw = message['raw_body'] as String? ?? '';
    final preview = raw.length > 60 ? '${raw.substring(0, 60)}…' : raw;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: const BoxDecoration(
        color: AppColors.ctSurface,
        border: Border(top: BorderSide(color: AppColors.ctBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.ctTeal,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.reply_rounded,
                        size: 13, color: AppColors.ctTeal),
                    const SizedBox(width: 4),
                    Text(
                      'Respondiendo a $name',
                      style: AppTextStyles.badge.copyWith(color: AppColors.ctTeal),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  preview,
                  style: AppTextStyles.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded,
                size: 16, color: AppColors.ctText2),
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}

// ── Emoji picker bottom sheet ─────────────────────────────────────────────────

class _EmojiPickerSheet extends StatelessWidget {
  const _EmojiPickerSheet({required this.onEmoji, this.onReply});
  final void Function(String emoji) onEmoji;
  final VoidCallback? onReply;

  static const _emojis = ['❤️', '👍', '😂', '😮', '😢', '👎'];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _emojis
                .map((e) => GestureDetector(
                      onTap: () => onEmoji(e),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.ctSurface2,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(e,
                            style: AppTextStyles.body.copyWith(fontSize: 26)),
                      ),
                    ))
                .toList(),
          ),
          if (onReply != null) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: AppColors.ctBorder),
            InkWell(
              onTap: onReply,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.reply_rounded,
                        size: 18, color: AppColors.ctText2),
                    const SizedBox(width: 10),
                    Text(
                      'Responder',
                      style: AppTextStyles.body.copyWith(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Input de chat ─────────────────────────────────────────────────────────────

class _ChatInput extends StatefulWidget {
  const _ChatInput({
    required this.controller,
    this.onSend,
    this.onTyping,
    this.sending = false,
    this.enabled = true,
    this.hintText,
    this.onAttach,
    this.onMic,
    this.isRecording = false,
    this.recordingSeconds = 0,
    this.onStop,
    this.onCancel,
    this.sendColor,
  });
  final TextEditingController controller;
  final Future<void> Function()? onSend;
  final VoidCallback? onTyping;
  final bool sending;
  final bool enabled;
  final String? hintText;
  final void Function(String type)? onAttach;
  final VoidCallback? onMic;
  final bool isRecording;
  final int recordingSeconds;
  final Future<void> Function()? onStop;
  final VoidCallback? onCancel;
  final Color? sendColor;

  @override
  State<_ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<_ChatInput>
    with SingleTickerProviderStateMixin {
  bool _hoverSend = false;
  bool _stoppingRec = false;
  Timer? _typingTimer;
  late final AnimationController _pulse;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _focusNode = FocusNode(onKeyEvent: (node, event) {
      // En desktop/web: Enter envía, Shift+Enter inserta salto de línea
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.enter &&
          !HardwareKeyboard.instance.isShiftPressed) {
        final canSend =
            widget.onSend != null && !widget.sending && widget.enabled;
        if (canSend) {
          widget.onSend!().then((_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _focusNode.requestFocus();
            });
          });
        }
        return KeyEventResult.handled; // previene inserción de newline
      }
      return KeyEventResult.ignored;
    });
  }

  @override
  void didUpdateWidget(_ChatInput old) {
    super.didUpdateWidget(old);
    // Reset stopping state when a new recording starts
    if (widget.isRecording && !old.isRecording) {
      _stoppingRec = false;
    }
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _pulse.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    if (widget.onTyping == null) return;
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 800), widget.onTyping!);
  }

  String _formatDuration(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  PopupMenuItem<String> _buildAttachItem(
      String value, IconData icon, Color color, String label) {
    return PopupMenuItem(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(label,
              style: AppTextStyles.body.copyWith(color: AppColors.ctNavy)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ── Recording mode ──────────────────────────────────────────────
    if (widget.isRecording) {
      return Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(
          color: AppColors.ctSurface,
          border: Border(top: BorderSide(color: AppColors.ctBorder)),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close_rounded,
                  size: 20, color: AppColors.ctText3),
              tooltip: 'Cancelar',
            ),
            const SizedBox(width: 4),
            FadeTransition(
              opacity: _pulse,
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: AppColors.ctDanger,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Grabando… ${_formatDuration(widget.recordingSeconds)}',
                style: AppTextStyles.body,
              ),
            ),
            AppButton(
              label: 'Detener',
              onPressed: () async {
                setState(() => _stoppingRec = true);
                await widget.onStop!();
                if (mounted) setState(() => _stoppingRec = false);
              },
              variant: AppButtonVariant.teal,
              size: AppButtonSize.sm,
              prefixIcon: const Icon(Icons.stop_rounded, size: 14, color: AppColors.ctNavy),
              isDisabled: _stoppingRec || widget.onStop == null,
            ),
          ],
        ),
      );
    }

    // ── Normal input mode ───────────────────────────────────────────
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final textEmpty = value.text.isEmpty;
        final canSend =
            widget.onSend != null && !widget.sending && widget.enabled;
        final canMic =
            widget.onMic != null && widget.enabled && !widget.sending;

        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: AppColors.ctSurface,
            border:
                Border(top: BorderSide(color: AppColors.ctBorder)),
          ),
          child: Row(
            children: [
              // Attach button (no voice note — moved to mic button)
              if (widget.onAttach != null) ...[
                PopupMenuButton<String>(
                  onSelected: widget.onAttach,
                  tooltip: 'Adjuntar',
                  color: AppColors.ctSurface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  offset: const Offset(0, -175),
                  itemBuilder: (context) => [
                    _buildAttachItem('image', Icons.image_rounded,
                        AppColors.ctInfo, 'Imagen'),
                    _buildAttachItem('doc',
                        Icons.description_rounded,
                        AppColors.ctDanger, 'Documento'),
                    _buildAttachItem(
                        'location-request',
                        Icons.location_searching_rounded,
                        AppColors.ctTeal,
                        'Solicitar ubicación'),
                  ],
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    child: const Icon(Icons.attach_file_rounded,
                        size: 20, color: AppColors.ctText3),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              // TextField
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 5,
                  style: AppTextStyles.body,
                  enabled: widget.enabled && !widget.sending,
                  onChanged: widget.enabled ? _onChanged : null,
                  decoration: InputDecoration(
                    hintText: widget.hintText ?? 'Escribe un mensaje…',
                    hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                    filled: true,
                    fillColor: AppColors.ctSurface2,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: AppColors.ctBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: AppColors.ctBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: AppColors.ctTeal, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Right button: mic (text empty) or send (text present)
              if (textEmpty && !widget.sending)
                MouseRegion(
                  cursor: canMic
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
                  child: GestureDetector(
                    onTap: canMic ? widget.onMic : null,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: canMic
                                ? AppColors.ctTeal
                                : AppColors.ctSurface2,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.mic_rounded,
                            size: 18,
                            color: canMic
                                ? AppColors.ctNavy
                                : AppColors.ctText3,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else
                MouseRegion(
                  onEnter: (_) =>
                      setState(() => _hoverSend = true),
                  onExit: (_) =>
                      setState(() => _hoverSend = false),
                  cursor: canSend
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
                  child: GestureDetector(
                    onTap: canSend
                        ? () {
                            widget.onSend!().then((_) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) _focusNode.requestFocus();
                              });
                            });
                          }
                        : null,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: canSend
                                ? (_hoverSend
                                    ? (widget.sendColor ?? AppColors.ctTeal).withValues(alpha: 0.8)
                                    : (widget.sendColor ?? AppColors.ctTeal))
                                : AppColors.ctSurface2,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: widget.sending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.ctNavy,
                                  ),
                                )
                              : Icon(
                                  Icons.send_rounded,
                                  size: 16,
                                  color: canSend
                                      ? AppColors.ctNavy
                                      : AppColors.ctText3,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── Tab 2: Feed global ────────────────────────────────────────────────────────

class _TabFeed extends ConsumerStatefulWidget {
  const _TabFeed();

  @override
  ConsumerState<_TabFeed> createState() => _TabFeedState();
}

class _TabFeedState extends ConsumerState<_TabFeed> {
  DateTimeRange? _dateRange;
  TimeOfDay? _fromTime;
  TimeOfDay? _toTime;
  String _filterContact = '';
  String _filterContactPhone = '';
  String _filterDirection = '';
  String _filterFlow = '';
  String _keyword = '';
  List<Map<String, dynamic>> _feedMessages = [];
  StreamSubscription<List<Map<String, dynamic>>>? _feedSub;
  Timer? _keywordDebounce;
  bool _loading = true;
  Map<String, String> _operatorNameMap = {};

  @override
  void initState() {
    super.initState();
    _resubscribe();
  }

  @override
  void dispose() {
    _feedSub?.cancel();
    _keywordDebounce?.cancel();
    super.dispose();
  }

  void _clearFilters() {
    _keywordDebounce?.cancel();
    setState(() {
      _filterDirection = '';
      _filterContact = '';
      _filterContactPhone = '';
      _filterFlow = '';
      _dateRange = null;
      _fromTime = null;
      _toTime = null;
      _keyword = '';
    });
  }

  Future<void> _loadOperatorMap(String tenantId) async {
    try {
      final rows = await Supabase.instance.client
          .from('operators')
          .select('id, name')
          .eq('tenant_id', tenantId);
      if (mounted) {
        setState(() {
          _operatorNameMap = {
            for (final r in rows as List) r['id'] as String: r['name'] as String,
          };
        });
      }
    } catch (e) {
      debugPrint('_loadOperatorMap error: $e');
    }
  }

  void _resubscribe() {
    _feedSub?.cancel();
    setState(() => _loading = true);
    final tenantId = ref.read(activeTenantIdProvider);
    if (tenantId.isEmpty) return;
    _loadOperatorMap(tenantId);

    DateTime? fromDate;
    DateTime? toDate;
    if (_dateRange != null) {
      fromDate = DateTime(
        _dateRange!.start.year, _dateRange!.start.month, _dateRange!.start.day,
        _fromTime?.hour ?? 0, _fromTime?.minute ?? 0,
      );
      toDate = DateTime(
        _dateRange!.end.year, _dateRange!.end.month, _dateRange!.end.day,
        _toTime?.hour ?? 23, _toTime?.minute ?? 59, 59,
      );
    } else if (_fromTime != null || _toTime != null) {
      final now = DateTime.now();
      fromDate = DateTime(now.year, now.month, now.day,
          _fromTime?.hour ?? 0, _fromTime?.minute ?? 0);
      toDate = DateTime(now.year, now.month, now.day,
          _toTime?.hour ?? 23, _toTime?.minute ?? 59, 59);
    }

    _feedSub = SupabaseMessages.streamFeed(
      direction: _filterDirection.isEmpty ? null : _filterDirection,
      keyword: _keyword.isEmpty ? null : _keyword,
      tenantId: tenantId,
      fromDate: fromDate,
      toDate: toDate,
    ).listen((messages) {
      if (!mounted) return;
      // messages arrive descending; filter then reverse to ascending for display
      final filtered = messages.where(_matchesFilters).toList().reversed.toList();
      setState(() {
        _feedMessages = filtered;
        _loading = false;
        // BUG 2: limpiar contacto seleccionado si ya no está en el nuevo batch
        if (_filterContact.isNotEmpty &&
            !_contactPhoneMap.containsKey(_filterContact)) {
          _filterContact = '';
          _filterContactPhone = '';
        }
      });
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  bool _matchesFilters(Map<String, dynamic> msg) {
    final selectedChannelId = ref.read(selectedChannelIdProvider);
    if (selectedChannelId != null) {
      final msgChannelId = msg['channel_id'] as String?;
      if (msgChannelId != null && msgChannelId != selectedChannelId) return false;
    }
    if (_filterContact.isNotEmpty) {
      final direction = msg['direction'] as String?;
      final fromPhone = msg['from_phone'] as String? ?? '';
      final fromName = msg['from_name'] as String? ?? '';
      final toPhone = msg['to_phone'] as String? ?? '';
      // chat_id carries the recipient number on outbound messages
      final chatId = msg['chat_id'] as String? ?? '';
      final matchInbound = direction == 'inbound' &&
          (fromPhone == _filterContactPhone ||
              fromName == _filterContact);
      final matchOutbound = direction == 'outbound' &&
          (toPhone == _filterContactPhone || chatId == _filterContactPhone);
      if (!matchInbound && !matchOutbound) return false;
    }
    if (_filterFlow.isNotEmpty) {
      final num = msg['flow_number'];
      final flowLabel = num != null ? 'Flujo ${num.toString()}' : '';
      if (flowLabel != _filterFlow) return false;
    }
    return _matchesDateFilter(msg);
  }

  bool _matchesDateFilter(Map<String, dynamic> msg) {
    if (_dateRange == null && _fromTime == null) return true;
    final receivedAt =
        DateTime.tryParse(msg['received_at'] as String? ?? '');
    if (receivedAt == null) return false;
    final local = receivedAt.toLocal();
    if (_dateRange != null) {
      if (local.isBefore(_dateRange!.start)) { return false; }
      if (local.isAfter(
          _dateRange!.end.add(const Duration(days: 1)))) { return false; }
    } else if (_fromTime != null || _toTime != null) {
      // Sin rango de fecha explícito la UI muestra "Hoy HH:MM–HH:MM":
      // restringir al día actual antes de evaluar la hora.
      final now = DateTime.now();
      final isToday = local.year == now.year &&
          local.month == now.month &&
          local.day == now.day;
      if (!isToday) return false;
    }
    if (_fromTime != null) {
      final fromMinutes = _fromTime!.hour * 60 + _fromTime!.minute;
      final msgMinutes = local.hour * 60 + local.minute;
      if (msgMinutes < fromMinutes) { return false; }
    }
    if (_toTime != null) {
      final toMinutes = _toTime!.hour * 60 + _toTime!.minute;
      final msgMinutes = local.hour * 60 + local.minute;
      if (msgMinutes > toMinutes) { return false; }
    }
    return true;
  }

  // name → phone, built from inbound messages only
  Map<String, String> get _contactPhoneMap {
    final map = <String, String>{};
    for (final m in _feedMessages) {
      if ((m['direction'] as String?) != 'inbound') continue;
      final name = m['from_name'] as String? ?? '';
      final phone = m['from_phone'] as String? ?? '';
      if (name.isNotEmpty && phone.isNotEmpty) map[name] = phone;
    }
    return map;
  }

  List<String> get _uniqueContacts {
    final keys = _contactPhoneMap.keys.toList()..sort();
    return keys;
  }

  List<String> get _uniqueFlowOptions {
    final seen = <String>{};
    final result = <String>[];
    for (final m in _feedMessages) {
      final num = m['flow_number'];
      if (num == null) continue;
      final label = 'Flujo ${num.toString()}';
      if (seen.add(label)) result.add(label);
    }
    result.sort();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    // Reinicia el feed cuando cambia el tenant o el canal seleccionado
    ref.listen<String>(activeTenantIdProvider, (prev, next) {
      if (prev != null && prev != next) _resubscribe();
    });
    ref.listen<String?>(selectedChannelIdProvider, (prev, next) {
      if (prev != next) {
        _clearFilters();
        _resubscribe();
      }
    });

    return Column(
      children: [
        _FeedFilters(
          dateRange: _dateRange,
          fromTime: _fromTime,
          toTime: _toTime,
          filterContact: _filterContact,
          filterDirection: _filterDirection,
          filterFlow: _filterFlow,
          keyword: _keyword,
          contacts: _uniqueContacts,
          flows: _uniqueFlowOptions,
          onDateRange: (range, from, to) {
            setState(() {
              _dateRange = range;
              _fromTime = from;
              _toTime = to;
            });
            _resubscribe();
          },
          onContact: (v) {
            final name = v == 'Todos los contactos' ? '' : v;
            final phone = name.isEmpty ? '' : (_contactPhoneMap[name] ?? '');
            setState(() {
              _filterContact = name;
              _filterContactPhone = phone;
            });
            _resubscribe();
          },
          onDirection: (v) {
            setState(() => _filterDirection =
                v == 'Entrantes'
                    ? 'inbound'
                    : v == 'Salientes'
                        ? 'outbound'
                        : '');
            _resubscribe();
          },
          onFlow: (v) {
            setState(() =>
                _filterFlow = v == 'Todos los flujos' ? '' : v);
            _resubscribe();
          },
          onKeyword: (v) {
            _keywordDebounce?.cancel();
            _keywordDebounce = Timer(const Duration(milliseconds: 400), () {
              setState(() => _keyword = v);
              _resubscribe();
            });
          },
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _FeedMessages(
                  messages: _feedMessages,
                  channelType:
                      ref.watch(selectedChannelTypeProvider) ?? 'whatsapp',
                  hasActiveFilters: _filterDirection.isNotEmpty ||
                      _filterContact.isNotEmpty ||
                      _dateRange != null ||
                      _fromTime != null ||
                      _toTime != null ||
                      _keyword.isNotEmpty,
                  messageCount: _feedMessages.length,
                  operatorNameMap: _operatorNameMap,
                  onClearFilters: () {
                    _clearFilters();
                    _resubscribe();
                  },
                ),
        ),
      ],
    );
  }
}

// ── Feed: filtros ─────────────────────────────────────────────────────────────

class _FeedFilters extends StatefulWidget {
  const _FeedFilters({
    required this.dateRange,
    required this.fromTime,
    required this.toTime,
    required this.filterContact,
    required this.filterDirection,
    required this.filterFlow,
    required this.keyword,
    required this.contacts,
    required this.flows,
    required this.onDateRange,
    required this.onContact,
    required this.onDirection,
    required this.onFlow,
    required this.onKeyword,
  });

  final DateTimeRange? dateRange;
  final TimeOfDay? fromTime;
  final TimeOfDay? toTime;
  final String filterContact;
  final String filterDirection;
  final String filterFlow;
  final String keyword;
  final List<String> contacts;
  final List<String> flows;
  final void Function(DateTimeRange?, TimeOfDay?, TimeOfDay?) onDateRange;
  final ValueChanged<String> onContact;
  final ValueChanged<String> onDirection;
  final ValueChanged<String> onFlow;
  final ValueChanged<String> onKeyword;

  @override
  State<_FeedFilters> createState() => _FeedFiltersState();
}

class _FeedFiltersState extends State<_FeedFilters> {
  late TextEditingController _keywordCtrl;

  @override
  void initState() {
    super.initState();
    _keywordCtrl = TextEditingController(text: widget.keyword);
  }

  @override
  void didUpdateWidget(_FeedFilters old) {
    super.didUpdateWidget(old);
    if (widget.keyword != old.keyword &&
        _keywordCtrl.text != widget.keyword) {
      _keywordCtrl.text = widget.keyword;
    }
  }

  @override
  void dispose() {
    _keywordCtrl.dispose();
    super.dispose();
  }

  String _dateLabel() {
    final dr = widget.dateRange;
    final ft = widget.fromTime;
    final tt = widget.toTime;
    if (dr == null && ft == null) return 'Todas las fechas';

    String dateStr;
    if (dr == null) {
      dateStr = 'Hoy';
    } else {
      final now = DateTime.now();
      final isToday = dr.start.year == now.year &&
          dr.start.month == now.month &&
          dr.start.day == now.day &&
          dr.end.year == now.year &&
          dr.end.month == now.month &&
          dr.end.day == now.day;
      if (isToday) {
        dateStr = 'Hoy';
      } else {
        final s = dr.start;
        final e = dr.end;
        final sameDay = s.year == e.year &&
            s.month == e.month &&
            s.day == e.day;
        if (sameDay) {
          dateStr =
              '${s.day.toString().padLeft(2, '0')}/${s.month.toString().padLeft(2, '0')}';
        } else {
          dateStr =
              '${s.day.toString().padLeft(2, '0')}/${s.month.toString().padLeft(2, '0')}'
              ' – ${e.day.toString().padLeft(2, '0')}/${e.month.toString().padLeft(2, '0')}';
        }
      }
    }

    if (ft != null || tt != null) {
      String fmtTime(TimeOfDay t) =>
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      final fromStr = ft != null ? fmtTime(ft) : '00:00';
      final toStr = tt != null ? fmtTime(tt) : '23:59';
      return '$dateStr $fromStr–$toStr';
    }
    return dateStr;
  }

  @override
  Widget build(BuildContext context) {
    final dirLabel = widget.filterDirection.isEmpty
        ? 'Todas las direcciones'
        : widget.filterDirection == 'inbound'
            ? 'Entrantes'
            : 'Salientes';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.ctBorder)),
      ),
      child: Row(
        children: [
          // Date range picker
          AppButton(
            label: _dateLabel(),
            onPressed: () async {
              final result = await showDialog<
                  ({
                    DateTimeRange? range,
                    TimeOfDay? fromTime,
                    TimeOfDay? toTime
                  })>(
                context: context,
                builder: (_) => _DateFilterModal(
                  initialRange: widget.dateRange,
                  initialFromTime: widget.fromTime,
                  initialToTime: widget.toTime,
                ),
              );
              if (result == null) return;
              widget.onDateRange(result.range, result.fromTime, result.toTime);
            },
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            prefixIcon: const Icon(Icons.date_range_rounded, size: 13),
          ),
          const SizedBox(width: 8),
          _FilterDropdown(
            label: 'Todos los contactos',
            value: widget.filterContact.isEmpty
                ? 'Todos los contactos'
                : widget.filterContact,
            options: ['Todos los contactos', ...widget.contacts],
            onChanged: widget.onContact,
          ),
          const SizedBox(width: 8),
          _FilterDropdown(
            label: 'Todas las direcciones',
            value: dirLabel,
            options: const [
              'Todas las direcciones',
              'Entrantes',
              'Salientes',
            ],
            onChanged: widget.onDirection,
          ),
          const SizedBox(width: 8),
          _FilterDropdown(
            label: 'Todos los flujos',
            value: widget.filterFlow.isEmpty ||
                    !widget.flows.contains(widget.filterFlow)
                ? 'Todos los flujos'
                : widget.filterFlow,
            options: ['Todos los flujos', ...widget.flows],
            onChanged: widget.onFlow,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 30,
              child: TextField(
                controller: _keywordCtrl,
                style: AppTextStyles.navItem.copyWith(color: AppColors.ctText),
                decoration: InputDecoration(
                  hintText: 'Buscar…',
                  hintStyle: AppTextStyles.navItem.copyWith(color: AppColors.ctText3),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 14,
                    color: AppColors.ctText3,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: const BorderSide(
                        color: AppColors.ctBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: const BorderSide(
                        color: AppColors.ctBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: const BorderSide(
                        color: AppColors.ctTeal, width: 1.5),
                  ),
                ),
                onChanged: widget.onKeyword,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Feed: lista de mensajes ───────────────────────────────────────────────────

class _FeedMessages extends StatefulWidget {
  const _FeedMessages({
    required this.messages,
    required this.channelType,
    required this.hasActiveFilters,
    required this.messageCount,
    required this.operatorNameMap,
    this.onClearFilters,
  });

  final List<Map<String, dynamic>> messages;
  final String channelType;
  final bool hasActiveFilters;
  final int messageCount;
  final Map<String, String> operatorNameMap;
  final VoidCallback? onClearFilters;

  @override
  State<_FeedMessages> createState() => _FeedMessagesState();

  static const _avatarColors = [
    Color(0xFFDCFCE7),
    AppColors.ctInfoBg,
    AppColors.ctWarnBg,
    Color(0xFFFCE7F3),
    Color(0xFFEDE9FE),
    AppColors.ctOrangeBg,
  ];
  static const _avatarTextColors = [
    Color(0xFF166534),
    AppColors.ctInfoText,
    AppColors.ctWarnText,
    Color(0xFF9D174D),
    Color(0xFF5B21B6),
    AppColors.ctOrangeText,
  ];

  static Color _avatarBg(String phone) =>
      _avatarColors[phone.hashCode.abs() % _avatarColors.length];

  static Color _avatarFg(String phone) =>
      _avatarTextColors[phone.hashCode.abs() % _avatarTextColors.length];
}

class _FeedMessagesState extends State<_FeedMessages> {
  final _scrollCtrl = ScrollController();
  bool _atBottom = true;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    if (widget.messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
    }
  }

  @override
  void didUpdateWidget(_FeedMessages old) {
    super.didUpdateWidget(old);
    if (widget.messageCount > old.messageCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (old.messageCount == 0 || _atBottom) _jumpToBottom();
      });
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    final nearBottom = pos.pixels >= pos.maxScrollExtent - 150;
    if (nearBottom != _atBottom) setState(() => _atBottom = nearBottom);
  }

  void _jumpToBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
  }

  List<({String label, List<Map<String, dynamic>> msgs})> _buildGroups() {
    final groups = <({String label, List<Map<String, dynamic>> msgs})>[];
    DateTime? lastDay;
    for (final msg in widget.messages) {
      final iso = msg['received_at'] as String?;
      DateTime? dt;
      if (iso != null) dt = DateTime.tryParse(iso)?.toLocal();
      if (dt != null) {
        final day = DateTime(dt.year, dt.month, dt.day);
        if (lastDay == null || day != lastDay) {
          groups.add((label: _formatDate(dt), msgs: []));
          lastDay = day;
        }
      } else if (groups.isEmpty) {
        groups.add((label: '', msgs: []));
      }
      if (groups.isNotEmpty) groups.last.msgs.add(msg);
    }
    return groups;
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(dt.year, dt.month, dt.day);
    if (d == today) return 'Hoy';
    if (d == yesterday) return 'Ayer';
    const months = [
      '', 'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    return '${dt.day} ${months[dt.month]} ${dt.year}';
  }

  String _timeLabel(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  Widget _dateSepChip(String label) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.ctSurface2,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: AppTextStyles.bodySmall,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (widget.messages.isEmpty) {
      return Container(
        color: const Color(0xFFF0F2F5),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.hasActiveFilters
                  ? Icons.filter_list
                  : Icons.chat_bubble_outline,
              size: 32,
              color: AppColors.ctText3,
            ),
            const SizedBox(height: 12),
            Text(
              widget.hasActiveFilters ? 'Sin resultados' : 'Sin mensajes',
              style: AppTextStyles.body.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ctNavy),
            ),
            const SizedBox(height: 4),
            Text(
              widget.hasActiveFilters
                  ? 'Ningún mensaje coincide con los filtros activos.'
                  : 'Aún no hay mensajes en este canal.',
              style: AppTextStyles.pageSubtitle,
            ),
            if (widget.hasActiveFilters && widget.onClearFilters != null) ...[
              const SizedBox(height: 16),
              GestureDetector(
                onTap: widget.onClearFilters,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.ctBorder),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Limpiar filtros',
                    style: AppTextStyles.pageSubtitle,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final groups = _buildGroups();
    final showTruncatedBanner = widget.messageCount >= 200;

    return Container(
      color: const Color(0xFFF0F2F5),
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: groups.length + (showTruncatedBanner ? 1 : 0),
        itemBuilder: (context, i) {
          if (showTruncatedBanner && i == groups.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.history, size: 14, color: AppColors.ctText3),
                  const SizedBox(width: 6),
                  Text(
                    'Mostrando los últimos 200 mensajes',
                    style: AppTextStyles.navItem.copyWith(color: AppColors.ctText3),
                  ),
                ],
              ),
            );
          }
          final group = groups[i];
          return StickyHeader(
            header: _dateSepChip(group.label),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: group.msgs.map((msg) {
                final msgId = msg['id'] as String? ?? '';
                final direction = msg['direction'] as String?;
                final isOutbound = direction == 'outbound';
                final phone = msg['from_phone'] as String? ??
                    msg['chat_id'] as String? ?? '';
                final name = msg['from_name'] as String? ?? phone;
                final chatId = msg['chat_id'] as String? ?? '';
                final time = _timeLabel(msg['received_at'] as String?);
                final waStatus = msg['wa_status'] as String?;
                final body = _msgBody(msg);
                final messageType = msg['message_type'] as String?;
                final mediaUrl = msg['media_url'] as String?;
                final origin = msg['origin'] as String? ?? 'ai_worker';

                if (isOutbound) {
                  final operatorId = msg['operator_id'] as String?;
                  final resolvedName = operatorId != null
                      ? widget.operatorNameMap[operatorId]
                      : null;
                  return _FeedOutboundBubble(
                    key: ValueKey(msgId),
                    body: body,
                    time: time,
                    toPhone: chatId,
                    senderName: _outboundSenderName(msg),
                    waStatus: waStatus,
                    origin: origin,
                    channelType: widget.channelType,
                    messageType: messageType,
                    mediaUrl: mediaUrl,
                    recipientName: resolvedName,
                    broadcastId: msg['broadcast_id'] as String?,
                  );
                }
                return _FeedInboundBubble(
                  key: ValueKey(msgId),
                  body: body,
                  time: time,
                  name: name,
                  phone: phone,
                  chatId: chatId,
                  avatarBg: _FeedMessages._avatarBg(phone),
                  avatarTextColor: _FeedMessages._avatarFg(phone),
                  messageType: messageType,
                  mediaUrl: mediaUrl,
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}

// ── Feed: helper de contenido ────────────────────────────────────────────────

/// Guard para HtmlElementView en el feed — prefijo 'feed-' evita colisiones con chat.
final Set<String> _feedRegisteredMediaViews = {};

Widget _buildFeedBody(
  String body,
  String? messageType,
  String direction, {
  String? mediaUrl,
  Color? textColor,
}) {
  final isOutbound = direction == 'outbound';
  final Color effectiveTextColor =
      textColor ?? (isOutbound ? AppColors.ctText : AppColors.ctText);

  // ── imagen ──────────────────────────────────────────────────────────────────
  if (messageType == 'image' || messageType == 'sticker') {
    final mUrl = mediaUrl?.isNotEmpty == true ? mediaUrl! : null;
    if (mUrl == null) {
      return Text('[${messageType == 'sticker' ? 'Sticker' : 'Imagen'}]',
          style: AppTextStyles.body.copyWith(color: effectiveTextColor));
    }
    final maxW = messageType == 'sticker' ? 120.0 : 220.0;
    final maxH = messageType == 'sticker' ? 120.0 : 220.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        mUrl,
        width: maxW,
        height: maxH,
        fit: BoxFit.cover,
        errorBuilder: (context, e, s) => Text('[Imagen no disponible]',
            style: AppTextStyles.body.copyWith(color: effectiveTextColor.withValues(alpha: 0.6))),
      ),
    );
  }

  // ── audio ───────────────────────────────────────────────────────────────────
  if (messageType == 'audio' || messageType == 'voice') {
    final mUrl = mediaUrl?.isNotEmpty == true ? mediaUrl! : null;
    if (mUrl == null) {
      return Text('[Audio]',
          style: AppTextStyles.body.copyWith(color: effectiveTextColor));
    }
    final audioViewId = 'feed-audio-${mUrl.hashCode}';
    if (!_feedRegisteredMediaViews.contains(audioViewId)) {
      _feedRegisteredMediaViews.add(audioViewId);
      ui_web.platformViewRegistry.registerViewFactory(audioViewId, (int id) {
        final audio = html.AudioElement()
          ..controls = true
          ..style.width = '220px'
          ..style.outline = 'none'
          ..style.display = 'block';
        audio.append(html.SourceElement()
          ..src = mUrl
          ..type = 'audio/ogg');
        audio.append(html.SourceElement()
          ..src = mUrl
          ..type = 'audio/mpeg');
        return audio;
      });
    }
    return SizedBox(
      width: 220,
      height: 54,
      child: HtmlElementView(viewType: audioViewId),
    );
  }

  // ── video ───────────────────────────────────────────────────────────────────
  if (messageType == 'video') {
    final mUrl = mediaUrl?.isNotEmpty == true ? mediaUrl! : null;
    if (mUrl == null) {
      return Text('[Video]',
          style: AppTextStyles.body.copyWith(color: effectiveTextColor));
    }
    final videoViewId = 'feed-video-${mUrl.hashCode}';
    if (!_feedRegisteredMediaViews.contains(videoViewId)) {
      _feedRegisteredMediaViews.add(videoViewId);
      ui_web.platformViewRegistry.registerViewFactory(videoViewId, (int id) {
        final video = html.VideoElement()
          ..controls = true
          ..style.width = '240px'
          ..style.height = '135px'
          ..style.borderRadius = '8px'
          ..style.background = '#000'
          ..style.outline = 'none'
          ..style.display = 'block';
        video.append(html.SourceElement()
          ..src = mUrl
          ..type = 'video/mp4');
        return video;
      });
    }
    final caption =
        (body.isNotEmpty && !body.startsWith('[')) ? body : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 240,
          height: 135,
          child: HtmlElementView(viewType: videoViewId),
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(caption,
                style: AppTextStyles.body.copyWith(color: effectiveTextColor, height: 1.4)),
          ),
      ],
    );
  }

  // ── document ────────────────────────────────────────────────────────────────
  if (messageType == 'document') {
    final mUrl = mediaUrl?.isNotEmpty == true ? mediaUrl! : null;
    final fileName = body.isNotEmpty && !body.startsWith('[') ? body : 'Documento';
    return GestureDetector(
      onTap: mUrl != null ? () => launchUrl(Uri.parse(mUrl)) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_rounded,
              size: 20, color: effectiveTextColor.withValues(alpha: 0.7)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              fileName,
              style: AppTextStyles.body.copyWith(
                  color: mUrl != null ? AppColors.ctInfo : effectiveTextColor,
                  decoration: mUrl != null ? TextDecoration.underline : null),
            ),
          ),
        ],
      ),
    );
  }

  // ── location ────────────────────────────────────────────────────────────────
  if (messageType == 'location') {
    Map<String, dynamic>? locData;
    try {
      locData = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {}
    final locName = locData?['name'] as String? ??
        locData?['address'] as String? ??
        'Ubicación compartida';
    final lat = locData?['latitude']?.toString() ?? '';
    final lng = locData?['longitude']?.toString() ?? '';
    final mapsUrl = (lat.isNotEmpty && lng.isNotEmpty)
        ? 'https://maps.google.com/?q=$lat,$lng'
        : 'https://maps.google.com/';

    return Column(
      crossAxisAlignment:
          isOutbound ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on, color: Colors.red, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                locName,
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600, color: effectiveTextColor),
              ),
            ),
          ],
        ),
        if (lat.isNotEmpty && lng.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 24),
            child: Text(
              '$lat, $lng',
              style: AppTextStyles.bodySmall.copyWith(color: effectiveTextColor.withValues(alpha: 0.6)),
            ),
          ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => launchUrl(Uri.parse(mapsUrl)),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF53BDEB).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Ver en mapa',
              style: AppTextStyles.navItem.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFF53BDEB)),
            ),
          ),
        ),
      ],
    );
  }

  // ── texto (fallback) ─────────────────────────────────────────────────────────
  return Text(
    body,
    style: AppTextStyles.body.copyWith(color: effectiveTextColor, height: 1.4),
  );
}

// ── Feed: burbuja inbound ─────────────────────────────────────────────────────

class _FeedInboundBubble extends StatelessWidget {
  const _FeedInboundBubble({
    super.key,
    required this.body,
    required this.time,
    required this.name,
    required this.phone,
    required this.chatId,
    required this.avatarBg,
    required this.avatarTextColor,
    this.messageType,
    this.mediaUrl,
  });

  final String body;
  final String time;
  final String name;
  final String phone;
  final String chatId;
  final Color avatarBg;
  final Color avatarTextColor;
  final String? messageType;
  final String? mediaUrl;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(top: 4, right: 6),
            decoration: BoxDecoration(
              color: avatarBg,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(name),
              style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600, color: avatarTextColor),
            ),
          ),
          // Bubble
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name · $chatId',
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: 2),
                Container(
                  constraints: const BoxConstraints(maxWidth: 440),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(2),
                      topRight: Radius.circular(10),
                      bottomLeft: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                    ),
                    border: Border.all(color: AppColors.ctBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFeedBody(body, messageType, 'inbound',
                          mediaUrl: mediaUrl),
                      const SizedBox(height: 2),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          time,
                          style: AppTextStyles.caption,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Feed: burbuja outbound ────────────────────────────────────────────────────

class _FeedOutboundBubble extends StatelessWidget {
  const _FeedOutboundBubble({
    super.key,
    required this.body,
    required this.time,
    required this.toPhone,
    required this.senderName,
    required this.waStatus,
    required this.origin,
    required this.channelType,
    this.messageType,
    this.mediaUrl,
    this.recipientName,
    this.broadcastId,
  });

  final String body;
  final String time;
  final String toPhone;
  final String senderName;
  final String? waStatus;
  final String origin;
  final String channelType;
  final String? messageType;
  final String? mediaUrl;
  final String? recipientName;
  final String? broadcastId;

  Widget _statusIcon(Color baseColor) {
    switch (waStatus) {
      case 'read':
        return Icon(Icons.done_all, size: 12, color: baseColor);
      case 'delivered':
        return Icon(Icons.done_all,
            size: 12, color: baseColor.withValues(alpha: 0.5));
      case 'sent':
        return Icon(Icons.check,
            size: 12, color: baseColor.withValues(alpha: 0.5));
      case 'failed':
        return const Icon(Icons.error_outline,
            size: 12, color: AppColors.ctRedText);
      default:
        return Icon(Icons.check,
            size: 12, color: baseColor.withValues(alpha: 0.5));
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color bubbleBg;
    final Color bubbleTextColor;
    if (origin == 'human') {
      bubbleBg = AppColors.ctNavy;
      bubbleTextColor = AppColors.ctTeal;
    } else if (channelType == 'telegram') {
      bubbleBg = AppColors.ctInfoBg;
      bubbleTextColor = AppColors.ctText;
    } else {
      bubbleBg = AppColors.waBubbleAi;
      bubbleTextColor = AppColors.ctText;
    }
    final originStyle = _outboundOriginStyle({'origin': origin});

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (originStyle.badge != null) ...[
                      originStyle.badge!,
                      const SizedBox(width: 4),
                    ],
                    Text(
                      '$senderName → ${recipientName ?? toPhone}',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
                // Sub-label: broadcast chip or recipient name
                if (broadcastId != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.ctSurface2,
                          border: Border.all(color: AppColors.ctBorder),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.campaign_rounded, size: 10, color: AppColors.ctText3),
                            const SizedBox(width: 4),
                            Text('Broadcast',
                                style: AppFonts.geist(fontSize: 10, color: AppColors.ctText3)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ] else if (recipientName != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Icon(Icons.arrow_forward, size: 12, color: AppColors.ctText2),
                      const SizedBox(width: 3),
                      Text(recipientName!,
                          style: AppFonts.geist(fontSize: 10, color: AppColors.ctText2)),
                    ],
                  ),
                ],
                const SizedBox(height: 2),
                Container(
                  constraints: const BoxConstraints(maxWidth: 440),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: bubbleBg,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(10),
                      topRight: Radius.circular(2),
                      bottomLeft: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildFeedBody(body, messageType, 'outbound',
                          mediaUrl: mediaUrl, textColor: bubbleTextColor),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            time,
                            style: AppTextStyles.caption.copyWith(color: bubbleTextColor.withValues(alpha: 0.7)),
                          ),
                          const SizedBox(width: 3),
                          _statusIcon(bubbleTextColor),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Avatar mini del destinatario (solo cuando hay recipient_name y no es broadcast)
          if (recipientName != null && broadcastId == null) ...[
            const SizedBox(width: 6),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 1,
                  height: 14,
                  color: AppColors.ctText2.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 2),
                CircleAvatar(
                  radius: 9,
                  backgroundColor: _FeedMessages._avatarBg(recipientName!),
                  child: Text(
                    recipientName!.trim().split(RegExp(r'\s+')).take(2)
                        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
                        .join(),
                    style: AppTextStyles.caption.copyWith(fontSize: 7, fontWeight: FontWeight.w700, color: _FeedMessages._avatarFg(recipientName!)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Ghost button ──────────────────────────────────────────────────────────────

// ── Dropdown de filtro ────────────────────────────────────────────────────────

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.ctBorder2),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          style: AppTextStyles.navItem.copyWith(color: AppColors.ctText),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 14,
            color: AppColors.ctText3,
          ),
          items: options
              .map(
                (o) => DropdownMenuItem(
                  value: o,
                  child: Text(o),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

// ── Modal de filtro de fecha ──────────────────────────────────────────────────

class _DateFilterModal extends StatefulWidget {
  const _DateFilterModal({
    required this.initialRange,
    required this.initialFromTime,
    required this.initialToTime,
  });
  final DateTimeRange? initialRange;
  final TimeOfDay? initialFromTime;
  final TimeOfDay? initialToTime;

  @override
  State<_DateFilterModal> createState() => _DateFilterModalState();
}

class _DateFilterModalState extends State<_DateFilterModal> {
  DateTime? _startDate;
  DateTime? _endDate;
  TimeOfDay? _fromTime;
  TimeOfDay? _toTime;

  @override
  void initState() {
    super.initState();
    _startDate = widget.initialRange?.start;
    _endDate = widget.initialRange?.end;
    _fromTime = widget.initialFromTime;
    _toTime = widget.initialToTime;
  }

  String _timeLabel(TimeOfDay? t, String placeholder) {
    if (t == null) return placeholder;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  void _pop({required bool clear}) {
    if (clear) {
      Navigator.of(context).pop(
        (range: null, fromTime: null, toTime: null),
      );
      return;
    }
    DateTimeRange? range;
    if (_startDate != null) {
      range = DateTimeRange(
        start: _startDate!,
        end: _endDate ?? _startDate!,
      );
    }
    Navigator.of(context).pop(
      (range: range, fromTime: _fromTime, toTime: _toTime),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                'Filtrar por fecha y hora',
                style: AppTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),

              // Two calendars side by side
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Desde',
                          style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 290,
                          child: CalendarDatePicker(
                            key: ValueKey('start_${_startDate?.toIso8601String()}'),
                            initialDate: _startDate ?? DateTime.now(),
                            firstDate: DateTime(2024),
                            lastDate: DateTime.now(),
                            onDateChanged: (d) => setState(() {
                              _startDate = d;
                              if (_endDate != null &&
                                  _endDate!.isBefore(d)) {
                                _endDate = d;
                              }
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const VerticalDivider(width: 1),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Hasta',
                          style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 290,
                          child: CalendarDatePicker(
                            key: ValueKey('end_${_endDate?.toIso8601String()}'),
                            initialDate: _endDate ?? DateTime.now(),
                            firstDate: _startDate ?? DateTime(2024),
                            lastDate: DateTime.now(),
                            onDateChanged: (d) =>
                                setState(() => _endDate = d),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Time pickers
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: _timeLabel(_fromTime, 'Hora desde'),
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: _fromTime ??
                              const TimeOfDay(hour: 0, minute: 0),
                          helpText: 'Hora desde',
                        );
                        if (t != null) setState(() => _fromTime = t);
                      },
                      variant: AppButtonVariant.outline,
                      size: AppButtonSize.sm,
                      prefixIcon: const Icon(Icons.access_time_rounded, size: 14, color: AppColors.ctInk700),
                      expand: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppButton(
                      label: _timeLabel(_toTime, 'Hora hasta'),
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: _toTime ??
                              const TimeOfDay(hour: 23, minute: 59),
                          helpText: 'Hora hasta',
                        );
                        if (t != null) setState(() => _toTime = t);
                      },
                      variant: AppButtonVariant.outline,
                      size: AppButtonSize.sm,
                      prefixIcon: const Icon(Icons.access_time_rounded, size: 14, color: AppColors.ctInk700),
                      expand: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Actions
              Row(
                children: [
                  AppButton(
                    label: 'Limpiar',
                    onPressed: () => _pop(clear: true),
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.sm,
                  ),
                  const Spacer(),
                  AppButton(
                    label: 'Cancelar',
                    onPressed: () => Navigator.of(context).pop(null),
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.sm,
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    label: 'Aplicar',
                    onPressed: () => _pop(clear: false),
                    variant: AppButtonVariant.teal,
                    size: AppButtonSize.sm,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Nuevo Mensaje Dialog ───────────────────────────────────────────────────────

class _NewMessageDialog extends ConsumerStatefulWidget {
  const _NewMessageDialog();

  @override
  ConsumerState<_NewMessageDialog> createState() => _NewMessageDialogState();
}

class _NewMessageDialogState extends ConsumerState<_NewMessageDialog> {
  int _step = 0;

  // Step 1 — recipient selection
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _operators = [];
  bool _loadingAll = true;
  String? _loadError;

  // Step 2 — compose
  Map<String, dynamic>? _selected; // {name, phone}
  bool _checkingWindow = false;
  bool _windowOpen = false;
  bool _useTemplate = false;
  final _msgCtrl = TextEditingController();
  List<Map<String, dynamic>> _templates = [];
  String? _selectedTemplateId;
  String? _selectedChannelId;
  bool _sending = false;
  String? _sendError;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() { _loadingAll = true; _loadError = null; });
    try {
      final results = await Future.wait([
        OperatorsApi.listOperators(),
        ApiClient.instance.get('/templates'),
      ]);
      final ops = results[0] as List<Map<String, dynamic>>;

      final tplRaw = results[1] as dynamic;
      final tplData = tplRaw.data;
      final List tplList = tplData is List
          ? tplData
          : (tplData['templates'] ?? tplData['items'] ?? []) as List;
      final templates = tplList.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      if (mounted) {
        setState(() {
          _operators = ops;
          _templates = templates;
          _loadingAll = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loadingAll = false; _loadError = e.toString(); });
    }
  }

  Future<void> _selectRecipient(Map<String, dynamic> recipient) async {
    final channelId = ref.read(selectedChannelIdProvider) ?? '';
    setState(() {
      _selected = recipient;
      _checkingWindow = true;
      _step = 1;
      _selectedChannelId = channelId.isNotEmpty ? channelId : null;
    });
    try {
      final phone = recipient['phone'] as String? ?? '';
      final chatId = PhoneNormalizer.toChatId(phone);
      final db = Supabase.instance.client;
      final cutoff = DateTime.now().toUtc().subtract(const Duration(hours: 24)).toIso8601String();
      final rows = await db
          .from('wa_messages')
          .select('received_at')
          .eq('chat_id', chatId)
          .neq('direction', 'outbound')
          .gte('received_at', cutoff)
          .limit(1);
      final hasRecentInbound = (rows as List).isNotEmpty;
      if (mounted) {
        setState(() {
          _windowOpen = hasRecentInbound;
          _checkingWindow = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _windowOpen = false; _checkingWindow = false; });
    }
  }

  String _resolvePreview(Map<String, dynamic> tpl) {
    final body = tpl['body'] as String? ?? tpl['text'] as String? ?? '';
    final vars = tpl['variables'] as Map? ?? {};
    var result = body;
    vars.forEach((k, v) {
      result = result.replaceAll('{{$k}}', v?.toString() ?? '[$k]');
    });
    return result;
  }

  List<String> _resolveVars(Map<String, dynamic> tpl) {
    final raw = tpl['variables'];
    if (raw is List) {
      return raw.map((v) => v?.toString() ?? '').toList();
    }
    if (raw is Map) {
      final entries = raw.entries.toList()
        ..sort((a, b) {
          final ia = int.tryParse(a.key.toString()) ?? 0;
          final ib = int.tryParse(b.key.toString()) ?? 0;
          return ia.compareTo(ib);
        });
      return entries.map((e) => e.value?.toString() ?? '').toList();
    }
    return [];
  }

  Future<void> _send() async {
    if (_selected == null) return;
    final phone = _selected!['phone'] as String? ?? '';
    final name = _selected!['name'] as String? ?? phone;
    final userId = Supabase.instance.client.auth.currentUser?.id;

    debugPrint('[_send] channelId=$_selectedChannelId useTemplate=$_useTemplate templateId=$_selectedTemplateId');
    setState(() { _sending = true; _sendError = null; });
    try {
      final channelId = _selectedChannelId ?? '';
      if (channelId.isEmpty) {
        setState(() { _sending = false; _sendError = 'No se encontró canal WhatsApp para este operador.'; });
        return;
      }
      if (_useTemplate && _selectedTemplateId != null) {
        final tpl = _templates.firstWhere(
          (t) => (t['id'] ?? t['template_id'])?.toString() == _selectedTemplateId,
          orElse: () => {},
        );
        debugPrint('[_send] payload: to=$phone channel=$channelId template=${tpl['name'] ?? tpl['template_name']} lang=${tpl['language'] ?? tpl['lang']}');
        await ApiClient.instance.post(
          '/messages/send',
          data: {
            'to': phone,
            'channel_id': channelId,
            'template_name': tpl['name'] ?? tpl['template_name'] ?? '',
            'template_language': tpl['language'] ?? tpl['lang'] ?? 'es',
            'template_variables': _resolveVars(tpl),
            'sent_by_user_id': ?userId,
          },
        );
      } else {
        final text = _msgCtrl.text.trim();
        if (text.isEmpty) {
          setState(() { _sending = false; _sendError = 'Escribe un mensaje.'; });
          return;
        }
        await MessagesApi.sendWhatsAppMessage(
          to: phone,
          text: text,
          channelId: channelId,
          sentByUserId: userId,
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
        ref.read(selectedChannelTabProvider.notifier).state = 0;
        ref.read(selectedChatIdProvider.notifier).state = phone;
        ref.read(selectedChatNameProvider.notifier).state = name;
      }
    } on DioException catch (e) {
      debugPrint('[_send] DioException: status=${e.response?.statusCode} data=${e.response?.data}');
      final raw = e.response?.data?.toString() ?? e.message ?? '';
      if (mounted) setState(() { _sending = false; _sendError = _parseErrorMessage(raw); });
    } catch (e) {
      debugPrint('[_send] Exception: $e');
      if (mounted) setState(() { _sending = false; _sendError = _parseErrorMessage(e.toString()); });
    }
  }

  String _parseErrorMessage(dynamic error) {
    try {
      final detail = error.toString();
      if (detail.contains('131037') || detail.contains('display name')) {
        return 'El número aún no tiene el nombre de perfil aprobado por Meta. Por favor espera la aprobación antes de iniciar nuevas conversaciones.';
      }
      if (detail.contains('131026') || detail.contains('not in whitelist')) {
        return 'Este número no está registrado como destinatario de prueba.';
      }
      return 'Error al enviar el mensaje. Intenta de nuevo.';
    } catch (_) {
      return 'Error al enviar el mensaje. Intenta de nuevo.';
    }
  }

  List<Map<String, dynamic>> get _filteredOps {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _operators;
    return _operators.where((o) {
      final n = (o['display_name'] ?? o['name'] ?? '').toString().toLowerCase();
      final p = (o['phone'] ?? '').toString();
      return n.contains(q) || p.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: SizedBox(
        width: 480,
        height: _step == 0 ? 520 : null,
        child: _step == 0 ? _buildStep1() : _buildStep2(),
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Nuevo mensaje',
                  style: AppTextStyles.body.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ctNavy),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: AppColors.ctText3),
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Search
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            style: AppTextStyles.body.copyWith(color: AppColors.ctNavy),
            decoration: InputDecoration(
              hintText: 'Buscar por nombre o teléfono…',
              hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
              prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.ctText3),
              filled: true,
              fillColor: AppColors.ctSurface2,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // List
        Expanded(
          child: _loadingAll
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _loadError != null
                  ? Center(child: Text(_loadError!, style: AppTextStyles.navItem.copyWith(color: Colors.red)))
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 12),
                      children: [
                        if (_filteredOps.isNotEmpty) ...[
                          _NmSectionHeader(label: 'Operadores (${_filteredOps.length})'),
                          ..._filteredOps.map((op) {
                            final flows = (op['flows'] as List? ?? []);
                            String? chId;
                            for (final f in flows) {
                              if (f is Map) {
                                final types = f['channel_types'];
                                if (types is List && types.contains('whatsapp')) {
                                  final cid = f['channel_id'] as String?;
                                  if (cid != null && cid.isNotEmpty) { chId = cid; break; }
                                }
                              }
                            }
                            return _NmRecipientItem(
                              name: op['display_name'] ?? op['name'] ?? '—',
                              phone: op['phone'] ?? '',
                              onTap: () => _selectRecipient({
                                'name': op['display_name'] ?? op['name'] ?? '',
                                'phone': op['phone'] ?? '',
                                'channel_id': chId ?? '',
                              }),
                            );
                          }),
                        ],
                        if (_filteredOps.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(child: Text('Sin resultados', style: AppTextStyles.body.copyWith(color: AppColors.ctText3))),
                          ),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    final name = _selected?['name'] as String? ?? '';
    final phone = _selected?['phone'] as String? ?? '';
    final tpl = _selectedTemplateId == null
        ? null
        : _templates.firstWhere(
            (t) => (t['id'] ?? t['template_id'])?.toString() == _selectedTemplateId,
            orElse: () => {},
          );

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 18, color: AppColors.ctText3),
                onPressed: () => setState(() { _step = 0; _selected = null; }),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Nuevo mensaje',
                  style: AppTextStyles.body.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ctNavy),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: AppColors.ctText3),
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Recipient card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.ctSurface2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.ctTeal.withValues(alpha: 0.15),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.ctTeal),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500, color: AppColors.ctNavy)),
                    if (phone.isNotEmpty)
                      Text(phone, style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Window status
          if (_checkingWindow)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Text('Verificando ventana de 24h…', style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3)),
              ]),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _windowOpen ? AppColors.ctOkBg : AppColors.ctWarnBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _windowOpen ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                      size: 13,
                      color: _windowOpen ? AppColors.ctOkText : AppColors.ctWarnText,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _windowOpen
                          ? 'Ventana de 24h abierta — puedes enviar texto libre.'
                          : 'Ventana cerrada — solo puedes enviar plantillas aprobadas.',
                      style: AppTextStyles.bodySmall.copyWith(color: _windowOpen ? AppColors.ctOkText : AppColors.ctWarnText),
                    ),
                  ],
                ),
              ),
            ),
          // Mode toggle (only if window open)
          if (!_checkingWindow && _windowOpen) ...[
            Row(
              children: [
                _NmToggleBtn(
                  label: 'Texto libre',
                  active: !_useTemplate,
                  onTap: () => setState(() => _useTemplate = false),
                ),
                const SizedBox(width: 8),
                _NmToggleBtn(
                  label: 'Plantilla',
                  active: _useTemplate,
                  onTap: () => setState(() => _useTemplate = true),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          // Input area
          if (!_checkingWindow) ...[
            if (_useTemplate) ...[
              _NmTemplateDropdown(
                templates: _templates,
                selectedId: _selectedTemplateId,
                onChanged: (id) => setState(() { _selectedTemplateId = id; _useTemplate = true; }),
              ),
            ] else ...[
              TextField(
                controller: _msgCtrl,
                maxLines: 4,
                style: AppTextStyles.body.copyWith(color: AppColors.ctNavy),
                decoration: InputDecoration(
                  hintText: 'Escribe tu mensaje…',
                  hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                  filled: true,
                  fillColor: AppColors.ctSurface2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
            // Template preview
            if (_useTemplate && tpl != null && (tpl['body'] ?? tpl['text']) != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.ctTeal.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _resolvePreview(tpl),
                  style: AppTextStyles.navItem.copyWith(color: AppColors.ctNavy),
                ),
              ),
            ],
          ],
          // Error
          if (_sendError != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: AppColors.ctRedBg, borderRadius: BorderRadius.circular(6)),
              child: Text(_sendError!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctRedText)),
            ),
          ],
          const SizedBox(height: 16),
          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                label: 'Cancelar',
                onPressed: () => Navigator.of(context).pop(),
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.sm,
                isDisabled: _sending,
              ),
              const SizedBox(width: 8),
              AppButton(
                label: 'Enviar',
                onPressed: _send,
                variant: AppButtonVariant.teal,
                size: AppButtonSize.sm,
                isLoading: _sending,
                isDisabled: _checkingWindow,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Helpers internos del diálogo ─────────────────────────────────────────────

class _NmSectionHeader extends StatelessWidget {
  const _NmSectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(
        label,
        style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: AppColors.ctText3, letterSpacing: 0.3),
      ),
    );
  }
}

class _NmRecipientItem extends StatefulWidget {
  const _NmRecipientItem({required this.name, required this.phone, required this.onTap});
  final String name;
  final String phone;
  final VoidCallback onTap;

  @override
  State<_NmRecipientItem> createState() => _NmRecipientItemState();
}

class _NmRecipientItemState extends State<_NmRecipientItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: _hover ? AppColors.ctSurface2 : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.ctTeal.withValues(alpha: 0.12),
                child: Text(
                  widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                  style: AppTextStyles.badge.copyWith(color: AppColors.ctTeal),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500, color: AppColors.ctNavy)),
                  if (widget.phone.isNotEmpty)
                    Text(widget.phone, style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3)),
                ],
              ),
              const Spacer(),
              const Icon(Icons.chevron_right, size: 16, color: AppColors.ctText3),
            ],
          ),
        ),
      ),
    );
  }
}

class _NmToggleBtn extends StatelessWidget {
  const _NmToggleBtn({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.ctTeal : AppColors.ctSurface2,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: AppTextStyles.navItem.copyWith(fontWeight: FontWeight.w500, color: active ? AppColors.ctNavy : AppColors.ctText3),
        ),
      ),
    );
  }
}

class _NmTemplateDropdown extends StatelessWidget {
  const _NmTemplateDropdown({required this.templates, required this.selectedId, required this.onChanged});
  final List<Map<String, dynamic>> templates;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (templates.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.ctSurface2, borderRadius: BorderRadius.circular(8)),
        child: Text('No hay plantillas disponibles.', style: AppTextStyles.navItem.copyWith(color: AppColors.ctText3)),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: selectedId,
      hint: Text('Seleccionar plantilla…', style: AppTextStyles.body.copyWith(color: AppColors.ctText3)),
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.ctSurface2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: templates.map((t) {
        final id = (t['id'] ?? t['template_id'])?.toString() ?? '';
        final name = (t['name'] ?? t['template_name'] ?? id).toString();
        return DropdownMenuItem(value: id, child: Text(name, style: AppTextStyles.body.copyWith(color: AppColors.ctNavy)));
      }).toList(),
      onChanged: onChanged,
      dropdownColor: AppColors.ctSurface,
      style: AppTextStyles.body.copyWith(color: AppColors.ctNavy),
    );
  }
}

// ── Media Preview Dialog ──────────────────────────────────────────────────────

class _MediaPreviewDialog extends StatefulWidget {
  const _MediaPreviewDialog({
    required this.bytes,
    required this.filename,
    required this.onSend,
    this.audioDuration,
  });
  final Uint8List bytes;
  final String filename;
  final void Function(String? caption) onSend;
  final int? audioDuration;

  @override
  State<_MediaPreviewDialog> createState() => _MediaPreviewDialogState();
}

class _MediaPreviewDialogState extends State<_MediaPreviewDialog> {
  final _captionCtrl = TextEditingController();

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  void _handleSend() {
    widget.onSend(_isAudio ? null : _captionCtrl.text.trim());
  }

  String get _ext => widget.filename.contains('.')
      ? widget.filename.split('.').last.toLowerCase()
      : '';

  bool get _isImage => ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(_ext);
  bool get _isAudio => ['mp3', 'wav', 'ogg', 'aac', 'm4a', 'opus'].contains(_ext);

  String get _sizeLabel {
    final kb = widget.bytes.length / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  IconData get _docIcon {
    if (_ext == 'pdf') return Icons.picture_as_pdf_rounded;
    if (['doc', 'docx'].contains(_ext)) return Icons.article_rounded;
    if (['xls', 'xlsx'].contains(_ext)) return Icons.table_chart_rounded;
    if (['ppt', 'pptx'].contains(_ext)) return Icons.slideshow_rounded;
    return Icons.description_rounded;
  }

  Color get _docColor {
    if (_ext == 'pdf') return AppColors.ctDanger;
    if (['doc', 'docx'].contains(_ext)) return AppColors.ctInfo;
    if (['xls', 'xlsx'].contains(_ext)) return const Color(0xFF22C55E);
    if (['ppt', 'pptx'].contains(_ext)) return const Color(0xFFF97316);
    return AppColors.ctText3;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.ctSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vista previa',
                style: AppTextStyles.body.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ctNavy),
              ),
              const SizedBox(height: 16),
              // Preview area
              if (_isImage)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: Image.memory(widget.bytes, fit: BoxFit.contain),
                  ),
                )
              else if (_isAudio)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.ctSurface2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.mic_rounded, size: 32, color: AppColors.ctTeal),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.filename,
                              style: AppTextStyles.body.copyWith(color: AppColors.ctNavy),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget.audioDuration != null)
                              Text(
                                '${widget.audioDuration! ~/ 60}:${(widget.audioDuration! % 60).toString().padLeft(2, '0')}',
                                style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.ctSurface2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(_docIcon, size: 32, color: _docColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.filename,
                              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500, color: AppColors.ctNavy),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _sizeLabel,
                              style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              // Caption (not for audio)
              if (!_isAudio) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _captionCtrl,
                  style: AppTextStyles.body.copyWith(color: AppColors.ctNavy),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _handleSend(),
                  decoration: InputDecoration(
                    hintText: 'Agregar caption…',
                    hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                    filled: true,
                    fillColor: AppColors.ctSurface2,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancelar',
                    onPressed: () => Navigator.of(context).pop(),
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.sm,
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    label: 'Enviar',
                    onPressed: _handleSend,
                    variant: AppButtonVariant.teal,
                    size: AppButtonSize.sm,
                    prefixIcon: const Icon(Icons.send_rounded, size: 14, color: AppColors.ctNavy),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Location Dialog ───────────────────────────────────────────────────────────

class _LocationDialog extends StatefulWidget {
  const _LocationDialog({required this.onSend});
  final void Function(String url) onSend;

  @override
  State<_LocationDialog> createState() => _LocationDialogState();
}

class _LocationDialogState extends State<_LocationDialog> {
  final _urlCtrl = TextEditingController();

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _urlCtrl.text.trim().isNotEmpty;

    return AlertDialog(
      backgroundColor: AppColors.ctSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        'Enviar ubicación',
        style: AppTextStyles.body.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ctNavy),
      ),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: _urlCtrl,
          onChanged: (_) => setState(() {}),
          autofocus: true,
          style: AppTextStyles.body.copyWith(color: AppColors.ctNavy),
          decoration: InputDecoration(
            hintText: 'Pega una URL de Google Maps…',
            hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
            prefixIcon: const Icon(Icons.location_on_rounded, size: 18, color: AppColors.ctText3),
            filled: true,
            fillColor: AppColors.ctSurface2,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ),
      actions: [
        AppButton(
          label: 'Cancelar',
          onPressed: () => Navigator.of(context).pop(),
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.sm,
        ),
        AppButton(
          label: 'Enviar',
          onPressed: () => widget.onSend(_urlCtrl.text.trim()),
          variant: AppButtonVariant.teal,
          size: AppButtonSize.sm,
          isDisabled: !canSend,
        ),
      ],
    );
  }
}

