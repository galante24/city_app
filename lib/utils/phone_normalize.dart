/// Нормализация российского номера в E.164 (+7XXXXXXXXXX) для [profiles.phone_e164].
String? normalizePhoneToE164Ru(String? raw) {
  if (raw == null) {
    return null;
  }
  final String s = raw.trim();
  if (s.isEmpty) {
    return null;
  }
  String d = s.replaceAll(RegExp(r'[^\d+]'), '');
  if (d.isEmpty) {
    return null;
  }
  if (d.startsWith('+')) {
    if (d.startsWith('+7') && d.length == 12) {
      return d;
    }
    if (d.length >= 10) {
      return d;
    }
  }
  if (d.length == 11) {
    if (d.startsWith('8')) {
      return '+7${d.substring(1)}';
    }
    if (d.startsWith('7')) {
      return '+$d';
    }
  }
  if (d.length == 10) {
    return '+7$d';
  }
  if (d.startsWith('8') && d.length == 11) {
    return '+7${d.substring(1)}';
  }
  return d.startsWith('+') ? d : null;
}
