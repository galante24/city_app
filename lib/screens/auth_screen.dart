import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_ready.dart';

const Color kAuthScaffoldFill = Color(0xFF74B9FF);

/// Картинка [fitWidth] + подложка [kAuthScaffoldFill]; карточка внизу.
/// Вход: [signInWithPassword] / регистрация: [signUp] с [first_name].
const Color kAuthGreen = Color(0xFF0B723E);
const Color kAuthVkBlue = Color(0xFF2787F5);

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegister = false;
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
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
    final client = Supabase.instance.client;
    final String email = _loginController.text.trim();
    final String password = _passwordController.text;
    try {
      await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
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

  Future<void> _signUp() async {
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
    final client = Supabase.instance.client;
    try {
      final AuthResponse r = await client.auth.signUp(
        email: _loginController.text.trim(),
        password: _passwordController.text,
        data: <String, dynamic>{'first_name': _nameController.text.trim()},
      );
      if (mounted) {
        if (r.session == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Аккаунт создан. Подтвердите email, если требуется, затем войдите.',
              ),
            ),
          );
        }
        _nameController.clear();
        _passwordController.clear();
        setState(() {
          _isRegister = false;
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
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
    final String email = _loginController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Введите email в поле «Логин»'),
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
          SnackBar(content: Text(e.message)),
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
              'VK: $e. Включите провайдер в Supabase (Auth) и настройте redirect URL.',
            ),
          ),
        );
      }
    }
  }

  InputDecoration _fieldDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFF2F2F7),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kAuthGreen, width: 1.2),
      ),
      prefixIcon: Icon(icon, color: const Color(0xFF6C6C70)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double bottomPad = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      backgroundColor: kAuthScaffoldFill,
      resizeToAvoidBottomInset: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: ColoredBox(
              color: kAuthScaffoldFill,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                fit: StackFit.expand,
                children: <Widget>[
                  Align(
                    alignment: Alignment.topCenter,
                    child: Image.asset(
                      'assets/images/auth_bg.jpg',
                      fit: BoxFit.fitWidth,
                      width: double.infinity,
                      alignment: Alignment.topCenter,
                      errorBuilder:
                          (BuildContext c, Object e, StackTrace? st) {
                        return ColoredBox(
                          color: kAuthScaffoldFill,
                          child: const Center(
                            child: Icon(
                              Icons.landscape_outlined,
                              size: 64,
                              color: Color(0xFF5FA8E6),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: Material(
                color: Colors.white,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.55,
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 12 + bottomPad),
                    child: Form(
                      key: _formKey,
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                Center(
                                  child: SegmentedButton<bool>(
                                    showSelectedIcon: false,
                                    segments: const <ButtonSegment<bool>>[
                                      ButtonSegment<bool>(
                                        value: false,
                                        label: Text('Вход'),
                                        icon: Icon(Icons.login, size: 18),
                                      ),
                                      ButtonSegment<bool>(
                                        value: true,
                                        label: Text('Регистрация'),
                                        icon: Icon(
                                          Icons.person_add_outlined,
                                          size: 18,
                                        ),
                                      ),
                                    ],
                                    style: ButtonStyle(
                                      backgroundColor:
                                          WidgetStateProperty.resolveWith((
                                        Set<WidgetState> states,
                                      ) {
                                        if (states
                                            .contains(WidgetState.selected)) {
                                          return kAuthGreen;
                                        }
                                        return const Color(0xFFF2F2F7);
                                      }),
                                      foregroundColor:
                                          WidgetStateProperty.resolveWith((
                                        Set<WidgetState> states,
                                      ) {
                                        if (states
                                            .contains(WidgetState.selected)) {
                                          return Colors.white;
                                        }
                                        return kAuthGreen;
                                      }),
                                    ),
                                    selected: <bool>{_isRegister},
                                    onSelectionChanged: (Set<bool> s) {
                                      setState(() {
                                        _isRegister = s.first;
                                        _error = null;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _isRegister
                                      ? 'Новый аккаунт'
                                      : 'Вход в аккаунт',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1C1C1E),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (_isRegister) ...<Widget>[
                                  TextFormField(
                                    controller: _nameController,
                                    textInputAction: TextInputAction.next,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    decoration: _fieldDecoration(
                                      'Имя',
                                      Icons.badge_outlined,
                                    ),
                                    validator: (String? v) {
                                      if (!_isRegister) {
                                        return null;
                                      }
                                      if (v == null || v.trim().isEmpty) {
                                        return 'Введите имя';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                TextFormField(
                                  controller: _loginController,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autocorrect: false,
                                  autofillHints: const <String>[
                                    AutofillHints.email,
                                  ],
                                  decoration: _fieldDecoration(
                                    'Логин',
                                    Icons.person_outline,
                                  ),
                                  validator: (String? v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Введите логин (email)';
                                    }
                                    if (!v.contains('@')) {
                                      return 'Укажите email';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 10),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  autofillHints: const <String>[
                                    AutofillHints.password,
                                  ],
                                  decoration: _fieldDecoration(
                                    'Пароль',
                                    Icons.lock_outline,
                                  ).copyWith(
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                    ),
                                  ),
                                  validator: (String? v) {
                                    if (v == null || v.isEmpty) {
                                      return 'Введите пароль';
                                    }
                                    if (v.length < 6) {
                                      return 'Минимум 6 символов';
                                    }
                                    return null;
                                  },
                                ),
                                if (_error != null) ...<Widget>[
                                  const SizedBox(height: 8),
                                  Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: Color(0xFFC62828),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                                if (!_isRegister) ...<Widget>[
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: _forgotPassword,
                                      child: const Text(
                                        'Забыли пароль?',
                                        style: TextStyle(
                                          color: kAuthGreen,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ] else
                                  const SizedBox(height: 4),
                                const SizedBox(height: 4),
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
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
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
                                if (!_isRegister) ...<Widget>[
                                  const SizedBox(height: 10),
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
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
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
                                const SizedBox(height: 4),
                              ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
