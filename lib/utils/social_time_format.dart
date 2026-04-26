import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

/// Подпись времени: недавно — timeago, иначе «24.05.2026, 14:30».
String formatSocialTimestamp(DateTime? rawUtc) {
  if (rawUtc == null) {
    return '';
  }
  final DateTime local = rawUtc.toLocal();
  final Duration diff = DateTime.now().difference(local);
  if (diff < const Duration(minutes: 1)) {
    return 'только что';
  }
  if (diff < const Duration(days: 7)) {
    return timeago.format(local, locale: 'ru', allowFromNow: true);
  }
  try {
    return DateFormat('d MMMM yyyy, HH:mm', 'ru_RU').format(local);
  } on Object {
    return DateFormat('dd.MM.yyyy, HH:mm').format(local);
  }
}

DateTime? parseIsoUtc(String? iso) {
  if (iso == null || iso.isEmpty) {
    return null;
  }
  return DateTime.tryParse(iso);
}
