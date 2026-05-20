import 'package:dio/dio.dart';
import 'package:conectamos_platform/core/api/api_client.dart';

class ChannelsApi {
  static Future<List<Map<String, dynamic>>> listChannels() async {
    final response = await ApiClient.instance.get('/channels');
    return List<Map<String, dynamic>>.from(response.data);
  }

  static Future<Map<String, dynamic>> getChannel({
    required String channelId,
  }) async {
    final response = await ApiClient.instance.get('/channels/$channelId');
    return Map<String, dynamic>.from(response.data);
  }

  static Future<Map<String, dynamic>> createChannel({
    required String tenantWorkerId,
    required String displayName,
    required String color,
    String channelType = 'whatsapp',
    String? phoneNumberId,
    String? wabaId,
    String? waToken,
    Map<String, dynamic>? channelConfig,
  }) async {
    final Map<String, dynamic>? config;
    if (channelConfig != null) {
      config = channelConfig;
    } else {
      final creds = <String, dynamic>{};
      if (phoneNumberId != null) creds['phone_number_id'] = phoneNumberId;
      if (wabaId != null)        creds['waba_id']         = wabaId;
      if (waToken != null)       creds['access_token']    = waToken;
      config = creds.isNotEmpty ? {'credentials': creds} : null;
    }

    final response = await ApiClient.instance.post('/channels', data: {
      'tenant_worker_id': tenantWorkerId,
      'display_name':     displayName,
      'color':            color,
      'channel_type':     channelType,
      'channel_config': ?config,
    });
    return Map<String, dynamic>.from(response.data);
  }

  static Future<Map<String, dynamic>> updateChannel({
    required String channelId,
    String? displayName,
    String? color,
    bool? isActive,
    String? tenantWorkerId,
    String? channelType,
    String? phoneNumberId,
    String? wabaId,
    String? waToken,
    Map<String, dynamic>? channelConfig,
  }) async {
    // Credential fields are always nested under channel_config.credentials
    Map<String, dynamic>? effectiveConfig = channelConfig;
    if (phoneNumberId != null || wabaId != null || waToken != null) {
      final base = Map<String, dynamic>.from(channelConfig ?? {});
      final creds = Map<String, dynamic>.from(
        (base['credentials'] as Map?)?.cast<String, dynamic>() ?? {},
      );
      if (phoneNumberId != null) creds['phone_number_id'] = phoneNumberId;
      if (wabaId != null)        creds['waba_id']         = wabaId;
      if (waToken != null)       creds['access_token']    = waToken;
      base['credentials'] = creds;
      effectiveConfig = base;
    }

    final response = await ApiClient.instance.patch(
      '/channels/$channelId',
      data: {
        'display_name':     ?displayName,
        'color':            ?color,
        'is_active':        ?isActive,
        'tenant_worker_id': ?tenantWorkerId,
        'channel_type':     ?channelType,
        'channel_config':   ?effectiveConfig,
      },
    );
    return Map<String, dynamic>.from(response.data);
  }

  static Future<Map<String, dynamic>> deleteChannel({
    required String tenantWorkerId,
    required String channelId,
  }) async {
    final resp = await ApiClient.instance.delete(
      '/workers/$tenantWorkerId/channels/$channelId',
    );
    return resp.data as Map<String, dynamic>;
  }

  static Future<void> verifyCredentials({
    required String phoneNumberId,
    required String accessToken,
  }) async {
    await ApiClient.instance.post(
      '/channels/verify-credentials',
      data: {
        'phone_number_id': phoneNumberId,
        'access_token':    accessToken,
      },
    );
    // 422 lanzado por Dio como DioException — dejar que suba
  }

  static Future<void> activateWhatsapp({
    required String phoneNumberId,
    required String wabaId,
    required String accessToken,
    required String pin,
  }) async {
    await ApiClient.instance.post(
      '/channels/activate-whatsapp',
      data: {
        'phone_number_id': phoneNumberId,
        'waba_id':         wabaId,
        'access_token':    accessToken,
        'pin':             pin,
      },
    );
    // 422 lanzado por Dio como DioException — dejar que suba
  }

  static Future<Map<String, dynamic>> verifyTelegramToken(String botToken) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
    try {
      final response = await dio.get('https://api.telegram.org/bot$botToken/getMe');
      final data = response.data;
      if (data is Map && data['ok'] == true) {
        final result = (data['result'] as Map?)?.cast<String, dynamic>();
        final username = result?['username'] as String? ?? '';
        return {'ok': true, 'username': username};
      }
      final description = data is Map
          ? (data['description'] as String? ?? 'Token inválido')
          : 'Token inválido';
      throw Exception(description);
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map) {
        final desc = data['description'] as String?;
        if (desc != null) throw Exception(desc);
      }
      throw Exception('No se pudo verificar el token de Telegram');
    }
  }

  static Future<void> activateChannel({
    required String channelId,
  }) async {
    await ApiClient.instance.post('/channels/$channelId/activate');
  }

  static Future<Map<String, dynamic>> syncTemplates({
    required String channelId,
  }) async {
    final response = await ApiClient.instance.post(
      '/templates/sync',
      queryParameters: {'channel_id': channelId},
    );
    return Map<String, dynamic>.from(response.data);
  }

  static Future<List<Map<String, dynamic>>> listTemplates({
    required String channelId,
  }) async {
    final response = await ApiClient.instance.get(
      '/templates',
      queryParameters: {'channel_id': channelId},
    );
    final data = response.data;
    final List raw = data is List
        ? data
        : (data['templates'] ?? data['items'] ?? []) as List;
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> updateWelcomeTemplate({
    required String channelId,
    required String templateId,
  }) async {
    await ApiClient.instance.patch(
      '/channels/$channelId/welcome-template',
      data: {'template_id': templateId},
    );
  }

  static Future<Map<String, dynamic>> embeddedSignup({
    required String code,
    String? phoneNumberId,
    String? wabaId,
    String? businessId,
  }) async {
    final response = await ApiClient.instance.post(
      '/channels/embedded-signup',
      data: {
        'code': code,
        'phone_number_id': ?phoneNumberId,
        'waba_id': ?wabaId,
        'business_id': ?businessId,
      },
    );
    return Map<String, dynamic>.from(response.data);
  }

  static Future<void> postSignupEvent(
    Map<String, dynamic> eventData,
  ) async {
    await ApiClient.instance.post(
      '/channels/embedded-signup/events',
      data: eventData,
    );
  }
}
