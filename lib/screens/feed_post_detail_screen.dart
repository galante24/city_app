import 'dart:async';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_constants.dart';
import '../models/news_feed_category.dart';
import '../services/feed_post_state_hub.dart';
import '../services/feed_service.dart';
import '../utils/social_feed_format.dart';
import '../widgets/city_network_image.dart';
import '../widgets/media_progressive_image.dart';
import '../widgets/feed/comment_item.dart';
import '../widgets/feed/feed_compose_sheet.dart';
import '../widgets/feed/feed_fullscreen_gallery.dart';
import '../widgets/feed/feed_share_to_chat_dialog.dart';
import 'home_screen.dart' show SocialPost, socialPostFromMap;

/// Экран поста: комментарии-дерево, лайки, медиа, репост.
class FeedPostDetailScreen extends StatefulWidget {
  const FeedPostDetailScreen({
    super.key,
    required this.postId,
    required this.feed,
  });

  final String postId;
  final FeedService feed;

  @override
  State<FeedPostDetailScreen> createState() => _FeedPostDetailScreenState();
}

class _FeedPostDetailScreenState extends State<FeedPostDetailScreen> {
  SocialPost? _post;
  List<Map<String, dynamic>> _comments = <Map<String, dynamic>>[];
  Set<String> _likedCommentIds = <String>{};
  FeedAccess _access = FeedAccess.fallbackUser();
  bool _loading = true;
  String? _error;

  final TextEditingController _replyBody = TextEditingController();
  final FocusNode _replyFocus = FocusNode();
  final ImagePicker _picker = ImagePicker();
  final List<String> _replyImages = <String>[];
  String? _replyParentId;

  /// Автор комментария, на который отвечаем (для префикса «Имя, »).
  String? _replyTargetAuthor;

  /// Развёрнуты ли все ответы под комментарием [id].
  final Map<String, bool> _threadRepliesExpanded = <String, bool>{};
  bool _showEmoji = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _replyBody.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final FeedAccess a = await widget.feed.loadMyAccess();
      final Map<String, dynamic>? row = await widget.feed.fetchPostRow(
        widget.postId,
      );
      if (row == null) {
        if (mounted) {
          setState(() {
            _error = 'Пост не найден';
            _loading = false;
          });
        }
        return;
      }
      final List<Map<String, dynamic>> cm = await widget.feed.fetchComments(
        widget.postId,
      );
      final Set<String> lk = await widget.feed.fetchMyLikedCommentIds(
        cm.map((Map<String, dynamic> e) => e['id'].toString()),
      );
      final Set<String> likedPosts = await widget.feed.fetchMyLikedPostIds(
        <String>[widget.postId],
      );
      final SocialPost p = socialPostFromMap(row);
      p.isLiked = likedPosts.contains(p.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _access = a;
        _post = p;
        _comments = cm;
        _likedCommentIds = lk;
        _loading = false;
      });
      FeedPostStateHub.instance.syncFromCounts(
        p.id,
        likes: p.likes,
        comments: p.comments,
        isLiked: p.isLiked,
      );
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _togglePostLike() async {
    final SocialPost? p = _post;
    if (p == null) {
      return;
    }
    final FeedPostStateHub hub = FeedPostStateHub.instance;
    final ValueNotifier<FeedPostCounters> n = hub.notifierFor(p.id);
    final FeedPostCounters before = n.value;
    hub.toggleLikeOptimistic(p.id, before.isLiked);
    setState(() {
      p.isLiked = n.value.isLiked;
      p.likes = n.value.likes;
      p.comments = n.value.comments;
    });
    try {
      await widget.feed.togglePostLike(
        postId: p.id,
        currentlyLiked: before.isLiked,
      );
      final Map<String, dynamic>? row = await widget.feed.fetchPostRow(p.id);
      if (row != null && mounted) {
        hub.applyServerRow(
          p.id,
          row,
          isLiked: hub.notifierFor(p.id).value.isLiked,
        );
        setState(() {
          p.isLiked = hub.notifierFor(p.id).value.isLiked;
          p.likes = hub.notifierFor(p.id).value.likes;
          p.comments = hub.notifierFor(p.id).value.comments;
        });
      }
    } on Object {
      if (mounted) {
        n.value = before;
        setState(() {
          p.isLiked = before.isLiked;
          p.likes = before.likes;
          p.comments = before.comments;
        });
      }
    }
  }

  Future<void> _toggleCommentLike(
    String id,
    int currentCount,
    bool liked,
  ) async {
    if (!mounted) {
      return;
    }
    setState(() {
      if (liked) {
        _likedCommentIds.remove(id);
      } else {
        _likedCommentIds.add(id);
      }
      for (final Map<String, dynamic> m in _comments) {
        if (m['id']?.toString() == id) {
          final int c = (m['likes_count'] as num?)?.toInt() ?? 0;
          m['likes_count'] = c + (liked ? -1 : 1);
        }
      }
    });
    try {
      await widget.feed.toggleCommentLike(commentId: id, currentlyLiked: liked);
    } on Object {
      await _load();
    }
  }

  Future<void> _sendReply() async {
    final SocialPost? p = _post;
    if (p == null || _sending) {
      return;
    }
    String bodyText = _replyBody.text.trim();
    final String? parent = _replyParentId;
    final String? targetAuthor = _replyTargetAuthor?.trim();
    if (parent != null && targetAuthor != null && targetAuthor.isNotEmpty) {
      final String prefix = '$targetAuthor, ';
      if (bodyText.startsWith(prefix)) {
        bodyText = bodyText.substring(prefix.length).trim();
      }
    }
    if (bodyText.isEmpty && _replyImages.isEmpty) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.feed.addComment(
        postId: p.id,
        body: bodyText,
        parentId: parent,
        imagePublicUrls: List<String>.from(_replyImages),
      );
      _replyBody.clear();
      _replyImages.clear();
      _replyParentId = null;
      _replyTargetAuthor = null;
      await _load();
      if (mounted && _post != null) {
        final SocialPost pp = _post!;
        FeedPostStateHub.instance.syncFromCounts(
          pp.id,
          likes: pp.likes,
          comments: pp.comments,
          isLiked: pp.isLiked,
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _pickReplyImages() async {
    if (_replyImages.length >= 3) {
      return;
    }
    final List<XFile> files = await _picker.pickMultiImage(imageQuality: 88);
    if (files.isEmpty) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _sending = true);
    try {
      for (final XFile f in files) {
        if (_replyImages.length >= 3) {
          break;
        }
        _replyImages.add(await widget.feed.uploadFeedImage(f));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _deleteComment(String id) async {
    try {
      await widget.feed.deleteComment(id);
      await _load();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _deletePost() async {
    final SocialPost? p = _post;
    if (p == null) {
      return;
    }
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Удалить пост?'),
        content: const Text(
          'Удаление безвозвратно, вместе с комментариями и файлами.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              if (ctx.mounted) {
                Navigator.pop(ctx, false);
              }
            },
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (ctx.mounted) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    try {
      await widget.feed.deletePost(p.id);
      if (!mounted) {
        return;
      }
      Navigator.pop(context);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  bool _canEditPost(SocialPost p) {
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null || p.userId == null || p.userId != me) {
      return _access.isFullAdmin;
    }
    if (_access.isFullAdmin) {
      return true;
    }
    if (p.createdAtUtc == null) {
      return false;
    }
    return DateTime.now().toUtc().difference(p.createdAtUtc!) <=
        const Duration(minutes: 10);
  }

  Map<String?, List<Map<String, dynamic>>> _groupByParent() {
    final Map<String?, List<Map<String, dynamic>>> map =
        <String?, List<Map<String, dynamic>>>{};
    for (final Map<String, dynamic> c in _comments) {
      final String? pid = c['parent_id']?.toString();
      map.putIfAbsent(pid, () => <Map<String, dynamic>>[]).add(c);
    }
    for (final List<Map<String, dynamic>> list in map.values) {
      list.sort(
        (Map<String, dynamic> a, Map<String, dynamic> b) =>
            (a['created_at']?.toString() ?? '').compareTo(
              b['created_at']?.toString() ?? '',
            ),
      );
    }
    return map;
  }

  String _authorLabel(Map<String, dynamic> row) {
    final Object? ar = row['author'];
    if (ar is Map) {
      final String? fn = (ar['first_name'] as String?)?.trim();
      final String? un = (ar['username'] as String?)?.trim();
      if (fn != null && fn.isNotEmpty) {
        return fn;
      }
      if (un != null && un.isNotEmpty) {
        return '@$un';
      }
    }
    return '';
  }

  String? _avatarUrl(Map<String, dynamic> row) {
    final Object? ar = row['author'];
    if (ar is Map) {
      return (ar['avatar_url'] as String?)?.trim();
    }
    return null;
  }

  static String _repliesWord(int n) {
    final int m = n % 100;
    if (m >= 11 && m <= 14) {
      return 'ответов';
    }
    switch (n % 10) {
      case 1:
        return 'ответ';
      case 2:
      case 3:
      case 4:
        return 'ответа';
      default:
        return 'ответов';
    }
  }

  void _beginReplyTo(Map<String, dynamic> row) {
    final String id = row['id'].toString();
    final String label = _authorLabel(row);
    final String prefix = label.isEmpty ? '' : '$label, ';
    setState(() {
      _replyParentId = id;
      _replyTargetAuthor = label.isEmpty ? null : label;
      _replyBody.text = prefix;
      _replyBody.selection = TextSelection.collapsed(
        offset: _replyBody.text.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _replyFocus.requestFocus();
      }
    });
  }

  Widget _commentAvatar({
    required Map<String, dynamic> row,
    required int depth,
    required bool isDark,
  }) {
    final double r = depth > 0 ? 14.0 : 18.0;
    final String? av = _avatarUrl(row);
    final Widget avatar = av != null && av.isNotEmpty
        ? CityNetworkImage.avatar(
            context: context,
            imageUrl: av,
            diameter: r * 2,
            placeholderName: _authorLabel(row),
          )
        : CircleAvatar(
            radius: r,
            child: Icon(Icons.person, size: r * 1.1),
          );
    if (depth > 0 && !isDark) {
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: kEmeraldGlow.withValues(alpha: 0.38),
              blurRadius: 12,
              spreadRadius: 0.25,
            ),
            BoxShadow(
              color: kEmeraldGlow.withValues(alpha: 0.14),
              blurRadius: 18,
              spreadRadius: 0.5,
            ),
          ],
        ),
        child: avatar,
      );
    }
    return avatar;
  }

  Widget _commentTile(
    Map<String, dynamic> row,
    Map<String?, List<Map<String, dynamic>>> byParent, {
    required int depth,
  }) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final String id = row['id'].toString();
    final String body = (row['body'] as String?) ?? '';
    final List<String> imgs = commentMediaUrlsFromRow(row);
    final int likes = (row['likes_count'] as num?)?.toInt() ?? 0;
    final bool liked = _likedCommentIds.contains(id);
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    final String uid = row['user_id']?.toString() ?? '';
    final bool canDel =
        me != null &&
        (me == uid ||
            _access.isFullAdmin ||
            (_access.effectiveRole == 'moderator_news' &&
                categoryToDb(_post!.category) == 'smi') ||
            (_access.effectiveRole == 'moderator_important' &&
                categoryToDb(_post!.category) == 'administration'));

    final List<Map<String, dynamic>> children =
        byParent[id] ?? <Map<String, dynamic>>[];
    final bool expanded = _threadRepliesExpanded[id] ?? false;
    final int hiddenCount = children.length > 2 ? children.length - 2 : 0;
    final List<Map<String, dynamic>> visibleChildren =
        expanded || children.length <= 2 ? children : children.take(2).toList();

    final double thumb = depth > 0 ? 72 : 88;
    final Color? replyCardBg = depth > 0
        ? (isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.white.withValues(alpha: 0.9))
        : null;
    final Border? replyCardBorder = depth > 0
        ? Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : kPineGreen.withValues(alpha: 0.08),
          )
        : null;

    Widget mainBlock = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (depth > 0)
            Container(
              width: 2,
              margin: const EdgeInsets.only(right: 8, top: 2, bottom: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _commentAvatar(row: row, depth: depth, isDark: isDark),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _authorLabel(row),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        formatPostTime(row['created_at'] as String?),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(body),
                      if (imgs.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: CommentItem(urls: imgs, thumb: thumb),
                        ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 0,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          TextButton.icon(
                            onPressed: () => _beginReplyTo(row),
                            icon: const Icon(Icons.reply, size: 18),
                            label: const Text('Ответить'),
                          ),
                          IconButton(
                            onPressed: () =>
                                _toggleCommentLike(id, likes, liked),
                            icon: Icon(
                              liked ? Icons.favorite : Icons.favorite_border,
                              size: 20,
                              color: liked ? Colors.pink : null,
                            ),
                          ),
                          Text('$likes'),
                          if (canDel)
                            IconButton(
                              onPressed: () => _deleteComment(id),
                              icon: const Icon(Icons.delete_outline, size: 20),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (replyCardBg != null) {
      mainBlock = DecoratedBox(
        decoration: BoxDecoration(
          color: replyCardBg,
          borderRadius: BorderRadius.circular(12),
          border: replyCardBorder,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: mainBlock,
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(left: depth * 12.0, top: 10, right: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          mainBlock,
          if (hiddenCount > 0 && !expanded)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4),
              child: TextButton(
                onPressed: () =>
                    setState(() => _threadRepliesExpanded[id] = true),
                child: Text(
                  'Показать ещё $hiddenCount ${_repliesWord(hiddenCount)}',
                ),
              ),
            ),
          ...visibleChildren.map(
            (Map<String, dynamic> ch) =>
                _commentTile(ch, byParent, depth: depth + 1),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(title: const Text('Пост')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _post == null) {
      return Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(title: const Text('Пост')),
        body: Center(child: Text(_error ?? 'Ошибка')),
      );
    }
    final SocialPost p = _post!;
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    final String catDb = categoryToDb(p.category);
    final bool canDelete = _access.canDeletePostDb(
      postUserId: p.userId ?? '',
      categoryDb: catDb,
      myUserId: me,
    );

    final Map<String?, List<Map<String, dynamic>>> byParent = _groupByParent();
    final List<Map<String, dynamic>> roots =
        byParent[null] ?? <Map<String, dynamic>>[];

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Пост'),
        actions: <Widget>[
          if (_canEditPost(p))
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                await showFeedComposeSheet(
                  context: context,
                  feed: widget.feed,
                  access: _access,
                  initialCategory: p.category,
                  editingPostId: p.id,
                  initialTitle: p.title,
                  initialDescription: p.body,
                  initialImageUrls: p.imageUrls,
                );
                await _load();
              },
            ),
          if (canDelete)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _deletePost,
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                Text(
                  p.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (p.imageUrls.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(
                      minWidth: double.infinity,
                      maxHeight: 350,
                    ),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: p.imageUrls.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, int i) {
                        final double w = (MediaQuery.sizeOf(context).width - 40)
                            .clamp(160.0, 420.0);
                        return RepaintBoundary(
                          child: GestureDetector(
                            onTap: () {
                              if (!context.mounted) {
                                return;
                              }
                              Navigator.push<void>(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => FeedFullscreenGallery(
                                    urls: p.imageUrls,
                                    initialIndex: i,
                                  ),
                                ),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(26),
                              child: SizedBox(
                                width: w,
                                height: 350,
                                child: ProgressiveCachedImage(
                                  imageUrl: p.imageUrls[i],
                                  width: w,
                                  height: 350,
                                  fit: BoxFit.cover,
                                  borderRadius: 0,
                                  memCacheHeightMaxPx: 600,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                if (p.imageUrls.isNotEmpty) const SizedBox(height: 8),
                Text(p.body),
                const SizedBox(height: 8),
                ValueListenableBuilder<FeedPostCounters>(
                  valueListenable: FeedPostStateHub.instance.notifierFor(p.id),
                  builder: (BuildContext context, FeedPostCounters c, _) {
                    return Row(
                      children: <Widget>[
                        IconButton(
                          onPressed: _togglePostLike,
                          icon: Icon(
                            c.isLiked ? Icons.favorite : Icons.favorite_border,
                            color: c.isLiked ? Colors.pink : null,
                          ),
                        ),
                        Text('${c.likes}'),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text('${c.comments}'),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: const Icon(Icons.share_outlined),
                          onPressed: () {
                            final FeedPostCounters s = FeedPostStateHub.instance
                                .notifierFor(p.id)
                                .value;
                            p.isLiked = s.isLiked;
                            p.likes = s.likes;
                            p.comments = s.comments;
                            showFeedShareToChatDialog(
                              context: context,
                              feed: widget.feed,
                              post: p,
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
                const Divider(),
                Text(
                  'Комментарии',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                ...roots.map(
                  (Map<String, dynamic> r) =>
                      _commentTile(r, byParent, depth: 0),
                ),
              ],
            ),
          ),
          if (_replyParentId != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  label: Text(
                    _replyTargetAuthor != null &&
                            _replyTargetAuthor!.trim().isNotEmpty
                        ? 'Ответ для ${_replyTargetAuthor!.trim()}'
                        : 'Ответ',
                  ),
                  onDeleted: () {
                    final String? ta = _replyTargetAuthor?.trim();
                    setState(() {
                      _replyParentId = null;
                      _replyTargetAuthor = null;
                      if (ta != null && ta.isNotEmpty) {
                        final String prefix = '$ta, ';
                        final String t = _replyBody.text;
                        if (t.startsWith(prefix)) {
                          _replyBody.text = t.substring(prefix.length);
                        }
                      }
                    });
                  },
                ),
              ),
            ),
          Material(
            elevation: 6,
            child: Padding(
              padding: EdgeInsets.only(
                left: 8,
                right: 8,
                top: 6,
                bottom:
                    MediaQuery.paddingOf(context).bottom +
                    MediaQuery.viewInsetsOf(context).bottom +
                    6,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (_showEmoji)
                    SizedBox(
                      height: 200,
                      child: EmojiPicker(
                        textEditingController: _replyBody,
                        config: Config(
                          height: 200,
                          checkPlatformCompatibility: true,
                          locale: const Locale('ru'),
                          emojiViewConfig: const EmojiViewConfig(
                            emojiSizeMax: 24,
                            buttonMode: ButtonMode.MATERIAL,
                          ),
                        ),
                      ),
                    ),
                  Row(
                    children: <Widget>[
                      IconButton(
                        icon: const Icon(Icons.image_outlined),
                        onPressed: _sending ? null : _pickReplyImages,
                      ),
                      IconButton(
                        icon: const Icon(Icons.emoji_emotions_outlined),
                        onPressed: () =>
                            setState(() => _showEmoji = !_showEmoji),
                      ),
                      Expanded(
                        child: RepaintBoundary(
                          child: TextField(
                            controller: _replyBody,
                            focusNode: _replyFocus,
                            minLines: 1,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              hintText: 'Комментарий…',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _sending ? null : _sendReply,
                        icon: _sending
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send),
                      ),
                    ],
                  ),
                  if (_replyImages.isNotEmpty)
                    SizedBox(
                      height: 56,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: _replyImages
                            .map(
                              (String u) => Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ProgressiveCachedImage(
                                  imageUrl: u,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                  borderRadius: 8,
                                  memCacheHeightMaxPx: 600,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
