import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import 'dashboard_api.dart';

typedef TableDataKey = ({
  String dashboardSlug,
  String widgetId,
  String? start,
  String? end,
  String? filterKey,
  String? filterValue,
});

final tableDataProvider =
    FutureProvider.family<Map<String, dynamic>, TableDataKey>((ref, key) async {
  return DashboardApi.fetchTableData(
    dio: ref.read(apiClientProvider).dio,
    dashboardSlug: key.dashboardSlug,
    widgetId: key.widgetId,
    dateRangeStart: key.start,
    dateRangeEnd: key.end,
    metadataFilterKey: key.filterKey,
    metadataFilterValue: key.filterValue,
  );
});
