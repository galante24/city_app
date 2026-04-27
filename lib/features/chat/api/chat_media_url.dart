import '../../../config/app_secrets.dart';

/// Склеивает путь из API (`/v1/media/...`) с [kApiBaseUrl] для плеера.
String resolveChatMediaUrl(String pathOrUrl) {
  final String t = pathOrUrl.trim();
  if (t.isEmpty) {
    return t;
  }
  if (t.startsWith('http://') || t.startsWith('https://')) {
    return t;
  }
  final String base = kApiBaseUrl.replaceAll(RegExp(r'/$'), '');
  if (base.isEmpty) {
    return t;
  }
  if (t.startsWith('/')) {
    return '$base$t';
  }
  return '$base/$t';
}
