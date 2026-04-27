import 'package:meta/meta.dart';

/// Манифест OTA (JSON), размещаемый на HTTPS вместе с APK.
@immutable
class OtaUpdateManifest {
  const OtaUpdateManifest({
    required this.version,
    required this.versionCode,
    required this.apkUrl,
    this.sha256Hex,
    this.force = false,
    this.minVersionCode,
  });

  final String version;
  final int versionCode;
  final String apkUrl;
  final String? sha256Hex;
  final bool force;
  final int? minVersionCode;

  static OtaUpdateManifest? tryParseMap(Map<String, dynamic> json) {
    try {
      final String ver = (json['version'] as String? ?? '').trim();
      if (ver.isEmpty) {
        return null;
      }
      final Object? vcAny = json['version_code'] ?? json['build_number'];
      final int? vc = _parseInt(vcAny);
      if (vc == null) {
        return null;
      }
      final String url = (json['url'] as String? ?? '').trim();
      if (url.isEmpty) {
        return null;
      }
      final String? sha =
          (json['sha256'] as String? ?? json['sha_256'] as String?)?.trim();
      final bool force = json['force'] == true;
      final int? minVc = _parseInt(json['min_version_code'] ?? json['minVersionCode']);
      return OtaUpdateManifest(
        version: ver,
        versionCode: vc,
        apkUrl: url,
        sha256Hex: (sha == null || sha.isEmpty) ? null : sha,
        force: force,
        minVersionCode: minVc,
      );
    } on Object {
      return null;
    }
  }

  static int? _parseInt(Object? v) {
    if (v == null) {
      return null;
    }
    if (v is int) {
      return v;
    }
    return int.tryParse(v.toString().trim());
  }
}

/// Сравнение по [version_code] (Android [versionCode] / pubspec +N).
bool otaIsRemoteNewer({
  required int localCode,
  required int remoteCode,
}) =>
    remoteCode > localCode;

/// «Жёсткое» обновление: нельзя отказаться, если [force] или локальный код &lt; [minCode].
@immutable
class OtaForcePolicy {
  const OtaForcePolicy._(this.laterOk);

  final bool laterOk;

  factory OtaForcePolicy.from({
    required OtaUpdateManifest m,
    required int localCode,
  }) {
    if (m.force) {
      return const OtaForcePolicy._(false);
    }
    if (m.minVersionCode != null && localCode < m.minVersionCode!) {
      return const OtaForcePolicy._(false);
    }
    return const OtaForcePolicy._(true);
  }
}
