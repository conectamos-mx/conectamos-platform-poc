import 'package:dio/dio.dart';

class ChannelsApi {
  static Future<List<Map<String, dynamic>>> listChannels({required Dio dio}) async {
    final response = await dio.get('/channels');
    return List<Map<String, dynamic>>.from(response.data);
  }

  static Future<Map<String, dynamic>> getChannel({
    required Dio dio,
    required String channelId,
  }) async {
    final response = await dio.get('/channels/$channelId');
    return Map<String, dynamic>.from(response.data);
  }

  static Future<Map<String, dynamic>> createChannel({
    required Dio dio,
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

    final response = await dio.post('/channels', data: {
      'tenant_worker_id': tenantWorkerId,
      'display_name':     displayName,
      'color':            color,
      'channel_type':     channelType,
      'channel_config': ?config,
    });
    return Map<String, dynamic>.from(response.data);
  }

  static Future<Map<String, dynamic>> updateChannel({
    required Dio dio,
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

    final response = await dio.patch(
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
    required Dio dio,
    required String tenantWorkerId,
    required String channelId,
  }) async {
    final resp = await dio.delete(
      '/workers/$tenantWorkerId/channels/$channelId',
    );
    return resp.data as Map<String, dynamic>;
  }

  static Future<void> verifyCredentials({
    required Dio dio,
    required String phoneNumberId,
    required String accessToken,
  }) async {
    await dio.post(
      '/channels/verify-credentials',
      data: {
        'phone_number_id': phoneNumberId,
        'access_token':    accessToken,
      },
    );
    // 422 lanzado por Dio como DioException — dejar que suba
  }

  static Future<void> activateWhatsapp({
    required Dio dio,
    required String phoneNumberId,
    required String wabaId,
    required String accessToken,
    required String pin,
  }) async {
    await dio.post(
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
    required Dio dio,
    required String channelId,
  }) async {
    await dio.post('/channels/$channelId/activate');
  }

  static Future<Map<String, dynamic>> syncTemplates({
    required Dio dio,
    required String channelId,
  }) async {
    final response = await dio.post(
      '/templates/sync',
      queryParameters: {'channel_id': channelId},
    );
    return Map<String, dynamic>.from(response.data);
  }

  static Future<List<Map<String, dynamic>>> listTemplates({
    required Dio dio,
    required String channelId,
  }) async {
    final response = await dio.get(
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
    required Dio dio,
    required String channelId,
    required String templateId,
  }) async {
    await dio.patch(
      '/channels/$channelId/welcome-template',
      data: {'template_id': templateId},
    );
  }

  static Future<Map<String, dynamic>> embeddedSignup({
    required Dio dio,
    required String code,
    String? phoneNumberId,
    String? wabaId,
    String? businessId,
  }) async {
    final response = await dio.post(
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
    Map<String, dynamic> eventData, {
    required Dio dio,
  }) async {
    await dio.post(
      '/channels/embedded-signup/events',
      data: eventData,
    );
  }

  static Future<List<Map<String, dynamic>>> listChannelsByWorker({
    required Dio dio,
    required String tenantWorkerId,
  }) async {
    final response = await dio.get(
      '/channels',
      queryParameters: {'tenant_worker_id': tenantWorkerId},
    );
    final data = response.data;
    final List raw = data is List
        ? data
        : (data['channels'] ?? data['items'] ?? []) as List;
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
