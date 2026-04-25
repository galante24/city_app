import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../app_constants.dart';
import '../config/supabase_ready.dart';
import '../services/city_data_service.dart';

/// Мягкие нейтральные тона ленты
const Color kNewsScaffoldBg = Color(0xFFF2F2F7);
const Color kNewsCardBg = Color(0xFFFFFFFF);
const Color kNewsTextPrimary = Color(0xFF1C1C1E);
const Color kNewsTextSecondary = Color(0xFF6C6C70);

List<BoxShadow> cardFloatingShadows() {
  return [
    BoxShadow(
      color: const Color(0xFF0A0A0A).withValues(alpha: 0.06),
      blurRadius: 20,
      offset: const Offset(0, 6),
    ),
    BoxShadow(
      color: const Color(0xFF0A0A0A).withValues(alpha: 0.04),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];
}

enum NewsCategory {
  smi,
  administration,
  discussion,
}

String categoryLabelRu(NewsCategory c) {
  return switch (c) {
    NewsCategory.smi => 'СМИ',
    NewsCategory.administration => 'Администрация',
    NewsCategory.discussion => 'Обсуждение',
  };
}

String categoryToDb(NewsCategory c) {
  return switch (c) {
    NewsCategory.smi => 'smi',
    NewsCategory.administration => 'administration',
    NewsCategory.discussion => 'discussion',
  };
}

NewsCategory categoryFromDb(String? s) {
  switch (s) {
    case 'administration':
      return NewsCategory.administration;
    case 'discussion':
      return NewsCategory.discussion;
    case 'smi':
    default:
      return NewsCategory.smi;
  }
}

String formatPostTime(String? iso) {
  if (iso == null) {
    return '';
  }
  final d = DateTime.tryParse(iso);
  if (d == null) {
    return '';
  }
  final now = DateTime.now();
  final local = d.toLocal();
  final diff = now.difference(d);
  if (diff.inMinutes < 1) {
    return 'только что';
  }
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} мин. назад';
  }
  if (diff.inHours < 24) {
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  if (diff.inDays < 7) {
    return '${diff.inDays} дн. назад';
  }
  return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year}';
}

String _fileExtFromName(String name) {
  final int i = name.lastIndexOf('.');
  if (i < 0 || i >= name.length - 1) {
    return 'jpg';
  }
  return name.substring(i + 1).toLowerCase();
}

String _contentTypeForMedia(String kind, String ext) {
  if (kind == 'video') {
    return switch (ext) {
      'webm' => 'video/webm',
      'mov' => 'video/quicktime',
      _ => 'video/mp4',
    };
  }
  return switch (ext) {
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}

/// Загрузка в бакет [CityDataService.cityMediaBucket], возвращает публичный URL.
Future<String> _uploadCityMediaFile(
  XFile file, {
  required String mediaKind,
}) async {
  final c = CityDataService.client;
  if (c == null) {
    throw StateError('Supabase не инициализирован');
  }
  final String ext = _fileExtFromName(file.name);
  final String uid = c.auth.currentUser?.id ?? 'anon';
  final String path =
      'news/$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
  final String contentType = _contentTypeForMedia(mediaKind, ext);
  final bucket = c.storage.from(CityDataService.cityMediaBucket);
  if (kIsWeb) {
    final bytes = await file.readAsBytes();
    await bucket.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        upsert: true,
        contentType: contentType,
      ),
    );
  } else {
    await bucket.upload(
      path,
      File(file.path),
      fileOptions: FileOptions(
        upsert: true,
        contentType: contentType,
      ),
    );
  }
  return bucket.getPublicUrl(path);
}

SocialPost socialPostFromMap(Map<String, dynamic> m) {
  final String bodyRaw = (m['body'] as String?)?.trim() ??
      (m['content'] as String?)?.trim() ??
      (m['text'] as String?)?.trim() ??
      '';
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
    }
  }
  return SocialPost(
    id: m['id']?.toString() ?? '',
    author: m['author'] as String? ?? '',
    time: formatPostTime(
      m['created_at'] as String? ??
          m['published_at'] as String? ??
          m['inserted_at'] as String?,
    ),
    title: m['title'] as String? ?? '',
    body: bodyRaw,
    category: categoryFromDb(m['category'] as String?),
    mediaUrl: mediaUrl,
    mediaType: mediaType,
    likes: (m['likes'] as num?)?.toInt() ?? 0,
    comments: (m['comments'] as num?)?.toInt() ?? 0,
  );
}

class SocialPost {
  SocialPost({
    required this.id,
    required this.author,
    required this.time,
    required this.title,
    this.body = '',
    required this.category,
    this.mediaUrl,
    this.mediaType,
    this.likes = 0,
    this.comments = 0,
  });

  final String id;
  String author;
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
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final ImagePicker _mediaPicker = ImagePicker();
  StreamSubscription<AuthState>? _authSub;
  Stream<List<Map<String, dynamic>>>? _newsStream;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    if (supabaseAppReady) {
      _newsStream = CityDataService.watchNewsList();
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
        (AuthState data) {
          if (data.event == AuthChangeEvent.signedIn ||
              data.event == AuthChangeEvent.signedOut) {
            if (mounted) {
              setState(() {});
            }
          }
        },
      );
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  List<SocialPost> postsInCategory(
    List<SocialPost> all,
    NewsCategory c,
  ) {
    return all.where((p) => p.category == c).toList();
  }

  Widget buildCategoryFeed(List<SocialPost> items) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Пока нет публикаций',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      itemCount: items.length,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: 20),
      itemBuilder: (BuildContext context, int index) {
        final p = items[index];
        return SocialNewsCard(
          post: p,
          onLike: () {
            setState(() {
              if (p.isLiked) {
                p.likes = (p.likes - 1).clamp(0, 1 << 30);
              } else {
                p.likes += 1;
              }
              p.isLiked = !p.isLiked;
            });
          },
          onComment: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Комментарии — в разработке')),
            );
          },
          onShare: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Поделиться в чате — в разработке'),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> openCreateSheet() async {
    final formKey = GlobalKey<FormState>();
    String title = '';
    String body = '';
    XFile? pickedFile;
    String? pickedKind; // 'image' | 'video'
    var targetCategory = NewsCategory.values[_tabController.index];

    if (!context.mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: kNewsCardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
          ),
          child: StatefulBuilder(
            builder: (BuildContext context, void Function(void Function()) setModal) {
              return Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text(
                      'Новая публикация',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: kNewsTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<NewsCategory>(
                      key: ValueKey<NewsCategory>(targetCategory),
                      initialValue: targetCategory,
                      decoration: const InputDecoration(
                        labelText: 'Категория',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: kNewsScaffoldBg,
                      ),
                      items: NewsCategory.values
                          .map(
                            (NewsCategory c) => DropdownMenuItem<NewsCategory>(
                              value: c,
                              child: Text(categoryLabelRu(c)),
                            ),
                          )
                          .toList(),
                      onChanged: (NewsCategory? c) {
                        if (c == null) {
                          return;
                        }
                        setModal(() {
                          targetCategory = c;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Заголовок',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: kNewsScaffoldBg,
                      ),
                      maxLines: 2,
                      validator: (String? v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Введите заголовок';
                        }
                        return null;
                      },
                      onSaved: (String? v) => title = v?.trim() ?? '',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Текст',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: kNewsScaffoldBg,
                        alignLabelWithHint: true,
                        hintText: 'Текст новости',
                      ),
                      minLines: 4,
                      maxLines: 10,
                      validator: (String? v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Введите текст';
                        }
                        return null;
                      },
                      onSaved: (String? v) => body = v?.trim() ?? '',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        IconButton(
                          icon: Icon(
                            Icons.photo_camera_outlined,
                            color: pickedFile != null && pickedKind == 'image'
                                ? kPrimaryBlue
                                : kNewsTextSecondary,
                            size: 28,
                          ),
                          tooltip: 'Фото',
                          onPressed: () async {
                            final XFile? x = await _mediaPicker.pickImage(
                              source: ImageSource.gallery,
                              maxWidth: 1920,
                              imageQuality: 85,
                            );
                            if (x == null) {
                              return;
                            }
                            setModal(() {
                              pickedFile = x;
                              pickedKind = 'image';
                            });
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.videocam_outlined,
                            color: pickedFile != null && pickedKind == 'video'
                                ? kPrimaryBlue
                                : kNewsTextSecondary,
                            size: 28,
                          ),
                          tooltip: 'Видео',
                          onPressed: () async {
                            final XFile? x = await _mediaPicker.pickVideo(
                              source: ImageSource.gallery,
                            );
                            if (x == null) {
                              return;
                            }
                            setModal(() {
                              pickedFile = x;
                              pickedKind = 'video';
                            });
                          },
                        ),
                      ],
                    ),
                    if (pickedFile != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          pickedKind == 'video'
                              ? 'Видео: ${pickedFile!.name}'
                              : 'Фото: ${pickedFile!.name}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: kNewsTextSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) {
                          return;
                        }
                        if (!CityDataService.isCurrentUserAdminSync()) {
                          if (sheetContext.mounted) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Войдите как администратор: Профиль → вход по email',
                                ),
                              ),
                            );
                          }
                          return;
                        }
                        formKey.currentState!.save();
                        String? mediaUrl;
                        String? mediaType;
                        if (pickedFile != null && pickedKind != null) {
                          try {
                            mediaUrl = await _uploadCityMediaFile(
                              pickedFile!,
                              mediaKind: pickedKind!,
                            );
                            mediaType = pickedKind;
                          } on Object catch (e) {
                            if (sheetContext.mounted) {
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                SnackBar(
                                  content: Text('Загрузка файла: $e'),
                                ),
                              );
                            }
                            return;
                          }
                        }
                        try {
                          await CityDataService.insertNewsRow(
                            category: categoryToDb(targetCategory),
                            title: title,
                            body: body,
                            mediaUrl: mediaUrl,
                            mediaType: mediaType,
                          );
                        } on Object catch (e) {
                          if (sheetContext.mounted) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              SnackBar(
                                content: Text('Сохранение: $e'),
                              ),
                            );
                          }
                          return;
                        }
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Публикация сохранена'),
                            ),
                          );
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: kPrimaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Опубликовать'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!supabaseAppReady || _newsStream == null) {
      return Scaffold(
        backgroundColor: kNewsScaffoldBg,
        appBar: AppBar(
          title: const Text('Главная'),
        ),
        body: const Center(
          child: Text('Подключите Supabase (см. lib/config/supabase_config.dart)'),
        ),
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _newsStream!,
      builder: (
        BuildContext context,
        AsyncSnapshot<List<Map<String, dynamic>>> newsSnap,
      ) {
        final bool isAdmin = CityDataService.isCurrentUserAdminSync();
        final bool newsWaiting = newsSnap.connectionState ==
                ConnectionState.waiting &&
            !newsSnap.hasData;
        final List<Map<String, dynamic>> raw =
            newsSnap.data ?? <Map<String, dynamic>>[];
        final List<SocialPost> posts =
            raw.map(socialPostFromMap).toList();

        return Scaffold(
          backgroundColor: kNewsScaffoldBg,
          appBar: AppBar(
            backgroundColor: kPrimaryBlue,
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            shadowColor: Colors.transparent,
            title: const Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Главная',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Новости и важные объявления',
                  style: TextStyle(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              ],
            ),
            centerTitle: true,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(104),
              child: Material(
                color: kNewsCardBg,
                child: TabBar(
                  controller: _tabController,
                  labelColor: kPrimaryBlue,
                  unselectedLabelColor: kNewsTextSecondary,
                  indicatorColor: kPrimaryBlue,
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    height: 1.2,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    height: 1.2,
                  ),
                  indicatorSize: TabBarIndicatorSize.label,
                  tabs: const <Widget>[
                    Tab(
                      height: 58,
                      icon: Icon(Icons.newspaper, size: 22),
                      text: 'СМИ',
                    ),
                    Tab(
                      height: 58,
                      icon: Icon(Icons.campaign, size: 22),
                      text: 'Важные',
                    ),
                    Tab(
                      height: 58,
                      icon: Icon(Icons.forum, size: 22),
                      text: 'Обсуждение',
                    ),
                  ],
                ),
              ),
            ),
          ),
          floatingActionButton: isAdmin
              ? FloatingActionButton(
                  onPressed: openCreateSheet,
                  backgroundColor: kPrimaryBlue,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.add, size: 30),
                )
              : null,
          body: Column(
            children: <Widget>[
              if (newsWaiting)
                const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: const BouncingScrollPhysics(),
                  children: <Widget>[
                    buildCategoryFeed(
                      postsInCategory(posts, NewsCategory.smi),
                    ),
                    buildCategoryFeed(
                      postsInCategory(
                        posts,
                        NewsCategory.administration,
                      ),
                    ),
                    buildCategoryFeed(
                      postsInCategory(
                        posts,
                        NewsCategory.discussion,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SocialNewsCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kNewsCardBg,
        borderRadius: BorderRadius.circular(24),
        boxShadow: cardFloatingShadows(),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: kPrimaryBlue.withValues(alpha: 0.12),
                  child: const Icon(
                    Icons.campaign_outlined,
                    color: kPrimaryBlue,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.author,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: kNewsTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        post.time,
                        style: const TextStyle(
                          fontSize: 13,
                          color: kNewsTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              post.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1.25,
                color: kNewsTextPrimary,
              ),
            ),
          ),
          if (post.body.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                post.body,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: kNewsTextPrimary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (post.mediaUrl != null && post.mediaUrl!.isNotEmpty) ...<Widget>[
            if (post.mediaType == 'video')
              InlineVideoBlock(url: post.mediaUrl!)
            else
              Image.network(
                post.mediaUrl!,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (BuildContext c, Object e, StackTrace? st) =>
                    _brokenImagePlaceholder(),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) {
                    return child;
                  }
                  return SizedBox(
                    height: 220,
                    child: Center(
                      child: CircularProgressIndicator(
                        value: progress.expectedTotalBytes != null
                            ? progress.cumulativeBytesLoaded /
                                progress.expectedTotalBytes!
                            : null,
                        color: kPrimaryBlue,
                      ),
                    ),
                  );
                },
              ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                ActionChipPill(
                  icon: post.isLiked
                      ? Icons.favorite
                      : Icons.favorite_border,
                  label: post.likes.toString(),
                  iconColor: post.isLiked
                      ? const Color(0xFFE91E63)
                      : kNewsTextSecondary,
                  onPressed: onLike,
                ),
                ActionChipPill(
                  icon: Icons.chat_bubble_outline,
                  label: post.comments.toString(),
                  onPressed: onComment,
                ),
                ActionChipPill(
                  icon: Icons.send_outlined,
                  label: '',
                  onPressed: onShare,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _brokenImagePlaceholder() {
  return Container(
    height: 200,
    color: const Color(0xFFE5E5EA),
    child: const Center(
      child: Icon(
        Icons.broken_image_outlined,
        size: 48,
        color: kNewsTextSecondary,
      ),
    ),
  );
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
                color: iconColor ?? kNewsTextSecondary,
              ),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: kNewsTextSecondary,
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
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _inited = true;
            _error = null;
          });
        }
      }).catchError((Object e) {
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
      return Container(
        height: 200,
        color: const Color(0xFFE5E5EA),
        child: const Center(
          child: Text(
            'Видео недоступно',
            style: TextStyle(color: kNewsTextSecondary),
          ),
        ),
      );
    }
    if (!_inited || !_controller.value.isInitialized) {
      return const SizedBox(
        height: 220,
        child: Center(
          child: CircularProgressIndicator(color: kPrimaryBlue),
        ),
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
