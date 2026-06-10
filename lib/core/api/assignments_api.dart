import 'package:dio/dio.dart';

class AssignmentsApi {
  static Future<List<Map<String, dynamic>>> listAssignments({
    required Dio dio,
    required String tenantId,
    String? operatorId,
    String? scopeDate,
  }) async {
    final response = await dio.get(
      '/api/v1/assignments',
      queryParameters: {
        'operator_id': ?operatorId,
        'scope_date': ?scopeDate,
      },
    );
    final raw = response.data;
    final list = raw is List
        ? raw
        : (raw is Map ? (raw['items'] ?? raw['assignments'] ?? raw['data'] ?? []) : []);
    return List<Map<String, dynamic>>.from(
        (list as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }

  static Future<Map<String, dynamic>> getAssignment({
    required Dio dio,
    required String tenantId,
    required String assignmentId,
  }) async {
    final response =
        await dio.get('/api/v1/assignments/$assignmentId');
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> createAssignment({
    required Dio dio,
    required String tenantId,
    required String operatorId,
    required DateTime scopeStart,
    required DateTime scopeEnd,
    required List<Map<String, dynamic>> resources,
    required List<Map<String, dynamic>> flows,
    String source = 'manual',
  }) async {
    final scope =
        '[${scopeStart.toUtc().toIso8601String()},${scopeEnd.toUtc().toIso8601String()})';
    final response = await dio.post(
      '/api/v1/assignments/ingest',
      data: {
        'operator_id': operatorId,
        'scope': scope,
        'resources': resources,
        'flows': flows,
        'source': source,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<void> deleteAssignment({
    required Dio dio,
    required String tenantId,
    required String assignmentId,
  }) async {
    await dio.delete('/api/v1/assignments/$assignmentId');
  }
}
