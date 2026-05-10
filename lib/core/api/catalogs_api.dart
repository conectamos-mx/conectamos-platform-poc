import 'package:conectamos_platform/core/api/api_client.dart';

class CatalogsApi {
  static Future<List<Map<String, dynamic>>> listCatalogs({
    required String tenantId,
  }) async {
    final response = await ApiClient.instance.get(
      '/api/v1/catalogs',
      queryParameters: {'tenant_id': tenantId},
    );
    final raw = response.data;
    final list = raw is List
        ? raw
        : (raw is Map
            ? (raw['items'] ?? raw['catalogs'] ?? raw['data'] ?? [])
            : []);
    return List<Map<String, dynamic>>.from(
        (list as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }

  static Future<Map<String, dynamic>> getCatalog({
    required String tenantId,
    required String catalogId,
  }) async {
    final response = await ApiClient.instance.get(
      '/api/v1/catalogs/$catalogId',
      queryParameters: {'tenant_id': tenantId},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> getCatalogBySlug({
    required String tenantId,
    required String slug,
  }) async {
    final response = await ApiClient.instance.get(
      '/api/v1/catalogs/by-slug/$slug',
      queryParameters: {'tenant_id': tenantId},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> createCatalog({
    required String tenantId,
    required Map<String, dynamic> body,
  }) async {
    final response = await ApiClient.instance.post(
      '/api/v1/catalogs',
      data: {'tenant_id': tenantId, ...body},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> updateCatalog({
    required String tenantId,
    required String catalogId,
    required Map<String, dynamic> body,
  }) async {
    final response = await ApiClient.instance.put(
      '/api/v1/catalogs/$catalogId',
      queryParameters: {'tenant_id': tenantId},
      data: body,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<void> deleteCatalog({
    required String catalogId,
  }) async {
    await ApiClient.instance.delete('/api/v1/catalogs/$catalogId');
  }

  static Future<Map<String, dynamic>> syncCatalog({
    required String catalogId,
  }) async {
    final response = await ApiClient.instance.post(
      '/api/v1/catalogs/$catalogId/sync',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<List<Map<String, dynamic>>> listItems({
    required String tenantId,
    required String catalogId,
  }) async {
    final response = await ApiClient.instance.get(
      '/api/v1/catalogs/$catalogId/items',
      queryParameters: {'tenant_id': tenantId},
    );
    final raw = response.data;
    final list = raw is List
        ? raw
        : (raw is Map ? (raw['items'] ?? raw['data'] ?? []) : []);
    return List<Map<String, dynamic>>.from(
        (list as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }

  static Future<List<Map<String, dynamic>>> searchItems({
    required String tenantId,
    required String catalogId,
    required String q,
  }) async {
    final response = await ApiClient.instance.get(
      '/api/v1/catalogs/$catalogId/items/search',
      queryParameters: {'tenant_id': tenantId, 'q': q},
    );
    final raw = response.data;
    final list = raw is List
        ? raw
        : (raw is Map ? (raw['items'] ?? raw['data'] ?? []) : []);
    return List<Map<String, dynamic>>.from(
        (list as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }

  // stub — endpoint de sync log no disponible aún
  static Future<List<Map<String, dynamic>>> listSyncLog({
    required String tenantId,
    required String catalogId,
  }) async =>
      [];
}
