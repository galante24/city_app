import '../../config/app_secrets.dart';

const int kOtaMaxManifestLength = 65536;
const int kOtaMaxApkBytes = 200 * 1024 * 1024;

/// Нормализация [Uri.host] (DNS, без учёта регистра).
bool otaSameHost(String a, String b) {
  if (a.isEmpty || b.isEmpty) {
    return false;
  }
  return a.toLowerCase() == b.toLowerCase();
}

/// URL APK: только `https`, [apkUrl] — тот же host, что [manifestUrl], либо в [kUpdateTrustedApkHosts].
/// После редиректов сравнивайте [apkUrl] с [finalRequestUri] (финальный URL ответа).
bool otaIsApkUrlPolicyOk({
  required String manifestUrl,
  required String apkUrl,
}) {
  final Uri? m = Uri.tryParse(manifestUrl.trim());
  final Uri? u = Uri.tryParse(apkUrl.trim());
  if (m == null || u == null) {
    return false;
  }
  if (m.scheme != 'https' || u.scheme != 'https') {
    return false;
  }
  if (m.host.isEmpty || u.host.isEmpty) {
    return false;
  }
  if (otaSameHost(m.host, u.host)) {
    return true;
  }
  for (final String h in kUpdateTrustedApkHosts.split(',')) {
    final String t = h.trim();
    if (t.isNotEmpty && otaSameHost(t, u.host)) {
      return true;
    }
  }
  return false;
}
