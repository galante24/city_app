import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../app_constants.dart';
import '../services/job_vacancy_service.dart';
import '../widgets/soft_tab_header.dart';
import '../widgets/weather_app_bar_action.dart';
import '../utils/capitalize_first_formatter.dart';


/// Одна строка для SnackBar: код, сообщение, details, hint (без дублирования).
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

  static const double _fieldRadius = 14;

  InputDecoration _decoration(BuildContext context, String label, {String? hint}) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color outline = cs.outline.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.4 : 0.35);
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
        try {
          imageUrl = await JobVacancyService.uploadVacancyImage(_picked!);
        } on Object {
          // публикуем без фото, без всплывающих «ошибок» (любой авторизованный — без модерации)
        }
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Вакансия опубликована')));
      }
    } on PostgrestException catch (e) {
      if (!mounted) {
        return;
      }
      final String technical = _postgrestTechnicalLine(e);
      if (kDebugMode) {
        debugPrint(
          '[VacancyForm] PostgrestException\n'
          '  code: ${e.code}\n'
          '  message: ${e.message}\n'
          '  details: ${e.details}\n'
          '  hint: ${e.hint}',
        );
      }
      final bool tableMissing =
          e.code == 'PGRST205' &&
          (e.message.contains('job_vacancies') ||
              e.message.contains('schema cache'));
      final String text = tableMissing
          ? 'Сервер: не найдена таблица job_vacancies. В Supabase: SQL → вставьте supabase/migrations/014_job_vacancies.sql и выполните, либо в терминале: supabase link && supabase db push.'
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
        if (kDebugMode) {
          debugPrint('[VacancyForm] $e');
        }
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
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SoftTabHeader(
            leading: SoftHeaderBackButton(),
            title: 'Новая вакансия',
            trailing: SoftHeaderWeatherWithAction(),
          ),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                children: <Widget>[
            Text(
              'Заполните поля. Фото — по желанию.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[800],
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),
            Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              elevation: 0,
              shadowColor: Colors.transparent,
              child: InkWell(
                onTap: _saving ? null : _pickImage,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFDDDFE2)),
                  ),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _previewBlock(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _title,
              decoration: _decoration(context, 'Название вакансии'),
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.none,
              inputFormatters: <TextInputFormatter>[CapitalizeFirstFormatter()],
              validator: _req,
              enabled: !_saving,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _description,
              decoration: _decoration(context, 'Описание вакансии'),
              minLines: 4,
              maxLines: 10,
              validator: _req,
              enabled: !_saving,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _salary,
              decoration: _decoration(
                context,
                'Зарплата',
                hint: 'только цифры, напр. 60000',
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
              decoration: _decoration(context, 'Адрес работы'),
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
                'Контакты (телефон)',
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
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
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
            height: double.infinity,
          );
        },
      );
    }
    return Image.file(
      File(f.path),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }
}
