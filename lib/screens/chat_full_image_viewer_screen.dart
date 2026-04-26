import 'dart:async';

import 'package:flutter/material.dart';

import '../services/chat_download_share.dart';

/// Полноэкранный просмотр фото из чата (масштаб, шапка, меню как в референсе).
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
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.88),
        foregroundColor: Colors.white,
        elevation: 0,
        title: subtitle != null
            ? Text(
                subtitle!,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              )
            : null,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.share_outlined),
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
            icon: const Icon(Icons.more_vert),
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
                    leading: Icon(Icons.visibility_outlined, color: Colors.white70),
                    title: Text('Показать в чате', style: TextStyle(color: Colors.white)),
                  ),
                ),
                const PopupMenuItem<_ViewerMenuAction>(
                  value: _ViewerMenuAction.reply,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.reply_rounded, color: Colors.white70),
                    title: Text('Ответить', style: TextStyle(color: Colors.white)),
                  ),
                ),
                const PopupMenuItem<_ViewerMenuAction>(
                  value: _ViewerMenuAction.share,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.share_outlined, color: Colors.white70),
                    title: Text('Поделиться', style: TextStyle(color: Colors.white)),
                  ),
                ),
                if (canDelete)
                  const PopupMenuItem<_ViewerMenuAction>(
                    value: _ViewerMenuAction.delete,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline, color: Color(0xFFFF8A80)),
                      title: Text('Удалить', style: TextStyle(color: Color(0xFFFF8A80))),
                    ),
                  ),
              ];
            },
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.6,
          maxScale: 4,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (
              BuildContext _,
              Widget child,
              ImageChunkEvent? loadingProgress,
            ) {
              if (loadingProgress == null) {
                return child;
              }
              return const Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(color: Colors.white54),
              );
            },
            errorBuilder: (BuildContext _, Object error, StackTrace? st) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Не удалось загрузить изображение',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _ViewerMenuAction { showInChat, reply, share, delete }
