import 'package:conectamos_platform/core/api/api_client.dart';

class GroupsApi {
  static Future<List<Map<String, dynamic>>> listGroupsByTenant() async {
    final response = await ApiClient.instance.get('/groups/by-tenant');
    return List<Map<String, dynamic>>.from(response.data);
  }

  static Future<List<Map<String, dynamic>>> listGroups({
    required String channelId,
  }) async {
    final response = await ApiClient.instance.get(
      '/groups',
      queryParameters: {'channel_id': channelId},
    );
    return List<Map<String, dynamic>>.from(response.data);
  }

  static Future<Map<String, dynamic>> createGroup({
    required String channelId,
    required String subject,
    String? description,
  }) async {
    final response = await ApiClient.instance.post('/groups', data: {
      'channel_id': channelId,
      'subject': subject,
      'description': ?description,
    });
    return Map<String, dynamic>.from(response.data);
  }

  static Future<Map<String, dynamic>> getGroup({
    required String groupId,
  }) async {
    final response = await ApiClient.instance.get('/groups/$groupId');
    return Map<String, dynamic>.from(response.data);
  }

  static Future<Map<String, dynamic>> updateGroup({
    required String groupId,
    required String displayName,
  }) async {
    final response = await ApiClient.instance.patch(
      '/groups/$groupId',
      data: {'display_name': displayName},
    );
    return Map<String, dynamic>.from(response.data);
  }

  static Future<void> deleteGroup({
    required String groupId,
  }) async {
    await ApiClient.instance.delete('/groups/$groupId');
  }

  static Future<List<Map<String, dynamic>>> getVisibility({
    required String groupId,
  }) async {
    final response = await ApiClient.instance.get(
      '/groups/$groupId/visibility',
    );
    return List<Map<String, dynamic>>.from(response.data);
  }

  static Future<List<Map<String, dynamic>>> addVisibility({
    required String groupId,
    required List<String> tenantUserIds,
  }) async {
    final response = await ApiClient.instance.post(
      '/groups/$groupId/visibility',
      data: {'tenant_user_ids': tenantUserIds},
    );
    return List<Map<String, dynamic>>.from(response.data);
  }

  static Future<void> removeVisibility({
    required String groupId,
    required String tenantUserId,
  }) async {
    await ApiClient.instance.delete(
      '/groups/$groupId/visibility/$tenantUserId',
    );
  }

  // ── Control Towers ──────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> listControlTowers() async {
    final response = await ApiClient.instance.get('/control-towers');
    return List<Map<String, dynamic>>.from(response.data);
  }

  static Future<Map<String, dynamic>> createControlTower({
    required String workerId,
    required String displayName,
    String? description,
    required List<String> participantPhones,
  }) async {
    final response = await ApiClient.instance.post(
      '/control-towers',
      data: {
        'worker_id': workerId,
        'display_name': displayName,
        if (description != null) 'description': description,
        'participant_phones': participantPhones,
      },
    );
    return Map<String, dynamic>.from(response.data);
  }

  static Future<Map<String, dynamic>> getControlTower({
    required String towerId,
  }) async {
    final response = await ApiClient.instance.get('/control-towers/$towerId');
    return Map<String, dynamic>.from(response.data);
  }

  static Future<Map<String, dynamic>> updateControlTower({
    required String towerId,
    String? displayName,
    String? description,
    String? status,
    List<String>? participants,
    String? iconUrl,
  }) async {
    final response = await ApiClient.instance.put(
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
    required String towerId,
  }) async {
    await ApiClient.instance.delete('/control-towers/$towerId');
  }

  static Future<Map<String, dynamic>> sendMessageToTower({
    required String towerId,
    required String message,
  }) async {
    final response = await ApiClient.instance.post(
      '/control-towers/$towerId/send-message',
      data: {'message': message},
    );
    return Map<String, dynamic>.from(response.data);
  }
}
