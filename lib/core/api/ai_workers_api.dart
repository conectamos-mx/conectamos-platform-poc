import 'package:conectamos_platform/core/api/api_client.dart';

class AiWorkersApi {
  /// Workers contratados por el tenant.
  static Future<List<Map<String, dynamic>>> listWorkers() async {
    final response = await ApiClient.instance.get('/workers');
    return List<Map<String, dynamic>>.from(response.data);
  }

  /// Catálogo de workers visibles para el tenant.
  static Future<List<Map<String, dynamic>>> listCatalog() async {
    final response = await ApiClient.instance.get('/catalog/workers');
    return List<Map<String, dynamic>>.from(response.data);
  }

  /// Contratar un worker del catálogo para el tenant.
  static Future<Map<String, dynamic>> contractWorker({
    required String catalogWorkerId,
    String? displayName,
  }) async {
    final response = await ApiClient.instance.post('/workers/contract', data: {
      'catalog_worker_id': catalogWorkerId,
      'display_name':      ?displayName,
    });
    return Map<String, dynamic>.from(response.data);
  }

  /// Workers contratados por el tenant (alias explícito de listWorkers).
  static Future<List<Map<String, dynamic>>> listTenantWorkers() async {
    final response = await ApiClient.instance.get('/workers');
    return List<Map<String, dynamic>>.from(response.data);
  }

  /// Actualizar nombre personalizado o estado activo de un tenant_worker.
  static Future<Map<String, dynamic>> updateWorker({
    required String tenantWorkerId,
    String? displayName,
    bool? isActive,
  }) async {
    final response = await ApiClient.instance.patch(
      '/workers/$tenantWorkerId',
      data: {
        'display_name': ?displayName,
        'is_active':    ?isActive,
      },
    );
    return Map<String, dynamic>.from(response.data);
  }

  /// Dar de baja (soft delete) un tenant_worker.
  static Future<void> fireWorker(String tenantWorkerId) async {
    await ApiClient.instance.delete('/workers/$tenantWorkerId');
  }
}
