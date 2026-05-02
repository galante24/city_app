String formatPostTime(String? iso) {
  if (iso == null) {
    return '';
  }
  final DateTime? d = DateTime.tryParse(iso);
  if (d == null) {
    return '';
  }
  final DateTime now = DateTime.now();
  final DateTime local = d.toLocal();
  final Duration diff = now.difference(d);
  if (diff.inMinutes < 1) {
    return 'только что';
  }
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} мин. назад';
  }
  if (diff.inHours < 24) {
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  if (diff.inDays < 7) {
    return '${diff.inDays} дн. назад';
  }
  return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year}';
}
