import 'package:intl/intl.dart';

class DateTimeUtils {
  static final DateFormat _displayDate = DateFormat('d MMMM y', 'tr_TR');
  static final DateFormat _displayTime = DateFormat('HH:mm', 'tr_TR');

  static String formatDate(DateTime value) => _displayDate.format(value);

  static String formatTime(DateTime value) => _displayTime.format(value);

  static DateTime atTime(DateTime day, int hour, int minute) {
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  static DateTime stripTime(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}
