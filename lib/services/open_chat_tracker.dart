/// Какой чат сейчас открыт в [UserChatThreadScreen] (чтобы не дублировать уведомления).
class OpenChatTracker {
  OpenChatTracker._();

  static String? _id;

  static void setOpen(String? conversationId) {
    _id = conversationId;
  }

  static bool isThisChatOpen(String conversationId) {
    return _id == conversationId;
  }
}
