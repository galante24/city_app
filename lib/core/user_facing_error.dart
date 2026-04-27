import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Сообщение для SnackBar без полного stack trace и лишнего сырого вывода.
String messageForUser(Object error, {String fallback = 'Не удалось выполнить действие.'}) {
  if (error is PostgrestException) {
    return error.message;
  }
  if (error is AuthException) {
    return error.message;
  }
  if (kDebugMode) {
    debugPrint('userFacingError: $error');
  }
  return fallback;
}
