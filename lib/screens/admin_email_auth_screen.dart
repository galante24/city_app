import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/admin_config.dart';
import '../config/supabase_ready.dart';

/// Вход по email + OTP (код из письма). Нужен для `kAdministratorEmail`, чтобы в JWT был email.
class AdminEmailAuthScreen extends StatefulWidget {
  const AdminEmailAuthScreen({super.key});

  @override
  State<AdminEmailAuthScreen> createState() => _AdminEmailAuthScreenState();
}

class _AdminEmailAuthScreenState extends State<AdminEmailAuthScreen> {
  final _emailController = TextEditingController(text: kAdministratorEmail);
  final _codeController = TextEditingController();
  bool _sending = false;
  bool _verifying = false;
  String? _error;
  bool _codeSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty) {
      setState(() => _error = 'Введите email');
      return;
    }
    setState(() {
      _error = null;
      _sending = true;
    });
    try {
      if (!supabaseAppReady) {
        throw StateError('Supabase не инициализирован');
      }
      await Supabase.instance.client.auth.signInWithOtp(
        email: email,
        shouldCreateUser: true,
      );
      if (mounted) {
        setState(() => _codeSent = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Проверьте почту и введите код из письма.'),
          ),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _verify() async {
    final email = _emailController.text.trim().toLowerCase();
    final code = _codeController.text.replaceAll(RegExp(r'\s'), '');
    if (code.length < 4) {
      setState(() => _error = 'Введите код из письма');
      return;
    }
    setState(() {
      _error = null;
      _verifying = true;
    });
    try {
      if (!supabaseAppReady) {
        throw StateError('Supabase не инициализирован');
      }
      await Supabase.instance.client.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.email,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Вход выполнен')));
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } on Exception {
      if (mounted) {
        setState(() => _error = 'Код неверный или устарел');
      }
    } finally {
      if (mounted) {
        setState(() => _verifying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход администратора (email)')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          const Text(
            'Войдите под email администратора, чтобы видеть кнопки управления и публиковать новости. '
            'В Supabase Auth включите провайдер Email (OTP).',
            style: TextStyle(fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _emailController,
            enabled: !_codeSent,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
          ),
          if (!_codeSent) ...<Widget>[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _sending ? null : _sendOtp,
              child: _sending
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Получить код на почту'),
            ),
          ],
          if (_codeSent) ...<Widget>[
            const SizedBox(height: 16),
            const Text('Код из письма'),
            const SizedBox(height: 8),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '6 цифр',
              ),
              onSubmitted: (_) => _verify(),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _verifying ? null : _verify,
              child: _verifying
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Войти'),
            ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Color(0xFFC62828))),
          ],
        ],
      ),
    );
  }
}
