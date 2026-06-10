import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart';

class MessagesApi {
  static Future<List<Map<String, dynamic>>> listConversations({required Dio dio}) async {
    final response = await dio.get(
      '/messages',
      queryParameters: {'limit': 500},
    );
    final messages = List<Map<String, dynamic>>.from(response.data);

    final Map<String, Map<String, dynamic>> byChat = {};
    for (final msg in messages) {
      final chatId = msg['chat_id'] as String? ?? '';
      if (!byChat.containsKey(chatId)) {
        byChat[chatId] = msg;
      }
    }
    return byChat.values.toList();
  }

  static Future<List<Map<String, dynamic>>> listMessages({
    required Dio dio,
    String? chatId,
    int limit = 100,
  }) async {
    final response = await dio.get(
      '/messages',
      queryParameters: {
        'chat_id': ?chatId,
        'limit': limit,
      },
    );
    return List<Map<String, dynamic>>.from(response.data);
  }

  static Future<Map<String, dynamic>> sendMessage({
    required Dio dio,
    required String to,
    required String text,
    required String channelId,
    String? phoneNumberId,
  }) async {
    final response = await dio.post(
      '/messages/send',
      queryParameters: {
        'to': to,
        'text': text,
        'channel_id': channelId,
        'phone_number_id': ?phoneNumberId,
      },
    );
    return Map<String, dynamic>.from(response.data);
  }

  static Future<void> markRead(String waMessageId, {required Dio dio, String? tenantId, required String channelId}) async {
    // ignore: avoid_print
    debugPrint('[MessagesApi.markRead] entry — waMessageId=$waMessageId tenantId=$tenantId channelId=$channelId');
    if (waMessageId.isEmpty || waMessageId == 'null') {
      debugPrint('[MessagesApi.markRead] GUARD: empty/null waMessageId');
      return;
    }
    if (tenantId == null || tenantId.isEmpty) {
      debugPrint('[MessagesApi.markRead] GUARD: empty tenantId');
      return;
    }
    if (channelId.isEmpty) {
      debugPrint('[MessagesApi.markRead] GUARD: empty channelId');
      return;
    }
    try {
      await dio.post(
        '/messages/read',
        data: {'message_id': waMessageId, 'channel_id': channelId},
      );
      debugPrint('[MessagesApi.markRead] OK — $waMessageId');
    } catch (e) {
      debugPrint('[MessagesApi.markRead] ERROR — $waMessageId → $e');
    }
  }

  static Future<void> sendTyping(String waMessageId, {required Dio dio, String? tenantId, required String channelId}) async {
    if (waMessageId.isEmpty || waMessageId == 'null') return;
    if (tenantId == null || tenantId.isEmpty) return;
    if (channelId.isEmpty) return;
    try {
      await dio.post(
        '/messages/typing',
        data: {'message_id': waMessageId, 'channel_id': channelId},
      );
    } catch (_) {}
  }

  /// Envía un mensaje outbound a través del backend.
  /// El backend llama a Meta Graph API y persiste el registro en wa_messages.
  static Future<void> sendWhatsAppMessage({
    required Dio dio,
    required String to,
    required String text,
    required String channelId,
    String? sentByUserId,
    String? replyToMessageId,
  }) async {
    if (to.isEmpty || channelId.isEmpty) return;
    await dio.post(
      '/messages/send',
      data: {
        'to':                   to,
        'message':              text,
        'channel_id':           channelId,
        'sent_by_user_id':     ?sentByUserId,
        'reply_to_message_id': ?replyToMessageId,
      },
    );
  }

  /// Envía una reacción emoji sobre un mensaje.
  static Future<void> sendReaction({
    required Dio dio,
    required String messageId,
    required String emoji,
    required String toPhone,
    required String channelId,
  }) async {
    await dio.post(
      '/messages/send/reaction',
      data: {
        'message_id': messageId,
        'emoji':      emoji,
        'to_phone':   toPhone,
        'channel_id': channelId,
      },
    );
  }

  /// Envía una reacción emoji sobre un mensaje de Telegram.
  static Future<void> sendTelegramReaction({
    required Dio dio,
    required String channelId,
    required int toChatId,
    required int messageId,
    required String emoji,
    String? sentByUserId,
  }) async {
    await dio.post(
      '/messages/send/reaction/telegram',
      data: {
        'channel_id':   channelId,
        'to_chat_id':   toChatId,
        'message_id':   messageId,
        'emoji':        emoji,
        'sent_by_user_id': ?sentByUserId,
      },
    );
  }

  /// Envía un archivo multimedia (imagen, audio, documento) vía multipart.
  static Future<void> sendMedia({
    required Dio dio,
    required String to,
    required Uint8List fileBytes,
    required String filename,
    required String channelId,
    String? caption,
    String? sentByUserId,
    String? replyToMessageId,
  }) async {
    final formData = FormData.fromMap({
      'to': to,
      'channel_id': channelId,
      'file': MultipartFile.fromBytes(
        fileBytes,
        filename: filename,
        contentType: MediaType.parse(_contentTypeForFilename(filename)),
      ),
      if (caption != null && caption.isNotEmpty) 'caption': caption,
      'sent_by_user_id': ?sentByUserId,
      'reply_to_message_id': ?replyToMessageId,
    });
    await dio.post('/messages/send/media', data: formData);
  }

  /// Envía una ubicación de Google Maps parseando la URL.
  static Future<void> sendLocation({
    required Dio dio,
    required String to,
    required String channelId,
    required String googleMapsUrl,
    String? sentByUserId,
  }) async {
    await dio.post(
      '/messages/send/location',
      data: {
        'to':              to,
        'channel_id':      channelId,
        'google_maps_url': googleMapsUrl,
        'sent_by_user_id': ?sentByUserId,
      },
    );
  }

  /// Envía una solicitud de ubicación interactiva.
  static Future<void> sendLocationRequest({
    required Dio dio,
    required String to,
    required String channelId,
    String? sentByUserId,
  }) async {
    await dio.post(
      '/messages/send/location-request',
      data: {
        'to':              to,
        'channel_id':      channelId,
        'sent_by_user_id': ?sentByUserId,
      },
    );
  }

  static String _contentTypeForFilename(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.mp4'))  return 'audio/mp4';
    if (lower.endsWith('.ogg'))  return 'audio/ogg';
    if (lower.endsWith('.webm')) return 'audio/webm';
    if (lower.endsWith('.aac'))  return 'audio/aac';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png'))  return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf'))  return 'application/pdf';
    if (lower.endsWith('.doc'))  return 'application/msword';
    if (lower.endsWith('.docx')) return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    if (lower.endsWith('.xls'))  return 'application/vnd.ms-excel';
    if (lower.endsWith('.xlsx')) return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    return 'application/octet-stream';
  }
}
