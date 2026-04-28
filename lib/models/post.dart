/// Модель записи таблицы `public.posts`.
class Post {
  const Post({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.userId,
  });

  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final String userId;

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      createdAt: Post._parseTs(json['created_at']),
      userId: json['user_id'] as String,
    );
  }

  static DateTime _parseTs(Object? raw) {
    if (raw is DateTime) {
      return raw;
    }
    if (raw == null) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toUtc();
    }
    return DateTime.parse(raw.toString()).toUtc();
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'content': content,
      'created_at': createdAt.toUtc().toIso8601String(),
      'user_id': userId,
    };
  }

  @override
  String toString() => 'Post(id: $id, title: $title)';
}
