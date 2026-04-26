import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_card_styles.dart';
import '../app_constants.dart';
import '../models/conversation_list_item.dart';
import '../services/chat_service.dart';
import '../services/city_data_service.dart';
import '../services/place_service.dart';
import '../utils/image_cache_extent.dart';
import '../utils/author_embed.dart';
import '../utils/place_phone.dart';
import '../utils/social_time_format.dart';
import '../widgets/conversation_pick_list.dart';
import '../widgets/social_comment_tile.dart';
import '../widgets/social_header.dart';
import '../widgets/places_style.dart';
import 'place_assign_moderator_screen.dart';
import 'place_edit_field_screen.dart';
import 'place_edit_header_screen.dart';
import 'place_menu_manage_screen.dart';
import 'place_menu_screen.dart';
import 'place_new_post_screen.dart';

int _postCounterFromJson(dynamic v, {int? fallback}) {
  if (v == null) {
    return fallback ?? 0;
  }
  if (v is int) {
    return v;
  }
  if (v is num) {
    return v.round();
  }
  return fallback ?? 0;
}

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
  /// Совпадает с RLS menu_items: [is_profiles_admin], владелец или [place_moderators].
  bool _canEditMenu = false;

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
    final bool rlsAdmin = await CityDataService.isProfilesAdminRls();
    final String? owner = pl?['owner_id']?.toString();
    final bool canMod = await PlaceService.canModeratePlace(
      widget.placeId,
      isDbAdmin: admin,
      moderatorIds: mods,
      ownerId: owner,
    );
    final String? uid = Supabase.instance.client.auth.currentUser?.id;
    final bool canEditMenu = rlsAdmin ||
        (uid != null &&
            owner != null &&
            uid == owner) ||
        (uid != null && mods.contains(uid));
    if (mounted) {
      setState(() {
        _place = pl;
        _posts = posts;
        _subscribed = sub;
        _isAdmin = admin;
        _canMod = canMod;
        _canEditMenu = canEditMenu;
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
          maxLines: column == 'description'
              ? 12
              : column == 'phone'
                  ? 1
                  : 10,
        ),
      ),
    );
    if (ok == true && mounted) {
      await _load();
    }
  }

  Future<void> _callPlacePhone(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Не удалось открыть звонок (нет приложения)'),
            ),
          );
        }
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Звонок: $e')));
      }
    }
  }

  Widget? _placePhoneSubtitle(BuildContext context, String? phoneRaw) {
    final String trimmed = phoneRaw?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    final Uri? uri = PlacePhone.dialUri(trimmed);
    final String display = PlacePhone.formatDisplay(trimmed);
    final ColorScheme cs = Theme.of(context).colorScheme;
    if (uri == null) {
      return Text(
        display,
        style: TextStyle(
          fontSize: 14,
          height: 1.35,
          color: cs.onSurfaceVariant,
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _callPlacePhone(uri),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.phone_rounded, size: 20, color: kPrimaryBlue),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  display,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    color: kPrimaryBlue,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: kPrimaryBlue,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

  Future<void> _openMenuShowcase() async {
    final Map<String, dynamic>? pl = _place;
    if (pl == null) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => PlaceMenuScreen(
          placeId: widget.placeId,
          placeTitle: pl['title'] as String? ?? 'Заведение',
          canManage: _canEditMenu,
        ),
      ),
    );
  }

  Future<void> _openMenuManage() async {
    final Map<String, dynamic>? pl = _place;
    if (pl == null) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => PlaceMenuManageScreen(
          placeId: widget.placeId,
          placeTitle: pl['title'] as String? ?? 'Заведение',
        ),
      ),
    );
    if (mounted) {
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
                            loadingBuilder: (
                              BuildContext context,
                              Widget child,
                              ImageChunkEvent? progress,
                            ) {
                              if (progress == null) {
                                return child;
                              }
                              return ColoredBox(
                                color: cs.surfaceContainerHighest,
                                child: const Center(
                                  child: SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              );
                            },
                            errorBuilder:
                                (BuildContext context, Object error, StackTrace? st) =>
                                Container(
                              color: kPrimaryBlue.withValues(alpha: 0.15),
                              child: const Center(
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  color: Colors.white70,
                                  size: 40,
                                ),
                              ),
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
                          subtitleWidget: _placePhoneSubtitle(
                            context,
                            pl['phone'] as String?,
                          ),
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
                                if (_canEditMenu) ...<Widget>[
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: _openMenuManage,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: kPrimaryBlue,
                                      side: BorderSide(
                                        color: kPrimaryBlue.withValues(
                                          alpha: 0.55,
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                        horizontal: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          16,
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.tune_rounded,
                                      size: 22,
                                    ),
                                    label: const Text(
                                      'Управление меню',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
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
                        _MenuAndPromosHeroButton(onTap: _openMenuShowcase),
                        const SizedBox(height: 20),
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
                            placePhotoUrl:
                                (pl['photo_url'] as String?)?.trim(),
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

class _MenuAndPromosHeroButton extends StatelessWidget {
  const _MenuAndPromosHeroButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: <Color>[
            kPrimaryBlue,
            Color.lerp(kPrimaryBlue, const Color(0xFF0D47A1), 0.35)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: kPrimaryBlue.withValues(alpha: 0.38),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
            child: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.restaurant_menu_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Меню и акции',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Цифровая витрина заведения',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 13,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.95),
                  size: 30,
                ),
              ],
            ),
          ),
        ),
      ),
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
    this.placePhotoUrl,
    required this.placeId,
    required this.post,
    required this.onChanged,
  });

  final String placeTitle;
  final String? placePhotoUrl;
  final String placeId;
  final Map<String, dynamic> post;
  final Future<void> Function() onChanged;

  @override
  State<_PlacePostCard> createState() => _PlacePostCardState();
}

class _PlacePostCardState extends State<_PlacePostCard> {
  bool? _liked;
  int _likes = 0;
  int _comments = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _likes = _postCounterFromJson(widget.post['likes_count']);
    _comments = _postCounterFromJson(widget.post['comments_count']);
    unawaited(_syncLiked());
  }

  @override
  void didUpdateWidget(covariant _PlacePostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String newId = widget.post['id']?.toString() ?? '';
    final String oldId = oldWidget.post['id']?.toString() ?? '';
    if (newId != oldId) {
      _likes = _postCounterFromJson(widget.post['likes_count']);
      _comments = _postCounterFromJson(widget.post['comments_count']);
      _liked = null;
      unawaited(_syncLiked());
    } else {
      if (oldWidget.post['likes_count'] != widget.post['likes_count']) {
        _likes = _postCounterFromJson(
          widget.post['likes_count'],
          fallback: _likes,
        );
      }
      if (oldWidget.post['comments_count'] !=
          widget.post['comments_count']) {
        _comments = _postCounterFromJson(
          widget.post['comments_count'],
          fallback: _comments,
        );
      }
    }
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
    ).whenComplete(() async {
      await widget.onChanged();
    });
  }

  void _shareToChat() {
    final String pid = widget.post['id']?.toString() ?? '';
    if (pid.isEmpty) {
      return;
    }
    final String? img = (widget.post['image_url'] as String?)?.trim();
    final String msg = ChatService.buildPlaceShareBody(
      placeTitle: widget.placeTitle,
      placeId: widget.placeId,
      thumbUrl: img != null && img.isNotEmpty ? img : null,
    );
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
    final String? imgRaw = widget.post['image_url'] as String?;
    final String? img =
        imgRaw != null && imgRaw.trim().isNotEmpty ? imgRaw.trim() : null;
    final String body =
        (widget.post['content'] as String?)?.trim() ?? '';
    final String? photo =
        widget.placePhotoUrl != null && widget.placePhotoUrl!.trim().isNotEmpty
            ? widget.placePhotoUrl!.trim()
            : null;
    final String authorId = widget.post['author_id']?.toString() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (authorId.isNotEmpty)
              SocialHeader(
                userId: authorId,
                author: authorMapFromRow(widget.post),
                createdAt: parseIsoUtc(widget.post['created_at'] as String?),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: kPrimaryBlue.withValues(alpha: 0.14),
                    backgroundImage:
                        photo != null ? NetworkImage(photo) : null,
                    child: photo == null
                        ? Icon(
                            Icons.storefront_outlined,
                            color: kPrimaryBlue,
                            size: 24,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.placeTitle.isEmpty
                          ? 'Заведение'
                          : widget.placeTitle,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        height: 1.25,
                        color: cs.onSurface,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            if (widget.placeTitle.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.storefront_outlined,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '«${widget.placeTitle}»',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (body.isNotEmpty && body != ' ') ...<Widget>[
              const SizedBox(height: 12),
              Text(
                body,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: cs.onSurface,
                ),
              ),
            ],
            if (img != null) ...<Widget>[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints bc) {
                    final double w = bc.maxWidth;
                    double h = w / (16 / 9);
                    if (h > 300) {
                      h = 300;
                    }
                    return SizedBox(
                      width: w,
                      height: h,
                      child: Image.network(
                        img,
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        width: w,
                        height: h,
                        cacheWidth: imageCacheExtentPx(context, w),
                        cacheHeight: imageCacheExtentPx(context, h),
                        loadingBuilder: (
                          BuildContext context,
                          Widget child,
                          ImageChunkEvent? progress,
                        ) {
                          if (progress == null) {
                            return child;
                          }
                          return ColoredBox(
                            color: cs.surfaceContainerHighest,
                            child: const Center(
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        },
                        errorBuilder: (
                          BuildContext context,
                          Object error,
                          StackTrace? st,
                        ) =>
                            ColoredBox(
                          color: kPrimaryBlue.withValues(alpha: 0.12),
                          child: const Center(
                            child: Icon(
                              Icons.image_outlined,
                              color: kPrimaryBlue,
                              size: 40,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 4),
            Divider(
              height: 1,
              thickness: 1,
              color: cs.outlineVariant.withValues(alpha: 0.45),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: <Widget>[
                  _PostActionChip(
                    icon: _liked == true
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    iconColor:
                        _liked == true ? Colors.redAccent : null,
                    label: '$_likes',
                    onTap: _busy ? null : _toggleLike,
                    colorScheme: cs,
                  ),
                  const SizedBox(width: 4),
                  _PostActionChip(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: '$_comments',
                    onTap: _openComments,
                    colorScheme: cs,
                  ),
                  const SizedBox(width: 4),
                  _PostActionChip(
                    icon: Icons.send_rounded,
                    label: '',
                    tooltip: 'В чат',
                    onTap: _shareToChat,
                    colorScheme: cs,
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

class _PostActionChip extends StatelessWidget {
  const _PostActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.colorScheme,
    this.iconColor,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final ColorScheme colorScheme;
  final Color? iconColor;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final Widget child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            size: 20,
            color: iconColor ?? colorScheme.onSurfaceVariant,
          ),
          if (label.isNotEmpty) ...<Widget>[
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
    final Widget ink = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: child,
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: ink);
    }
    return ink;
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
  final FocusNode _inputFocus = FocusNode();
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
    _inputFocus.dispose();
    super.dispose();
  }

  void _insertMention(String snippet) {
    final String s = snippet.trim();
    if (s.isEmpty) {
      return;
    }
    final TextEditingValue v = _input.value;
    final String next = '${v.text}$s';
    _input.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _inputFocus.requestFocus();
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
                          const SizedBox(height: 10),
                      itemBuilder: (BuildContext c, int i) {
                        final Map<String, dynamic> m = _rows[i];
                        final String uid = m['user_id']?.toString() ?? '';
                        final String text =
                            m['content'] as String? ?? '';
                        return SocialCommentTile(
                          userId: uid,
                          bodyText: text,
                          author: authorMapFromRow(m),
                          createdAtIso: m['created_at'] as String?,
                          onMentionInsert: _insertMention,
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Container(
                      decoration: cloudCardDecoration(context, radius: 14),
                      child: TextField(
                        controller: _input,
                        focusNode: _inputFocus,
                        decoration: InputDecoration(
                          hintText: 'Комментарий… (@ник)',
                          filled: true,
                          fillColor: Colors.transparent,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
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
