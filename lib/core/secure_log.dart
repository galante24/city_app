import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// Не логировать тела ответов, токены, refresh. Только код/тип ошибки.
void debugLogHttpFailure(String label, int? statusCode, {Object? error}) {
  if (!kDebugMode) {
    return;
  }
  final String sc = statusCode?.toString() ?? '?';
  final String err = error == null ? '' : ' err=${error.runtimeType}';
  debugPrint('[$label] HTTP $sc$err');
}
