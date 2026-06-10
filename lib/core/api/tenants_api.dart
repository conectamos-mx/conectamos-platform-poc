import 'package:dio/dio.dart';

class TenantsApi {
  static Future<List<Map<String, dynamic>>> getTenants({
    required Dio dio,
    String? userId,
  }) async {
    final queryParams =
        userId != null ? {'user_id': userId} : null;
    final response = await dio.get(
      '/tenants',
      queryParameters: queryParams,
    );
    return List<Map<String, dynamic>>.from(response.data);
  }
}
