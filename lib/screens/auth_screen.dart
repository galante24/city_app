import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_ready.dart';

/// Фон, заголовок города, карточка входа. Вход: `signInWithPassword` (логин = email).
/// Администратор: sranometrr@gmail.com (права в приложении по email в сессии).
const Color kAuthGreen = Color(0xFF0B723E);
const Color kAuthVkBlue = Color(0xFF2787F5);

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
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
          const SnackBar(content: Text('Не удалось открыть окно входа ВКонтакте')),
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
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned.fill(
            child: Image.asset(
              'assets/images/auth_bg.jpg',
              fit: BoxFit.cover,
              errorBuilder: (BuildContext c, Object e, StackTrace? st) {
                return Container(
                  color: const Color(0xFF0B5C36),
                );
              },
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Column(
                    children: <Widget>[
                      const Icon(
                        Icons.location_city,
                        size: 80,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Лесосибирск',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'город в котором хочется жить!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: Material(
                  color: Colors.white,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, 24, 24, 20 + bottomPad),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const Text(
                            'Вход в аккаунт',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1C1C1E),
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _loginController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            autofillHints: const <String>[AutofillHints.email],
                            decoration: _fieldDecoration('Логин', Icons.person_outline),
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
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            autofillHints: const <String>[AutofillHints.password],
                            decoration: _fieldDecoration('Пароль', Icons.lock_outline)
                                .copyWith(
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
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: const TextStyle(
                                color: Color(0xFFC62828),
                                fontSize: 14,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
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
                          const SizedBox(height: 4),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _loading ? null : _signIn,
                              style: FilledButton.styleFrom(
                                backgroundColor: kAuthGreen,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
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
                                  : const Text(
                                      'Войти',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _loading
                                  ? null
                                  : () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (BuildContext c) {
                                            return const _RegisterScreen();
                                          },
                                        ),
                                      );
                                    },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: kAuthGreen,
                                side: const BorderSide(
                                  color: kAuthGreen,
                                  width: 1.4,
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                backgroundColor: Colors.transparent,
                              ),
                              child: const Text(
                                'Регистрация',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _loading ? null : _signInWithVk,
                              style: FilledButton.styleFrom(
                                backgroundColor: kAuthVkBlue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.messenger_outlined, size: 22),
                              label: const Text(
                                'Вход по VK ID',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Регистрация: email, пароль, имя — `signUp`, затем по необходимости подтверждение письмом.
class _RegisterScreen extends StatefulWidget {
  const _RegisterScreen();

  @override
  State<_RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<_RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  InputDecoration _dec(String l, IconData i) {
    return InputDecoration(
      labelText: l,
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
      prefixIcon: Icon(i, color: const Color(0xFF6C6C70)),
    );
  }

  Future<void> _submit() async {
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
        email: _emailController.text.trim(),
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
        Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Регистрация'),
        backgroundColor: kAuthGreen,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: _dec('Имя', Icons.badge_outlined),
              validator: (String? v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Введите имя';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: _dec('Email', Icons.email_outlined),
              validator: (String? v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Введите email';
                }
                if (!v.contains('@')) {
                  return 'Некорректный email';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscure,
              decoration: _dec('Пароль', Icons.lock_outline).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
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
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Color(0xFFC62828), fontSize: 14),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: kAuthGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
                  : const Text('Создать аккаунт', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
