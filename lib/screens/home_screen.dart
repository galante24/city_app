import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../app_card_styles.dart';
import '../app_constants.dart';
import '../config/supabase_ready.dart';
import '../models/news_feed_category.dart';
import '../services/feed_post_state_hub.dart';
import '../services/feed_service.dart';
import '../services/weather_service.dart';
import '../widgets/feed/feed_comments_bottom_sheet.dart';
import '../widgets/feed/feed_compose_sheet.dart';
import '../widgets/feed/feed_fullscreen_gallery.dart';
import '../widgets/feed/feed_share_to_chat_dialog.dart';
import '../widgets/city_network_image.dart';
import '../widgets/media_progressive_image.dart';
import '../utils/social_feed_format.dart';
import '../widgets/portal/portal_home_weather_corner.dart';

class _PostsBuckets {
  const _PostsBuckets({
    required this.smi,
    required this.administration,
    required this.discussion,
  });

  final List<SocialPost> smi;
  final List<SocialPost> administration;
  final List<SocialPost> discussion;
}

SocialPost socialPostFromMap(Map<String, dynamic> m) {
  final String bodyRaw =
      (m['body'] as String?)?.trim() ??
      (m['content'] as String?)?.trim() ??
      (m['text'] as String?)?.trim() ??
      '';
  final List<String> imageUrls =
      (m['image_urls'] as List?)
          ?.map((dynamic e) => e.toString().trim())
          .where((String s) => s.isNotEmpty)
          .toList() ??
      <String>[];
  String? mediaUrl = (m['media_url'] as String?)?.trim();
  String? mediaType = (m['media_type'] as String?)?.trim();
  if (mediaUrl == null || mediaUrl.isEmpty) {
    final String? vu = m['video_url'] as String?;
    final String? iu = m['image_url'] as String?;
    if (vu != null && vu.isNotEmpty) {
      mediaUrl = vu;
      mediaType = 'video';
    } else if (iu != null && iu.isNotEmpty) {
      mediaUrl = iu;
      mediaType = 'image';
    } else if (imageUrls.isNotEmpty) {
      mediaUrl = imageUrls.first;
      mediaType = 'image';
    }
  }
  String authorLabel = '';
  String? authorAvatar;
  final Object? ar = m['author'];
  if (ar is Map) {
    final String? fn = (ar['first_name'] as String?)?.trim();
    final String? un = (ar['username'] as String?)?.trim();
    if (fn != null && fn.isNotEmpty) {
      authorLabel = fn;
    } else if (un != null && un.isNotEmpty) {
      authorLabel = '@$un';
    }
    authorAvatar = (ar['avatar_url'] as String?)?.trim();
  } else if (m['author'] is String) {
    authorLabel = (m['author'] as String).trim();
  }
  final String? createdRaw =
      m['created_at'] as String? ??
      m['published_at'] as String? ??
      m['inserted_at'] as String?;
  final DateTime? createdUtc = createdRaw == null
      ? null
      : DateTime.tryParse(createdRaw)?.toUtc();
  return SocialPost(
    id: m['id']?.toString() ?? '',
    author: authorLabel,
    authorAvatarUrl: authorAvatar,
    time: formatPostTime(createdRaw),
    title: m['title'] as String? ?? '',
    body: bodyRaw,
    category: categoryFromDb(m['category'] as String?),
    mediaUrl: mediaUrl,
    mediaType: mediaType,
    likes:
        (m['likes_count'] as num?)?.toInt() ??
        (m['likes'] as num?)?.toInt() ??
        0,
    comments:
        (m['comments_count'] as num?)?.toInt() ??
        (m['comments'] as num?)?.toInt() ??
        0,
    imageUrls: imageUrls,
    userId: m['user_id']?.toString(),
    createdAtUtc: createdUtc,
  );
}

class SocialPost {
  SocialPost({
    required this.id,
    required this.author,
    this.authorAvatarUrl,
    required this.time,
    required this.title,
    this.body = '',
    required this.category,
    this.mediaUrl,
    this.mediaType,
    this.likes = 0,
    this.comments = 0,
    this.imageUrls = const <String>[],
    this.userId,
    this.createdAtUtc,
  });

  final String id;
  String author;
  final String? authorAvatarUrl;
  String time;
  String title;
  String body;
  final NewsCategory category;

  /// Публичный URL из [city_media] или старые поля.
  final String? mediaUrl;

  /// `image` или `video`.
  final String? mediaType;
  int likes;
  int comments;
  bool isLiked = false;

  /// Галерея поста (`posts.image_urls`).
  final List<String> imageUrls;

  /// Автор (`posts.user_id`).
  final String? userId;

  final DateTime? createdAtUtc;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<void>? _feedInvalidateSub;
  VoidCallback? _onFeedInvalidateBus;
  FeedService? _feed;
  FeedAccess _feedAccess = FeedAccess.fallbackUser();
  final Map<NewsCategory, List<SocialPost>> _feedPages =
      <NewsCategory, List<SocialPost>>{
        NewsCategory.smi: <SocialPost>[],
        NewsCategory.administration: <SocialPost>[],
        NewsCategory.discussion: <SocialPost>[],
      };
  final Map<NewsCategory, int> _feedOffset = <NewsCategory, int>{
    NewsCategory.smi: 0,
    NewsCategory.administration: 0,
    NewsCategory.discussion: 0,
  };
  final Map<NewsCategory, bool> _feedHasMore = <NewsCategory, bool>{
    NewsCategory.smi: true,
    NewsCategory.administration: true,
    NewsCategory.discussion: true,
  };
  final Map<NewsCategory, bool> _feedLoadingMore = <NewsCategory, bool>{
    NewsCategory.smi: false,
    NewsCategory.administration: false,
    NewsCategory.discussion: false,
  };
  final Map<NewsCategory, ScrollController> _feedScrollControllers =
      <NewsCategory, ScrollController>{
        NewsCategory.smi: ScrollController(),
        NewsCategory.administration: ScrollController(),
        NewsCategory.discussion: ScrollController(),
      };
  bool _feedBootstrapping = false;
  Future<WeatherCurrent?>? _portalWeatherFuture;
  bool _darkBgPrecached = false;

  Future<void> _bootstrapFeed() async {
    if (_feed == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _feedBootstrapping = true);
    try {
      _feedAccess = await _feed!.loadMyAccess();
      for (final NewsCategory c in NewsCategory.values) {
        _feedOffset[c] = 0;
        _feedHasMore[c] = true;
        _feedPages[c] = <SocialPost>[];
      }
      await _loadFeedPage(NewsCategory.smi, reset: true);
      await _loadFeedPage(NewsCategory.administration, reset: true);
      await _loadFeedPage(NewsCategory.discussion, reset: true);
    } finally {
      if (mounted) {
        setState(() => _feedBootstrapping = false);
      }
    }
  }

  Future<void> _prependPostFromRow(Map<String, dynamic> row) async {
    if (_feed == null) {
      return;
    }
    final SocialPost p = socialPostFromMap(row);
    final NewsCategory cat = p.category;
    try {
      final Set<String> liked = await _feed!.fetchMyLikedPostIds(<String>{
        p.id,
      });
      p.isLiked = liked.contains(p.id);
      if (!mounted) {
        return;
      }
      setState(() {
        final List<SocialPost> cur = List<SocialPost>.from(
          _feedPages[cat] ?? <SocialPost>[],
        );
        final List<SocialPost> next = <SocialPost>[
          p,
          ...cur.where((SocialPost x) => x.id != p.id),
        ];
        _feedPages[cat] = next;
        _feedOffset[cat] = next.length;
        FeedPostStateHub.instance.syncFromCounts(
          p.id,
          likes: p.likes,
          comments: p.comments,
          isLiked: p.isLiked,
        );
      });
    } on Object {
      if (mounted) {
        unawaited(_bootstrapFeed());
      }
    }
  }

  Future<void> _loadFeedPage(NewsCategory cat, {required bool reset}) async {
    if (_feed == null) {
      return;
    }
    if (_feedLoadingMore[cat] == true) {
      return;
    }
    final int off = reset ? 0 : (_feedOffset[cat] ?? 0);
    if (!reset && (_feedHasMore[cat] != true)) {
      return;
    }
    _feedLoadingMore[cat] = true;
    if (mounted) {
      setState(() {});
    }
    try {
      final List<Map<String, dynamic>> rows = await _feed!.fetchPostsPage(
        category: cat,
        offset: off,
      );
      final List<SocialPost> mapped = rows
          .map(socialPostFromMap)
          .toList(growable: false);
      final Set<String> ids = mapped.map((SocialPost p) => p.id).toSet();
      final Set<String> liked = await _feed!.fetchMyLikedPostIds(ids);
      for (final SocialPost p in mapped) {
        p.isLiked = liked.contains(p.id);
        FeedPostStateHub.instance.syncFromCounts(
          p.id,
          likes: p.likes,
          comments: p.comments,
          isLiked: p.isLiked,
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        if (reset) {
          _feedPages[cat] = mapped;
          _feedOffset[cat] = mapped.length;
        } else {
          _feedPages[cat] = <SocialPost>[
            ..._feedPages[cat] ?? <SocialPost>[],
            ...mapped,
          ];
          _feedOffset[cat] = (_feedOffset[cat] ?? 0) + mapped.length;
        }
        _feedHasMore[cat] = mapped.length >= FeedService.pageSize;
        _feedLoadingMore[cat] = false;
      });
    } on Object {
      if (mounted) {
        setState(() => _feedLoadingMore[cat] = false);
      }
    }
  }

  void _onFeedScroll(NewsCategory cat) {
    final ScrollController sc = _feedScrollControllers[cat]!;
    if (!sc.hasClients || _feed == null) {
      return;
    }
    if (_feedLoadingMore[cat] == true || _feedHasMore[cat] != true) {
      return;
    }
    final double max = sc.position.maxScrollExtent;
    if (max <= 0) {
      return;
    }
    if (sc.position.pixels > max - 280) {
      unawaited(_loadFeedPage(cat, reset: false));
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    if (supabaseAppReady) {
      _feed = FeedService.tryOf(Supabase.instance.client);
      _portalWeatherFuture = WeatherService.hasApiKey
          ? WeatherService.fetchCurrent()
          : null;
      if (_feed != null) {
        unawaited(_bootstrapFeed());
        _feedInvalidateSub = _feed!.feedInvalidateStream().listen((_) {
          if (mounted) {
            unawaited(_bootstrapFeed());
          }
        });
        _onFeedInvalidateBus = () {
          if (!mounted) {
            return;
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            final FeedInvalidateSignal? s =
                FeedInvalidateBus.instance.signal.value;
            if (s == null) {
              return;
            }
            if (s.insertedPostRow != null) {
              unawaited(_prependPostFromRow(s.insertedPostRow!));
            } else {
              unawaited(_bootstrapFeed());
            }
          });
        };
        FeedInvalidateBus.instance.signal.addListener(_onFeedInvalidateBus!);
      }
      for (final NewsCategory c in NewsCategory.values) {
        _feedScrollControllers[c]!.addListener(() => _onFeedScroll(c));
      }
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((
        AuthState data,
      ) {
        if (data.event == AuthChangeEvent.signedIn ||
            data.event == AuthChangeEvent.signedOut) {
          if (mounted) {
            unawaited(_bootstrapFeed());
            setState(() {});
          }
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_darkBgPrecached) {
      _darkBgPrecached = true;
      unawaited(precacheImage(AssetImage(kDarkThemeBackgroundAsset), context));
    }
  }

  @override
  void dispose() {
    if (_onFeedInvalidateBus != null) {
      FeedInvalidateBus.instance.signal.removeListener(_onFeedInvalidateBus!);
      _onFeedInvalidateBus = null;
    }
    _feedInvalidateSub?.cancel();
    _authSub?.cancel();
    for (final ScrollController sc in _feedScrollControllers.values) {
      sc.dispose();
    }
    _tabController.dispose();
    super.dispose();
  }

  Widget buildCategoryFeed(List<SocialPost> items, NewsCategory category) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final ScrollController sc = _feedScrollControllers[category]!;
    final bool showLoader = _feedLoadingMore[category] == true;
    final int n = items.length;
    if (n == 0 && !_feedBootstrapping) {
      return ColoredBox(
        color: Colors.transparent,
        child: ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(
            kScreenHorizontalPadding,
            12,
            kScreenHorizontalPadding,
            130,
          ),
          children: <Widget>[
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Пока нет публикаций',
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    color: isDark ? Colors.white70 : Colors.grey[600],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return ColoredBox(
      color: Colors.transparent,
      child: ListView.separated(
        addAutomaticKeepAlives: true,
        controller: sc,
        padding: const EdgeInsets.fromLTRB(
          kScreenHorizontalPadding,
          12,
          kScreenHorizontalPadding,
          130,
        ),
        itemCount: n + (showLoader ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: kCloudListSpacing),
        itemBuilder: (BuildContext context, int index) {
          if (index >= n) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final SocialPost p = items[index];
          return SocialNewsCard(
            post: p,
            onLike: () {
              if (_feed == null) {
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
              unawaited(() async {
                try {
                  await _feed!.togglePostLike(
                    postId: p.id,
                    currentlyLiked: before.isLiked,
                  );
                  final Map<String, dynamic>? row = await _feed!.fetchPostRow(
                    p.id,
                  );
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
              }());
            },
            onComment: () {
              if (_feed == null) {
                return;
              }
              unawaited(
                showFeedCommentsBottomSheet(
                  context: context,
                  feed: _feed!,
                  postId: p.id,
                  postTitle: p.title,
                ),
              );
            },
            onShare: () {
              if (_feed == null) {
                return;
              }
              final FeedPostCounters s = FeedPostStateHub.instance
                  .notifierFor(p.id)
                  .value;
              p.isLiked = s.isLiked;
              p.likes = s.likes;
              p.comments = s.comments;
              unawaited(
                showFeedShareToChatDialog(
                  context: context,
                  feed: _feed!,
                  post: p,
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!supabaseAppReady || _feed == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Theme(
          data: Theme.of(context).copyWith(canvasColor: Colors.transparent),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Укажите SUPABASE_URL и SUPABASE_ANON_KEY '
                '(api_keys.example.json → api_keys.json, '
                'flutter run --dart-define-from-file=api_keys.json)',
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(fontSize: 15, height: 1.35),
              ),
            ),
          ),
        ),
      );
    }

    final _PostsBuckets byCat = _PostsBuckets(
      smi: List<SocialPost>.from(
        _feedPages[NewsCategory.smi] ?? <SocialPost>[],
      ),
      administration: List<SocialPost>.from(
        _feedPages[NewsCategory.administration] ?? <SocialPost>[],
      ),
      discussion: List<SocialPost>.from(
        _feedPages[NewsCategory.discussion] ?? <SocialPost>[],
      ),
    );
    return Builder(
      builder: (BuildContext context) {
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        final double screenW = MediaQuery.sizeOf(context).width;
        final double screenH = MediaQuery.sizeOf(context).height;
        final EdgeInsets safePad = MediaQuery.paddingOf(context);
        final double headerLeft = screenW < 360 ? 14.0 : 20.0;
        final double headerRightInset = (safePad.right + 84.0).clamp(
          78.0,
          120.0,
        );
        final double lentaFont = isDark ? 14.5 : 14.5;
        final double cityTitleFont = isDark ? 16.5 : 16.5;
        final double citySubFont = isDark ? 11.0 : 11.0;
        final double heraldSize = screenW < 360 ? 28.0 : 30.0;
        // Светлая тема: те же вертикальные отступы, что и в тёмной (портал).
        final double topSkyGap = (screenH * 0.088 + 34).clamp(58.0, 118.0);
        final double headerExtraDrop = (screenH * 0.078).clamp(46.0, 96.0);
        final double headerTopInset = (topSkyGap + headerExtraDrop).clamp(
          72.0,
          178.0,
        );
        return Scaffold(
          extendBody: true,
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.transparent,
          body: Theme(
            data: Theme.of(context).copyWith(canvasColor: Colors.transparent),
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.transparent,
                    child: SafeArea(
                      bottom: false,
                      minimum: const EdgeInsets.only(top: 8),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            SizedBox(height: headerTopInset),
                            Padding(
                              padding: EdgeInsets.only(
                                left: headerLeft,
                                right: headerRightInset,
                                bottom: 6,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: <Widget>[
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.asset(
                                      'assets/app_icon.png',
                                      width: heraldSize,
                                      height: heraldSize,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (
                                            BuildContext context,
                                            Object error,
                                            StackTrace? stackTrace,
                                          ) {
                                            return SizedBox(
                                              width: heraldSize,
                                              height: heraldSize,
                                            );
                                          },
                                    ),
                                  ),
                                  SizedBox(width: screenW < 360 ? 8 : 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          'Лесосибирск',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.montserrat(
                                            fontSize: cityTitleFont,
                                            fontWeight: FontWeight.w700,
                                            height: 1.15,
                                            color: Colors.white,
                                            shadows: const <Shadow>[
                                              Shadow(
                                                color: Color(0x66000000),
                                                offset: Offset(0, 1),
                                                blurRadius: 3,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          'город леса',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.montserrat(
                                            fontSize: citySubFont,
                                            fontWeight: FontWeight.w400,
                                            height: 1.15,
                                            color: Colors.white.withValues(
                                              alpha: 0.9,
                                            ),
                                            shadows: const <Shadow>[
                                              Shadow(
                                                color: Color(0x59000000),
                                                offset: Offset(0, 1),
                                                blurRadius: 2,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.only(
                                left: headerLeft,
                                right: headerRightInset,
                                bottom: 6,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Городская лента',
                                  textAlign: TextAlign.left,
                                  style: GoogleFonts.montserrat(
                                    fontSize: lentaFont,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.15,
                                    height: 1.2,
                                    color: isDark ? Colors.white : kPineGreen,
                                    shadows: isDark
                                        ? const <Shadow>[
                                            Shadow(
                                              color: Color(0x59000000),
                                              offset: Offset(0, 1),
                                              blurRadius: 2,
                                            ),
                                          ]
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: _PortalNewsTabBarShell(
                                          isDark: isDark,
                                          child: TabBar(
                                            controller: _tabController,
                                            isScrollable: true,
                                            tabAlignment: TabAlignment.start,
                                            padding: EdgeInsets.zero,
                                            labelColor: isDark
                                                ? kPortalGold
                                                : kPineGreen,
                                            unselectedLabelColor: isDark
                                                ? Colors.white.withValues(
                                                    alpha: 0.55,
                                                  )
                                                : kNavOliveMuted,
                                            indicatorColor: isDark
                                                ? kPortalGold
                                                : kPineGreen,
                                            indicatorWeight: 2.5,
                                            labelStyle: GoogleFonts.montserrat(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                            unselectedLabelStyle:
                                                GoogleFonts.montserrat(
                                                  fontWeight: FontWeight.w500,
                                                  fontSize: 12,
                                                ),
                                            indicatorSize:
                                                TabBarIndicatorSize.label,
                                            dividerColor: Colors.transparent,
                                            tabs: const <Widget>[
                                              Tab(
                                                height: 48,
                                                icon: Icon(
                                                  Icons.newspaper,
                                                  size: 20,
                                                ),
                                                text: 'СМИ',
                                              ),
                                              Tab(
                                                height: 48,
                                                icon: Icon(
                                                  Icons.campaign,
                                                  size: 20,
                                                ),
                                                text: 'Важные',
                                              ),
                                              Tab(
                                                height: 48,
                                                icon: Icon(
                                                  Icons.forum,
                                                  size: 20,
                                                ),
                                                text: 'Обсуждение',
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (_feedAccess.canCreateSomewhere)
                                        IconButton.filledTonal(
                                          style: IconButton.styleFrom(
                                            backgroundColor: isDark
                                                ? null
                                                : kEmeraldGlow.withValues(
                                                    alpha: 0.16,
                                                  ),
                                            foregroundColor: isDark
                                                ? null
                                                : kPineGreen,
                                          ),
                                          onPressed: () async {
                                            if (_feed == null) {
                                              return;
                                            }
                                            await showFeedComposeSheet(
                                              context: context,
                                              feed: _feed!,
                                              access: _feedAccess,
                                              initialCategory: NewsCategory
                                                  .values[_tabController.index],
                                            );
                                          },
                                          icon: const Icon(Icons.add),
                                          tooltip: 'Новая публикация',
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (_feedBootstrapping)
                              LinearProgressIndicator(
                                minHeight: 2,
                                color: kPrimaryBlue,
                                backgroundColor: Colors.transparent,
                              ),
                            Expanded(
                              child: ColoredBox(
                                color: Colors.transparent,
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: TabBarView(
                                    controller: _tabController,
                                    physics: const ClampingScrollPhysics(),
                                    children: <Widget>[
                                      _KeepAliveFeed(
                                        child: buildCategoryFeed(
                                          byCat.smi,
                                          NewsCategory.smi,
                                        ),
                                      ),
                                      _KeepAliveFeed(
                                        child: buildCategoryFeed(
                                          byCat.administration,
                                          NewsCategory.administration,
                                        ),
                                      ),
                                      _KeepAliveFeed(
                                        child: buildCategoryFeed(
                                          byCat.discussion,
                                          NewsCategory.discussion,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                PortalHomeWeatherCorner(
                  future: _portalWeatherFuture,
                  darkForeground: isDark,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PortalNewsTabBarShell extends StatelessWidget {
  const _PortalNewsTabBarShell({required this.isDark, required this.child});

  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isDark) {
      return RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: kPineGreen.withValues(alpha: 0.1)),
            ),
            child: child,
          ),
        ),
      );
    }
    // Без BackdropFilter: размытие на весь таб-бар при перелистывании сильно грузит GPU.
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.48),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _KeepAliveFeed extends StatefulWidget {
  const _KeepAliveFeed({required this.child});

  final Widget child;

  @override
  State<_KeepAliveFeed> createState() => _KeepAliveFeedState();
}

class _KeepAliveFeedState extends State<_KeepAliveFeed>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ColoredBox(color: Colors.transparent, child: widget.child);
  }
}

class SocialNewsCard extends StatefulWidget {
  const SocialNewsCard({
    super.key,
    required this.post,
    required this.onLike,
    required this.onComment,
    required this.onShare,
  });

  final SocialPost post;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;

  @override
  State<SocialNewsCard> createState() => _SocialNewsCardState();
}

class _SocialNewsCardState extends State<SocialNewsCard> {
  bool _bodyExpanded = false;

  SocialPost get post => widget.post;

  void _openGallery(List<String> urls, int i) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => FeedFullscreenGallery(urls: urls, initialIndex: i),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color onSurface = isDark ? Colors.white : cs.onSurface;
    final Color muted = isDark
        ? Colors.white.withValues(alpha: 0.65)
        : cs.onSurface.withValues(alpha: 0.65);
    final double kCardRadius = isDark ? 25 : 24;
    final bool hasGallery = post.imageUrls.isNotEmpty;

    final Widget column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: <Widget>[
              post.authorAvatarUrl != null && post.authorAvatarUrl!.isNotEmpty
                  ? CityNetworkImage.avatar(
                      context: context,
                      imageUrl: post.authorAvatarUrl,
                      diameter: 40,
                      placeholderName: post.author,
                    )
                  : CircleAvatar(
                      radius: 20,
                      child: Icon(
                        Icons.campaign_rounded,
                        color: isDark ? kPortalGold : kEmeraldGlow,
                        size: 22,
                      ),
                    ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  post.time,
                  style: GoogleFonts.montserrat(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: muted,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (post.author.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
            child: Text(
              post.author,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              style: GoogleFonts.montserrat(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: onSurface,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            post.title,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
            style: GoogleFonts.montserrat(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.25,
              color: onSurface,
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (hasGallery)
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints bc) {
              final double maxW = bc.maxWidth.isFinite && bc.maxWidth > 0
                  ? bc.maxWidth
                  : MediaQuery.sizeOf(context).width;
              return Container(
                constraints: BoxConstraints(
                  minWidth: double.infinity,
                  maxHeight: 350,
                ),
                width: maxW,
                child: ListView.separated(
                  addAutomaticKeepAlives: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: post.imageUrls.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, int i) {
                    final double slotW = math
                        .min(maxW - 32, MediaQuery.sizeOf(context).width * 0.88)
                        .clamp(160.0, 520.0);
                    return RepaintBoundary(
                      child: GestureDetector(
                        onTap: () => _openGallery(post.imageUrls, i),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(26),
                          child: SizedBox(
                            width: slotW,
                            height: 350,
                            child: ProgressiveCachedImage(
                              imageUrl: post.imageUrls[i],
                              width: slotW,
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
              );
            },
          )
        else if (post.mediaUrl != null &&
            post.mediaUrl!.isNotEmpty) ...<Widget>[
          if (post.mediaType == 'video')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InlineVideoBlock(url: post.mediaUrl!),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: () => _openGallery(<String>[post.mediaUrl!], 0),
                child: ClipRRect(
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
                        child: CityNetworkImage.fillParent(
                          imageUrl: post.mediaUrl!,
                          boxFit: BoxFit.cover,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
        if (post.body.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              post.body,
              maxLines: _bodyExpanded ? null : 4,
              overflow: _bodyExpanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: GoogleFonts.montserrat(
                fontSize: 15,
                height: 1.4,
                color: onSurface,
              ),
            ),
          ),
          if (post.body.length > 140 || post.body.split('\n').length > 4)
            TextButton(
              onPressed: () => setState(() => _bodyExpanded = !_bodyExpanded),
              child: Text(_bodyExpanded ? 'Свернуть' : 'Развернуть'),
            ),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: ValueListenableBuilder<FeedPostCounters>(
            valueListenable: FeedPostStateHub.instance.notifierFor(post.id),
            builder: (BuildContext context, FeedPostCounters c, _) {
              return Row(
                children: <Widget>[
                  ActionChipPill(
                    icon: c.isLiked ? Icons.favorite : Icons.favorite_border,
                    label: c.likes.toString(),
                    iconColor: c.isLiked ? const Color(0xFFE91E63) : muted,
                    onPressed: widget.onLike,
                  ),
                  ActionChipPill(
                    icon: Icons.chat_bubble_outline,
                    label: c.comments.toString(),
                    onPressed: widget.onComment,
                  ),
                  ActionChipPill(
                    icon: Icons.send_outlined,
                    label: '',
                    onPressed: widget.onShare,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );

    if (isDark) {
      return RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(kCardRadius),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(kCardRadius),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: column,
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kCardRadius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(kCardRadius),
            border: Border.all(color: kPineGreen.withValues(alpha: 0.08)),
          ),
          child: column,
        ),
      ),
    );
  }
}

class ActionChipPill extends StatelessWidget {
  const ActionChipPill({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 24,
                color:
                    iconColor ??
                    Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.55),
              ),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class InlineVideoBlock extends StatefulWidget {
  const InlineVideoBlock({super.key, required this.url});

  final String url;

  @override
  State<InlineVideoBlock> createState() => _InlineVideoBlockState();
}

class _InlineVideoBlockState extends State<InlineVideoBlock> {
  late final VideoPlayerController _controller;
  bool _inited = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..addListener(_tick)
      ..initialize()
          .then((_) {
            if (mounted) {
              setState(() {
                _inited = true;
                _error = null;
              });
            }
          })
          .catchError((Object e) {
            if (mounted) {
              setState(() {
                _error = 'Видео не загружено';
                _inited = false;
              });
            }
          });
  }

  void _tick() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_tick);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      final ColorScheme cs = Theme.of(context).colorScheme;
      return Container(
        height: 200,
        color: cs.surfaceContainerHighest,
        child: Center(
          child: Text(
            'Видео недоступно',
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.55)),
          ),
        ),
      );
    }
    if (!_inited || !_controller.value.isInitialized) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator(color: kPrimaryBlue)),
      );
    }
    return AspectRatio(
      aspectRatio: _controller.value.aspectRatio,
      child: Stack(
        alignment: Alignment.center,
        children: [
          VideoPlayer(_controller),
          Material(
            color: Colors.black26,
            type: MaterialType.transparency,
            child: IconButton(
              onPressed: () {
                if (_controller.value.isPlaying) {
                  _controller.pause();
                } else {
                  _controller.play();
                }
                setState(() {});
              },
              icon: Icon(
                _controller.value.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill,
                size: 64,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
