/// Разбор вложенного автора из ответа Supabase (`author:profiles!...`).
Map<String, dynamic>? authorMapFromRow(Map<String, dynamic> row) {
  final dynamic a = row['author'];
  if (a is Map<String, dynamic>) {
    return a;
  }
  return null;
}

String authorFullNameFromMap(Map<String, dynamic>? m) {
  if (m == null) {
    return 'Пользователь';
  }
  final String fn = (m['first_name'] as String?)?.trim() ?? '';
  final String ln = (m['last_name'] as String?)?.trim() ?? '';
  final String full = '$fn $ln'.trim();
  if (full.isNotEmpty) {
    return full;
  }
  final String? u = (m['username'] as String?)?.trim();
  if (u != null && u.isNotEmpty) {
    return u.startsWith('@') ? u : '@$u';
  }
  return 'Пользователь';
}

String? authorAvatarUrlFromMap(Map<String, dynamic>? m) {
  if (m == null) {
    return null;
  }
  final String? u = (m['avatar_url'] as String?)?.trim();
  if (u == null || u.isEmpty) {
    return null;
  }
  return u;
}

String? authorIdFromMap(Map<String, dynamic>? m) {
  if (m == null) {
    return null;
  }
  return m['id']?.toString();
}
