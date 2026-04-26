import 'package:flutter/services.dart';

/// Телефон заведения: хранение в виде `+7` и 10 цифр (`+79131234567`).
class PlacePhone {
  PlacePhone._();

  static final RegExp _stored = RegExp(r'^\+7\d{10}$');

  /// 10 цифр после семёрки (национальная часть), для маски и валидации.
  static String tenDigitNationalFromAny(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return '';
    }
    String d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('8') && d.length >= 11) {
      d = '7${d.substring(1)}';
    }
    if (d.length > 11 && d.startsWith('7')) {
      d = d.substring(0, 11);
    }
    if (d.length == 11 && d.startsWith('7')) {
      return d.substring(1);
    }
    if (d.startsWith('7') && d.length > 1 && d.length < 11) {
      return d.substring(1);
    }
    if (d.length <= 10 && !d.startsWith('7')) {
      return d;
    }
    return '';
  }

  /// Маска: `+7 (XXX) XXX-XX-XX` (национальная часть до 10 цифр).
  static String maskTen(String tenDigits) {
    if (tenDigits.isEmpty) {
      return '+7 ';
    }
    final String t =
        tenDigits.length > 10 ? tenDigits.substring(0, 10) : tenDigits;
    final StringBuffer buf = StringBuffer('+7 (');
    buf.write(t.length >= 3 ? t.substring(0, 3) : t);
    buf.write(')');
    if (t.length > 3) {
      buf.write(' ');
      buf.write(t.length >= 6 ? t.substring(3, 6) : t.substring(3));
    }
    if (t.length > 6) {
      buf.write('-');
      buf.write(t.length >= 8 ? t.substring(6, 8) : t.substring(6));
    }
    if (t.length > 8) {
      buf.write('-');
      buf.write(t.substring(8));
    }
    return buf.toString();
  }

  static String formatDisplay(String? raw) {
    return maskTen(tenDigitNationalFromAny(raw));
  }

  /// `null` — неполный номер; `''` — очистить поле.
  static String? toStoredOrEmpty(String maskedOrDigits) {
    final String d = maskedOrDigits.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) {
      return '';
    }
    String full = d;
    if (full.startsWith('8') && full.length >= 11) {
      full = '7${full.substring(1)}';
    }
    if (full.length == 10) {
      full = '7$full';
    }
    if (full.length == 11 && full.startsWith('7')) {
      return '+$full';
    }
    return null;
  }

  static bool isCompleteStored(String? s) {
    final String? t = s?.trim();
    if (t == null || t.isEmpty) {
      return false;
    }
    return _stored.hasMatch(t);
  }

  static Uri? dialUri(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final String d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length == 11 && d.startsWith('7')) {
      return Uri.parse('tel:+$d');
    }
    if (d.length == 10) {
      return Uri.parse('tel:+7$d');
    }
    return null;
  }
}

/// Ввод только мобильного РФ: фиксированная маска `+7 (…) …-…-…`.
class RuPhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('8')) {
      digits = '7${digits.substring(1)}';
    }
    if (digits.startsWith('7')) {
      digits = digits.substring(1);
    }
    if (digits.length > 10) {
      digits = digits.substring(0, 10);
    }
    final String masked = PlacePhone.maskTen(digits);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}
