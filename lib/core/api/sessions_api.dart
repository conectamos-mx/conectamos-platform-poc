import 'package:dio/dio.dart';

class SessionsApi {
  static Future<List<Map<String, dynamic>>> listSessions({
    required Dio dio,
    String? status,
    String? operatorId,
  }) async {
    final response = await dio.get(
      '/sessions',
      queryParameters: {
        'status': ?status,
        'operator_id': ?operatorId,
      },
    );
    return List<Map<String, dynamic>>.from(response.data);
  }

  static Future<List<Map<String, dynamic>>> getSessionEvents(
    String sessionId, {
    required Dio dio,
  }) async {
    final response = await dio.get(
      '/sessions/$sessionId/events',
    );
    return List<Map<String, dynamic>>.from(response.data);
  }

  static Future<void> patchStatus({
    required Dio dio,
    required String sessionId,
    required String status,
  }) async {
    await dio.patch(
      '/sessions/$sessionId',
      data: {'status': status},
    );
  }

  /// Busca el ID de la sesión activa para un chat (phone).
  static Future<String?> findActiveSessionId({
    required Dio dio,
    required String chatId,
  }) async {
    try {
      final sessions = await listSessions(dio: dio);
      final match = sessions.firstWhere(
        (s) => (s['chat_id'] as String?) == chatId || (s['phone'] as String?) == chatId,
        orElse: () => {},
      );
      return match['id'] as String?;
    } catch (_) {
      return null;
    }
  }
}
