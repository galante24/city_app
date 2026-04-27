import '../../../services/chat_service.dart' show ChatPlaceShareParsed;
import '../../../services/place_service.dart';

/// Резолв превью «место в чате»: один [Future] на один и тот же [ChatPlaceShareParsed].
class ChatPlaceShareResolved {
  const ChatPlaceShareResolved({
    required this.placeId,
    required this.title,
    this.photoUrl,
  });

  final String placeId;
  final String title;
  final String? photoUrl;
}

class ChatPlaceShareResolutionCache {
  ChatPlaceShareResolutionCache._();
  static final ChatPlaceShareResolutionCache I = ChatPlaceShareResolutionCache._();

  final Map<String, Future<ChatPlaceShareResolved?>> _futures =
      <String, Future<ChatPlaceShareResolved?>>{};

  String _key(ChatPlaceShareParsed p) {
    return '${p.directPlaceId ?? ''}\u{1f}${p.legacyPostId ?? ''}';
  }

  Future<ChatPlaceShareResolved?> futureFor(ChatPlaceShareParsed p) {
    return _futures.putIfAbsent(_key(p), () => _resolve(p));
  }
}

Future<ChatPlaceShareResolved?> _resolve(
  ChatPlaceShareParsed p,
) async {
  if (p.directPlaceId != null && p.directPlaceId!.isNotEmpty) {
    final Map<String, dynamic>? row =
        await PlaceService.fetchPlace(p.directPlaceId!);
    final String? t = (row?['title'] as String?)?.trim();
    final String title = t != null && t.isNotEmpty ? t : p.headline;
    String? photo = p.thumbUrl?.trim();
    if (photo == null || photo.isEmpty) {
      photo = (row?['photo_url'] as String?)?.trim();
    }
    if (photo == null || photo.isEmpty) {
      photo = (row?['cover_url'] as String?)?.trim();
    }
    return ChatPlaceShareResolved(
      placeId: p.directPlaceId!,
      title: title,
      photoUrl: photo,
    );
  }
  final String? pid = p.legacyPostId;
  if (pid == null || pid.isEmpty) {
    return null;
  }
  final Map<String, dynamic>? post = await PlaceService.fetchPlacePostById(pid);
  if (post == null) {
    return null;
  }
  final String? plId = post['place_id']?.toString();
  if (plId == null || plId.isEmpty) {
    return null;
  }
  final Map<String, dynamic>? pl = await PlaceService.fetchPlace(plId);
  final String? pt = (pl?['title'] as String?)?.trim();
  final String title = pt != null && pt.isNotEmpty ? pt : p.headline;
  String? photo = (post['image_url'] as String?)?.trim();
  if (photo == null || photo.isEmpty) {
    photo = (pl?['photo_url'] as String?)?.trim();
  }
  if (photo == null || photo.isEmpty) {
    photo = (pl?['cover_url'] as String?)?.trim();
  }
  if (photo == null || photo.isEmpty) {
    photo = p.thumbUrl?.trim();
  }
  return ChatPlaceShareResolved(
    placeId: plId,
    title: title,
    photoUrl: photo,
  );
}
