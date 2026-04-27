/// Очистка пользовательского текста перед отправкой в API (UTF-8, без NUL, длина).
class ChatInputSanitizer {
  ChatInputSanitizer._();

  static const int kMaxChatBodyLength = 12000;

  static String sanitizeOutgoingText(String raw) {
    String s = raw.replaceAll('\x00', '').trim();
    if (s.length > kMaxChatBodyLength) {
      s = s.substring(0, kMaxChatBodyLength);
    }
    return s;
  }
}
