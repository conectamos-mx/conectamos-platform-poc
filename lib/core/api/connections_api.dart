import 'package:dio/dio.dart';

class ConnectionsApi {
  /// Returns the Google OAuth authorization URL.
  static Future<String> getGoogleAuthUrl({required Dio dio}) async {
    final resp = await dio.get('/integrations/google/auth-url');
    return resp.data['auth_url'] as String;
  }

  /// Returns Google connection status.
  /// Shape: { connected: bool, email: String|null, connected_at: String|null }
  static Future<Map<String, dynamic>> getGoogleStatus({required Dio dio}) async {
    final resp = await dio.get('/integrations/google/status');
    return Map<String, dynamic>.from(resp.data as Map);
  }

  /// Disconnects the Google integration for the active tenant.
  static Future<void> disconnectGoogle({required Dio dio}) async {
    await dio.delete('/integrations/google');
  }

  /// Fetches the header row (first row) from a Google Sheets spreadsheet.
  /// Returns a list of column names.
  static Future<List<String>> getSheetHeaders({
    required Dio dio,
    required String spreadsheetId,
    required String sheetName,
  }) async {
    final resp = await dio.get(
      '/integrations/google/sheets/headers',
      queryParameters: {
        'spreadsheet_id': spreadsheetId,
        'sheet_name': sheetName,
      },
    );
    return List<String>.from(resp.data['headers'] as List);
  }

  // ── Microsoft OAuth ────────────────────────────────────────────────────────

  /// Returns the Microsoft OAuth authorization URL.
  /// Shape: { url: "https://login.microsoftonline.com/..." }
  static Future<String> getMicrosoftAuthUrl({required Dio dio, required String tenantId}) async {
    final resp = await dio.get(
      '/oauth/microsoft/url',
      queryParameters: {'tenant_id': tenantId},
    );
    return resp.data['url'] as String;
  }

  /// Returns Microsoft connection status for the tenant.
  static Future<Map<String, dynamic>> getMicrosoftStatus({
    required Dio dio,
    required String tenantId,
  }) async {
    final resp = await dio.get(
      '/oauth/status',
      queryParameters: {'tenant_id': tenantId},
    );
    return Map<String, dynamic>.from(resp.data as Map);
  }

  /// Revokes the Microsoft integration for the active tenant.
  static Future<void> disconnectMicrosoft({required Dio dio, required String tenantId}) async {
    await dio.delete(
      '/oauth/microsoft/revoke',
      queryParameters: {'tenant_id': tenantId},
    );
  }
}
