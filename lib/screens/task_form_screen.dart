import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../app_card_styles.dart';
import '../app_constants.dart';
import '../services/task_service.dart';
import '../utils/capitalize_first_formatter.dart';
import '../widgets/soft_tab_header.dart';
import '../widgets/weather_app_bar_action.dart';

String _postgrestLine(PostgrestException e) {
  final StringBuffer b = StringBuffer('code=${e.code}');
  if (e.message.isNotEmpty) {
    b.write(' · ${e.message}');
  }
  return b.toString();
}

class TaskFormScreen extends StatefulWidget {
  const TaskFormScreen({super.key});

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _phone = TextEditingController(text: '+7');
  final TextEditingController _price = TextEditingController();

  bool _saving = false;
  static const double _radius = 16;

  InputDecoration _cloudFieldDecoration(
    BuildContext context,
    String label, {
    String? hint,
    Widget? prefixIcon,
    String? helperText,
    int? helperMaxLines,
  }) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      helperText: helperText,
      helperMaxLines: helperMaxLines,
      filled: true,
      fillColor: Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: const BorderSide(color: kPrimaryBlue, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: const BorderSide(color: Color(0xFFE53935)),
      ),
      labelStyle: TextStyle(color: cs.onSurfaceVariant),
    );
  }

  Widget _cloudField(BuildContext context, {required Widget child}) {
    return Container(
      decoration: cloudCardDecoration(context, radius: _radius),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: child,
    );
  }

  @override
  void initState() {
    super.initState();
    _phone.addListener(_syncPhoneOptional);
  }

  @override
  void dispose() {
    _phone.removeListener(_syncPhoneOptional);
    _title.dispose();
    _description.dispose();
    _phone.dispose();
    _price.dispose();
    super.dispose();
  }

  void _syncPhoneOptional() {
    String v = _phone.text;
    if (v.isEmpty) {
      return;
    }
    const String prefix = '+7';
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

  String? _phoneOptional(String? v) {
    final String t = v?.trim() ?? '';
    if (t.isEmpty || t == '+7') {
      return null;
    }
    if (!RegExp(r'^\+7\d{10}$').hasMatch(t)) {
      return 'Номер: +7 и 10 цифр или оставьте пустым';
    }
    return null;
  }

  String? _priceOptional(String? v) {
    final String t = v?.trim() ?? '';
    if (t.isEmpty) {
      return null;
    }
    if (int.tryParse(t) == null) {
      return 'Только целое число';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _saving = true);
    try {
      final String p = _phone.text.trim();
      final String pNorm = (p == '+7' || p.isEmpty) ? '' : p;
      final String pr = _price.text.trim();
      final double? priceVal =
          pr.isEmpty ? null : double.tryParse(pr);
      await TaskService.insert(
        title: _title.text,
        description: _description.text,
        phone: pNorm.isEmpty ? null : pNorm,
        price: priceVal,
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
      final bool missing = e.code == 'PGRST205' &&
          (e.message.contains('tasks') || e.message.contains('schema cache'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            missing
                ? 'Таблица tasks не найдена. Выполните миграции 026 и 031 (supabase db push). ${_postgrestLine(e)}'
                : _postgrestLine(e),
          ),
          duration: const Duration(seconds: 8),
        ),
      );
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
                    'Укажите суть задачи. Телефон можно не указывать — тогда отклик только в чате.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _cloudField(
                    context,
                    child: TextFormField(
                      controller: _title,
                      decoration: _cloudFieldDecoration(context, 'Заголовок'),
                      minLines: 1,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      inputFormatters: <TextInputFormatter>[
                        CapitalizeFirstFormatter(),
                      ],
                      validator: _req,
                      enabled: !_saving,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _cloudField(
                    context,
                    child: TextFormField(
                      controller: _description,
                      decoration: _cloudFieldDecoration(context, 'Описание'),
                      minLines: 4,
                      maxLines: 12,
                      validator: _req,
                      enabled: !_saving,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _cloudField(
                    context,
                    child: TextFormField(
                      controller: _price,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: _cloudFieldDecoration(
                        context,
                        'Сумма вознаграждения',
                        hint: 'Необязательно, ₽',
                        prefixIcon: Icon(
                          Icons.currency_ruble_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 22,
                        ),
                        helperText: 'Только цифры; можно оставить пустым',
                      ),
                      validator: _priceOptional,
                      enabled: !_saving,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _cloudField(
                    context,
                    child: TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(RegExp(r'[+\d]*')),
                        LengthLimitingTextInputFormatter(12),
                      ],
                      decoration: _cloudFieldDecoration(
                        context,
                        'Номер телефона',
                        hint: '+7XXXXXXXXXX',
                        prefixIcon: const Icon(Icons.phone_rounded, size: 22),
                        helperText:
                            'Необязательно: для кнопки «Позвонить» в объявлении',
                        helperMaxLines: 2,
                      ),
                      validator: _phoneOptional,
                      enabled: !_saving,
                    ),
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
}
