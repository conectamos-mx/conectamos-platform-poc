import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:conectamos_platform/core/api/api_client.dart';

class ExecutionsApi {
  ExecutionsApi._();

  /// Lista executions con filtros, paginación y objetos enriquecidos.
  /// Usa GET /api/v1/dashboard/executions.
  /// X-Tenant-ID es inyectado automáticamente por el interceptor de ApiClient.
  static Future<Map<String, dynamic>> listExecutions({
    required String tenantId,
    List<String>? status,
    List<String>? workerIds,
    List<String>? operatorIds,
    List<String>? flowIds,
    List<String>? actorTypes,
    String? channelType,
    String? dateRange,
    String dateField = 'created_at',
    String? dateFrom,
    String? dateTo,
    String? search,
    String? fieldKey,
    List<String>? fieldValues,
    String sortCol = 'created_at',
    String sortDir = 'desc',
    int page = 1,
    int limit = 25,
  }) async {
    final params = <String, dynamic>{
      'sort_col':   sortCol,
      'sort_dir':   sortDir,
      'page':       page,
      'limit':      limit,
      'date_field': dateField,
    };
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (workerIds != null && workerIds.isNotEmpty) params['worker_id'] = workerIds;
    if (operatorIds != null && operatorIds.isNotEmpty) params['operator_id'] = operatorIds;
    if (flowIds != null && flowIds.isNotEmpty) params['flow_id'] = flowIds;
    if (actorTypes != null && actorTypes.isNotEmpty) params['actor_type'] = actorTypes;
    if (channelType != null) params['channel_type'] = channelType;
    if (dateRange != null) params['date_range'] = dateRange;
    if (dateFrom != null) params['date_from'] = dateFrom;
    if (dateTo != null) params['date_to'] = dateTo;
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (fieldKey != null) params['field_key'] = fieldKey;
    if (fieldValues != null && fieldValues.isNotEmpty) params['field_values'] = fieldValues;

    final resp = await ApiClient.instance.get(
      '/api/v1/dashboard/executions',
      queryParameters: params,
    );
    final data = resp.data;
    // Normaliza: el endpoint puede devolver lista plana o wrapper con items/total
    if (data is List) {
      return {'items': data, 'total': data.length};
    }
    return Map<String, dynamic>.from(data as Map);
  }

  /// Lista vistas guardadas del tenant.
  static Future<List<Map<String, dynamic>>> listViews({
    required String tenantId,
  }) async {
    final resp = await ApiClient.instance.get(
      '/api/v1/dashboard/views',
    );
    final data = resp.data;
    final list = data is List
        ? data
        : (data is Map ? (data['items'] ?? data['views'] ?? []) : []);
    return List<Map<String, dynamic>>.from(
        (list as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }

  /// Crea una vista guardada con los filtros actuales.
  static Future<Map<String, dynamic>> createView({
    required String tenantId,
    required String name,
    required Map<String, dynamic> filters,
  }) async {
    final resp = await ApiClient.instance.post(
      '/api/v1/dashboard/views',
      data: {
        'name':    name,
        'filters': filters,
      },
    );
    return Map<String, dynamic>.from(resp.data as Map);
  }

  /// Elimina una vista guardada.
  static Future<void> deleteView({required String viewId}) async {
    await ApiClient.instance.delete('/api/v1/dashboard/views/$viewId');
  }

  /// Exporta ejecuciones filtradas como XLSX (bytes).
  static Future<Uint8List> exportExecutions({
    required String tenantId,
    List<String>? status,
    List<String>? workerIds,
    List<String>? operatorIds,
    List<String>? flowIds,
    List<String>? actorTypes,
    String? channelType,
    String? dateRange,
    String dateField = 'created_at',
    String? dateFrom,
    String? dateTo,
    String? search,
    String? fieldKey,
    List<String>? fieldValues,
  }) async {
    final params = <String, dynamic>{'date_field': dateField};
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (workerIds != null && workerIds.isNotEmpty) params['worker_id'] = workerIds;
    if (operatorIds != null && operatorIds.isNotEmpty) params['operator_id'] = operatorIds;
    if (flowIds != null && flowIds.isNotEmpty) params['flow_id'] = flowIds;
    if (actorTypes != null && actorTypes.isNotEmpty) params['actor_type'] = actorTypes;
    if (channelType != null) params['channel_type'] = channelType;
    if (dateRange != null) params['date_range'] = dateRange;
    if (dateFrom != null) params['date_from'] = dateFrom;
    if (dateTo != null) params['date_to'] = dateTo;
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (fieldKey != null) params['field_key'] = fieldKey;
    if (fieldValues != null && fieldValues.isNotEmpty) params['field_values'] = fieldValues;

    final resp = await ApiClient.instance.get(
      '/api/v1/dashboard/executions/export',
      queryParameters: params,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(resp.data as List<int>);
  }

  /// Retorna la lista de estatus disponibles para ejecuciones.
  static Future<List<Map<String, String>>> getExecutionStatuses() async {
    try {
      final response = await ApiClient.instance.get('/flow-executions/statuses');
      final raw = response.data;
      final list = raw is Map ? (raw['statuses'] ?? []) : (raw is List ? raw : []);
      return (list as List)
          .whereType<Map>()
          .map((e) => {'value': e['value']?.toString() ?? '', 'label': e['label']?.toString() ?? ''})
          .where((e) => e['value']!.isNotEmpty)
          .toList();
    } catch (_) {
      return [
        {'value': 'active',             'label': 'Activa'},
        {'value': 'paused',             'label': 'Pausada'},
        {'value': 'completed',          'label': 'Completada'},
        {'value': 'abandoned',          'label': 'Abandonada'},
        {'value': 'escalated',          'label': 'Escalada'},
        {'value': 'pending_completion', 'label': 'Pendiente de completar'},
        {'value': 'pending_dashboard',  'label': 'En revisión'},
        {'value': 'pending_input',      'label': 'Esperando respuesta'},
        {'value': 'created',            'label': 'Creada'},
      ];
    }
  }

  /// Lista mensajes asociados a una ejecución.
  static Future<List<Map<String, dynamic>>> getMessages({
    required String executionId,
  }) async {
    final resp = await ApiClient.instance.get(
      '/api/v1/dashboard/executions/$executionId/messages',
    );
    final data = resp.data;
    final list = data is List
        ? data
        : (data is Map ? (data['messages'] ?? []) : []);
    return List<Map<String, dynamic>>.from(
        (list as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }

  /// Campos buscables por clave de campo (para filtro avanzado).
  static Future<Map<String, dynamic>> getSearchableFields({
    required String tenantId,
    List<String>? workerIds,
  }) async {
    final params = <String, dynamic>{};
    if (workerIds != null && workerIds.isNotEmpty) {
      params['worker_id'] = workerIds;
    }

    final resp = await ApiClient.instance.get(
      '/api/v1/dashboard/executions/searchable-fields',
      queryParameters: params,
    );
    return resp.data as Map<String, dynamic>;
  }
}
