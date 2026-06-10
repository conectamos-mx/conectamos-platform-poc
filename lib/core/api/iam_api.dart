import 'package:dio/dio.dart';

class IamApi {
  static Future<List<Map<String, dynamic>>> getUsers({required Dio dio}) async {
    final res = await dio.get('/iam/users');
    final data = res.data;
    final List raw = data is List
        ? data
        : (data['users'] ?? data['items'] ?? []) as List;
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<List<Map<String, dynamic>>> getRoles({required Dio dio}) async {
    final res = await dio.get('/iam/roles');
    final data = res.data;
    final List raw = data is List
        ? data
        : (data['roles'] ?? data['items'] ?? []) as List;
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> updateUser(
    String id,
    Map<String, dynamic> data, {
    required Dio dio,
  }) async {
    await dio.patch('/iam/users/$id', data: data);
  }

  static Future<void> updateUserRole(String id, String roleId, {required Dio dio}) async {
    await dio.patch(
      '/iam/users/$id/role',
      data: {'role_id': roleId},
    );
  }

  static Future<void> resendInvite(String id, {required Dio dio}) async {
    await dio.post('/iam/users/$id/resend-invite');
  }

  static Future<void> inviteUser(Map<String, dynamic> data, {required Dio dio}) async {
    await dio.post('/iam/invite', data: data);
  }

  static Future<void> resetPassword(String email, {required Dio dio}) async {
    await dio.post(
      '/iam/password-reset',
      data: {'email': email},
    );
  }

  static Future<List<Map<String, dynamic>>> getUserChannels({
    required Dio dio,
    required String tenantUserId,
  }) async {
    final res = await dio.get(
      '/supervisor-channel-access',
      queryParameters: {'tenant_user_id': tenantUserId},
    );
    final data = res.data;
    final List raw = data is List ? data : (data['items'] ?? []) as List;
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> assignChannel({
    required Dio dio,
    required String tenantUserId,
    required String channelId,
  }) async {
    await dio.post(
      '/supervisor-channel-access',
      data: {
        'tenant_user_id': tenantUserId,
        'channel_id':     channelId,
      },
    );
  }

  static Future<void> removeChannel({
    required Dio dio,
    required String tenantUserId,
    required String channelId,
  }) async {
    await dio.delete(
      '/supervisor-channel-access',
      data: {
        'tenant_user_id': tenantUserId,
        'channel_id':     channelId,
      },
    );
  }

  static Future<Map<String, dynamic>> linkOperator({
    required Dio dio,
    required String tenantUserId,
    required String phone,
  }) async {
    final res = await dio.post(
      '/iam/users/$tenantUserId/link-operator',
      data: {'phone': phone},
    );
    return res.data is Map
        ? Map<String, dynamic>.from(res.data as Map)
        : {};
  }

  static Future<void> unlinkOperator({
    required Dio dio,
    required String tenantUserId,
  }) async {
    await dio.post(
      '/iam/users/$tenantUserId/unlink-operator',
    );
  }

  static Future<Map<String, dynamic>> getInvitation(String token, {required Dio dio}) async {
    final res = await dio.get('/iam/invite/$token');
    return res.data is Map
        ? Map<String, dynamic>.from(res.data as Map)
        : <String, dynamic>{};
  }

  static Future<void> acceptInvitation(
    String token, {
    required String password,
    required Dio dio,
  }) async {
    await dio.post(
      '/iam/invite/$token/accept',
      data: {'password': password},
    );
  }

  static Future<void> deleteUser(String id, {required Dio dio}) async {
    await dio.delete('/iam/users/$id');
  }

  static Future<void> revokeInvitation(String id, {required Dio dio}) async {
    await dio.delete('/iam/invitations/$id');
  }
}
