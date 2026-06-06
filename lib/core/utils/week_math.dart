// ADR-413 + ADR-414 — Calendar-arithmetic helpers with timezone support.
// All functions use the global active zone via toZone().

import 'package:intl/intl.dart';
import 'tz_format.dart';

final _fMonthAbbr = DateFormat('MMM', 'es_MX');
final _fIsoDate = DateFormat('yyyy-MM-dd');

/// Returns the Monday of the week containing [d] in active tenant timezone.
DateTime mondayOf(DateTime d) {
  final r = toZone(d);
  final diff = r.dt.weekday - 1;
  return DateTime(r.dt.year, r.dt.month, r.dt.day - diff);
}

/// "yyyy-MM-dd" from DateTime in active tenant timezone.
String isoDate(DateTime d) {
  final r = toZone(d);
  return _fIsoDate.format(r.dt);
}

/// "d-d Mes yyyy" or "d Mes - d Mes yyyy" range label.
/// Converts [monday] to active tenant timezone before formatting.
String weekRangeLabel(DateTime monday) {
  final r = toZone(monday);
  final mon = r.dt;
  final sunday = mon.add(const Duration(days: 6));
  if (mon.month == sunday.month) {
    return '${mon.day}\u2013${sunday.day} ${_fMonthAbbr.format(mon)} ${mon.year}';
  }
  return '${mon.day} ${_fMonthAbbr.format(mon)} \u2013 '
      '${sunday.day} ${_fMonthAbbr.format(sunday)} ${mon.year}';
}
