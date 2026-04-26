import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../app_constants.dart';
import '../models/real_estate_listing_kind.dart';
import '../services/real_estate_listing_service.dart';
import '../utils/capitalize_first_formatter.dart';
import '../widgets/soft_tab_header.dart';
import '../widgets/weather_app_bar_action.dart';

String _postgrestTechnicalLine(PostgrestException e) {
  final StringBuffer b = StringBuffer();
  b.write('code=${e.code}');
  if (e.message.isNotEmpty) {
    b.write(' · ${e.message}');
  }
  final String? d = e.details?.toString();
  if (d != null && d.isNotEmpty && d != e.message) {
    b.write(' · $d');
  }
  if (e.hint != null && e.hint!.isNotEmpty) {
    b.write(' · hint: ${e.hint}');
  }
  String s = b.toString();
  const int maxLen = 500;
  if (s.length > maxLen) {
    s = '${s.substring(0, maxLen)}…';
  }
  return s;
}

class RealEstateCategoryFormScreen extends StatefulWidget {
  const RealEstateCategoryFormScreen({super.key, required this.kind});

  final RealEstateListingKind kind;

  @override
  State<RealEstateCategoryFormScreen> createState() =>
      _RealEstateCategoryFormScreenState();
}

class _RealEstateCategoryFormScreenState
    extends State<RealEstateCategoryFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _price = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _phone = TextEditingController(text: '+7');

  XFile? _picked;
  bool _saving = false;

  static const double _fieldRadius = 14;

  InputDecoration _decoration(
    BuildContext context,
    String label, {
    String? hint,
  }) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color outline = cs.outline.withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.4 : 0.35,
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: cs.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: const BorderSide(color: kPrimaryBlue, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: const BorderSide(color: Color(0xFFE53935)),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _phone.addListener(_syncPhone);
  }

  @override
  void dispose() {
    _phone.removeListener(_syncPhone);
    _title.dispose();
    _description.dispose();
    _price.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _syncPhone() {
    const String prefix = '+7';
    String v = _phone.text;
    if (!v.startsWith(prefix)) {
      _phone.value = const TextEditingValue(
        text: prefix,
        selection: TextSelection.collapsed(offset: prefix.length),
      );
      return;
    }
    final String tail = v.substring(2).replaceAll(RegExp(r'\D'), '');
    final String clipped = tail.length > 10 ? tail.substring(0, 10) : tail;
    final String next = '$prefix$clipped';
    if (next != v) {
      _phone.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }
  }

  String? _req(String? v) {
    if (v == null || v.trim().isEmpty) {
      return 'Обязательное поле';
    }
    return null;
  }

  String? _phoneValidator(String? v) {
    if (v == null || v.trim().isEmpty) {
      return 'Укажите телефон';
    }
    if (!RegExp(r'^\+7\d{10}$').hasMatch(v.trim())) {
      return 'Номер: +7 и 10 цифр';
    }
    return null;
  }

  Future<void> _pickImage() async {
    final ImagePicker p = ImagePicker();
    final XFile? f = await p.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 88,
    );
    if (f != null) {
      setState(() => _picked = f);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _saving = true);
    try {
      String? imageUrl;
      if (_picked != null) {
        try {
          imageUrl =
              await RealEstateListingService.uploadImage(widget.kind, _picked!);
        } on Object {
          // публикуем без фото
        }
      }
      await RealEstateListingService.insert(
        widget.kind,
        title: _title.text,
        description: _description.text,
        price: _price.text,
        propertyAddress: _address.text,
        contactPhone: _phone.text.trim(),
        imageUrl: imageUrl,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Объявление опубликовано')),
        );
      }
    } on PostgrestException catch (e) {
      if (!mounted) {
        return;
      }
      final String technical = _postgrestTechnicalLine(e);
      if (kDebugMode) {
        debugPrint(
          '[RealEstateForm ${widget.kind.tableName}] PostgrestException\n'
          '  code: ${e.code}\n'
          '  message: ${e.message}\n',
        );
      }
      final bool tableMissing = e.code == 'PGRST205' &&
          (e.message.contains(widget.kind.tableName) ||
              e.message.contains('schema cache'));
      final String text = tableMissing
          ? 'Сервер: не найдена таблица ${widget.kind.tableName}. Выполните миграцию supabase/migrations/022_estate_categories_listings.sql (supabase db push).'
          : technical;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Не удалось опубликовать. $text',
            style: const TextStyle(fontSize: 14, height: 1.25),
          ),
          duration: const Duration(seconds: 10),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            duration: const Duration(seconds: 8),
            behavior: SnackBarBehavior.floating,
          ),
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
    final Color frameOutline = cs.outline.withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.45 : 0.35,
    );
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SoftTabHeader(
            leading: SoftHeaderBackButton(),
            title: 'Новое объявление',
            trailing: SoftHeaderWeatherWithAction(),
          ),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                children: <Widget>[
                  Text(
                    'Категория: ${widget.kind.listTitle}. Фото — по желанию.',
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Фотография',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Material(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    child: InkWell(
                      onTap: _saving ? null : _pickImage,
                      child: Container(
                        width: double.infinity,
                        height: 160,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: frameOutline),
                        ),
                        child: _previewBlock(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _title,
                    decoration: _decoration(context, 'Тема'),
                    minLines: 1,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.none,
                    inputFormatters: <TextInputFormatter>[
                      CapitalizeFirstFormatter(),
                    ],
                    validator: _req,
                    enabled: !_saving,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _description,
                    decoration: _decoration(context, 'Описание'),
                    minLines: 4,
                    maxLines: 10,
                    validator: _req,
                    enabled: !_saving,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _price,
                    decoration: _decoration(
                      context,
                      'Цена',
                      hint: 'только цифры',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    validator: _req,
                    enabled: !_saving,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _address,
                    decoration: _decoration(
                      context,
                      widget.kind.addressFieldLabel,
                    ),
                    minLines: 1,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    validator: _req,
                    enabled: !_saving,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[+\d]*')),
                      LengthLimitingTextInputFormatter(12),
                    ],
                    decoration: _decoration(
                      context,
                      'Номер телефона',
                      hint: '+7 и 10 цифр',
                    ),
                    validator: _phoneValidator,
                    enabled: !_saving,
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: kPrimaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
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
                        : const Text(
                            'Опубликовать',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewBlock() {
    final XFile? f = _picked;
    if (f == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kPrimaryBlue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.add_photo_alternate_rounded,
              size: 40,
              color: kPrimaryBlue,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Нажмите, чтобы выбрать фото',
            style: TextStyle(
              color: kPrimaryBlue,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Необязательно',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      );
    }
    if (kIsWeb) {
      return FutureBuilder<Uint8List>(
        future: f.readAsBytes(),
        builder: (BuildContext c, AsyncSnapshot<Uint8List> s) {
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Image.memory(
            s.data!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: 160,
          );
        },
      );
    }
    return Image.file(
      File(f.path),
      fit: BoxFit.cover,
      width: double.infinity,
      height: 160,
    );
  }
}
