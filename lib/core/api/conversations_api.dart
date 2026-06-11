import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ConversationsApi {
  static Future<List<Map<String, dynamic>>> listConversations({
    required Dio dio,
    required String channelId,
    bool includeUnregistered = false,
  }) async {
    final params = <String, dynamic>{'channel_id': channelId};
    if (includeUnregistered) params['include_unregistered'] = 'true';
    final response = await dio.get(
      '/conversations',
      queryParameters: params,
    );
    final data = response.data;
    final List raw = data is List
        ? data
        : (data['conversations'] ?? data['items'] ?? []) as List;
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// DELETE /wa-messages — hard-delete de mensajes sin operador (solo admin).
  /// from_phone es el chat_id del contacto no registrado.
  static Future<void> deleteUnregisteredConversation({
    required Dio dio,
    required String fromPhone,
    required String channelId,
  }) async {
    await dio.delete(
      '/wa-messages',
      queryParameters: {
        'from_phone': fromPhone,
        'channel_id': channelId,
      },
    );
  }

  /// PATCH /conversations/assign — asigna un operador a un chat no registrado.
  static Future<void> assignConversationOperator({
    required Dio dio,
    required String chatId,
    required String channelId,
    required String operatorId,
  }) async {
    await dio.patch(
      '/conversations/assign',
      data: {
        'chat_id': chatId,
        'channel_id': channelId,
        'operator_id': operatorId,
      },
    );
  }

  static Future<void> markChatRead({
    required Dio dio,
    required String chatId,
    required String channelId,
  }) async {
    try {
      await dio.post('/panel-read', data: {
        'chat_id': chatId,
        'channel_id': channelId,
      });
    } catch (e) {
      debugPrint('[markChatRead] error: $e');
      // Non-critical — no lanzar excepción
    }
  }
}
