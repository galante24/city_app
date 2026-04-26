import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_constants.dart';
import '../services/place_push_service.dart';
import '../services/place_service.dart';
import '../widgets/soft_tab_header.dart';
import '../widgets/weather_app_bar_action.dart';

class PlaceNewPostScreen extends StatefulWidget {
  const PlaceNewPostScreen({super.key, required this.placeId});

  final String placeId;

  @override
  State<PlaceNewPostScreen> createState() => _PlaceNewPostScreenState();
}

class _PlaceNewPostScreenState extends State<PlaceNewPostScreen> {
  final TextEditingController _content = TextEditingController();
  XFile? _image;
  bool _notify = false;
  bool _saving = false;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String t = _content.text.trim();
    if (t.isEmpty && _image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Текст или фото')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      String? imageUrl;
      if (_image != null) {
        imageUrl = await PlaceService.uploadPlaceImage(_image!);
      }
      final Map<String, dynamic> row = await PlaceService.createPost(
        placeId: widget.placeId,
        content: t.isEmpty ? ' ' : t,
        imageUrl: imageUrl,
        notifySubscribers: _notify,
      );
      final String postId = row['id']?.toString() ?? '';
      if (_notify && postId.isNotEmpty) {
        await PlacePushService.notifySubscribersIfNeeded(postId);
      }
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Запись опубликована')),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SoftTabHeader(
            leading: SoftHeaderBackButton(),
            title: 'Новая запись',
            trailing: SoftHeaderWeatherWithAction(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                TextField(
                  controller: _content,
                  maxLines: 8,
                  minLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Текст новости или акции',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: const Text('Фото'),
                  trailing: const Icon(Icons.add_photo_alternate_outlined),
                  onTap: _saving
                      ? null
                      : () async {
                          final XFile? f = await ImagePicker().pickImage(
                            source: ImageSource.gallery,
                            maxWidth: 2000,
                            imageQuality: 88,
                          );
                          if (f != null) {
                            setState(() => _image = f);
                          }
                        },
                ),
                if (_image != null && !kIsWeb)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.file(
                        File(_image!.path),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _notify,
                  onChanged: _saving
                      ? null
                      : (bool? v) => setState(() => _notify = v ?? false),
                  title: const Text('Отправить уведомление подписчикам'),
                  subtitle: Text(
                    'Только тем, у кого включены уведомления заведений и есть FCM-токен',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: kPrimaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Опубликовать'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
