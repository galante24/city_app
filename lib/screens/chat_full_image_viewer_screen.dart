import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

import '../services/chat_download_share.dart';

/// Полноэкранный просмотр фото из чата: [PhotoView] с pan при зуме ([enablePanAlways]).
class ChatFullImageViewerScreen extends StatelessWidget {
  const ChatFullImageViewerScreen({
    super.key,
    required this.imageUrl,
    this.subtitle,
    this.onShowInChat,
    this.onReply,
    this.onDelete,
    this.canDelete = false,
  });

  final String imageUrl;
  final String? subtitle;
  final VoidCallback? onShowInChat;
  final VoidCallback? onReply;
  final VoidCallback? onDelete;
  final bool canDelete;

  Future<void> _confirmDelete(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) {
        return AlertDialog(
          title: const Text('Удалить сообщение?'),
          content: const Text('Сообщение будет помечено как удалённое.'),
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
    if (ok == true && context.mounted) {
      Navigator.of(context).pop();
      onDelete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          RepaintBoundary(
            child: PhotoView(
              imageProvider: CachedNetworkImageProvider(imageUrl),
              enablePanAlways: true,
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 4,
              initialScale: PhotoViewComputedScale.contained,
              basePosition: Alignment.center,
              filterQuality: FilterQuality.medium,
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              loadingBuilder: (BuildContext context, ImageChunkEvent? event) {
                final double? p =
                    event == null || event.expectedTotalBytes == null
                    ? null
                    : event.cumulativeBytesLoaded /
                          (event.expectedTotalBytes ?? 1);
                return Center(
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      color: Colors.white54,
                      value: p,
                    ),
                  ),
                );
              },
              errorBuilder: (BuildContext ctx, Object err, StackTrace? st) {
                return const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white38,
                    size: 56,
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              elevation: 0,
              child: SizedBox(
                height: kToolbarHeight,
                child: Row(
                  children: <Widget>[
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: subtitle != null
                          ? Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.share_outlined,
                        color: Colors.white,
                      ),
                      tooltip: 'Поделиться',
                      onPressed: () {
                        unawaited(
                          shareNetworkFileToDevice(
                            context: context,
                            url: imageUrl,
                            suggestedName: 'chat_image.jpg',
                          ),
                        );
                      },
                    ),
                    PopupMenuButton<_ViewerMenuAction>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      color: const Color(0xFF2C2C2E),
                      surfaceTintColor: Colors.transparent,
                      elevation: 8,
                      onSelected: (_ViewerMenuAction a) {
                        if (a == _ViewerMenuAction.showInChat) {
                          Navigator.of(context).pop();
                          onShowInChat?.call();
                          return;
                        }
                        if (a == _ViewerMenuAction.reply) {
                          Navigator.of(context).pop();
                          onReply?.call();
                          return;
                        }
                        if (a == _ViewerMenuAction.share) {
                          unawaited(
                            shareNetworkFileToDevice(
                              context: context,
                              url: imageUrl,
                              suggestedName: 'chat_image.jpg',
                            ),
                          );
                          return;
                        }
                        if (a == _ViewerMenuAction.delete) {
                          unawaited(_confirmDelete(context));
                        }
                      },
                      itemBuilder: (BuildContext c) {
                        return <PopupMenuEntry<_ViewerMenuAction>>[
                          const PopupMenuItem<_ViewerMenuAction>(
                            value: _ViewerMenuAction.showInChat,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.visibility_outlined,
                                color: Colors.white70,
                              ),
                              title: Text(
                                'Показать в чате',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                          const PopupMenuItem<_ViewerMenuAction>(
                            value: _ViewerMenuAction.reply,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.reply_rounded,
                                color: Colors.white70,
                              ),
                              title: Text(
                                'Ответить',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                          const PopupMenuItem<_ViewerMenuAction>(
                            value: _ViewerMenuAction.share,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.share_outlined,
                                color: Colors.white70,
                              ),
                              title: Text(
                                'Поделиться',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                          if (canDelete)
                            const PopupMenuItem<_ViewerMenuAction>(
                              value: _ViewerMenuAction.delete,
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.delete_outline,
                                  color: Color(0xFFFF8A80),
                                ),
                                title: Text(
                                  'Удалить',
                                  style: TextStyle(color: Color(0xFFFF8A80)),
                                ),
                              ),
                            ),
                        ];
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _ViewerMenuAction { showInChat, reply, share, delete }
