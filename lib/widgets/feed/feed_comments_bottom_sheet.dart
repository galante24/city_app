import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../app_constants.dart';
import '../../app_navigator_key.dart';
import '../../screens/feed_post_detail_screen.dart';
import '../../services/feed_post_state_hub.dart';
import '../../services/feed_service.dart';
import '../../utils/social_feed_format.dart';
import '../city_network_image.dart';
import '../media_progressive_image.dart';
import 'feed_fullscreen_gallery.dart';

/// Комментарии к посту в модальном окне (без перехода на экран поста).
Future<void> showFeedCommentsBottomSheet({
  required BuildContext context,
  required FeedService feed,
  required String postId,
  String? postTitle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext ctx) => _FeedCommentsSheet(
      feed: feed,
      postId: postId.trim(),
      postTitle: postTitle,
    ),
  );
}

class _FeedCommentsSheet extends StatefulWidget {
  const _FeedCommentsSheet({
    required this.feed,
    required this.postId,
    this.postTitle,
  });

  final FeedService feed;
  final String postId;
  final String? postTitle;

  @override
  State<_FeedCommentsSheet> createState() => _FeedCommentsSheetState();
}

class _FeedCommentsSheetState extends State<_FeedCommentsSheet> {
  List<Map<String, dynamic>> _comments = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;
  final TextEditingController _body = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _sending = false;
  String? _replyParentId;
  String? _replyTargetAuthor;
  final Map<String, bool> _threadRepliesExpanded = <String, bool>{};
  final ImagePicker _picker = ImagePicker();
  final List<String> _pendingCommentImages = <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _body.dispose();
    _focus.dispose();
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
      final List<Map<String, dynamic>> cm = await widget.feed.fetchComments(
        widget.postId,
      );
      if (mounted) {
        setState(() {
          _comments = cm;
          _loading = false;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _send() async {
    String bodyText = _body.text.trim();
    final String? parent = _replyParentId;
    final String? targetAuthor = _replyTargetAuthor?.trim();
    if (parent != null && targetAuthor != null && targetAuthor.isNotEmpty) {
      final String prefix = '$targetAuthor, ';
      if (bodyText.startsWith(prefix)) {
        bodyText = bodyText.substring(prefix.length).trim();
      }
    }
    if (bodyText.isEmpty && _pendingCommentImages.isEmpty) {
      return;
    }
    if (_sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.feed.addComment(
        postId: widget.postId,
        body: bodyText,
        parentId: parent,
        imagePublicUrls: List<String>.from(_pendingCommentImages),
      );
      _body.clear();
      _pendingCommentImages.clear();
      _replyParentId = null;
      _replyTargetAuthor = null;
      FeedPostStateHub.instance.bumpComments(widget.postId, 1);
      await _load();
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

  Future<void> _pickCommentImages() async {
    if (_pendingCommentImages.length >= 3) {
      return;
    }
    final List<XFile> files = await _picker.pickMultiImage(imageQuality: 88);
    if (files.isEmpty || !mounted) {
      return;
    }
    setState(() => _sending = true);
    try {
      for (final XFile f in files) {
        if (_pendingCommentImages.length >= 3) {
          break;
        }
        _pendingCommentImages.add(await widget.feed.uploadFeedImage(f));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
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
      _body.text = prefix;
      _body.selection = TextSelection.collapsed(offset: _body.text.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
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
            child: Icon(
              Icons.person,
              size: r * 1.1,
              color: isDark ? kEmeraldGlow : kPineGreen,
            ),
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
    required bool isDark,
  }) {
    final ThemeData theme = Theme.of(context);
    final String id = row['id'].toString();
    final String body = (row['body'] as String?) ?? '';
    final List<String> imgs =
        (row['image_urls'] as List?)
            ?.map((dynamic e) => e.toString())
            .where((String s) => s.trim().isNotEmpty)
            .toList() ??
        <String>[];

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
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        formatPostTime(row['created_at'] as String?),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: GoogleFonts.montserrat(
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                      if (imgs.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: FeedCommentAttachmentGrid(
                            urls: imgs,
                            thumb: thumb,
                            onPhotoTap: (int i) {
                              Navigator.push<void>(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => FeedFullscreenGallery(
                                    urls: imgs,
                                    initialIndex: i,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 6),
                      TextButton.icon(
                        onPressed: () => _beginReplyTo(row),
                        icon: const Icon(Icons.reply, size: 18),
                        label: const Text('Ответить'),
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
      padding: EdgeInsets.only(left: depth * 12.0, top: 10, right: 4),
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
                _commentTile(ch, byParent, depth: depth + 1, isDark: isDark),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final BorderRadius top = const BorderRadius.vertical(
      top: Radius.circular(26),
    );
    final Color panelBg = isDark
        ? Colors.black.withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: 0.92);

    final Map<String?, List<Map<String, dynamic>>> byParent = _groupByParent();
    final List<Map<String, dynamic>> roots =
        byParent[null] ?? <Map<String, dynamic>>[];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.58,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (BuildContext context, ScrollController scrollCtl) {
        return ClipRRect(
          borderRadius: top,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: panelBg,
              borderRadius: top,
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : kPineGreen.withValues(alpha: 0.1),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: kEmeraldGlow.withValues(alpha: isDark ? 0.2 : 0.28),
                  blurRadius: 18,
                  spreadRadius: 0,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              children: <Widget>[
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          widget.postTitle?.trim().isNotEmpty == true
                              ? widget.postTitle!.trim()
                              : 'Комментарии',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.montserrat(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : kPineGreen,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          final String pid = widget.postId;
                          final FeedService f = widget.feed;
                          Navigator.pop(context);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            final BuildContext? root =
                                rootNavigatorKey.currentContext;
                            if (root != null && root.mounted) {
                              unawaited(
                                Navigator.of(root).push<void>(
                                  MaterialPageRoute<void>(
                                    builder: (_) => FeedPostDetailScreen(
                                      postId: pid,
                                      feed: f,
                                    ),
                                  ),
                                ),
                              );
                            }
                          });
                        },
                        child: const Text('Пост'),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(_error!),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollCtl,
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          itemCount: roots.length,
                          itemBuilder: (BuildContext c, int i) {
                            return _commentTile(
                              roots[i],
                              byParent,
                              depth: 0,
                              isDark: isDark,
                            );
                          },
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
                              final String t = _body.text;
                              if (t.startsWith(prefix)) {
                                _body.text = t.substring(prefix.length);
                              }
                            }
                          });
                        },
                      ),
                    ),
                  ),
                Material(
                  elevation: 8,
                  color: theme.colorScheme.surface,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 8,
                      right: 12,
                      top: 8,
                      bottom:
                          MediaQuery.paddingOf(context).bottom +
                          MediaQuery.viewInsetsOf(context).bottom +
                          8,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (_pendingCommentImages.isNotEmpty)
                          RepaintBoundary(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                bottom: 8,
                                left: 4,
                              ),
                              child: SizedBox(
                                height: 56,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _pendingCommentImages.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 6),
                                  itemBuilder: (BuildContext c, int i) {
                                    final String u = _pendingCommentImages[i];
                                    return Stack(
                                      children: <Widget>[
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: ProgressiveCachedImage(
                                            imageUrl: u,
                                            width: 56,
                                            height: 56,
                                            fit: BoxFit.cover,
                                            borderRadius: 8,
                                          ),
                                        ),
                                        Positioned(
                                          top: 0,
                                          right: 0,
                                          child: Material(
                                            color: Colors.black54,
                                            shape: const CircleBorder(),
                                            child: InkWell(
                                              customBorder:
                                                  const CircleBorder(),
                                              onTap: () => setState(
                                                () => _pendingCommentImages
                                                    .removeAt(i),
                                              ),
                                              child: const Icon(
                                                Icons.close,
                                                size: 16,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        Row(
                          children: <Widget>[
                            IconButton(
                              tooltip: 'Фото (до 3)',
                              onPressed:
                                  _sending || _pendingCommentImages.length >= 3
                                  ? null
                                  : () => unawaited(_pickCommentImages()),
                              icon: Icon(
                                Icons.add_photo_alternate_outlined,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            Expanded(
                              child: RepaintBoundary(
                                child: TextField(
                                  controller: _body,
                                  focusNode: _focus,
                                  minLines: 1,
                                  maxLines: 4,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  decoration: const InputDecoration(
                                    hintText: 'Комментарий…',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  onSubmitted: (_) => unawaited(_send()),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _sending
                                  ? null
                                  : () => unawaited(_send()),
                              child: _sending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send_rounded, size: 20),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
