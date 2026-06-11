import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

class SupabaseReadReceipts {
  /// Carga todos los last_read_at del usuario desde el backend.
  static Future<Map<String, DateTime>> loadAll({
    required Dio dio,
    required String userId,
    required String tenantId,
  }) async {
    try {
      final response = await dio.get(
        '/read-receipts',
        queryParameters: {'user_id': userId, 'tenant_id': tenantId},
      );
      final rows = List<Map<String, dynamic>>.from(response.data as List);
      final result = <String, DateTime>{};
      for (final row in rows) {
        final chatId = row['chat_id'] as String?;
        final lastRead =
            DateTime.tryParse(row['last_read_at'] as String? ?? '');
        if (chatId != null && lastRead != null) {
          result[chatId] = lastRead;
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  /// Guarda o actualiza el last_read_at de un chat a través del backend.
  static Future<void> setLastRead(
    String chatId,
    DateTime time,
    String tenantId, {
    required Dio dio,
  }) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      await dio.post(
        '/read-receipts',
        data: {
          'user_id': userId,
          'tenant_id': tenantId,
          'chat_id': chatId,
          'last_read_at': time.toIso8601String(),
        },
      );
    } catch (_) {
      // silencioso — no bloquear la UI si falla la persistencia
    }
  }
}
