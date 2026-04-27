import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_constants.dart';
import '../services/place_service.dart';
import '../widgets/city_network_image.dart';
import '../widgets/soft_tab_header.dart';
import '../widgets/weather_app_bar_action.dart';

num? _parseMoneyInput(String s) {
  final String t = s.replaceAll(' ', '').replaceAll(',', '.');
  if (t.isEmpty) {
    return null;
  }
  return num.tryParse(t);
}

/// Создание или редактирование позиции меню (модераторы / админ).
class PlaceMenuItemEditScreen extends StatefulWidget {
  const PlaceMenuItemEditScreen({
    super.key,
    required this.placeId,
    this.existing,
  });

  final String placeId;
  final Map<String, dynamic>? existing;

  bool get isEdit => existing != null;

  @override
  State<PlaceMenuItemEditScreen> createState() =>
      _PlaceMenuItemEditScreenState();
}

class _PlaceMenuItemEditScreenState extends State<PlaceMenuItemEditScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _category = TextEditingController();
  final TextEditingController _price = TextEditingController();
  final TextEditingController _oldPrice = TextEditingController();
  bool _available = true;
  XFile? _newPhoto;
  String? _existingPhotoUrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final Map<String, dynamic>? e = widget.existing;
    if (e != null) {
      _title.text = (e['title'] as String?) ?? '';
      _description.text = (e['description'] as String?) ?? '';
      _category.text = (e['category'] as String?) ?? '';
      final dynamic p = e['price'];
      if (p is num) {
        _price.text = p == p.roundToDouble() ? '${p.toInt()}' : '$p';
      }
      final dynamic op = e['old_price'];
      if (op != null && op is num) {
        _oldPrice.text = op == op.roundToDouble() ? '${op.toInt()}' : '$op';
      }
      _available = e['is_available'] != false;
      _existingPhotoUrl = (e['photo_url'] as String?)?.trim();
      if (_existingPhotoUrl != null && _existingPhotoUrl!.isEmpty) {
        _existingPhotoUrl = null;
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _category.dispose();
    _price.dispose();
    _oldPrice.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_saving) {
      return;
    }
    final XFile? f = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 88,
    );
    if (f != null) {
      setState(() => _newPhoto = f);
    }
  }

  Future<void> _save() async {
    final String title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите название')),
      );
      return;
    }
    final num? price = _parseMoneyInput(_price.text);
    if (price == null || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите цену (число)')),
      );
      return;
    }
    num? oldPrice = _parseMoneyInput(_oldPrice.text);
    if (oldPrice != null && oldPrice <= 0) {
      oldPrice = null;
    }
    setState(() => _saving = true);
    try {
      String? photoUrl = _existingPhotoUrl;
      if (_newPhoto != null) {
        photoUrl = await PlaceService.uploadMenuItemPhoto(_newPhoto!);
      }
      if (widget.isEdit) {
        final String id = widget.existing!['id']?.toString() ?? '';
        if (id.isEmpty) {
          throw StateError('Нет id');
        }
        await PlaceService.updateMenuItem(id, <String, dynamic>{
          'title': title,
          'description': _description.text.trim(),
          'category': _category.text.trim(),
          'price': price,
          'old_price': oldPrice,
          'photo_url': photoUrl,
          'is_available': _available,
        });
      } else {
        await PlaceService.insertMenuItem(
          placeId: widget.placeId,
          title: title,
          description: _description.text.trim(),
          category: _category.text.trim(),
          price: price,
          oldPrice: oldPrice,
          photoUrl: photoUrl,
          isAvailable: _available,
        );
      }
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isEdit ? 'Сохранено' : 'Позиция добавлена'),
          ),
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
          SoftTabHeader(
            leading: const SoftHeaderBackButton(),
            title: widget.isEdit ? 'Редактирование' : 'Новая позиция',
            trailing: const SoftHeaderWeatherWithAction(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Text(
                  'Фото',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                AspectRatio(
                  aspectRatio: 1,
                  child: Material(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _saving ? null : _pickPhoto,
                      child: _buildPhotoPreview(cs),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Название *',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _description,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Краткое описание',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _category,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Категория (например: Еда, Напитки)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _price,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Цена *',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(
                              Radius.circular(14),
                            ),
                          ),
                          suffixText: '₽',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _oldPrice,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Старая цена',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(
                              Radius.circular(14),
                            ),
                          ),
                          suffixText: '₽',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Если указать старую цену, в витрине появится скидка и ярлык «АКЦИЯ».',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('В наличии'),
                  value: _available,
                  activeThumbColor: kPrimaryBlue,
                  onChanged: _saving
                      ? null
                      : (bool v) {
                          setState(() => _available = v);
                        },
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: kPrimaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
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
                      : Text(
                          widget.isEdit ? 'Сохранить' : 'Добавить',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoPreview(ColorScheme cs) {
    if (_newPhoto != null) {
      if (kIsWeb) {
        return const Center(
          child: Icon(Icons.image_outlined, size: 48, color: kPrimaryBlue),
        );
      }
      return Image.file(
        File(_newPhoto!.path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }
    final String? url = _existingPhotoUrl;
    if (url != null && url.isNotEmpty) {
      return CityNetworkImage.fillParent(
        imageUrl: url,
        boxFit: BoxFit.cover,
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.add_photo_alternate_outlined, size: 44, color: cs.primary),
          const SizedBox(height: 8),
          Text(
            'Нажмите, чтобы выбрать фото',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
