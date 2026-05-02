import 'package:flutter/foundation.dart';

/// Счётчики поста для синхронизации карточки ленты, шита комментариев и экрана поста.
@immutable
class FeedPostCounters {
  const FeedPostCounters({
    required this.likes,
    required this.comments,
    required this.isLiked,
  });

  final int likes;
  final int comments;
  final bool isLiked;

  FeedPostCounters copyWith({int? likes, int? comments, bool? isLiked}) {
    return FeedPostCounters(
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      isLiked: isLiked ?? this.isLiked,
    );
  }
}

/// Единый [ValueNotifier] на id поста — лайки и комментарии обновляются везде одновременно.
final class FeedPostStateHub {
  FeedPostStateHub._();
  static final FeedPostStateHub instance = FeedPostStateHub._();

  final Map<String, ValueNotifier<FeedPostCounters>> _byPostId =
      <String, ValueNotifier<FeedPostCounters>>{};

  ValueNotifier<FeedPostCounters> notifierFor(String postId) {
    final String id = postId.trim();
    return _byPostId.putIfAbsent(
      id,
      () => ValueNotifier<FeedPostCounters>(
        const FeedPostCounters(likes: 0, comments: 0, isLiked: false),
      ),
    );
  }

  void syncFromCounts(
    String postId, {
    required int likes,
    required int comments,
    required bool isLiked,
  }) {
    notifierFor(postId).value = FeedPostCounters(
      likes: likes,
      comments: comments,
      isLiked: isLiked,
    );
  }

  /// Строка из PostgREST ([likes_count], [comments_count]); [isLiked] если уже известен.
  void applyServerRow(
    String postId,
    Map<String, dynamic> row, {
    bool? isLiked,
  }) {
    final ValueNotifier<FeedPostCounters> n = notifierFor(postId);
    final int likes = (row['likes_count'] as num?)?.toInt() ?? n.value.likes;
    final int comments =
        (row['comments_count'] as num?)?.toInt() ?? n.value.comments;
    n.value = FeedPostCounters(
      likes: likes,
      comments: comments,
      isLiked: isLiked ?? n.value.isLiked,
    );
  }

  void toggleLikeOptimistic(String postId, bool wasLiked) {
    final ValueNotifier<FeedPostCounters> n = notifierFor(postId);
    final FeedPostCounters c = n.value;
    n.value = c.copyWith(
      likes: c.likes + (wasLiked ? -1 : 1),
      isLiked: !wasLiked,
    );
  }

  void bumpComments(String postId, int delta) {
    final ValueNotifier<FeedPostCounters> n = notifierFor(postId);
    final FeedPostCounters c = n.value;
    n.value = c.copyWith(comments: c.comments + delta);
  }
}

/// Ручное обновление ленты (после публикации и т. п.), опционально — строка нового поста.
@immutable
class FeedInvalidateSignal {
  const FeedInvalidateSignal({this.insertedPostRow});
  final Map<String, dynamic>? insertedPostRow;
}

/// Шина вне Realtime: мгновенный refresh / optimistic prepend.
final class FeedInvalidateBus {
  FeedInvalidateBus._();
  static final FeedInvalidateBus instance = FeedInvalidateBus._();

  final ValueNotifier<FeedInvalidateSignal?> signal =
      ValueNotifier<FeedInvalidateSignal?>(null);

  void bump({Map<String, dynamic>? insertedPostRow}) {
    signal.value = FeedInvalidateSignal(insertedPostRow: insertedPostRow);
  }
}
