import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/news_feed_category.dart';
import '../../services/feed_post_state_hub.dart';
import '../../services/feed_service.dart';
import '../media_progressive_image.dart';

/// Нижняя форма: заголовок, описание, до 10 фото, эмодзи.
Future<void> showFeedComposeSheet({
  required BuildContext context,
  required FeedService feed,
  required FeedAccess access,
  required NewsCategory initialCategory,
  String? editingPostId,
  String? initialTitle,
  String? initialDescription,
  List<String>? initialImageUrls,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext sheetContext) {
      return _FeedComposeBody(
        feed: feed,
        access: access,
        initialCategory: initialCategory,
        editingPostId: editingPostId,
        initialTitle: initialTitle,
        initialDescription: initialDescription,
        initialImageUrls: initialImageUrls,
      );
    },
  );
}

class _FeedComposeBody extends StatefulWidget {
  const _FeedComposeBody({
    required this.feed,
    required this.access,
    required this.initialCategory,
    this.editingPostId,
    this.initialTitle,
    this.initialDescription,
    this.initialImageUrls,
  });

  final FeedService feed;
  final FeedAccess access;
  final NewsCategory initialCategory;
  final String? editingPostId;
  final String? initialTitle;
  final String? initialDescription;
  final List<String>? initialImageUrls;

  @override
  State<_FeedComposeBody> createState() => _FeedComposeBodyState();
}

class _FeedComposeBodyState extends State<_FeedComposeBody> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _desc = TextEditingController();
  final FocusNode _descFocus = FocusNode();
  final ImagePicker _picker = ImagePicker();

  late NewsCategory _category;
  final List<String> _imageUrls = <String>[];
  bool _saving = false;
  bool _showEmoji = false;

  bool get _isEdit => widget.editingPostId != null;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _title.text = widget.initialTitle ?? '';
    _desc.text = widget.initialDescription ?? '';
    if (widget.initialImageUrls != null) {
      _imageUrls.addAll(widget.initialImageUrls!);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _descFocus.dispose();
    super.dispose();
  }

  List<DropdownMenuItem<NewsCategory>> _categoryItems() {
    return NewsCategory.values
        .where(widget.access.canPublishIn)
        .map(
          (NewsCategory c) => DropdownMenuItem<NewsCategory>(
            value: c,
            child: Text(categoryLabelRu(c)),
          ),
        )
        .toList();
  }

  Future<void> _pickPhotos() async {
    if (_imageUrls.length >= 10) {
      return;
    }
    final List<XFile> files = await _picker.pickMultiImage(imageQuality: 90);
    if (files.isEmpty) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _saving = true);
    try {
      for (final XFile f in files) {
        if (_imageUrls.length >= 10) {
          break;
        }
        final String url = await widget.feed.uploadFeedImage(f);
        _imageUrls.add(url);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (!widget.access.canPublishIn(_category)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет прав для этой категории')),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await widget.feed.updatePost(
          postId: widget.editingPostId!,
          title: _title.text,
          description: _desc.text,
          imagePublicUrls: List<String>.from(_imageUrls),
        );
        FeedInvalidateBus.instance.bump();
      } else {
        final Map<String, dynamic> inserted = await widget.feed.createPost(
          category: _category,
          title: _title.text,
          description: _desc.text,
          imagePublicUrls: List<String>.from(_imageUrls),
        );
        FeedInvalidateBus.instance.bump(insertedPostRow: inserted);
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEdit ? 'Пост обновлён' : 'Публикация сохранена'),
          ),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets pad = EdgeInsets.only(
      left: 20,
      right: 20,
      top: 16,
      bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
    );
    final List<DropdownMenuItem<NewsCategory>> items = _categoryItems();
    if (items.isEmpty) {
      return Padding(padding: pad, child: const Text('Нет прав на публикацию'));
    }
    return Padding(
      padding: pad,
      child: RepaintBoundary(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                _isEdit ? 'Редактирование' : 'Новая публикация',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              if (!_isEdit)
                DropdownButtonFormField<NewsCategory>(
                  initialValue:
                      items.any(
                        (DropdownMenuItem<NewsCategory> e) =>
                            e.value == _category,
                      )
                      ? _category
                      : items.first.value!,
                  decoration: const InputDecoration(
                    labelText: 'Категория',
                    border: OutlineInputBorder(),
                  ),
                  items: items,
                  onChanged: _saving
                      ? null
                      : (NewsCategory? c) {
                          if (c != null) {
                            setState(() => _category = c);
                          }
                        },
                ),
              if (!_isEdit) const SizedBox(height: 12),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Заголовок',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                validator: (String? v) => (v == null || v.trim().isEmpty)
                    ? 'Введите заголовок'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _desc,
                focusNode: _descFocus,
                decoration: InputDecoration(
                  labelText: 'Описание',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'Смайлы',
                    icon: const Icon(Icons.emoji_emotions_outlined),
                    onPressed: () => setState(() {
                      _showEmoji = !_showEmoji;
                      if (_showEmoji) {
                        _descFocus.requestFocus();
                      }
                    }),
                  ),
                ),
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
              ),
              if (_showEmoji)
                SizedBox(
                  height: 240,
                  child: EmojiPicker(
                    textEditingController: _desc,
                    config: Config(
                      height: 240,
                      checkPlatformCompatibility: true,
                      locale: const Locale('ru'),
                      emojiViewConfig: const EmojiViewConfig(
                        emojiSizeMax: 26,
                        buttonMode: ButtonMode.MATERIAL,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed: _saving ? null : _pickPhotos,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text('Фото (${_imageUrls.length}/10)'),
                  ),
                ],
              ),
              if (_imageUrls.isNotEmpty)
                SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _imageUrls.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, int i) {
                      return Stack(
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: RepaintBoundary(
                              child: ProgressiveCachedImage(
                                imageUrl: _imageUrls[i],
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                                borderRadius: 8,
                              ),
                            ),
                          ),
                          Positioned(
                            top: -6,
                            right: -6,
                            child: IconButton.filled(
                              style: IconButton.styleFrom(
                                minimumSize: const Size(28, 28),
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: _saving
                                  ? null
                                  : () =>
                                        setState(() => _imageUrls.removeAt(i)),
                              icon: const Icon(Icons.close, size: 16),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isEdit ? 'Сохранить' : 'Опубликовать'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
