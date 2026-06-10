import 'package:dio/dio.dart';

class DashboardApi {
  static Future<Map<String, dynamic>> fetchTableData({
    required Dio dio,
    required String dashboardSlug,
    required String widgetId,
    String? dateRangeStart,
    String? dateRangeEnd,
    String? metadataFilterKey,
    String? metadataFilterValue,
  }) async {
    final params = <String, dynamic>{
      'dashboard_slug': dashboardSlug,
      'widget_id': widgetId,
    };
    if (dateRangeStart != null) params['date_range_start'] = dateRangeStart;
    if (dateRangeEnd != null) params['date_range_end'] = dateRangeEnd;
    if (metadataFilterKey != null) params['metadata_filter_key'] = metadataFilterKey;
    if (metadataFilterValue != null) params['metadata_filter_value'] = metadataFilterValue;
    final resp = await dio.get(
      '/api/v1/dashboard/table-data',
      queryParameters: params,
    );
    return Map<String, dynamic>.from(resp.data as Map);
  }
}
