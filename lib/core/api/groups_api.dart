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
}
