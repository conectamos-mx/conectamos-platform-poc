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

  /// Fetches the header row (first row) from an Excel file in OneDrive.
  /// Returns a list of column names.
  static Future<List<String>> getExcelHeaders({
    required String fileId,
    required String sheetName,
  }) async {
    final resp = await ApiClient.instance.get(
      '/integrations/microsoft/excel/headers',
      queryParameters: {
        'file_id': fileId,
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

  /// Lists Excel files from OneDrive for the tenant.
  static Future<List<Map<String, dynamic>>> getOnedriveFiles({
    required String tenantId,
  }) async {
    final response = await ApiClient.instance.get(
      '/api/v1/catalogs/tools/onedrive-files',
      queryParameters: {'tenant_id': tenantId},
    );
    final raw = response.data;
    final list = raw is Map ? (raw['files'] ?? []) : (raw is List ? raw : []);
    return List<Map<String, dynamic>>.from(
        (list as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
  }
}
