import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_ready.dart';

/// Админ-почта в приложении: sranometrr@gmail.com (JWT / RLS).
const Color kAuthGreen = Color(0xFF0B723E);
const Color kAuthVkBrand = Color(0xFF2787F5);
const Color kAuthFieldBorder = Color(0xFFD1D1D6);
const Color kAuthTitle = Color(0xFF1C1C1E);

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
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _loginController.text.trim(),
        password: _passwordController.text,
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
    try {
      final AuthResponse r = await Supabase.instance.client.auth.signUp(
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
        setState(() => _isRegister = false);
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
          const SnackBar(content: Text('Введите email в поле «Логин»')),
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
              'VK: $e. Настройте провайдер в Supabase (Auth) и redirect URL.',
            ),
          ),
        );
      }
    }
  }

  InputDecoration _inputDecoration(String label, {Widget? suffix}) {
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: kAuthGreen, width: 1.2),
      ),
      errorBorder: border.copyWith(
        borderSide: const BorderSide(color: Color(0xFFC62828)),
      ),
      prefixIcon: _FieldGlyph(
        child: _LoginGlyph(label: label),
      ),
      suffixIcon: suffix,
    );
  }

  @override
  Widget build(BuildContext context) {
    final double bottomPad = MediaQuery.viewInsetsOf(context).bottom;
    final double maxCardH = MediaQuery.sizeOf(context).height * 0.55;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned.fill(
            child: Image.asset(
              'assets/images/auth_bg.jpg',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (BuildContext c, Object e, StackTrace? st) {
                return const ColoredBox(color: Color(0xFF4A7BA7));
              },
            ),
          ),
          SafeArea(
            top: false,
            bottom: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxCardH),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                    child: Container(
                      width: double.infinity,
                      color: Colors.white,
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(24, 22, 24, 16 + bottomPad),
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
                              const SizedBox(height: 20),
                              if (_isRegister) ...<Widget>[
                                TextFormField(
                                  controller: _nameController,
                                  textInputAction: TextInputAction.next,
                                  textCapitalization: TextCapitalization.words,
                                  decoration: _inputDecoration('Имя'),
                                  validator: (String? v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Введите имя';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                              ],
                              TextFormField(
                                controller: _loginController,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                autofillHints: const <String>[
                                  AutofillHints.email,
                                ],
                                decoration: _inputDecoration('Логин'),
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
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                autofillHints: const <String>[
                                  AutofillHints.password,
                                ],
                                decoration: _inputDecoration(
                                  'Пароль',
                                  suffix: IconButton(
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                    style: IconButton.styleFrom(
                                      foregroundColor: const Color(0xFF8E8E93),
                                    ),
                                    icon: _EyeGlyph(
                                      open: _obscurePassword,
                                    ),
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
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFC62828),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
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
                              const SizedBox(height: 10),
                              if (!_isRegister)
                                OutlinedButton(
                                  onPressed: _loading
                                      ? null
                                      : () {
                                          setState(() {
                                            _isRegister = true;
                                            _error = null;
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
                                      borderRadius: BorderRadius.circular(12),
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
                                const SizedBox(height: 4),
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
                                const SizedBox(height: 8),
                                OutlinedButton(
                                  onPressed: _loading
                                      ? null
                                      : _signInWithVk,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: kAuthTitle,
                                    side: const BorderSide(
                                      color: kAuthFieldBorder,
                                    ),
                                    backgroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                      horizontal: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: <Widget>[
                                      _VkMark(),
                                      const SizedBox(width: 10),
                                      const Text(
                                        'Вход по VK ID',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
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
            ),
          ),
        ],
      ),
    );
  }
}

/// Узкая колонка слева: без [Icons] из Material — только кастомная графика полей.
class _FieldGlyph extends StatelessWidget {
  const _FieldGlyph({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 8),
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

class _LoginGlyph extends StatelessWidget {
  const _LoginGlyph({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    if (label == 'Пароль') {
      return CustomPaint(
        size: const Size(22, 22),
        painter: _LockPainter(),
      );
    }
    return CustomPaint(
      size: const Size(22, 22),
      painter: _PersonPainter(),
    );
  }
}

class _PersonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = const Color(0xFF8E8E93)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final double w = size.width;
    final double h = size.height;
    final Offset c = Offset(w / 2, h * 0.38);
    canvas.drawCircle(c, w * 0.18, p);
    final Path path = Path()
      ..moveTo(w * 0.2, h * 0.92)
      ..quadraticBezierTo(
        w * 0.2,
        h * 0.55,
        w / 2,
        h * 0.55,
      )
      ..quadraticBezierTo(
        w * 0.8,
        h * 0.55,
        w * 0.8,
        h * 0.92,
      );
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LockPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = const Color(0xFF8E8E93)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final double w = size.width;
    final double h = size.height;
    final Rect ar = Rect.fromLTWH(
      w * 0.22,
      h * 0.08,
      w * 0.56,
      h * 0.4,
    );
    canvas.drawArc(ar, -pi, pi, false, p);
    canvas.drawRect(
      Rect.fromLTWH(w * 0.22, h * 0.46, w * 0.56, h * 0.46),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EyeGlyph extends StatelessWidget {
  const _EyeGlyph({required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(22, 22),
      painter: _EyePainter(slash: open),
    );
  }
}

class _EyePainter extends CustomPainter {
  _EyePainter({required this.slash});

  final bool slash;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = const Color(0xFF8E8E93)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final double w = size.width;
    final double h = size.height;
    final Path eye = Path()
      ..moveTo(w * 0.1, h * 0.5)
      ..quadraticBezierTo(w * 0.5, h * 0.1, w * 0.9, h * 0.5)
      ..quadraticBezierTo(w * 0.5, h * 0.9, w * 0.1, h * 0.5);
    canvas.drawPath(eye, p);
    canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.12, p);
    if (slash) {
      canvas.drawLine(
        Offset(w * 0.2, h * 0.8),
        Offset(w * 0.8, h * 0.2),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EyePainter oldDelegate) =>
      oldDelegate.slash != slash;
}

class _VkMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: kAuthVkBrand,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'В',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 14,
          height: 1,
        ),
      ),
    );
  }
}
