import 'dart:typed_data';
import 'package:conectamos_platform/core/api/api_client.dart';
import 'package:dio/dio.dart';

class OperatorsApi {
  static Future<List<Map<String, dynamic>>> listOperators() async {
    final response = await ApiClient.instance.get('/operators');
    return List<Map<String, dynamic>>.from(response.data);
  }

  static Future<Map<String, dynamic>> getOperator(String operatorId) async {
    final response = await ApiClient.instance.get('/operators/$operatorId');
    return Map<String, dynamic>.from(response.data);
  }

  static Future<Map<String, dynamic>> createOperator({
    required String displayName,
    required String phone,
    List<String> roleIds = const [],
    String? telegramChatId,
    String? email,
    String? nationality,
    String? identityType,
    String? identityNumber,
    String? profilePictureUrl,
    List<Map<String, dynamic>>? phoneSecondary,
    Map<String, dynamic>? customFieldValues,
  }) async {
    final metadata = <String, dynamic>{};
    if (telegramChatId != null && telegramChatId.isNotEmpty) {
      metadata['telegram_chat_id'] = telegramChatId;
    }
    if (phoneSecondary != null && phoneSecondary.isNotEmpty) {
      metadata['phone_secondary'] = phoneSecondary;
    }

    final response = await ApiClient.instance.post(
      '/operators',
      data: {
        'display_name': displayName,
        'phone': phone,
        'role_ids': roleIds,
        if (email != null && email.isNotEmpty) 'email': email,
        if (nationality != null && nationality.isNotEmpty)
          'nationality': nationality,
        'identity_type': ?identityType,
        if (identityNumber != null && identityNumber.isNotEmpty)
          'identity_number': identityNumber,
        if (profilePictureUrl != null && profilePictureUrl.isNotEmpty)
          'profile_picture_url': profilePictureUrl,
        if (metadata.isNotEmpty) 'metadata': metadata,
        if (customFieldValues != null && customFieldValues.isNotEmpty)
          'custom_field_values': customFieldValues,
      },
    );
    return Map<String, dynamic>.from(response.data);
  }

  static Future<Map<String, dynamic>> updateOperator({
    required String id,
    required String displayName,
    required String phone,
    List<String> roleIds = const [],
    String? telegramChatId,
    String? email,
    String? profilePictureUrl,
    List<Map<String, dynamic>>? phoneSecondary,
    Map<String, dynamic>? customFieldValues,
  }) async {
    final extraMeta = <String, dynamic>{};
    if (phoneSecondary != null) {
      extraMeta['phone_secondary'] = phoneSecondary;
    }

    final response = await ApiClient.instance.put(
      '/operators/$id',
      data: {
        'display_name': displayName,
        'phone': phone,
        'role_ids': roleIds,
        'telegram_chat_id': telegramChatId ?? '',
        'email':                ?email,
        'profile_picture_url':  ?profilePictureUrl,
        if (extraMeta.isNotEmpty) 'extra_metadata': extraMeta,
        if (customFieldValues != null && customFieldValues.isNotEmpty)
          'custom_field_values': customFieldValues,
      },
    );
    return Map<String, dynamic>.from(response.data);
  }

  static Future<void> patchStatus({
    required String id,
    required String status,
  }) async {
    await ApiClient.instance.patch(
      '/operators/$id/status',
      data: {'status': status},
    );
  }

  /// GET /operators/{id}/available-channel-types?tenant_id=
  /// Returns the channel types the operator actually has via assigned flows.
  static Future<List<String>> getAvailableChannelTypes({
    required String operatorId,
  }) async {
    final response = await ApiClient.instance.get(
      '/operators/$operatorId/available-channel-types',
    );
    final data = response.data;
    final List raw = data is Map
        ? ((data['channel_types'] ?? data['types'] ?? []) as List)
        : data is List
            ? data
            : [];
    return raw.map((e) => e.toString()).toList();
  }

  /// PATCH /operators/{id} — persists the ordered list of preferred channel types.
  static Future<void> patchPreferredChannelTypes({
    required String id,
    required List<String> types,
  }) async {
    await ApiClient.instance.put(
      '/operators/$id',
      data: {'preferred_channel_types': types},
    );
  }

  /// PUT /operators/{id} — updates the operator's role_ids array.
  static Future<void> patchRoleIds({
    required String id,
    required List<String> roleIds,
  }) async {
    await ApiClient.instance.put(
      '/operators/$id',
      data: {'role_ids': roleIds},
    );
  }

  static Future<List<Map<String, dynamic>>> listOperatorFlows({
    required String operatorId,
  }) async {
    final response = await ApiClient.instance.get('/operators/$operatorId/flows');
    return List<Map<String, dynamic>>.from(response.data);
  }

  static Future<void> assignFlow({
    required String operatorId,
    required String flowDefinitionId,
  }) async {
    await ApiClient.instance.post(
      '/operators/$operatorId/flows',
      data: {
        'flow_definition_id': flowDefinitionId,
      },
    );
  }

  static Future<void> removeFlow({
    required String operatorId,
    required String flowDefinitionId,
  }) async {
    await ApiClient.instance.delete('/operators/$operatorId/flows/$flowDefinitionId');
  }

  /// Sends a Telegram invite to the operator via the given channel.
  /// Returns the response body (may include expires_at).
  static Future<Map<String, dynamic>> sendTelegramInvite({
    required String operatorId,
    required String channelId,
    String? phone,
  }) async {
    final response = await ApiClient.instance.post(
      '/operators/$operatorId/send-telegram-invite',
      data: {
        'channel_id': channelId,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      },
    );
    return response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : {};
  }

  /// GET /operators/{id}/available-telegram-channels
  /// Returns: {"channels": [{"channel_id": "uuid", "bot_username": "...", "worker_name": "..."}, ...]}
  static Future<List<Map<String, dynamic>>> getAvailableTelegramChannels(
    String operatorId,
  ) async {
    final response = await ApiClient.instance.get(
      '/operators/$operatorId/available-telegram-channels',
    );
    final data = response.data;
    if (data is Map && data['channels'] is List) {
      return List<Map<String, dynamic>>.from(data['channels'] as List);
    }
    return [];
  }

  static Future<Map<String, dynamic>> importDryRun({
    required Uint8List fileBytes,
    required String fileName,
    String strategy = 'all_or_nothing',
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(fileBytes, filename: fileName),
      'strategy': strategy,
    });
    final response = await ApiClient.instance.post(
      '/operators/import',
      data: formData,
      queryParameters: {'dry_run': 'true'},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> importOperators({
    required Uint8List fileBytes,
    required String fileName,
    String strategy = 'all_or_nothing',
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(fileBytes, filename: fileName),
      'strategy': strategy,
    });
    final response = await ApiClient.instance.post(
      '/operators/import',
      data: formData,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> linkToUser({
    required String operatorId,
    String? tenantUserId,
    String? phone,
  }) async {
    assert(tenantUserId != null || phone != null,
        'Se requiere tenantUserId o phone');
    final body = <String, dynamic>{};
    if (tenantUserId != null) body['tenant_user_id'] = tenantUserId;
    if (phone != null) body['phone'] = phone;
    final res = await ApiClient.instance.post(
      '/operators/$operatorId/link-to-user',
      data: body,
    );
    return res.data is Map
        ? Map<String, dynamic>.from(res.data as Map)
        : {};
  }

  static Future<void> unlinkFromUser({
    required String operatorId,
  }) async {
    await ApiClient.instance.post(
      '/operators/$operatorId/unlink-from-user',
    );
  }

  /// `GET /operators/lookup?phone=E164`
  static Future<Map<String, dynamic>> lookupByPhone({
    required String phone,
  }) async {
    final response = await ApiClient.instance.get(
      '/operators/lookup',
      queryParameters: {'phone': phone},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// POST /operators (new creation contract with optional tenant-user link)
  static Future<Map<String, dynamic>> createOperatorV2({
    required String displayName,
    required String phone,
    List<String> roleIds = const [],
    String? linkToTenantUserId,
    List<String>? preferredChannelTypes,
    bool createDespiteSoftDeleted = false,
  }) async {
    final response = await ApiClient.instance.post(
      '/operators',
      data: {
        'display_name': displayName,
        'phone': phone,
        'role_ids': roleIds,
        'link_to_tenant_user_id': ?linkToTenantUserId,
        if (preferredChannelTypes != null && preferredChannelTypes.isNotEmpty)
          'preferred_channel_types': preferredChannelTypes,
        if (createDespiteSoftDeleted)
          'create_despite_soft_deleted': true,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// POST /operators/:id/restore
  static Future<Map<String, dynamic>> restoreOperator({
    required String id,
    String? linkToTenantUserId,
  }) async {
    final response = await ApiClient.instance.post(
      '/operators/$id/restore',
      data: {
        'link_to_tenant_user_id': ?linkToTenantUserId,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static String templateUrl({String nationality = 'MX'}) {
    return '${ApiClient.baseUrl}/operators/export/template?nationality=$nationality';
  }
}
