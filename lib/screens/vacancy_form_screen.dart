import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../app_constants.dart';
import '../services/job_vacancy_service.dart';

class VacancyFormScreen extends StatefulWidget {
  const VacancyFormScreen({super.key});

  @override
  State<VacancyFormScreen> createState() => _VacancyFormScreenState();
}

class _VacancyFormScreenState extends State<VacancyFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _salary = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _phone = TextEditingController(text: '+7');

  XFile? _picked;
  bool _saving = false;

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
    _salary.dispose();
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
        imageUrl = await JobVacancyService.uploadVacancyImage(_picked!);
      }
      await JobVacancyService.insert(
        title: _title.text,
        description: _description.text,
        salary: _salary.text,
        workAddress: _address.text,
        contactPhone: _phone.text.trim(),
        imageUrl: imageUrl,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Вакансия опубликована')),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white,
        title: const Text('Новая вакансия'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Column(
                  children: <Widget>[
                    Text(
                      'Фото (необязательно)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: _saving ? null : _pickImage,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.black12),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _preview(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: <Widget>[
                      TextFormField(
                        controller: _title,
                        decoration: const InputDecoration(
                          labelText: 'Название вакансии',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        maxLines: 2,
                        textCapitalization: TextCapitalization.sentences,
                        validator: _req,
                        enabled: !_saving,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'Описание вакансии',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
                filled: true,
                fillColor: Colors.white,
              ),
              maxLines: 5,
              validator: _req,
              enabled: !_saving,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _salary,
              decoration: const InputDecoration(
                labelText: 'Зарплата',
                border: OutlineInputBorder(),
                hintText: 'например, от 60 000 ₽',
                filled: true,
                fillColor: Colors.white,
              ),
              validator: _req,
              enabled: !_saving,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(
                labelText: 'Адрес работы',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              validator: _req,
              enabled: !_saving,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[+\d]*')),
                LengthLimitingTextInputFormatter(12),
              ],
              decoration: const InputDecoration(
                labelText: 'Контакты (телефон)',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
                hintText: '+7XXXXXXXXXX',
              ),
              validator: _phoneValidator,
              enabled: !_saving,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: kPrimaryBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
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
                  : const Text('Опубликовать'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    final XFile? f = _picked;
    if (f == null) {
      return ColoredBox(
        color: kPrimaryBlue.withValues(alpha: 0.08),
        child: const Center(
          child: Icon(Icons.add_photo_alternate_outlined, size: 40, color: kPrimaryBlue),
        ),
      );
    }
    if (kIsWeb) {
      return FutureBuilder<Uint8List>(
        future: f.readAsBytes(),
        builder: (BuildContext c, AsyncSnapshot<Uint8List> s) {
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Image.memory(s.data!, fit: BoxFit.cover, width: 100, height: 100);
        },
      );
    }
    return Image.file(
      File(f.path),
      fit: BoxFit.cover,
      width: 100,
      height: 100,
    );
  }
}
