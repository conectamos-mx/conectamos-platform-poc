import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseMessages {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<List<Map<String, dynamic>>> listConversations({
    String? tenantId,
  }) async {
    var query = _client
        .from('wa_messages')
        .select(
            'id, wa_message_id, chat_id, from_phone, from_name, raw_body, message_type, received_at, direction, wa_status, channel_id, context_message_id, context_from, reaction_emoji, reaction_message_id, media_url');

    if (tenantId != null && tenantId.isNotEmpty) {
      query = query.eq('tenant_id', tenantId);
    }

    final response = await query
        .order('received_at', ascending: false)
        .limit(500);
    final messages = List<Map<String, dynamic>>.from(response);

    final Map<String, Map<String, dynamic>> byChat = {};

    for (final msg in messages) {
      final chatId = msg['chat_id'] as String? ?? '';
      if (chatId.isEmpty) continue;

      final isInbound = (msg['direction'] as String?) != 'outbound';

      if (!byChat.containsKey(chatId)) {
        byChat[chatId] = Map<String, dynamic>.from(msg);
        byChat[chatId]!['contact_name'] =
            isInbound ? msg['from_name'] : null;
      } else {
        final existingIsOutbound =
            byChat[chatId]!['direction'] == 'outbound';
        if (existingIsOutbound && isInbound) {
          byChat[chatId]!['from_name'] = msg['from_name'];
        }
        if (isInbound && byChat[chatId]!['contact_name'] == null) {
          byChat[chatId]!['contact_name'] = msg['from_name'];
        }
      }
    }

    for (final entry in byChat.entries) {
      entry.value['contact_name'] ??= entry.key;
    }

    final result = byChat.values.toList();
    result.sort((a, b) {
      final aTime =
          DateTime.tryParse(a['received_at'] as String? ?? '') ?? DateTime(0);
      final bTime =
          DateTime.tryParse(b['received_at'] as String? ?? '') ?? DateTime(0);
      return bTime.compareTo(aTime);
    });

    return result;
  }

  static Future<List<Map<String, dynamic>>> getMessages(
    String chatId, {
    int limit = 100,
    String? tenantId,
    DateTime? before,
    bool ascending = true,
  }) async {
    var query = _client
        .from('wa_messages')
        .select(
            'id, wa_message_id, chat_id, from_phone, from_name, raw_body, message_type, received_at, direction, wa_status, channel_id, context_message_id, context_from, reaction_emoji, reaction_message_id, media_url')
        .eq('chat_id', chatId);

    if (tenantId != null && tenantId.isNotEmpty) {
      query = query.eq('tenant_id', tenantId);
    }
    if (before != null) {
      query = query.lt('received_at', before.toUtc().toIso8601String());
    }

    return List<Map<String, dynamic>>.from(
      await query.order('received_at', ascending: ascending).limit(limit),
    );
  }

  /// Streams individual INSERT events on wa_messages for the given chat.
  /// Emits one Map per new row — no full-list re-emit.
  static Stream<Map<String, dynamic>> streamNewMessages(
    String chatId, {
    String? tenantId,
  }) {
    final controller = StreamController<Map<String, dynamic>>();
    RealtimeChannel? rtChannel;

    rtChannel = _client
        .channel('chat_inserts_$chatId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'wa_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: chatId,
          ),
          callback: (payload) {
            final row = Map<String, dynamic>.from(payload.newRecord);
            if (tenantId != null &&
                tenantId.isNotEmpty &&
                row['tenant_id'] != tenantId) {
              return;
            }
            if (!controller.isClosed) controller.add(row);
          },
        )
        .subscribe();

    controller.onCancel = () {
      if (rtChannel != null) _client.removeChannel(rtChannel);
    };

    return controller.stream;
  }

  @Deprecated('Use getMessages + streamNewMessages instead')
  static Stream<List<Map<String, dynamic>>> streamMessages(
    String chatId, {
    String? tenantId,
  }) {
    return _client
        .from('wa_messages')
        .stream(primaryKey: ['id'])
        .eq('chat_id', chatId)
        .order('received_at', ascending: true)
        .map((data) {
          var list = List<Map<String, dynamic>>.from(data);
          if (tenantId != null && tenantId.isNotEmpty) {
            list = list.where((m) => m['tenant_id'] == tenantId).toList();
          }
          return list;
        });
  }

  /// Streams individual INSERT events on wa_messages for the given channel+tenant.
  /// Emits one Map per new row — no full-list re-emit.
  /// Fields: all wa_messages columns in the Realtime payload.
  static Stream<Map<String, dynamic>> streamIncomingMessages({
    required String channelId,
    required String tenantId,
  }) {
    final controller = StreamController<Map<String, dynamic>>();
    RealtimeChannel? rtChannel;

    rtChannel = _client
        .channel('convo_feed_$channelId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'wa_messages',
          callback: (payload) {
            final row = Map<String, dynamic>.from(payload.newRecord);
            // Client-side filter: ensure this row belongs to the active channel+tenant
            if (row['channel_id'] == channelId && row['tenant_id'] == tenantId) {
              if (!controller.isClosed) controller.add(row);
            }
          },
        )
        .subscribe();

    controller.onCancel = () {
      if (rtChannel != null) _client.removeChannel(rtChannel);
    };

    return controller.stream;
  }

  static Stream<List<Map<String, dynamic>>> streamFeed({
    String? chatId,
    String? direction,
    String? keyword,
    required String tenantId,
    DateTime? fromDate,
    DateTime? toDate,
    int limit = 200,
  }) {
    assert(tenantId.isNotEmpty, 'streamFeed: tenantId must not be empty');

    // When a date range is active, use a static SELECT query so we can apply
    // DB-level gte/lte filters. The .stream() builder only supports .eq(), so
    // date filtering client-side over a 200-row window would miss messages.
    if (fromDate != null || toDate != null) {
      return Stream.fromFuture(
        _fetchFeedStatic(
          chatId: chatId,
          direction: direction,
          keyword: keyword,
          tenantId: tenantId,
          fromDate: fromDate,
          toDate: toDate,
          limit: 500,
        ),
      );
    }

    final query = Supabase.instance.client
        .from('wa_messages')
        .stream(primaryKey: ['id'])
        .eq('tenant_id', tenantId)
        .order('received_at', ascending: false)
        .limit(limit);

    return query.map((data) {
      var messages = List<Map<String, dynamic>>.from(data);

      if (chatId != null && chatId.isNotEmpty) {
        messages = messages.where((m) => m['chat_id'] == chatId).toList();
      }
      if (direction != null && direction.isNotEmpty) {
        messages =
            messages.where((m) => m['direction'] == direction).toList();
      }
      if (keyword != null && keyword.isNotEmpty) {
        final kw = keyword.toLowerCase();
        messages = messages.where((m) {
          final body = (m['raw_body'] as String? ?? '').toLowerCase();
          final name = (m['from_name'] as String? ?? '').toLowerCase();
          return body.contains(kw) || name.contains(kw);
        }).toList();
      }
      return messages;
    });
  }

  static Future<List<Map<String, dynamic>>> _fetchFeedStatic({
    String? chatId,
    String? direction,
    String? keyword,
    required String tenantId,
    DateTime? fromDate,
    DateTime? toDate,
    int limit = 500,
  }) async {
    var query = _client
        .from('wa_messages')
        .select('*')
        .eq('tenant_id', tenantId);

    if (chatId != null && chatId.isNotEmpty) {
      query = query.eq('chat_id', chatId);
    }
    if (direction != null && direction.isNotEmpty) {
      query = query.eq('direction', direction);
    }
    if (fromDate != null) {
      query = query.gte('received_at', fromDate.toUtc().toIso8601String());
    }
    if (toDate != null) {
      query = query.lte('received_at', toDate.toUtc().toIso8601String());
    }

    var messages = List<Map<String, dynamic>>.from(
      await query.order('received_at', ascending: false).limit(limit),
    );

    if (keyword != null && keyword.isNotEmpty) {
      final kw = keyword.toLowerCase();
      messages = messages.where((m) {
        final body = (m['raw_body'] as String? ?? '').toLowerCase();
        final name = (m['from_name'] as String? ?? '').toLowerCase();
        return body.contains(kw) || name.contains(kw);
      }).toList();
    }

    return messages;
  }
}
