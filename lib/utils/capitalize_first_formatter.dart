import 'package:flutter/services.dart';

/// Первая буква значения (в т.ч. кириллица) — заглавная, остальное без изменений.
class CapitalizeFirstFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String t = newValue.text;
    if (t.isEmpty) {
      return newValue;
    }
    if (t.length == 1) {
      return TextEditingValue(
        text: t[0].toUpperCase(),
        selection: newValue.selection,
        composing: TextRange.empty,
      );
    }
    return TextEditingValue(
      text: t[0].toUpperCase() + t.substring(1),
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}
