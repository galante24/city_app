import '../services/chat_service.dart';

/// Паттерны: `@username` или `@[Имя Фамилия]`.
final RegExp kCommentMentionPattern = RegExp(
  r'@\[([^\]]+)\]|@([a-zA-Z0-9_\u0400-\u04FF]+)',
  unicode: true,
);

String? _fullNameFromRow(Map<String, dynamic> r) {
  final String fn = (r['first_name'] as String?)?.trim() ?? '';
  final String ln = (r['last_name'] as String?)?.trim() ?? '';
  final String t = '$fn $ln'.trim();
  return t.isEmpty ? null : t;
}

/// Текст для вставки в поле комментария (с пробелом в конце).
String mentionInsertionFromProfile(Map<String, dynamic>? profile) {
  if (profile == null) {
    return '';
  }
  String? u = (profile['username'] as String?)?.trim();
  if (u != null && u.isNotEmpty) {
    if (u.startsWith('@')) {
      u = u.substring(1);
    }
    return '@$u ';
  }
  final String? full = _fullNameFromRow(profile);
  if (full != null) {
    return '@[$full] ';
  }
  return '';
}

/// Находит user_id по тексту комментария (упоминания).
Future<List<String>> resolveMentionedUserIds(String rawText) async {
  final Set<String> out = <String>{};
  final String text = rawText.trim();
  if (text.isEmpty) {
    return <String>[];
  }
  for (final Match m in kCommentMentionPattern.allMatches(text)) {
    final String? bracket = m.group(1);
    final String? atWord = m.group(2);
    if (bracket != null && bracket.trim().isNotEmpty) {
      final String inner = bracket.trim();
      final List<Map<String, dynamic>> rows =
          await ChatService.searchProfilesForChat(inner);
      bool found = false;
      for (final Map<String, dynamic> r in rows) {
        final String? dn = _fullNameFromRow(r);
        if (dn != null && dn.toLowerCase() == inner.toLowerCase()) {
          final String? id = r['id']?.toString();
          if (id != null) {
            out.add(id);
          }
          found = true;
          break;
        }
      }
      if (!found && rows.length == 1) {
        final String? id = rows.first['id']?.toString();
        if (id != null) {
          out.add(id);
        }
      }
    } else if (atWord != null && atWord.isNotEmpty) {
      final String? id = await ChatService.findUserIdByUsername(atWord);
      if (id != null) {
        out.add(id);
      }
    }
  }
  return List<String>.from(out);
}
