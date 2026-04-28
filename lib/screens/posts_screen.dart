import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/post.dart';
import '../services/post_service.dart';

/// Экран ленты постов (REST + realtime).
class PostsScreen extends StatefulWidget {
  const PostsScreen({super.key});

  @override
  State<PostsScreen> createState() => _PostsScreenState();
}

class _PostsScreenState extends State<PostsScreen> {
  late final PostService _service;
  late final Stream<List<Post>> _postsStream;

  @override
  void initState() {
    super.initState();
    _service = PostService(Supabase.instance.client);
    _postsStream = _service.streamPosts();
  }

  void _toastError(Object e) {
    if (!mounted) {
      return;
    }
    final String msg = e.toString().replaceFirst('Exception: ', '');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ошибка: $msg')),
    );
  }

  Future<void> _openCreateDialog() async {
    final TextEditingController titleCtrl = TextEditingController();
    final TextEditingController bodyCtrl = TextEditingController();

    final bool? saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Новый пост'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Заголовок',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Текст',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 3,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await _service.createPost(titleCtrl.text, bodyCtrl.text);
                  if (!dialogContext.mounted) {
                    return;
                  }
                  Navigator.of(dialogContext).pop(true);
                } catch (e) {
                  if (!dialogContext.mounted) {
                    return;
                  }
                  _toastError(e);
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );

    titleCtrl.dispose();
    bodyCtrl.dispose();

    if (!mounted || saved != true) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Пост сохранён')),
    );
  }

  static String _formatDate(DateTime utc) {
    final DateFormat fmt = DateFormat.yMMMd('ru').add_jm();
    return fmt.format(utc.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Посты')),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateDialog,
        tooltip: 'Новый пост',
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<Post>>(
        stream: _postsStream,
        builder:
            (BuildContext context, AsyncSnapshot<List<Post>> snapshot) {
              if (snapshot.hasError && !snapshot.hasData) {
                final Object e = snapshot.error!;
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Не удалось загрузить посты: $e',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              if (!snapshot.hasData &&
                  snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final List<Post> items = snapshot.data ?? <Post>[];
              final String? myId =
                  Supabase.instance.client.auth.currentUser?.id;

              if (items.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Пока нет постов. Нажмите «+», чтобы добавить.',
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: items.length,
                itemBuilder: (BuildContext context, int i) {
                  final Post p = items[i];
                  final bool isMine =
                      myId != null && p.userId == myId;
                  Widget card = Card(
                    margin:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            p.title,
                            style:
                                Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            p.content,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _formatDate(p.createdAt),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.outline,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  );

                  if (isMine) {
                    return Dismissible(
                      key: ValueKey<String>('post-${p.id}'),
                      direction: DismissDirection.horizontal,
                      background: Container(
                        color: Theme.of(context).colorScheme.error,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: Theme.of(context).colorScheme.onError,
                        ),
                      ),
                      confirmDismiss:
                          (DismissDirection direction) async {
                        final bool? ok = await showDialog<bool>(
                          context: context,
                          builder: (BuildContext ctx) {
                            return AlertDialog(
                              title: const Text('Удалить пост?'),
                              content: Text(
                                '«${p.title}» будет удалён безвозвратно.',
                              ),
                              actions: <Widget>[
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(ctx).pop(false),
                                  child: const Text('Отмена'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(ctx).pop(true),
                                  child: const Text('Удалить'),
                                ),
                              ],
                            );
                          },
                        );
                        if (ok != true) {
                          return false;
                        }
                        try {
                          await _service.deletePost(p.id);
                          if (!context.mounted) {
                            return false;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Пост удалён')),
                          );
                          return true;
                        } catch (e) {
                          if (context.mounted) {
                            _toastError(e);
                          }
                          return false;
                        }
                      },
                      child: card,
                    );
                  }

                  return card;
                },
              );
            },
      ),
    );
  }
}
