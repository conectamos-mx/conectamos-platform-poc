import 'package:dio/dio.dart';

class CatalogsApi {
  static Future<List<Map<String, dynamic>>> listCatalogs({
    required Dio dio,
    required String tenantId,
  }) async {
    final response = await dio.get(
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
    required Dio dio,
    required String tenantId,
    required String catalogId,
  }) async {
    final response = await dio.get(
      '/api/v1/catalogs/$catalogId',
      queryParameters: {'tenant_id': tenantId},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> getCatalogBySlug({
    required Dio dio,
    required String tenantId,
    required String slug,
  }) async {
    final response = await dio.get(
      '/api/v1/catalogs/by-slug/$slug',
      queryParameters: {'tenant_id': tenantId},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> createCatalog({
    required Dio dio,
    required String tenantId,
    required Map<String, dynamic> body,
  }) async {
    final response = await dio.post(
      '/api/v1/catalogs',
      data: {'tenant_id': tenantId, ...body},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> updateCatalog({
    required Dio dio,
    required String tenantId,
    required String catalogId,
    required Map<String, dynamic> body,
  }) async {
    final response = await dio.put(
      '/api/v1/catalogs/$catalogId',
      queryParameters: {'tenant_id': tenantId},
      data: body,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<void> deleteCatalog({
    required Dio dio,
    required String catalogId,
  }) async {
    await dio.delete('/api/v1/catalogs/$catalogId');
  }

  static Future<Map<String, dynamic>> syncCatalog({
    required Dio dio,
    required String catalogId,
  }) async {
    final response = await dio.post(
      '/api/v1/catalogs/$catalogId/sync',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<List<Map<String, dynamic>>> getOnedriveFiles({
    required Dio dio,
    required String tenantId,
  }) async {
    final response = await dio.get(
      '/api/v1/catalogs/tools/onedrive-files',
      queryParameters: {'tenant_id': tenantId},
    );
    final raw = response.data;
    final list = raw is Map
        ? (raw['files'] ?? [])
        : (raw is List ? raw : []);
    return List<Map<String, dynamic>>.from(
        (list as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }

  static Future<Map<String, dynamic>> getOnedrivePreview({
    required Dio dio,
    required String tenantId,
    required String fileId,
    String? sheetName,
  }) async {
    final params = <String, dynamic>{
      'tenant_id': tenantId,
      'file_id': fileId,
    };
    if (sheetName != null && sheetName.isNotEmpty) {
      params['sheet_name'] = sheetName;
    }
    final response = await dio.get(
      '/api/v1/catalogs/tools/onedrive-preview',
      queryParameters: params,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> sheetsPreview({
    required Dio dio,
    required String tenantId,
    required String sheetUrl,
    String? sheetName,
  }) async {
    final params = <String, dynamic>{
      'tenant_id': tenantId,
      'sheet_url': sheetUrl,
    };
    if (sheetName != null && sheetName.isNotEmpty) {
      params['sheet_name'] = sheetName;
    }
    final response = await dio.get(
      '/api/v1/catalogs/tools/sheets-preview',
      queryParameters: params,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<List<Map<String, dynamic>>> listItems({
    required Dio dio,
    required String tenantId,
    required String catalogId,
  }) async {
    final response = await dio.get(
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
    required Dio dio,
    required String tenantId,
    required String catalogId,
    required String q,
  }) async {
    final response = await dio.get(
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

  static Future<List<Map<String, dynamic>>> getFieldTypes({
    required Dio dio,
  }) async {
    final response = await dio.get('/api/v1/field-types');
    final raw = response.data;
    final list = raw is Map
        ? (raw['types'] ?? raw['items'] ?? raw['data'] ?? [])
        : (raw is List ? raw : []);
    return List<Map<String, dynamic>>.from(
        (list as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }

  static Future<List<Map<String, dynamic>>> listSyncLog({
    required Dio dio,
    required String tenantId,
    required String catalogId,
    int limit = 50,
  }) async {
    final response = await dio.get(
      '/api/v1/catalogs/$catalogId/sync-log',
      queryParameters: {'tenant_id': tenantId, 'limit': limit},
    );
    final raw = response.data;
    final list = raw is Map ? (raw['logs'] ?? []) : (raw is List ? raw : []);
    return List<Map<String, dynamic>>.from(
        (list as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }

  static Future<Map<String, dynamic>> listItemsPaged({
    required Dio dio,
    required String tenantId,
    required String catalogId,
    int page = 1,
    int pageSize = 50,
    String? search,
  }) async {
    final params = <String, dynamic>{
      'tenant_id': tenantId,
      'page': page,
      'page_size': pageSize,
    };
    if (search != null && search.isNotEmpty) params['search'] = search;
    final response = await dio.get(
      '/api/v1/catalogs/$catalogId/items',
      queryParameters: params,
    );
    final raw = response.data;
    if (raw is Map) {
      final list = raw['items'] ?? raw['data'] ?? [];
      return {
        'items': List<Map<String, dynamic>>.from(
            (list as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e))),
        'total': raw['total'] ?? 0,
        'page': raw['page'] ?? page,
        'pages': raw['pages'] ?? 1,
      };
    }
    return {'items': <Map<String, dynamic>>[], 'total': 0, 'page': 1, 'pages': 1};
  }

  static Future<Map<String, dynamic>> createItem({
    required Dio dio,
    required String tenantId,
    required String catalogId,
    required Map<String, dynamic> data,
  }) async {
    final response = await dio.post(
      '/api/v1/catalogs/$catalogId/items',
      queryParameters: {'tenant_id': tenantId},
      data: {'data': data},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> updateItem({
    required Dio dio,
    required String tenantId,
    required String catalogId,
    required String itemId,
    required Map<String, dynamic> data,
  }) async {
    final response = await dio.put(
      '/api/v1/catalogs/$catalogId/items/$itemId',
      queryParameters: {'tenant_id': tenantId},
      data: {'data': data},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> deleteItem({
    required Dio dio,
    required String tenantId,
    required String catalogId,
    required String itemId,
  }) async {
    final response = await dio.delete(
      '/api/v1/catalogs/$catalogId/items/$itemId',
      queryParameters: {'tenant_id': tenantId},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<List<Map<String, dynamic>>> getUsages({
    required Dio dio,
    required String tenantId,
    required String catalogId,
  }) async {
    final response = await dio.get(
      '/api/v1/catalogs/$catalogId/usages',
    );
    final list = response.data as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
