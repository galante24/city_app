import 'package:flutter/widgets.dart';

/// Якорь по [ScrollPosition] при prepend: \(pixels' = pixels + \Delta max\).
class ChatListExtentAnchor {
  const ChatListExtentAnchor._({
    required this.pixels,
    required this.maxScrollExtent,
  });

  final double pixels;
  final double maxScrollExtent;

  static ChatListExtentAnchor? capture(ScrollController c) {
    if (!c.hasClients) {
      return null;
    }
    return ChatListExtentAnchor._(
      pixels: c.position.pixels,
      maxScrollExtent: c.position.maxScrollExtent,
    );
  }

  void apply(ScrollController c) {
    if (!c.hasClients) {
      return;
    }
    final double d = c.position.maxScrollExtent - maxScrollExtent;
    c.jumpTo(
      (pixels + d).clamp(0.0, c.position.maxScrollExtent),
    );
  }
}

/// Два кадра: layout после [maxScrollExtent] — без «прыжка» при пагинации.
void applyPrependScrollRecovery({
  required ScrollController controller,
  required ChatListExtentAnchor? extentAnchor,
}) {
  if (extentAnchor == null) {
    return;
  }
  void go() {
    if (controller.hasClients) {
      extentAnchor.apply(controller);
    }
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    go();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      go();
    });
  });
}
