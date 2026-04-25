import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_ready.dart';

const Color _kText = Color(0xFF1A1A1A);

String normalizeRussianPhoneToE164(String raw) {
  final d = StringBuffer();
  for (int i = 0; i < raw.length; i++) {
    final c = raw[i];
    if (c.contains(RegExp(r'[0-9]'))) {
      d.write(c);
    }
  }
  var s = d.toString();
  if (s.startsWith('8') && s.length == 11) {
    s = '7${s.substring(1)}';
  } else if (s.startsWith('9') && s.length == 10) {
    s = '7$s';
  } else if (!s.startsWith('7') && s.length >= 9) {
    s = '7$s';
  }
  if (s.isEmpty) {
    return raw;
  }
  return '+$s';
}

class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _sendingOtp = false;
  bool _verifying = false;
  String? _error;
  bool _codeSent = false;
  String? _phoneE164;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    setState(() {
      _error = null;
      _sendingOtp = true;
    });
    var phone = normalizeRussianPhoneToE164(_phoneController.text.trim());
    if (!phone.startsWith('+')) {
      phone = '+$phone';
    }
    if (phone.length < 12) {
      setState(() {
        _error = 'Введите номер в формате 9XX XXX-XX-XX';
        _sendingOtp = false;
      });
      return;
    }
    _phoneE164 = phone;
    try {
      if (!supabaseAppReady) {
        throw StateError('Supabase не инициализирован. Проверьте kSupabaseUrl / ключ.');
      }
      final client = Supabase.instance.client;
      await client.auth.signInWithOtp(phone: phone);
      if (mounted) {
        setState(() {
          _codeSent = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Код отправлен. Введите SMS на этот номер.')),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
        });
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _error = 'Не удалось отправить SMS. Проверьте номер и настройки Supabase (Phone).';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _sendingOtp = false);
      }
    }
  }

  Future<void> _verifyOtp() async {
    final phone = _phoneE164 ?? normalizeRussianPhoneToE164(_phoneController.text.trim());
    if (!phone.startsWith('+')) {
      return;
    }
    final code = _codeController.text.replaceAll(' ', '');
    if (code.length < 4) {
      setState(() => _error = 'Введите код из SMS');
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
        phone: phone,
        token: code,
        type: OtpType.sms,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Вы вошли в аккаунт')),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _error = 'Код неверный или устарел';
        });
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
      appBar: AppBar(
        title: const Text('Вход'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          const Text(
            'Войдите по номеру телефона, чтобы публиковать новости и менять расписание парома. '
            'В панели Supabase включите SMS-провайдера и RLS, как в supabase/001_init.sql',
            style: TextStyle(color: _kText, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _phoneController,
            enabled: !_codeSent,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Телефон',
              hintText: '+7 9XX XXX-XX-XX',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) {
              if (!_codeSent) {
                _sendOtp();
              }
            },
          ),
          if (!_codeSent) ...<Widget>[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _sendingOtp ? null : _sendOtp,
              child: _sendingOtp
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Получить SMS-код'),
            ),
          ],
          if (_codeSent) ...<Widget>[
            const SizedBox(height: 16),
            const Text('Код из SMS', style: TextStyle(color: _kText)),
            const SizedBox(height: 8),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Код',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _verifying ? null : _verifyOtp,
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
            TextButton(
              onPressed: _sendingOtp
                  ? null
                  : () {
                      setState(() {
                        _codeSent = false;
                        _codeController.clear();
                        _error = null;
                      });
                    },
              child: const Text('Изменить номер'),
            ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Color(0xFFC62828), fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}
