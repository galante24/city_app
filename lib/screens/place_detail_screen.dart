import 'dart:async';

import 'package:flutter/material.dart';

import '../app_constants.dart';
import '../models/conversation_list_item.dart';
import '../services/chat_service.dart';
import '../services/city_data_service.dart';
import '../services/place_service.dart';
import '../utils/image_cache_extent.dart';
import '../widgets/conversation_pick_list.dart';
import '../widgets/places_style.dart';
import 'place_assign_moderator_screen.dart';
import 'place_edit_field_screen.dart';
import 'place_edit_header_screen.dart';
import 'place_new_post_screen.dart';

class PlaceDetailScreen extends StatefulWidget {
  const PlaceDetailScreen({super.key, required this.placeId});

  final String placeId;

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  Map<String, dynamic>? _place;
  List<Map<String, dynamic>> _posts = <Map<String, dynamic>>[];
  bool _subscribed = false;
  bool _loading = true;
  bool _isAdmin = false;
  bool _canMod = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final Map<String, dynamic>? pl = await PlaceService.fetchPlace(widget.placeId);
    final List<Map<String, dynamic>> posts =
        await PlaceService.fetchPosts(widget.placeId);
    final List<String> mods =
        await PlaceService.fetchModeratorUserIds(widget.placeId);
    final bool sub = await PlaceService.isSubscribed(widget.placeId);
    final bool admin = await CityDataService.isProfilesOrEmailAdmin();
    final String? owner = pl?['owner_id']?.toString();
    final bool canMod = await PlaceService.canModeratePlace(
      widget.placeId,
      isDbAdmin: admin,
      moderatorIds: mods,
      ownerId: owner,
    );
    if (mounted) {
      setState(() {
        _place = pl;
        _posts = posts;
        _subscribed = sub;
        _isAdmin = admin;
        _canMod = canMod;
        _loading = false;
      });
    }
  }

  Future<void> _toggleSubscribe() async {
    try {
      if (_subscribed) {
        await PlaceService.unsubscribe(widget.placeId);
      } else {
        await PlaceService.subscribe(widget.placeId);
      }
      if (mounted) {
        setState(() => _subscribed = !_subscribed);
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Подписка: $e')),
        );
      }
    }
  }

  Future<void> _openEditHeader() async {
    final Map<String, dynamic>? pl = _place;
    if (pl == null) {
      return;
    }
    final bool? ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext c) => PlaceEditHeaderScreen(
          placeId: widget.placeId,
          initialTitle: pl['title'] as String? ?? '',
          initialPhotoUrl: pl['photo_url'] as String?,
          initialCoverUrl: pl['cover_url'] as String?,
        ),
      ),
    );
    if (ok == true && mounted) {
      await _load();
    }
  }

  Future<void> _openEditField(
    String column,
    String screenTitle,
    String label,
  ) async {
    final Map<String, dynamic>? pl = _place;
    if (pl == null) {
      return;
    }
    final bool? ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext c) => PlaceEditFieldScreen(
          placeId: widget.placeId,
          title: screenTitle,
          column: column,
          initialValue: (pl[column] as String?) ?? '',
          label: label,
          maxLines: column == 'description' ? 12 : 10,
        ),
      ),
    );
    if (ok == true && mounted) {
      await _load();
    }
  }

  Future<void> _newPost() async {
    final bool? ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext c) =>
            PlaceNewPostScreen(placeId: widget.placeId),
      ),
    );
    if (ok == true && mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Map<String, dynamic>? pl = _place;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _loading || pl == null
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: <Widget>[
                SliverAppBar(
                  expandedHeight: 200,
                  pinned: true,
                  backgroundColor: cs.surface,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        if ((pl['cover_url'] as String?) != null &&
                            (pl['cover_url'] as String).toString().isNotEmpty)
                          Image.network(
                            pl['cover_url'] as String,
                            fit: BoxFit.cover,
                            cacheWidth: imageCacheExtentPx(context, 800),
                            errorBuilder:
                                (BuildContext context, Object error, StackTrace? st) =>
                                Container(
                              color: kPrimaryBlue.withValues(alpha: 0.15),
                            ),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: <Color>[
                                  kPrimaryBlue.withValues(alpha: 0.35),
                                  cs.surface,
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        Positioned(
                          left: 16,
                          bottom: 16,
                          child: Row(
                            children: <Widget>[
                              if ((pl['photo_url'] as String?) != null &&
                                  (pl['photo_url'] as String)
                                      .toString()
                                      .isNotEmpty)
                                CircleAvatar(
                                  radius: 36,
                                  backgroundImage: NetworkImage(
                                    pl['photo_url'] as String,
                                  ),
                                )
                              else
                                CircleAvatar(
                                  radius: 36,
                                  backgroundColor: Colors.white,
                                  child: Icon(
                                    Icons.store_rounded,
                                    size: 36,
                                    color: kPrimaryBlue,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        PlacesSectionHeader(
                          title: pl['title'] as String? ?? 'Заведение',
                          description: pl['description'] as String?,
                          subtitle: (pl['phone'] as String?)?.trim().isNotEmpty ==
                                  true
                              ? pl['phone'] as String
                              : null,
                        ),
                        if (!_canMod) ...<Widget>[
                          _DetailSubscribeBar(
                            subscribed: _subscribed,
                            onToggle: _toggleSubscribe,
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_isAdmin) ...<Widget>[
                          OutlinedButton.icon(
                            onPressed: () async {
                              await Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (BuildContext c) =>
                                      PlaceAssignModeratorScreen(
                                    placeId: widget.placeId,
                                    placeTitle:
                                        pl['title'] as String? ?? '',
                                  ),
                                ),
                              );
                              if (mounted) {
                                await _load();
                              }
                            },
                            icon: const Icon(Icons.person_add_alt_rounded),
                            label: const Text('Назначить модератора'),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (_canMod) ...<Widget>[
                          PlacesModeratorActionCard(
                            title: 'Управление заведением',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: <Widget>[
                                    _modChip(
                                      context,
                                      'Шапка',
                                      Icons.image_outlined,
                                      _openEditHeader,
                                    ),
                                    _modChip(
                                      context,
                                      'Меню',
                                      Icons.restaurant_menu_rounded,
                                      () => unawaited(_openEditField(
                                        'menu',
                                        'Меню',
                                        'Текст меню',
                                      )),
                                    ),
                                    _modChip(
                                      context,
                                      'Описание',
                                      Icons.subject_rounded,
                                      () => unawaited(_openEditField(
                                        'description',
                                        'Описание',
                                        'О заведении',
                                      )),
                                    ),
                                    _modChip(
                                      context,
                                      'Акции',
                                      Icons.local_offer_outlined,
                                      () => unawaited(_openEditField(
                                        'promotions',
                                        'Акции',
                                        'Текущие акции',
                                      )),
                                    ),
                                    _modChip(
                                      context,
                                      'Новости',
                                      Icons.newspaper_rounded,
                                      () => unawaited(_openEditField(
                                        'news',
                                        'Новости (блок)',
                                        'Статический блок новостей на странице',
                                      )),
                                    ),
                                    _modChip(
                                      context,
                                      'Телефон',
                                      Icons.phone_rounded,
                                      () => unawaited(_openEditField(
                                        'phone',
                                        'Телефон',
                                        'Номер для связи',
                                      )),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _newPost,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: kPrimaryBlue,
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: const Icon(Icons.post_add_rounded),
                                  label: const Text('Новая запись в ленте'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        _staticBlock(context, 'Меню', pl['menu'] as String?),
                        _staticBlock(
                          context,
                          'Акции',
                          pl['promotions'] as String?,
                        ),
                        _staticBlock(
                          context,
                          'Новости',
                          pl['news'] as String?,
                        ),
                        const PlacesSectionHeader(
                          title: 'Лента',
                          subtitle: 'Посты заведения',
                        ),
                      ],
                    ),
                  ),
                ),
                if (_posts.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'Пока нет записей',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (BuildContext c, int i) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: _PlacePostCard(
                            placeTitle: pl['title'] as String? ?? '',
                            placeId: widget.placeId,
                            post: _posts[i],
                            onChanged: _load,
                          ),
                        );
                      },
                      childCount: _posts.length,
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
    );
  }

  Widget _staticBlock(BuildContext context, String title, String? body) {
    final String t = body?.trim() ?? '';
    if (t.isEmpty) {
      return const SizedBox.shrink();
    }
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: cs.onSurface.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modChip(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onTap,
  ) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: kPrimaryBlue),
      label: Text(label),
      onPressed: onTap,
      backgroundColor: kPrimaryBlue.withValues(alpha: 0.08),
      side: BorderSide(color: kPrimaryBlue.withValues(alpha: 0.35)),
    );
  }
}

class _DetailSubscribeBar extends StatefulWidget {
  const _DetailSubscribeBar({
    required this.subscribed,
    required this.onToggle,
  });

  final bool subscribed;
  final Future<void> Function() onToggle;

  @override
  State<_DetailSubscribeBar> createState() => _DetailSubscribeBarState();
}

class _DetailSubscribeBarState extends State<_DetailSubscribeBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 1, end: 0.97).animate(
        CurvedAnimation(parent: _ac, curve: Curves.easeOut),
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.tonal(
          onPressed: () async {
            await _ac.forward();
            await _ac.reverse();
            await widget.onToggle();
          },
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            backgroundColor: widget.subscribed
                ? kPrimaryBlue.withValues(alpha: 0.12)
                : kPrimaryBlue,
            foregroundColor:
                widget.subscribed ? kPrimaryBlue : Colors.white,
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              widget.subscribed ? 'Отписаться' : 'Подписаться',
              key: ValueKey<bool>(widget.subscribed),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlacePostCard extends StatefulWidget {
  const _PlacePostCard({
    required this.placeTitle,
    required this.placeId,
    required this.post,
    required this.onChanged,
  });

  final String placeTitle;
  final String placeId;
  final Map<String, dynamic> post;
  final Future<void> Function() onChanged;

  @override
  State<_PlacePostCard> createState() => _PlacePostCardState();
}

class _PlacePostCardState extends State<_PlacePostCard> {
  bool? _liked;
  int _likes = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _likes = (widget.post['likes_count'] as int?) ?? 0;
    unawaited(_syncLiked());
  }

  Future<void> _syncLiked() async {
    final String pid = widget.post['id']?.toString() ?? '';
    if (pid.isEmpty) {
      return;
    }
    final bool v = await PlaceService.isPostLikedByMe(pid);
    if (mounted) {
      setState(() => _liked = v);
    }
  }

  Future<void> _toggleLike() async {
    final String pid = widget.post['id']?.toString() ?? '';
    if (pid.isEmpty || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      if (_liked == true) {
        await PlaceService.unlikePost(pid);
        setState(() {
          _liked = false;
          _likes = (_likes - 1).clamp(0, 1 << 30);
        });
      } else {
        await PlaceService.likePost(pid);
        setState(() {
          _liked = true;
          _likes = _likes + 1;
        });
      }
    } on Object {
      await widget.onChanged();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _openComments() {
    final String pid = widget.post['id']?.toString() ?? '';
    if (pid.isEmpty) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext c) => _CommentsSheet(postId: pid),
    );
  }

  void _shareToChat() {
    final String pid = widget.post['id']?.toString() ?? '';
    if (pid.isEmpty) {
      return;
    }
    final String content =
        (widget.post['content'] as String?)?.trim() ?? '';
    final String preview = content.length > 180
        ? '${content.substring(0, 180)}…'
        : content;
    final String msg =
        '📍 ${widget.placeTitle}\n\n$preview\n\npost:$pid';
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Отправить в чат',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            SizedBox(
              height: 320,
              child: ConversationPickList(
                excludeConversationId: null,
                emptyMessage: 'Нет чатов',
                onPick: (ConversationListItem item) async {
                  Navigator.of(c).pop();
                  try {
                    await ChatService.sendMessage(item.id, msg);
                    if (!mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Отправлено в чат')),
                    );
                  } on Object catch (e) {
                    if (!mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка: $e')),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String? img = widget.post['image_url'] as String?;
    final String body =
        (widget.post['content'] as String?)?.trim() ?? '';
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (img != null && img.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  img,
                  fit: BoxFit.cover,
                  cacheWidth: imageCacheExtentPx(context, 600),
                ),
              ),
            if (body.isNotEmpty && body != ' ') ...<Widget>[
              if (img != null && img.isNotEmpty) const SizedBox(height: 10),
              Text(
                body,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: cs.onSurface,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                IconButton(
                  onPressed: _busy ? null : _toggleLike,
                  icon: Icon(
                    _liked == true
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: _liked == true ? Colors.redAccent : cs.onSurface,
                  ),
                ),
                Text('$_likes'),
                IconButton(
                  onPressed: _openComments,
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                ),
                IconButton(
                  onPressed: _shareToChat,
                  icon: const Icon(Icons.send_rounded),
                  tooltip: 'В чат',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({required this.postId});

  final String postId;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final TextEditingController _input = TextEditingController();
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final List<Map<String, dynamic>> list =
        await PlaceService.fetchComments(widget.postId);
    if (mounted) {
      setState(() {
        _rows = list;
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    final String t = _input.text.trim();
    if (t.isEmpty) {
      return;
    }
    await PlaceService.addComment(widget.postId, t);
    _input.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final double padBottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: padBottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Комментарии',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: cs.onSurface,
                ),
              ),
            ),
            SizedBox(
              height: 280,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _rows.length,
                      separatorBuilder: (BuildContext context, int index) =>
                          const Divider(height: 1),
                      itemBuilder: (BuildContext c, int i) {
                        final Map<String, dynamic> m = _rows[i];
                        final String uid = m['user_id']?.toString() ?? '';
                        final String text =
                            m['content'] as String? ?? '';
                        return FutureBuilder<String?>(
                          future: ChatService.displayNameForUserId(uid),
                          builder: (BuildContext ctx, AsyncSnapshot<String?> s) {
                            final String name = s.data ?? uid;
                            return ListTile(
                              dense: true,
                              title: Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: Text(text),
                            );
                          },
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _input,
                      decoration: const InputDecoration(
                        hintText: 'Комментарий…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _send,
                    icon: const Icon(Icons.send_rounded),
                    color: kPrimaryBlue,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
