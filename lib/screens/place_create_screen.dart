import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_constants.dart';
import '../services/place_service.dart';
import '../widgets/soft_tab_header.dart';
import '../widgets/weather_app_bar_action.dart';

class PlaceCreateScreen extends StatefulWidget {
  const PlaceCreateScreen({super.key});

  @override
  State<PlaceCreateScreen> createState() => _PlaceCreateScreenState();
}

class _PlaceCreateScreenState extends State<PlaceCreateScreen> {
  final TextEditingController _title = TextEditingController();
  XFile? _photo;
  XFile? _cover;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String t = _title.text.trim();
    if (t.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      String? photoUrl;
      String? coverUrl;
      if (_photo != null) {
        photoUrl = await PlaceService.uploadPlaceImage(_photo!);
      }
      if (_cover != null) {
        coverUrl = await PlaceService.uploadPlaceImage(_cover!);
      }
      await PlaceService.createPlace(
        title: t,
        photoUrl: photoUrl,
        coverUrl: coverUrl,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Заведение создано')),
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

  Future<void> _pick(bool cover) async {
    final ImagePicker p = ImagePicker();
    final XFile? f = await p.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 88,
    );
    if (f != null) {
      setState(() {
        if (cover) {
          _cover = f;
        } else {
          _photo = f;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SoftTabHeader(
            leading: SoftHeaderBackButton(),
            title: 'Новое заведение',
            trailing: SoftHeaderWeatherWithAction(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(
                    labelText: 'Название',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Обложка'),
                  subtitle: const Text('широкое фото шапки'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _saving ? null : () => _pick(true),
                ),
                if (_cover != null && !kIsWeb)
                  Image.file(
                    File(_cover!.path),
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                const SizedBox(height: 8),
                ListTile(
                  title: const Text('Аватар / логотип'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _saving ? null : () => _pick(false),
                ),
                if (_photo != null && !kIsWeb)
                  Image.file(File(_photo!.path), height: 100, fit: BoxFit.cover),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: kPrimaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Создать'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
