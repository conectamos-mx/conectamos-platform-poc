// ADR-413 — Extracted calendar-arithmetic helpers (pure functions).
// All naive — no TZ conversion; caller passes already-local DateTimes.

import 'package:intl/intl.dart';

final _fMonthAbbr = DateFormat('MMM', 'es_MX');
final _fIsoDate = DateFormat('yyyy-MM-dd');

/// Returns the Monday of the week containing [d].
/// Naive — operates on calendar fields as-is.
DateTime mondayOf(DateTime d) {
  final diff = d.weekday - 1;
  return DateTime(d.year, d.month, d.day - diff);
}

/// "yyyy-MM-dd" from DateTime. Naive.
String isoDate(DateTime d) => _fIsoDate.format(d);

/// "d-d Mes yyyy" or "d Mes - d Mes yyyy" range label.
/// Naive — operates on calendar fields as-is.
String weekRangeLabel(DateTime monday) {
  final sunday = monday.add(const Duration(days: 6));
  if (monday.month == sunday.month) {
    return '${monday.day}\u2013${sunday.day} ${_fMonthAbbr.format(monday)} ${monday.year}';
  }
  return '${monday.day} ${_fMonthAbbr.format(monday)} \u2013 '
      '${sunday.day} ${_fMonthAbbr.format(sunday)} ${monday.year}';
}
