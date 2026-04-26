/// Ссылки из текста сообщений чата.
final RegExp kChatUrlRegexp = RegExp(
  r'https?://[^\s<>\[\]()\"]+',
  caseSensitive: false,
);

List<String> extractUrlsFromChatText(String text) {
  if (text.startsWith('!img:') ||
      text.startsWith('!file:b64:')) {
    return <String>[];
  }
  return kChatUrlRegexp
      .allMatches(text)
      .map((RegExpMatch m) => m.group(0)!.trim())
      .where((String u) => u.isNotEmpty)
      .toList();
}
