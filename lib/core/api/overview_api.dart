import 'package:dio/dio.dart';

class OverviewApi {
  static Future<Map<String, dynamic>> getKpis({
    required Dio dio,
    required String tenantId,
  }) async {
    final response = await dio.get(
      '/tenants/$tenantId/kpis',
    );
    return Map<String, dynamic>.from(response.data);
  }

  static Future<Map<String, dynamic>> getFlowExecutionsDebug({
    required Dio dio,
    required String tenantId,
  }) async {
    final response = await dio.get(
      '/tenants/$tenantId/flow-executions/debug',
    );
    return Map<String, dynamic>.from(response.data);
  }
}
