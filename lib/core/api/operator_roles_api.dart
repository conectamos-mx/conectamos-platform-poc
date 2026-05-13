import 'package:conectamos_platform/core/api/api_client.dart';

class OperatorRolesApi {
  static Future<List<Map<String, dynamic>>> listRoles({
    required String tenantId,
  }) async {
    final res = await ApiClient.instance.get('/api/v1/operator-roles');
    final raw = res.data;
    final list = raw is List
        ? raw
        : (raw is Map
            ? (raw['operator_roles'] ?? raw['items'] ?? raw['roles'] ?? raw['data'] ?? [])
            : []);
    return List<Map<String, dynamic>>.from(
        (list as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }

  static Future<Map<String, dynamic>> createRole({
    required String tenantId,
    required Map<String, dynamic> body,
  }) async {
    final res = await ApiClient.instance.post(
      '/api/v1/operator-roles',
      data: {'tenant_id': tenantId, ...body},
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<Map<String, dynamic>> updateRole({
    required String tenantId,
    required String roleId,
    required Map<String, dynamic> body,
  }) async {
    final res = await ApiClient.instance.put(
      '/api/v1/operator-roles/$roleId',
      queryParameters: {'tenant_id': tenantId},
      data: body,
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<void> deleteRole({required String roleId}) async {
    await ApiClient.instance.delete('/api/v1/operator-roles/$roleId');
  }

  static Future<List<Map<String, dynamic>>> listOperatorsByRole({
    required String tenantId,
    required String roleId,
  }) async {
    final res = await ApiClient.instance.get(
      '/api/v1/operator-roles/$roleId/operators',
      queryParameters: {'tenant_id': tenantId},
    );
    final raw = res.data;
    final list = raw is List
        ? raw
        : (raw is Map
            ? (raw['items'] ?? raw['operators'] ?? raw['data'] ?? [])
            : []);
    return List<Map<String, dynamic>>.from(
        (list as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }
}
