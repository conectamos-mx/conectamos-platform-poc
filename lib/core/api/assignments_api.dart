import 'package:conectamos_platform/core/api/api_client.dart';

class AssignmentsApi {
  static Future<List<Map<String, dynamic>>> getAssignments({
    required String tenantId,
    String? operatorId,
    String? assignmentType,
    String? scopeDate,
  }) async {
    final params = <String, dynamic>{'tenant_id': tenantId};
    if (operatorId != null) params['operator_id'] = operatorId;
    if (assignmentType != null) params['assignment_type'] = assignmentType;
    if (scopeDate != null) params['scope_date'] = scopeDate;
    final response = await ApiClient.instance.get(
      '/api/v1/assignments',
      queryParameters: params,
    );
    final raw = response.data;
    final list = raw is List
        ? raw
        : (raw is Map ? (raw['items'] ?? raw['assignments'] ?? raw['data'] ?? []) : []);
    return List<Map<String, dynamic>>.from(
        (list as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }

  static Future<Map<String, dynamic>> createAssignment({
    required String tenantId,
    required Map<String, dynamic> body,
  }) async {
    final response = await ApiClient.instance.post(
      '/api/v1/assignments',
      data: {'tenant_id': tenantId, ...body},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<void> deleteAssignment({
    required String tenantId,
    required String assignmentId,
  }) async {
    await ApiClient.instance.delete(
      '/api/v1/assignments/$assignmentId',
      queryParameters: {'tenant_id': tenantId},
    );
  }

  static Future<Map<String, dynamic>> bulkUpsert({
    required String tenantId,
    required List<Map<String, dynamic>> assignments,
  }) async {
    final response = await ApiClient.instance.post(
      '/api/v1/assignments/bulk',
      data: {'tenant_id': tenantId, 'assignments': assignments},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> materialize({
    required String tenantId,
    required String catalogSlug,
    required String assignmentType,
    required Map<String, dynamic> mapping,
  }) async {
    final response = await ApiClient.instance.post(
      '/api/v1/assignments/materialize',
      data: {
        'tenant_id': tenantId,
        'catalog_slug': catalogSlug,
        'assignment_type': assignmentType,
        'mapping': mapping,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  // ── Assignment Types ──────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getAssignmentTypes({
    required String tenantId,
  }) async {
    final response = await ApiClient.instance.get('/api/v1/assignment-types');
    final raw = response.data;
    final list = raw is List
        ? raw
        : (raw is Map
            ? (raw['items'] ?? raw['types'] ?? raw['data'] ?? [])
            : []);
    return List<Map<String, dynamic>>.from(
        (list as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }

  static Future<Map<String, dynamic>> createAssignmentType({
    required String tenantId,
    required Map<String, dynamic> body,
  }) async {
    final response = await ApiClient.instance.post(
      '/api/v1/assignment-types',
      data: {'tenant_id': tenantId, ...body},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> updateAssignmentType({
    required String tenantId,
    required String slug,
    required Map<String, dynamic> body,
  }) async {
    final response = await ApiClient.instance.put(
      '/api/v1/assignment-types/$slug',
      queryParameters: {'tenant_id': tenantId},
      data: body,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> deleteAssignmentType({
    required String tenantId,
    required String slug,
  }) async {
    final response = await ApiClient.instance.delete(
      '/api/v1/assignment-types/$slug',
      queryParameters: {'tenant_id': tenantId},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }
}
