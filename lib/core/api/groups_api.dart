import 'package:dio/dio.dart';

class GroupsApi {
  static Future<List<Map<String, dynamic>>> listGroupsByTenant({required Dio dio}) async {
    final response = await dio.get('/groups/by-tenant');
    return List<Map<String, dynamic>>.from(response.data);
  }

  static Future<List<Map<String, dynamic>>> listGroups({
    required Dio dio,
    required String channelId,
  }) async {
    final response = await dio.get(
      '/groups',
      queryParameters: {'channel_id': channelId},
    );
    return List<Map<String, dynamic>>.from(response.data);
  }

  static Future<Map<String, dynamic>> createGroup({
    required Dio dio,
    required String channelId,
    required String subject,
    String? description,
  }) async {
    final response = await dio.post('/groups', data: {
      'channel_id': channelId,
      'subject': subject,
      'description': ?description,
    });
    return Map<String, dynamic>.from(response.data);
  }

  static Future<Map<String, dynamic>> getGroup({
    required Dio dio,
    required String groupId,
  }) async {
    final response = await dio.get('/groups/$groupId');
    return Map<String, dynamic>.from(response.data);
  }

  static Future<Map<String, dynamic>> updateGroup({
    required Dio dio,
    required String groupId,
    required String displayName,
  }) async {
    final response = await dio.patch(
      '/groups/$groupId',
      data: {'display_name': displayName},
    );
    return Map<String, dynamic>.from(response.data);
  }

  static Future<void> deleteGroup({
    required Dio dio,
    required String groupId,
  }) async {
    await dio.delete('/groups/$groupId');
  }

  static Future<List<Map<String, dynamic>>> getVisibility({
    required Dio dio,
    required String groupId,
  }) async {
    final response = await dio.get(
      '/groups/$groupId/visibility',
    );
    return List<Map<String, dynamic>>.from(response.data);
  }

  static Future<List<Map<String, dynamic>>> addVisibility({
    required Dio dio,
    required String groupId,
    required List<String> tenantUserIds,
  }) async {
    final response = await dio.post(
      '/groups/$groupId/visibility',
      data: {'tenant_user_ids': tenantUserIds},
    );
    return List<Map<String, dynamic>>.from(response.data);
  }

  static Future<void> removeVisibility({
    required Dio dio,
    required String groupId,
    required String tenantUserId,
  }) async {
    await dio.delete(
      '/groups/$groupId/visibility/$tenantUserId',
    );
  }

  // ── Control Towers ──────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> listControlTowers({required Dio dio}) async {
    final response = await dio.get('/control-towers');
    return List<Map<String, dynamic>>.from(response.data);
  }

  static Future<Map<String, dynamic>> createControlTower({
    required Dio dio,
    required String workerId,
    required String displayName,
    String? description,
    required List<String> participantPhones,
    String? iconUrl,
  }) async {
    final response = await dio.post(
      '/control-towers',
      data: {
        'worker_id': workerId,
        'display_name': displayName,
        if (description != null) 'description': description,
        'participant_phones': participantPhones,
        if (iconUrl != null) 'icon_url': iconUrl,
      },
    );
    return Map<String, dynamic>.from(response.data);
  }

  static Future<Map<String, dynamic>> getControlTower({
    required Dio dio,
    required String towerId,
  }) async {
    final response = await dio.get('/control-towers/$towerId');
    return Map<String, dynamic>.from(response.data);
  }

  static Future<Map<String, dynamic>> updateControlTower({
    required Dio dio,
    required String towerId,
    String? displayName,
    String? description,
    String? status,
    List<String>? participants,
    String? iconUrl,
  }) async {
    final response = await dio.put(
      '/control-towers/$towerId',
      data: {
        if (displayName != null) 'display_name': displayName,
        if (description != null) 'description': description,
        if (status != null) 'status': status,
        if (participants != null) 'participants': participants,
        if (iconUrl != null && iconUrl.isNotEmpty) 'icon_url': iconUrl,
      },
    );
    return Map<String, dynamic>.from(response.data);
  }

  static Future<void> deleteControlTower({
    required Dio dio,
    required String towerId,
  }) async {
    await dio.delete('/control-towers/$towerId');
  }

  static Future<Map<String, dynamic>> sendMessageToTower({
    required Dio dio,
    required String towerId,
    required String message,
  }) async {
    final response = await dio.post(
      '/control-towers/$towerId/send-message',
      data: {'message': message},
    );
    return Map<String, dynamic>.from(response.data);
  }

  static Future<String> uploadControlTowerIcon({
    required Dio dio,
    required List<int> fileBytes,
    required String fileName,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        fileBytes,
        filename: fileName,
      ),
    });
    final response = await dio.post(
      '/control-towers/upload-icon',
      data: formData,
    );
    return response.data['url'] as String;
  }
}
