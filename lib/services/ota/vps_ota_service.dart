import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../config/app_secrets.dart';
import 'ota_models.dart';
import 'ota_url_policy.dart';

class OtaException implements Exception {
  OtaException(this.message);
  final String message;
  @override
  String toString() => message;
}

class VpsOtaService {
  VpsOtaService._();

  static final BaseOptions _otaOptions = BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(minutes: 5),
    followRedirects: true,
    maxRedirects: 3,
    // Только 2xx-успех: иначе 404/301/500 не считаются валидным APK/JSON.
    validateStatus: (int? s) => s != null && s == 200,
  );

  static final Dio _dio = Dio(_otaOptions);

  static Future<OtaUpdateManifest?> loadManifest() async {
    final String mUrl = kUpdateManifestUrl.trim();
    if (mUrl.isEmpty) {
      return null;
    }
    if (!mUrl.toLowerCase().startsWith('https://')) {
      throw OtaException('Некорректный UPDATE_MANIFEST_URL (нужен HTTPS).');
    }
    final Uri configured = Uri.parse(mUrl);
    final Response<String> response = await _dio.get<String>(
      mUrl,
      options: Options(
        responseType: ResponseType.plain,
        validateStatus: _otaOptions.validateStatus,
      ),
    );
    if (response.data == null) {
      throw OtaException('Пустой ответ манифеста OTA.');
    }
    final String body = response.data!;
    if (utf8.encode(body).length > kOtaMaxManifestLength) {
      throw OtaException('Слишком большой манифест (лимит $kOtaMaxManifestLength байт).');
    }
    _assertNoHostEscalation(
      label: 'манифеста',
      configuredHost: configured.host,
      finalUri: response.realUri,
    );
    final Object? j = jsonDecode(body);
    if (j is! Map<String, dynamic>) {
      throw OtaException('Некорректный JSON манифеста.');
    }
    final OtaUpdateManifest? m = OtaUpdateManifest.tryParseMap(j);
    if (m == null) {
      throw OtaException('Поля version, version_code, url обязательны в манифесте.');
    }
    if (kUpdateRequireSha256 &&
        (m.sha256Hex == null || m.sha256Hex!.trim().isEmpty)) {
      throw OtaException(
        'В манифесте нет sha256. Добавьте sha256 (рекомендуется) или в dev '
        'сборке: --dart-define=UPDATE_REQUIRE_SHA256=false',
      );
    }
    if (!otaIsApkUrlPolicyOk(manifestUrl: mUrl, apkUrl: m.apkUrl)) {
      throw OtaException(
        'URL APK не разрешён политикой (другой host). '
        'Добавьте хост в UPDATE_TRUSTED_APK_HOSTS при необходимости.',
      );
    }
    if (m.sha256Hex != null) {
      final String h = m.sha256Hex!.trim();
      if (!RegExp(r'^(?:[0-9a-fA-F]{64})$').hasMatch(h)) {
        throw OtaException('Поле sha256 в манифесте должно быть 64 hex-символа.');
      }
    }
    return m;
  }

  /// Манифест [configuredHost] (из env) == финальный [finalUri] после редиректов (тот же host, HTTPS).
  static void _assertNoHostEscalation({
    required String label,
    required String configuredHost,
    required Uri finalUri,
  }) {
    if (finalUri.scheme != 'https') {
      throw OtaException('Ошибка $label: ожидается HTTPS, получено: ${finalUri.scheme}.');
    }
    if (finalUri.host.isEmpty) {
      throw OtaException('Ошибка $label: пустой host в ответе.');
    }
    if (!otaSameHost(configuredHost, finalUri.host)) {
      throw OtaException('Ошибка $label: редирект на другой host запрещён политикой OTA.');
    }
  }

  static OtaUpdateManifest? filterByLocalBuild({
    required OtaUpdateManifest m,
    required int localCode,
  }) {
    if (!otaIsRemoteNewer(localCode: localCode, remoteCode: m.versionCode)) {
      return null;
    }
    return m;
  }

  static Future<String> _apkFilePath() async {
    final Directory d = await getTemporaryDirectory();
    final Directory sub = Directory(p.join(d.path, 'ota_update'));
    if (!await sub.exists()) {
      await sub.create(recursive: true);
    }
    return p.join(sub.path, 'city_update.apk');
  }

  static Future<void> downloadVerifyAndOpen({
    required OtaUpdateManifest manifest,
    required void Function(double? fraction, String status) onProgress,
  }) async {
    if (kUpdateRequireSha256 &&
        (manifest.sha256Hex == null || manifest.sha256Hex!.trim().isEmpty)) {
      throw OtaException('sha256 в манифесте обязателен — установка отклонена.');
    }
    final String mUrl = kUpdateManifestUrl.trim();
    final String path = await _apkFilePath();
    final File out = File(path);
    if (await out.exists()) {
      await out.delete();
    }
    onProgress(0, 'Скачивание…');
    final Response<dynamic> dl;
    try {
      dl = await _dio.download(
        manifest.apkUrl,
        path,
        onReceiveProgress: (int r, int t) {
          if (t > 0) {
            onProgress(r / t, 'Скачивание…');
          } else {
            onProgress(null, 'Скачивание…');
          }
        },
        options: Options(
          validateStatus: _otaOptions.validateStatus,
        ),
      );
    } on DioException catch (e) {
      if (await out.exists()) {
        await out.delete();
      }
      throw OtaException('Скачивание: ${e.message ?? e}');
    }
    if (!otaIsApkUrlPolicyOk(
      manifestUrl: mUrl,
      apkUrl: dl.realUri.toString(),
    )) {
      if (await out.exists()) {
        await out.delete();
      }
      throw OtaException(
        'APK скачан с URL, не разрешённого политикой (в т.ч. после редиректов).',
      );
    }
    onProgress(1, 'Проверка целостности…');
    final int fileLen = await out.length();
    if (fileLen > kOtaMaxApkBytes) {
      await out.delete();
      throw OtaException(
        'APK слишком велик (>${kOtaMaxApkBytes ~/ (1024 * 1024)} МБ), установка отклонена.',
      );
    }
    if (manifest.sha256Hex != null) {
      final String expected = manifest.sha256Hex!.trim().toLowerCase();
      final String actual = (await _sha256HexOfFile(out)).toLowerCase();
      if (actual != expected) {
        await out.delete();
        throw OtaException(
          'Контрольная сумма (SHA-256) не совпала с манифестом, установка отменена. '
          'Свяжитесь с разработчиком.',
        );
      }
    }
    onProgress(1, 'Запуск установщика…');
    try {
      final OpenResult r = await OpenFilex.open(
        path,
        type: 'application/vnd.android.package-archive',
      );
      if (r.type != ResultType.done) {
        _logOtaOpenFailure(
          'open_filex status ${r.type}: ${r.message}',
        );
        throw OtaException(
          'Не удалось открыть установщик: ${r.message}. '
          'Проверьте разрешение «установка из неизвестных источников».',
        );
      }
    } on OtaException {
      rethrow;
    } catch (e, st) {
      _logOtaOpenFailure('$e', st);
      throw OtaException(
        'Не удалось открыть APK (установщик). '
        'Проверьте разрешения и повторите. '
        'Если сбой повторяется, установите пакет вручную из папки загрузок.',
      );
    }
  }

  static void _logOtaOpenFailure(String message, [StackTrace? st]) {
    if (kDebugMode) {
      // ignore: avoid_print
      debugPrint('[OTA] open install: $message');
      if (st != null) {
        // ignore: avoid_print
        debugPrint('$st');
      }
    }
  }

  static Future<String> _sha256HexOfFile(File f) async {
    return sha256.convert(await f.readAsBytes()).toString();
  }
}
