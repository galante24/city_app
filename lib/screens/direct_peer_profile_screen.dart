import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/chat_download_share.dart';
import '../services/chat_service.dart';
import '../services/city_data_service.dart';
import '../services/notification_prefs.dart';
import '../utils/chat_links.dart';
import '../utils/phone_normalize.dart';
import '../widgets/city_network_image.dart';

/// Профиль собеседника в личном чате (шапка-галерея, действия, вкладки медиа/файлы/ссылки).
class DirectPeerProfileScreen extends StatefulWidget {
  const DirectPeerProfileScreen({
    super.key,
    required this.conversationId,
    required this.peerUserId,
    required this.title,
  });

  final String conversationId;
  final String peerUserId;
  final String title;

  @override
  State<DirectPeerProfileScreen> createState() =>
      _DirectPeerProfileScreenState();
}

class _DirectPeerProfileScreenState extends State<DirectPeerProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final PageController _photoController = PageController();
  int _photoIndex = 0;

  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _messages = <Map<String, dynamic>>[];
  bool _loading = true;
  bool? _muted;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    unawaited(_load());
    unawaited(_loadMuted());
  }

  Future<void> _loadMuted() async {
    final bool m = await NotificationPrefs.isConversationMuted(
      widget.conversationId,
    );
    if (mounted) {
      setState(() => _muted = m);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final Map<String, dynamic>? row = await CityDataService.fetchProfileRow(
      widget.peerUserId,
    );
    final List<Map<String, dynamic>> msg =
        await ChatService.fetchChatMessagesNewestFirst(widget.conversationId);
    if (mounted) {
      setState(() {
        _profile = row;
        _messages = msg;
        _loading = false;
      });
    }
  }

  Future<void> _toggleMute() async {
    final bool cur = _muted == true;
    await NotificationPrefs.setConversationMuted(widget.conversationId, !cur);
    if (mounted) {
      setState(() => _muted = !cur);
    }
  }

  List<String> get _gallery {
    final String? av = (_profile?['avatar_url'] as String?)?.trim();
    return ChatService.peerGalleryUrls(
      peerUserId: widget.peerUserId,
      avatarUrl: av,
      messagesNewestFirst: _messages,
    );
  }

  String get _displayName {
    if (_profile == null) {
      return widget.title;
    }
    final String fn = (_profile!['first_name'] as String?)?.trim() ?? '';
    final String ln = (_profile!['last_name'] as String?)?.trim() ?? '';
    final String t = ('$fn $ln').trim();
    return t.isNotEmpty ? t : widget.title;
  }

  String? get _usernameAt {
    final String? u = (_profile?['username'] as String?)?.trim();
    if (u == null || u.isEmpty) {
      return null;
    }
    return u.startsWith('@') ? u : '@$u';
  }

  String? get _about {
    final String? a = (_profile?['about'] as String?)?.trim();
    if (a == null || a.isEmpty) {
      return null;
    }
    return a;
  }

  String? get _phoneDisplay {
    final String? raw = (_profile?['phone_e164'] as String?)?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return raw.startsWith('+') ? raw : '+$raw';
  }

  @override
  void dispose() {
    _tabController.dispose();
    _photoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final List<String> photos = _gallery;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : NestedScrollView(
              headerSliverBuilder: (BuildContext c, bool inner) {
                return <Widget>[
                  SliverAppBar(
                    pinned: true,
                    expandedHeight: 280,
                    backgroundColor: Colors.transparent,
                    foregroundColor: cs.onSurface,
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    flexibleSpace: FlexibleSpaceBar(
                      background: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          if (photos.isEmpty)
                            ColoredBox(
                              color: cs.surfaceContainerHighest,
                              child: Icon(
                                Icons.person,
                                size: 96,
                                color: cs.onSurfaceVariant,
                              ),
                            )
                          else
                            PageView.builder(
                              controller: _photoController,
                              itemCount: photos.length,
                              onPageChanged: (int i) {
                                setState(() => _photoIndex = i);
                              },
                              itemBuilder: (BuildContext ctx, int i) {
                                final double bannerW = MediaQuery.sizeOf(
                                  ctx,
                                ).width;
                                final double bannerH = bannerW * 0.55;
                                return SizedBox(
                                  width: bannerW,
                                  height: bannerH,
                                  child: CityNetworkImage.fillParent(
                                    imageUrl: photos[i],
                                    boxFit: BoxFit.cover,
                                  ),
                                );
                              },
                            ),
                          if (photos.length > 1)
                            Positioned(
                              top: MediaQuery.paddingOf(context).top + 52,
                              left: 8,
                              right: 8,
                              child: Row(
                                children: List<Widget>.generate(
                                  photos.length,
                                  (int i) => Expanded(
                                    child: Container(
                                      height: 3,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: i <= _photoIndex
                                            ? Colors.white
                                            : Colors.white38,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                32,
                                16,
                                16,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: <Color>[
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.75),
                                  ],
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    _displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'в приложении',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.85,
                                      ),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          _RoundAction(
                            icon: Icons.chat_bubble_outline,
                            label: 'Чат',
                            onTap: () => Navigator.of(context).pop(),
                          ),
                          _RoundAction(
                            icon: _muted == true
                                ? Icons.notifications_off_outlined
                                : Icons.notifications_active_outlined,
                            label: 'Звук',
                            onTap: _toggleMute,
                          ),
                          _RoundAction(
                            icon: Icons.call_outlined,
                            label: 'Звонок',
                            onTap: _phoneDisplay == null
                                ? null
                                : () async {
                                    final String? e164 = normalizePhoneToE164Ru(
                                      _phoneDisplay!,
                                    );
                                    if (e164 == null) {
                                      return;
                                    }
                                    final Uri uri = Uri.parse('tel:$e164');
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri);
                                    }
                                  },
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(child: _infoCard(context)),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _TabBarDelegate(
                      tabBar: TabBar(
                        controller: _tabController,
                        labelColor: cs.primary,
                        unselectedLabelColor: cs.onSurfaceVariant,
                        indicatorColor: cs.primary,
                        tabs: const <Tab>[
                          Tab(text: 'Медиа'),
                          Tab(text: 'Файлы'),
                          Tab(text: 'Ссылки'),
                        ],
                      ),
                      bg: cs.surface,
                    ),
                  ),
                ];
              },
              body: TabBarView(
                controller: _tabController,
                children: <Widget>[
                  _MediaTab(messages: _messages),
                  _FilesTab(messages: _messages),
                  _LinksTab(messages: _messages),
                ],
              ),
            ),
    );
  }

  Widget _infoCard(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_phoneDisplay != null) ...<Widget>[
                SelectableText(
                  _phoneDisplay!,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  'Телефон',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
              ],
              if (_about != null) ...<Widget>[
                Text(
                  _about!,
                  style: TextStyle(
                    fontSize: 15,
                    color: cs.onSurface,
                    height: 1.35,
                  ),
                ),
                Text(
                  'О себе',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
              ],
              if (_usernameAt != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SelectableText(
                            _usernameAt!,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                            ),
                          ),
                          Text(
                            'Никнейм',
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Копировать ник',
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: _usernameAt!),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Ник скопирован')),
                          );
                        }
                      },
                      icon: Icon(Icons.copy_outlined, color: cs.primary),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate({required this.tabBar, required this.bg});

  final TabBar tabBar;
  final Color bg;

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(color: bg, child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) {
    return oldDelegate.tabBar != tabBar || oldDelegate.bg != bg;
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, color: Colors.white, size: 26),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaTab extends StatelessWidget {
  const _MediaTab({required this.messages});

  final List<Map<String, dynamic>> messages;

  List<_MediaItem> _items() {
    final List<_MediaItem> out = <_MediaItem>[];
    for (final Map<String, dynamic> m in messages) {
      if (m['deleted_at'] != null) {
        continue;
      }
      final String? created = m['created_at'] as String?;
      final String body = (m['body'] as String?) ?? '';
      final String? img = ChatService.imageUrlFromMessageBody(body);
      if (img != null) {
        out.add(_MediaItem(url: img, createdAt: created, isVideo: false));
        continue;
      }
      final ChatFileMeta? f = ChatService.fileMetaFromMessageBody(body);
      if (f != null && (f.isImage || f.isVideo)) {
        out.add(_MediaItem(url: f.url, createdAt: created, isVideo: f.isVideo));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final List<_MediaItem> items = _items();
    if (items.isEmpty) {
      return const Center(child: Text('Нет медиа в этом чате'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: items.length,
      itemBuilder: (BuildContext c, int i) {
        final _MediaItem it = items[i];
        final double thumb = (MediaQuery.sizeOf(c).width - 8 * 2 - 4 * 2) / 3;
        return GestureDetector(
          onTap: () => shareNetworkFileToDevice(
            context: context,
            url: it.url,
            suggestedName: Uri.parse(it.url).pathSegments.isNotEmpty
                ? Uri.parse(it.url).pathSegments.last
                : 'media',
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (it.isVideo)
                  ColoredBox(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    child: const Center(
                      child: Icon(Icons.videocam_outlined, size: 40),
                    ),
                  )
                else
                  CityNetworkImage.square(
                    imageUrl: it.url,
                    size: thumb,
                    borderRadius: 0,
                  ),
                if (it.isVideo)
                  const Align(
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.play_circle_fill,
                      color: Colors.white,
                      size: 40,
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

class _MediaItem {
  _MediaItem({
    required this.url,
    required this.createdAt,
    required this.isVideo,
  });

  final String url;
  final String? createdAt;
  final bool isVideo;
}

class _FilesTab extends StatelessWidget {
  const _FilesTab({required this.messages});

  final List<Map<String, dynamic>> messages;

  List<ChatFileMeta> _files() {
    final List<ChatFileMeta> out = <ChatFileMeta>[];
    for (final Map<String, dynamic> m in messages) {
      if (m['deleted_at'] != null) {
        continue;
      }
      final ChatFileMeta? f = ChatService.fileMetaFromMessageBody(
        (m['body'] as String?) ?? '',
      );
      if (f != null && !f.isImage && !f.isVideo) {
        out.add(f);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final List<ChatFileMeta> files = _files();
    if (files.isEmpty) {
      return const Center(child: Text('Нет файлов в этом чате'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: files.length,
      separatorBuilder: (_, int _) => const Divider(height: 1),
      itemBuilder: (BuildContext c, int i) {
        final ChatFileMeta f = files[i];
        return ListTile(
          leading: const Icon(Icons.insert_drive_file_outlined),
          title: Text(f.name),
          subtitle: Text(f.mime, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: () => shareNetworkFileToDevice(
              context: context,
              url: f.url,
              suggestedName: f.name,
            ),
          ),
          onTap: () => shareNetworkFileToDevice(
            context: context,
            url: f.url,
            suggestedName: f.name,
          ),
        );
      },
    );
  }
}

enum _LinksSort { byDate, byUrl }

class _LinksTab extends StatefulWidget {
  const _LinksTab({required this.messages});

  final List<Map<String, dynamic>> messages;

  @override
  State<_LinksTab> createState() => _LinksTabState();
}

class _LinksTabState extends State<_LinksTab> {
  _LinksSort _sort = _LinksSort.byDate;

  List<({String url, String? created})> _entries() {
    final Map<String, String?> firstSeen = <String, String?>{};
    for (final Map<String, dynamic> m in widget.messages) {
      if (m['deleted_at'] != null) {
        continue;
      }
      final String body = (m['body'] as String?) ?? '';
      final String? at = m['created_at'] as String?;
      for (final String u in extractUrlsFromChatText(body)) {
        firstSeen.putIfAbsent(u, () => at);
      }
    }
    final List<({String url, String? created})> list = firstSeen.entries
        .map((MapEntry<String, String?> e) => (url: e.key, created: e.value))
        .toList();
    if (_sort == _LinksSort.byDate) {
      list.sort((a, b) {
        final DateTime? da = a.created != null
            ? DateTime.tryParse(a.created!)
            : null;
        final DateTime? db = b.created != null
            ? DateTime.tryParse(b.created!)
            : null;
        if (da == null && db == null) {
          return 0;
        }
        if (da == null) {
          return 1;
        }
        if (db == null) {
          return -1;
        }
        return db.compareTo(da);
      });
    } else {
      list.sort((a, b) => a.url.compareTo(b.url));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final List<({String url, String? created})> entries = _entries();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SegmentedButton<_LinksSort>(
            segments: const <ButtonSegment<_LinksSort>>[
              ButtonSegment<_LinksSort>(
                value: _LinksSort.byDate,
                label: Text('По дате'),
              ),
              ButtonSegment<_LinksSort>(
                value: _LinksSort.byUrl,
                label: Text('По ссылке'),
              ),
            ],
            selected: <_LinksSort>{_sort},
            onSelectionChanged: (Set<_LinksSort> s) {
              setState(() => _sort = s.first);
            },
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('Нет ссылок в сообщениях'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: entries.length,
                  itemBuilder: (BuildContext c, int i) {
                    final ({String url, String? created}) e = entries[i];
                    return ListTile(
                      title: Text(
                        e.url,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      subtitle: e.created != null ? Text(e.created!) : null,
                      onTap: () async {
                        final Uri uri = Uri.parse(e.url);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
