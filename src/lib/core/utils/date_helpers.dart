import 'package:intl/intl.dart';

class DateHelpers {
  static final _dateFormat = DateFormat('yyyy-MM-dd');
  static final _timeFormat = DateFormat('HH:mm');
  static final _dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm');
  static final _iso8601Format = DateFormat("yyyy-MM-dd'T'HH:mm:ss");

  static String formatDate(DateTime dt) => _dateFormat.format(dt);
  static String formatTime(DateTime dt) => _timeFormat.format(dt);
  static String formatDateTime(DateTime dt) => _dateTimeFormat.format(dt);
  static String formatIso8601(DateTime dt) => _iso8601Format.format(dt);

  static DateTime startOfYear(int year) => DateTime(year);
  static DateTime endOfYear(int year) => DateTime(year, 12, 31, 23, 59, 59);

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // Number of calendar days until the given date (negative = past).
  static int daysUntil(DateTime target) {
    final today = DateTime.now();
    final d = DateTime(target.year, target.month, target.day)
        .difference(DateTime(today.year, today.month, today.day));
    return d.inDays;
  }
}
