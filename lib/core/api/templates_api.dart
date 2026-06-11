import 'package:dio/dio.dart';

class TemplatesApi {
  /// Lista plantillas por canal y tenant.
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

  /// Sincroniza plantillas desde Meta para un canal y tenant.
  static Future<void> syncTemplates({
    required Dio dio,
    required String channelId,
  }) async {
    await dio.post(
      '/templates/sync',
      queryParameters: {'channel_id': channelId},
    );
  }

  /// Obtiene la plantilla de bienvenida del sistema.
  static Future<Map<String, dynamic>?> getDefault({
    required Dio dio,
    required String channelId,
  }) async {
    try {
      final response = await dio.get(
        '/templates/default',
        queryParameters: {'channel_id': channelId},
      );
      return Map<String, dynamic>.from(response.data as Map);
    } catch (_) {
      return null;
    }
  }

  /// Crea una nueva plantilla y la envía a Meta para aprobación.
  static Future<void> createTemplate({
    required Dio dio,
    required String name,
    required String category,
    required String language,
    required String bodyText,
    required List<Map<String, dynamic>> variables,
    bool isWelcome = false,
    required String channelId,
    // Optional template components
    String? headerType,        // 'TEXT' | 'IMAGE' | 'VIDEO' | 'DOCUMENT'
    String? headerText,        // only when headerType == 'TEXT'
    String? headerExampleUrl,  // only when headerType is media
    String? footerText,
    List<Map<String, dynamic>>? buttons,
  }) async {
    await dio.post(
      '/templates',
      data: {
        'name':       name,
        'category':   category,
        'language':   language,
        'body_text':  bodyText,
        'variables':  variables,
        'is_welcome': isWelcome,
        'channel_id': channelId,
        'header_type': ?headerType,
        if (headerType == 'TEXT' && (headerText?.isNotEmpty ?? false))
          'header_text': headerText,
        if (headerType != null && headerType != 'TEXT' &&
            (headerExampleUrl?.isNotEmpty ?? false))
          'header_example_url': headerExampleUrl,
        if (footerText != null && footerText.isNotEmpty)
          'footer_text': footerText,
        if (buttons != null && buttons.isNotEmpty)
          'buttons': buttons,
      },
      options: Options(
        validateStatus: (s) => s != null && s >= 200 && s < 300,
      ),
    );
  }

  /// Elimina una plantilla por ID.
  static Future<void> deleteTemplate({
    required Dio dio,
    required String templateId,
    required String channelId,
  }) async {
    await dio.delete(
      '/templates/$templateId',
      queryParameters: {'channel_id': channelId},
    );
  }
}
