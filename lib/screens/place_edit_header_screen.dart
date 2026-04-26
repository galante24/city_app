import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_constants.dart';
import '../services/place_service.dart';
import '../utils/image_cache_extent.dart';
import '../widgets/soft_tab_header.dart';
import '../widgets/weather_app_bar_action.dart';

class PlaceEditHeaderScreen extends StatefulWidget {
  const PlaceEditHeaderScreen({
    super.key,
    required this.placeId,
    required this.initialTitle,
    this.initialPhotoUrl,
    this.initialCoverUrl,
  });

  final String placeId;
  final String initialTitle;
  final String? initialPhotoUrl;
  final String? initialCoverUrl;

  @override
  State<PlaceEditHeaderScreen> createState() => _PlaceEditHeaderScreenState();
}

class _PlaceEditHeaderScreenState extends State<PlaceEditHeaderScreen> {
  late final TextEditingController _title =
      TextEditingController(text: widget.initialTitle);
  XFile? _photo;
  XFile? _cover;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String t = _title.text.trim();
    if (t.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Название обязательно')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final Map<String, dynamic> patch = <String, dynamic>{'title': t};
      if (_photo != null) {
        patch['photo_url'] = await PlaceService.uploadPlaceImage(_photo!);
      }
      if (_cover != null) {
        patch['cover_url'] = await PlaceService.uploadPlaceImage(_cover!);
      }
      await PlaceService.updatePlace(widget.placeId, patch);
      if (mounted) {
        Navigator.of(context).pop(true);
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
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SoftTabHeader(
            leading: SoftHeaderBackButton(),
            title: 'Шапка заведения',
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
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Новая обложка'),
                  onTap: _saving ? null : () => _pick(true),
                ),
                if (_cover != null && !kIsWeb)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.file(
                        File(_cover!.path),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                  )
                else if (widget.initialCoverUrl != null &&
                    widget.initialCoverUrl!.isNotEmpty &&
                    _cover == null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints bc) {
                          final double w = bc.maxWidth;
                          final double h = w * 9 / 16;
                          return Image.network(
                            widget.initialCoverUrl!,
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            width: w,
                            height: h,
                            cacheWidth: imageCacheExtentPx(context, w),
                            cacheHeight: imageCacheExtentPx(context, h),
                            loadingBuilder: (
                              BuildContext context,
                              Widget child,
                              ImageChunkEvent? progress,
                            ) {
                              if (progress == null) {
                                return child;
                              }
                              return ColoredBox(
                                color: cs.surfaceContainerHighest,
                                child: const Center(
                                  child: SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              );
                            },
                            errorBuilder:
                                (BuildContext c, Object e, StackTrace? st) =>
                                    ColoredBox(
                              color: kPrimaryBlue.withValues(alpha: 0.12),
                              child: const Center(
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  color: kPrimaryBlue,
                                  size: 40,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ListTile(
                  title: const Text('Новый логотип'),
                  onTap: _saving ? null : () => _pick(false),
                ),
                if (_photo != null && !kIsWeb)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: 100,
                      height: 100,
                      child: Image.file(
                        File(_photo!.path),
                        fit: BoxFit.cover,
                        width: 100,
                        height: 100,
                      ),
                    ),
                  )
                else if (widget.initialPhotoUrl != null &&
                    widget.initialPhotoUrl!.isNotEmpty &&
                    _photo == null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: 100,
                      height: 100,
                      child: Image.network(
                        widget.initialPhotoUrl!,
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        width: 100,
                        height: 100,
                        cacheWidth: imageCacheExtentPx(context, 100),
                        cacheHeight: imageCacheExtentPx(context, 100),
                        loadingBuilder: (
                          BuildContext context,
                          Widget child,
                          ImageChunkEvent? progress,
                        ) {
                          if (progress == null) {
                            return child;
                          }
                          return ColoredBox(
                            color: cs.surfaceContainerHighest,
                            child: const Center(
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          );
                        },
                        errorBuilder:
                            (BuildContext c, Object e, StackTrace? st) =>
                                ColoredBox(
                          color: kPrimaryBlue.withValues(alpha: 0.12),
                          child: const Center(
                            child: Icon(
                              Icons.store_rounded,
                              color: kPrimaryBlue,
                              size: 40,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
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
                      : const Text('Сохранить'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
