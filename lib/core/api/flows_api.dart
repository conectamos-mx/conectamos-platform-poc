import 'package:dio/dio.dart';

class FlowsApi {
  static Future<List<Map<String, dynamic>>> listFlows({
    required Dio dio,
    String? triggerSource,
  }) async {
    final params = <String, dynamic>{};
    if (triggerSource != null) params['trigger_source'] = triggerSource;
    final response = await dio.get(
      '/flows',
      queryParameters: params,
    );
    return List<Map<String, dynamic>>.from(response.data);
  }

  static Future<List<Map<String, dynamic>>> getFlowsByWorker({
    required Dio dio,
    required String tenantWorkerId,
  }) async {
    final response = await dio.get(
      '/flows',
      queryParameters: {
        'tenant_worker_id': tenantWorkerId,
      },
    );
    final raw = response.data;
    final list = raw is List ? raw : (raw is Map ? (raw['flows'] ?? raw['items'] ?? raw['data'] ?? []) : []);
    return List<Map<String, dynamic>>.from(
        (list as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }

  static Future<Map<String, dynamic>> getFlow({
    required Dio dio,
    required String flowId,
  }) async {
    final response = await dio.get(
      '/flows/$flowId',
    );
    return Map<String, dynamic>.from(response.data);
  }

  static Future<Map<String, dynamic>> createFlow({
    required Dio dio,
    required String tenantWorkerId,
    required String name,
    required String slug,
    String? description,
    List<Map<String, dynamic>> fields = const [],
    Map<String, dynamic> behavior = const {},
    List<String>? allowedRoleIds,
    List<String>? triggerSources,
  }) async {
    final response = await dio.post('/flows', data: {
      'tenant_worker_id': tenantWorkerId,
      'name':             name,
      'slug':             slug,
      'description':      ?description,
      'fields':           fields,
      'behavior':         behavior,
      'allowed_role_ids': ?allowedRoleIds,
      'trigger_sources':  ?triggerSources,
    });
    return Map<String, dynamic>.from(response.data);
  }

  static Future<Map<String, dynamic>> updateFlow({
    required Dio dio,
    required String flowId,
    String? name,
    String? slug,
    String? description,
    bool? isActive,
    List<Map<String, dynamic>>? fields,
    Map<String, dynamic>? behavior,
    Map<String, dynamic>? onComplete,
    List<String>? triggerSources,
    bool? sendProactive,
    List<String>? allowedRoleIds,
    List<Map<String, dynamic>>? preconditions,
  }) async {
    final body = <String, dynamic>{
      'name':              ?name,
      'slug':              ?slug,
      'description':       ?description,
      'is_active':         ?isActive,
      'fields':            ?fields,
      'behavior':          ?behavior,
      'on_complete':       ?onComplete,
      'trigger_sources':   ?triggerSources,
      'send_proactive':    ?sendProactive,
      'allowed_role_ids':  ?allowedRoleIds,
      'preconditions':     ?preconditions,
    };
    final response = await dio.patch(
      '/flows/$flowId',
      data: body,
    );
    return Map<String, dynamic>.from(response.data);
  }

  static Future<void> deleteFlow({
    required Dio dio,
    required String flowId,
  }) async {
    try {
      await dio.delete(
        '/flows/$flowId',
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        final data = e.response?.data;
        final detail = data is Map ? data['detail'] : null;
        if (detail is Map) {
          throw FlowDeleteBlockedException(
            code: detail['code'] as String? ?? 'flow_has_active_executions',
            message: detail['message'] as String? ?? 'Este flujo tiene ejecuciones activas.',
            activeCount: detail['active_count'] as int? ?? 0,
          );
        }
      }
      rethrow;
    }
  }

  // ── Integrations ────────────────────────────────────────────────────────────

  // @deprecated — usar listIntegrationsByTenant
  static Future<List<Map<String, dynamic>>> listIntegrations({
    required Dio dio,
    required String flowId,
  }) async {
    final response = await dio.get(
      '/flows/$flowId/integrations',
    );
    final raw = response.data;
    final list = raw is List
        ? raw
        : (raw is Map ? (raw['integrations'] ?? raw['items'] ?? raw['data'] ?? []) : []);
    return List<Map<String, dynamic>>.from(
        (list as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }

  // @deprecated — usar createIntegrationForTenant
  static Future<Map<String, dynamic>> createIntegration({
    required Dio dio,
    required String flowId,
    required String name,
    required String integrationType,
    String? endpointUrl,
    bool includeAncestors = false,
    int rateLimitPerMinute = 60,
  }) async {
    final response = await dio.post(
      '/flows/$flowId/integrations',
      data: {
        'name':                name,
        'integration_type':    integrationType,
        'endpoint_url':        ?endpointUrl,
        'include_ancestors':   includeAncestors,
        'rate_limit_per_minute': rateLimitPerMinute,
      },
    );
    return Map<String, dynamic>.from(response.data);
  }

  static Future<Map<String, dynamic>> patchIntegration({
    required Dio dio,
    required String flowId,
    required String integrationId,
    required String endpointUrl,
  }) async {
    final response = await dio.patch(
      '/flows/$flowId/integrations/$integrationId',
      data: {'endpoint_url': endpointUrl},
    );
    return Map<String, dynamic>.from(response.data);
  }

  // @deprecated — usar deleteIntegrationById
  static Future<void> deleteIntegration({
    required Dio dio,
    required String flowId,
    required String integrationId,
  }) async {
    await dio.delete(
      '/flows/$flowId/integrations/$integrationId',
    );
  }

  // ── Tenant-level integrations ────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> listIntegrationsByTenant({
    required Dio dio,
    String? tenantWorkerId,
    String? integrationType,
  }) async {
    final params = <String, dynamic>{};
    if (tenantWorkerId != null) params['tenant_worker_id'] = tenantWorkerId;
    if (integrationType != null) params['integration_type'] = integrationType;
    final response = await dio.get(
      '/integrations',
      queryParameters: params,
    );
    final raw = response.data;
    final list = raw is List
        ? raw
        : (raw is Map
            ? (raw['integrations'] ?? raw['items'] ?? raw['data'] ?? [])
            : []);
    return List<Map<String, dynamic>>.from(
        (list as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }

  static Future<Map<String, dynamic>> createIntegrationForTenant({
    required Dio dio,
    required String name,
    required String integrationType,
    required String tenantWorkerId,
    String? endpointUrl,
    int rateLimitPerMinute = 60,
  }) async {
    final response = await dio.post(
      '/integrations',
      data: {
        'name': name,
        'integration_type': integrationType,
        'tenant_worker_id': tenantWorkerId,
        'endpoint_url': ?endpointUrl,
        'rate_limit_per_minute': rateLimitPerMinute,
      },
    );
    return Map<String, dynamic>.from(response.data);
  }

  static Future<void> deleteIntegrationById({
    required Dio dio,
    required String integrationId,
  }) async {
    await dio.delete(
      '/integrations/$integrationId',
    );
  }

  // ── Dashboard (executions) ──────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> listPendingExecutions({
    required Dio dio,
    String? flowSlug,
  }) async {
    final params = <String, dynamic>{
      'status': 'pending_dashboard',
    };
    if (flowSlug != null) params['flow_slug'] = flowSlug;
    final response = await dio.get(
      '/api/v1/dashboard/executions',
      queryParameters: params,
    );
    final raw = response.data;
    final list = raw is List ? raw : (raw is Map ? (raw['items'] ?? raw['executions'] ?? raw['data'] ?? []) : []);
    return List<Map<String, dynamic>>.from(
        (list as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }

  static Future<Map<String, dynamic>?> getActiveFlow({
    required Dio dio,
    required String operatorId,
  }) async {
    final response = await dio.get(
      '/flows/active',
      queryParameters: {
        'operator_id': operatorId,
      },
    );
    final data = response.data as Map<String, dynamic>?;
    return data?['execution'] as Map<String, dynamic>?;
  }

  static Future<Map<String, dynamic>> getExecution({
    required Dio dio,
    required String executionId,
  }) async {
    final response = await dio.get(
      '/api/v1/dashboard/executions/$executionId',
    );
    final data = Map<String, dynamic>.from(response.data);
    return data;
  }

  static Future<void> submitExecution({
    required Dio dio,
    required String executionId,
    required Map<String, String> fields,
  }) async {
    await dio.post(
      '/api/v1/dashboard/executions/$executionId/submit',
      data: {'fields': fields},
    );
  }

  static Future<Map<String, dynamic>> abandonExecution({
    required Dio dio,
    required String executionId,
  }) async {
    final resp = await dio.post(
      '/api/v1/dashboard/flow-executions/$executionId/abandon',
    );
    return resp.data as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> listDashboardConfigurations({
    required Dio dio,
  }) async {
    final response = await dio.get(
      '/api/v1/dashboard/configurations',
    );
    final raw = response.data;
    final list = raw is List ? raw : <dynamic>[];
    return List<Map<String, dynamic>>.from(
        list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }

  static Future<Map<String, dynamic>?> getDashboardConfiguration({
    required Dio dio,
    required String slug,
  }) async {
    try {
      final response = await dio.get(
        '/api/v1/dashboard/configurations/$slug',
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getDashboardKpis({
    required Dio dio,
    required String dashboardSlug,
    String? dateRangeStart,
    String? dateRangeEnd,
  }) async {
    final params = <String, dynamic>{'dashboard_slug': dashboardSlug};
    if (dateRangeStart != null) params['date_range_start'] = dateRangeStart;
    if (dateRangeEnd != null) params['date_range_end'] = dateRangeEnd;
    final response = await dio.get(
      '/api/v1/dashboard/kpis',
      queryParameters: params,
    );
    final raw = response.data;
    final list = raw is List ? raw : [];
    // Convertir lista a mapa widget_id → kpi data para lookup O(1)
    final Map<String, dynamic> byWidgetId = {};
    for (final item in list) {
      if (item is Map && item['widget_id'] != null) {
        byWidgetId[item['widget_id'] as String] = Map<String, dynamic>.from(item);
      }
    }
    return byWidgetId;
  }

  static Future<List<Map<String, dynamic>>> getDashboardActivity({
    required Dio dio,
    required String dashboardSlug,
    String? dateRangeStart,
    String? dateRangeEnd,
  }) async {
    final params = <String, dynamic>{'dashboard_slug': dashboardSlug};
    if (dateRangeStart != null) params['date_range_start'] = dateRangeStart;
    if (dateRangeEnd != null) params['date_range_end'] = dateRangeEnd;
    final response = await dio.get(
      '/api/v1/dashboard/activity',
      queryParameters: params,
    );
    final raw = response.data;
    final list = raw is List ? raw : <dynamic>[];
    return List<Map<String, dynamic>>.from(
        list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }

  static Future<List<Map<String, dynamic>>> getActionTypes({
    required Dio dio,
  }) async {
    final response = await dio.get('/flows/action-types');
    final raw = response.data;
    final list = raw is Map ? (raw['types'] ?? []) : raw;
    return List<Map<String, dynamic>>.from(
        (list as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }

  static Future<List<Map<String, dynamic>>> getPreconditionTypes({
    required Dio dio,
  }) async {
    final response = await dio.get(
      '/flows/precondition-types',
    );
    final raw = response.data;
    final list = raw is Map ? (raw['types'] ?? []) : raw;
    return List<Map<String, dynamic>>.from(
        (list as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }

  static Future<Map<String, dynamic>> getDashboardCharts({
    required Dio dio,
    required String dashboardSlug,
    String? dateRangeStart,
    String? dateRangeEnd,
  }) async {
    final params = <String, dynamic>{'dashboard_slug': dashboardSlug};
    if (dateRangeStart != null) params['date_range_start'] = dateRangeStart;
    if (dateRangeEnd != null) params['date_range_end'] = dateRangeEnd;
    final response = await dio.get(
      '/api/v1/dashboard/charts',
      queryParameters: params,
    );
    final raw = response.data;
    final list = raw is List ? raw : [];
    final Map<String, dynamic> byWidgetId = {};
    for (final item in list) {
      if (item is Map && item['widget_id'] != null) {
        byWidgetId[item['widget_id'] as String] = Map<String, dynamic>.from(item);
      }
    }
    return byWidgetId;
  }
}

class FlowDeleteBlockedException implements Exception {
  FlowDeleteBlockedException({
    required this.code,
    required this.message,
    required this.activeCount,
  });
  final String code;
  final String message;
  final int activeCount;

  @override
  String toString() => message;
}
