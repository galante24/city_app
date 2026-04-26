import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_ready.dart';

/// Админ: sranometrr@gmail.com (роли в JWT / RLS).
///
/// Redirect из письма подтверждения (должен быть в Supabase Auth → URL Configuration).
/// Полный путь GitHub Pages, включая `/city_app/`, иначе возможен 404.
const String kAuthEmailRedirectTo = 'https://galante24.github.io/city_app/';

/// Минимальная длина пароля при регистрации (нужна для сочетания с правилами).
const int kRegisterPasswordMinLength = 6;

/// Хотя бы одна заглавная буква (латиница / кириллица).
final RegExp kRegisterPasswordHasUpper = RegExp(r'[A-ZЁА-Я]');

/// Хотя бы один символ из набора: !@#$%^&*
final RegExp kRegisterPasswordHasSpecial = RegExp(r'[!@#$%^&*]');

const Color kAuthGreen = Color(0xFF0B723E);
const Color kAuthVkBlue = Color(0xFF2787F5);
const Color kAuthFieldBorder = Color(0xFFD1D1D6);
const Color kAuthTitle = Color(0xFF1C1C1E);

/// Фон панели входа/регистрации: белый с лёгкой прозрачностью поверх фото.
const Color kAuthPanelBackground = Color(0xE0FFFFFF);

/// Сообщения GoTrue/Supabase на английском — показ пользователю по-русски.
String _ruAuthErrorMessage(String? message) {
  if (message == null || message.trim().isEmpty) {
    return 'Произошла ошибка. Повторите попытку.';
  }
  final String m = message.trim();
  final String l = m.toLowerCase();
  if (l.contains('invalid login credentials')) {
    return 'Неверный email или пароль';
  }
  if (l.contains('email not confirmed') || l.contains('email not verified')) {
    return 'Сначала подтвердите email по ссылке из письма';
  }
  if (l.contains('user already registered') || l.contains('already registered')) {
    return 'Этот email уже зарегистрирован. Войдите или сбросьте пароль';
  }
  if (l.contains('email rate limit') || l.contains('rate limit')) {
    return 'Слишком много писем или попыток. Подождите немного и повторите';
  }
  return m;
}

/// Первая буква слова (после пробела, дефиса, апострофа) — заглавная; остальные без насильного смена регистра.
class _CapitalizeNameWordStartsFormatter extends TextInputFormatter {
  const _CapitalizeNameWordStartsFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }
    final String t = newValue.text;
    final StringBuffer out = StringBuffer();
    bool capNext = true;
    for (int i = 0; i < t.length; i++) {
      final String ch = t[i];
      if (ch == ' ' || ch == '-' || ch == '\'') {
        out.write(ch);
        capNext = true;
        continue;
      }
      if (capNext) {
        out.write(ch.toUpperCase());
        capNext = false;
      } else {
        out.write(ch);
      }
    }
    final String result = out.toString();
    int offset = newValue.selection.end;
    if (offset < 0) {
      offset = 0;
    } else if (offset > result.length) {
      offset = result.length;
    }
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _passwordRepeatController = TextEditingController();

  /// Дата рождения (только при регистрации); уходит в user_metadata и затем в profiles.
  DateTime? _birthDate;

  bool _isRegister = false;
  bool _obscurePassword = true;
  bool _obscurePasswordRepeat = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _passwordRepeatController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(
    String label, {
    IconData? icon,
    Widget? suffix,
  }) {
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kAuthFieldBorder, width: 1),
    );
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: Color(0xFF8E8E93),
        fontWeight: FontWeight.w500,
      ),
      filled: true,
      fillColor: Colors.white,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: kAuthGreen, width: 1.2),
      ),
      errorBorder: border.copyWith(
        borderSide: const BorderSide(color: Color(0xFFC62828)),
      ),
      focusedErrorBorder: border.copyWith(
        borderSide: const BorderSide(color: Color(0xFFC62828)),
      ),
      prefixIcon: icon != null
          ? Icon(icon, color: const Color(0xFF8E8E93), size: 22)
          : null,
      suffixIcon: suffix,
    );
  }

  Future<void> _signIn() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (!supabaseAppReady) {
      setState(() => _error = 'Supabase не инициализирован');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _error = _ruAuthErrorMessage(e.message));
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Пароль при регистрации: длина [kRegisterPasswordMinLength], ≥1 заглавная, ≥1 спецсимвол (безопасность).
  bool _isPasswordValidForRegistration(String password) {
    if (password.length < kRegisterPasswordMinLength) {
      return false;
    }
    if (!kRegisterPasswordHasUpper.hasMatch(password)) {
      return false;
    }
    if (!kRegisterPasswordHasSpecial.hasMatch(password)) {
      return false;
    }
    return true;
  }

  Future<void> _signUp() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final String password = _passwordController.text;
    if (!_isPasswordValidForRegistration(password)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Пароль: минимум 6 символов, обязательно одна заглавная буква '
              'и минимум один спецсимвол (! @ # % ^ & * и т. п.)',
            ),
          ),
        );
      }
      return;
    }
    if (password != _passwordRepeatController.text) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Пароли не совпадают')),
        );
      }
      return;
    }
    if (_birthDate == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Укажите дату рождения')),
        );
      }
      return;
    }
    if (!supabaseAppReady) {
      setState(() => _error = 'Supabase не инициализирован');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final AuthResponse r = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        emailRedirectTo: kAuthEmailRedirectTo,
        data: <String, dynamic>{
          'first_name': _firstNameController.text.trim(),
          'last_name': _lastNameController.text.trim(),
          'birth_date': '${_birthDate!.year.toString().padLeft(4, '0')}-'
              '${_birthDate!.month.toString().padLeft(2, '0')}-'
              '${_birthDate!.day.toString().padLeft(2, '0')}',
        },
      );
      if (mounted) {
        // Если в Supabase выключено «Confirm email», с session не null — вход сразу.
        if (r.session == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Аккаунт создан. Подтвердите email, если в проекте включено '
                'подтверждение (Auth → Email), затем войдите.',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Регистрация прошла успешно, вы вошли в аккаунт.'),
            ),
          );
        }
        _firstNameController.clear();
        _lastNameController.clear();
        _passwordController.clear();
        _passwordRepeatController.clear();
        _emailController.clear();
        setState(() {
          _isRegister = false;
          _birthDate = null;
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _error = _ruAuthErrorMessage(e.message));
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _forgotPassword() async {
    final String email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Введите адрес в поле «Ваша почта»'),
          ),
        );
      }
      return;
    }
    if (!supabaseAppReady) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Supabase не инициализирован')),
        );
      }
      return;
    }
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Проверьте почту: ссылка для сброса пароля'),
          ),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_ruAuthErrorMessage(e.message))),
        );
      }
    }
  }

  Future<void> _signInWithVk() async {
    if (!supabaseAppReady) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Supabase не инициализирован')),
        );
      }
      return;
    }
    setState(() => _error = null);
    try {
      final bool ok = await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider('vk'),
        redirectTo: null,
      );
      if (mounted && !ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось открыть окно входа ВКонтакте'),
          ),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'VK: $e. Настройте провайдер в Supabase (Auth) и redirect URL.',
            ),
          ),
        );
      }
    }
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) {
      return 'Введите почту';
    }
    if (!v.contains('@')) {
      return 'Некорректный email';
    }
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) {
      return 'Введите пароль';
    }
    if (_isRegister) {
      if (v.length < kRegisterPasswordMinLength) {
        return 'Минимум $kRegisterPasswordMinLength символов';
      }
      if (!kRegisterPasswordHasUpper.hasMatch(v)) {
        return 'Нужна минимум одна заглавная буква';
      }
      if (!kRegisterPasswordHasSpecial.hasMatch(v)) {
        return 'Нужен минимум один спецсимвол (! @ # % ^ & * и т. п.)';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final double bottomPad = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned.fill(
            child: Image.asset(
              'assets/images/auth_bg.jpg',
              fit: BoxFit.contain,
              alignment: Alignment.center,
              errorBuilder: (BuildContext c, Object e, StackTrace? st) {
                return const ColoredBox(color: Color(0xFF4A7BA7));
              },
            ),
          ),
          SafeArea(
            top: false,
            bottom: false,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                final double maxCardH = (box.maxHeight * 0.7).clamp(220.0, 520.0);
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: Material(
                    color: Colors.transparent,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: box.maxWidth,
                        maxHeight: maxCardH,
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(30),
                        ),
                        child: ColoredBox(
                          color: kAuthPanelBackground,
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                              24,
                              20,
                              24,
                              20 + bottomPad,
                            ),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            child: Form(
                              key: _formKey,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  Text(
                                    _isRegister
                                        ? 'Регистрация'
                                        : 'Вход в аккаунт',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: kAuthTitle,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  if (_isRegister) ...<Widget>[
                                    TextFormField(
                                      controller: _firstNameController,
                                      textInputAction: TextInputAction.next,
                                      textCapitalization:
                                          TextCapitalization.none,
                                      inputFormatters: const <TextInputFormatter>[
                                        _CapitalizeNameWordStartsFormatter(),
                                      ],
                                      decoration: _fieldDecoration(
                                        'Имя',
                                        icon: Icons.badge_outlined,
                                      ),
                                      validator: (String? v) {
                                        if (v == null || v.trim().isEmpty) {
                                          return 'Введите имя';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 10),
                                    TextFormField(
                                      controller: _lastNameController,
                                      textInputAction: TextInputAction.next,
                                      textCapitalization:
                                          TextCapitalization.none,
                                      inputFormatters: const <TextInputFormatter>[
                                        _CapitalizeNameWordStartsFormatter(),
                                      ],
                                      decoration: _fieldDecoration(
                                        'Фамилия',
                                        icon: Icons.badge_outlined,
                                      ),
                                      validator: (String? v) {
                                        if (v == null || v.trim().isEmpty) {
                                          return 'Введите фамилию';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 10),
                                    Material(
                                      color: const Color(0xFFF2F2F7),
                                      borderRadius: BorderRadius.circular(10),
                                      child: InkWell(
                                        onTap: () async {
                                          final DateTime now = DateTime.now();
                                          final DateTime? d = await showDatePicker(
                                            context: context,
                                            initialDate: _birthDate ?? DateTime(now.year - 20, 1, 1),
                                            firstDate: DateTime(1920, 1, 1),
                                            lastDate: now,
                                          );
                                          if (d != null) {
                                            setState(() => _birthDate = d);
                                          }
                                        },
                                        borderRadius: BorderRadius.circular(10),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                          child: Row(
                                            children: <Widget>[
                                              const Icon(
                                                Icons.calendar_today_outlined,
                                                size: 20,
                                                color: Color(0xFF6C6C70),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  _birthDate == null
                                                      ? 'Дата рождения (обязательно)'
                                                      : '${_birthDate!.day.toString().padLeft(2, '0')}.'
                                                          '${_birthDate!.month.toString().padLeft(2, '0')}.'
                                                          '${_birthDate!.year}',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: _birthDate == null
                                                        ? const Color(0xFF8E8E93)
                                                        : kAuthTitle,
                                                    fontWeight: _birthDate == null ? FontWeight.w400 : FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                  TextFormField(
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    autocorrect: false,
                                    autofillHints: const <String>[
                                      AutofillHints.email,
                                    ],
                                    decoration: _fieldDecoration(
                                      'Ваша почта',
                                      icon: Icons.email_outlined,
                                    ),
                                    validator: _validateEmail,
                                  ),
                                  const SizedBox(height: 10),
                                  TextFormField(
                                    controller: _passwordController,
                                    obscureText: _obscurePassword,
                                    autofillHints: _isRegister
                                        ? const <String>[]
                                        : const <String>[
                                            AutofillHints.password,
                                          ],
                                    decoration: _fieldDecoration(
                                      'Пароль',
                                      icon: Icons.lock_outline,
                                      suffix: IconButton(
                                        onPressed: () {
                                          setState(() {
                                            _obscurePassword = !_obscurePassword;
                                          });
                                        },
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                        ),
                                        color: const Color(0xFF8E8E93),
                                      ),
                                    ),
                                    validator: _validatePassword,
                                  ),
                                  if (_isRegister) ...<Widget>[
                                    const SizedBox(height: 10),
                                    TextFormField(
                                      controller: _passwordRepeatController,
                                      obscureText: _obscurePasswordRepeat,
                                      decoration: _fieldDecoration(
                                        'Повторите пароль',
                                        icon: Icons.lock_outline,
                                        suffix: IconButton(
                                          onPressed: () {
                                            setState(() {
                                              _obscurePasswordRepeat =
                                                  !_obscurePasswordRepeat;
                                            });
                                          },
                                          icon: Icon(
                                            _obscurePasswordRepeat
                                                ? Icons.visibility_outlined
                                                : Icons
                                                    .visibility_off_outlined,
                                          ),
                                          color: const Color(0xFF8E8E93),
                                        ),
                                      ),
                                      validator: (String? v) {
                                        if (v == null || v.isEmpty) {
                                          return 'Повторите пароль';
                                        }
                                        return null;
                                      },
                                    ),
                                  ],
                                  if (_error != null) ...<Widget>[
                                    const SizedBox(height: 8),
                                    Text(
                                      _error!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xFFC62828),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      onPressed: _loading
                                          ? null
                                          : _isRegister
                                              ? _signUp
                                              : _signIn,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: kAuthGreen,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: _loading
                                          ? const SizedBox(
                                              height: 22,
                                              width: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : Text(
                                              _isRegister
                                                  ? 'Зарегистрироваться'
                                                  : 'Войти',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (!_isRegister)
                                    OutlinedButton(
                                      onPressed: _loading
                                          ? null
                                          : () {
                                              setState(() {
                                                _isRegister = true;
                                                _error = null;
                                                _passwordRepeatController
                                                    .clear();
                                              });
                                            },
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: kAuthGreen,
                                        side: const BorderSide(
                                          color: kAuthGreen,
                                          width: 1.2,
                                        ),
                                        backgroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: const Text(
                                        'Регистрация',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    )
                                  else
                                    TextButton(
                                      onPressed: _loading
                                          ? null
                                          : () {
                                              setState(() {
                                                _isRegister = false;
                                                _error = null;
                                                _passwordRepeatController
                                                    .clear();
                                              });
                                            },
                                      child: const Text(
                                        'Уже есть аккаунт? Войти',
                                        style: TextStyle(
                                          color: kAuthGreen,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  if (!_isRegister) ...<Widget>[
                                    const SizedBox(height: 2),
                                    Center(
                                      child: TextButton(
                                        onPressed: _forgotPassword,
                                        child: const Text(
                                          'Забыли пароль?',
                                          style: TextStyle(
                                            color: kAuthGreen,
                                            fontWeight: FontWeight.w500,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: _loading
                                            ? null
                                            : _signInWithVk,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: kAuthVkBlue,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          elevation: 0,
                                        ),
                                        icon: const Icon(
                                          Icons.messenger_outlined,
                                          size: 20,
                                        ),
                                        label: const Text(
                                          'Вход по VK ID',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
