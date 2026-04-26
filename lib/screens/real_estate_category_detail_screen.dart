import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_constants.dart'
    show kPrimaryBlue, listingFloorAreaWithSuffix;
import '../models/real_estate_listing_kind.dart';
import '../services/chat_service.dart';
import '../services/city_data_service.dart';
import '../services/real_estate_listing_service.dart';
import '../utils/image_cache_extent.dart';
import '../widgets/soft_tab_header.dart';
import '../widgets/weather_app_bar_action.dart';
import 'user_chat_thread_screen.dart';

class RealEstateCategoryDetailScreen extends StatefulWidget {
  const RealEstateCategoryDetailScreen({
    super.key,
    required this.kind,
    required this.row,
    required this.accent,
  });

  final RealEstateListingKind kind;
  final Map<String, dynamic> row;
  final Color accent;

  @override
  State<RealEstateCategoryDetailScreen> createState() =>
      _RealEstateCategoryDetailScreenState();
}

class _RealEstateCategoryDetailScreenState
    extends State<RealEstateCategoryDetailScreen> {
  bool _busy = false;
  bool? _canDelete;

  String get _id => widget.row['id']?.toString() ?? '';
  String get _authorId => widget.row['author_id']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_resolveCanDelete());
  }

  Future<void> _resolveCanDelete() async {
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) {
      if (mounted) {
        setState(() => _canDelete = false);
      }
      return;
    }
    if (_authorId == me) {
      if (mounted) {
        setState(() => _canDelete = true);
      }
      return;
    }
    if (CityDataService.isCurrentUserAdminSync()) {
      if (mounted) {
        setState(() => _canDelete = true);
      }
      return;
    }
    final Map<String, dynamic>? p = await CityDataService.fetchProfileRow(me);
    final bool admin = p?['is_admin'] == true;
    if (mounted) {
      setState(() => _canDelete = admin);
    }
  }

  Future<void> _openChat() async {
    if (_authorId.isEmpty) {
      return;
    }
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) {
      return;
    }
    if (_authorId == me) {
      return;
    }
    setState(() => _busy = true);
    try {
      final String conv = await ChatService.getOrCreateDirectConversation(
        _authorId,
      );
      final String name =
          (await ChatService.displayNameForUserId(_authorId)) ?? 'Чат';
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext c) => UserChatThreadScreen(
            conversationId: conv,
            title: name,
            listItem: null,
            directPeerUserId: _authorId,
          ),
        ),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть чат')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _call(String phone) async {
    final Uri? uri = _telUri(phone);
    if (uri == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Некорректный номер')),
        );
      }
      return;
    }
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

  static Uri? _telUri(String raw) {
    final String d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) {
      return null;
    }
    if (d.length == 11 && d.startsWith('7')) {
      return Uri.parse('tel:+$d');
    }
    if (d.length == 10) {
      return Uri.parse('tel:+7$d');
    }
    return Uri.parse('tel:${raw.trim()}');
  }

  Future<void> _delete() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) {
        return AlertDialog(
          title: const Text('Удалить объявление?'),
          content: const Text('Запись будет удалена без восстановления.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );
    if (ok != true) {
      return;
    }
    setState(() => _busy = true);
    try {
      await RealEstateListingService.deleteById(widget.kind, _id);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Объявление удалено')),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String title = widget.row['title'] as String? ?? '';
    final String desc = widget.row['description'] as String? ?? '';
    final String price = widget.row['price'] as String? ?? '';
    final String addr = RealEstateListingService.addressFromRow(widget.row);
    final String floorRaw = RealEstateListingService.floorAreaFromRow(
      widget.row,
    );
    final String floorLabel = listingFloorAreaWithSuffix(floorRaw);
    final String phone = widget.row['contact_phone'] as String? ?? '';
    final String? imageUrl = widget.row['image_url'] as String?;
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    final bool isOwner = me != null && me == _authorId;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color textPrimary = cs.onSurface;
    final Color textSecondary = cs.onSurfaceVariant;
    final Color bodyTextColor = cs.onSurface.withValues(alpha: 0.92);
    final double detailImgW = MediaQuery.sizeOf(context).width - 32;
    final double detailImgH = detailImgW * 9 / 16;
    final RealEstateListingKind k = widget.kind;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SoftTabHeader(
            leading: const SoftHeaderBackButton(),
            title: k.detailAppBarTitle,
            trailing: SoftHeaderWeatherWithAction(
              action: _canDelete == true
                  ? IconButton(
                      onPressed: _busy ? null : _delete,
                      icon: Icon(
                        Icons.delete_outline,
                        color: softHeaderTrailingIconColor(context),
                        size: 26,
                      ),
                      tooltip: 'Удалить',
                    )
                  : null,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: <Widget>[
                if (imageUrl != null && imageUrl.isNotEmpty) ...<Widget>[
                  Material(
                    elevation: 0.5,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        cacheWidth: imageCacheExtentPx(context, detailImgW),
                        cacheHeight: imageCacheExtentPx(context, detailImgH),
                        errorBuilder: (BuildContext c, Object e, StackTrace? st) =>
                            Container(
                          color: widget.accent.withValues(alpha: 0.12),
                          child: Icon(
                            k.headerIcon,
                            color: widget.accent,
                            size: 48,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                    height: 1.2,
                  ),
                ),
                if (price.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: kPrimaryBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(
                          Icons.payments_outlined,
                          color: kPrimaryBlue,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'от $price ₽',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: kPrimaryBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (floorLabel.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  _EstateInfoCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Icon(
                          Icons.square_foot_outlined,
                          size: 22,
                          color: kPrimaryBlue,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Квадратура',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: textSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                floorLabel,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: textPrimary,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (addr.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  _EstateInfoCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Icon(
                          Icons.place_outlined,
                          size: 22,
                          color: kPrimaryBlue,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                k.addressFieldLabel,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: textSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                addr,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: textPrimary,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _EstateInfoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'Описание',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        desc,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.45,
                          color: bodyTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _EstateInfoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'Контакты',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Material(
                        color: kPrimaryBlue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: () => _call(phone),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            child: Row(
                              children: <Widget>[
                                const Icon(
                                  Icons.call,
                                  color: kPrimaryBlue,
                                  size: 24,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    phone,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      color: kPrimaryBlue,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Icon(Icons.chevron_right, color: textSecondary),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (!isOwner && me != null) ...<Widget>[
                  FilledButton(
                    onPressed: _busy ? null : _openChat,
                    style: FilledButton.styleFrom(
                      backgroundColor: kPrimaryBlue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (_busy)
                          const Padding(
                            padding: EdgeInsets.only(right: 10),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          )
                        else
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(Icons.chat_bubble_outline, size: 22),
                          ),
                        const Text(
                          'Связаться в чате',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (isOwner) ...<Widget>[
                  Center(
                    child: Text(
                      'Это ваше объявление',
                      style: TextStyle(color: textSecondary, fontSize: 14),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EstateInfoCard extends StatelessWidget {
  const _EstateInfoCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 0.4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}
