import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_ready.dart';
import 'city_data_service.dart';

/// Заведения: места, подписки, модераторы, посты, лайки, комментарии.
class PlaceService {
  PlaceService._();

  static SupabaseClient? get _c {
    if (!supabaseAppReady) {
      return null;
    }
    return Supabase.instance.client;
  }

  static Future<List<Map<String, dynamic>>> fetchPlaces() async {
    final c = _c;
    if (c == null) {
      return <Map<String, dynamic>>[];
    }
    try {
      final List<dynamic> res = await c
          .from('places')
          .select()
          .order('created_at', ascending: false);
      return res.cast<Map<String, dynamic>>();
    } on Exception {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<Map<String, dynamic>?> fetchPlace(String id) async {
    final c = _c;
    if (c == null) {
      return null;
    }
    try {
      return await c.from('places').select().eq('id', id).maybeSingle();
    } on Exception {
      return null;
    }
  }

  static Future<Set<String>> fetchMySubscribedPlaceIds() async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      return <String>{};
    }
    try {
      final List<dynamic> rows = await c
          .from('place_subscriptions')
          .select('place_id')
          .eq('user_id', uid);
      return rows
          .cast<Map<String, dynamic>>()
          .map((Map<String, dynamic> m) => m['place_id']?.toString() ?? '')
          .where((String s) => s.isNotEmpty)
          .toSet();
    } on Exception {
      return <String>{};
    }
  }

  static Future<bool> isSubscribed(String placeId) async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      return false;
    }
    try {
      final Map<String, dynamic>? row = await c
          .from('place_subscriptions')
          .select('place_id')
          .eq('user_id', uid)
          .eq('place_id', placeId)
          .maybeSingle();
      return row != null;
    } on Exception {
      return false;
    }
  }

  static Future<void> subscribe(String placeId) async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      throw StateError('Нет сессии');
    }
    await c.from('place_subscriptions').insert(<String, dynamic>{
      'user_id': uid,
      'place_id': placeId,
    });
  }

  static Future<void> unsubscribe(String placeId) async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      throw StateError('Нет сессии');
    }
    await c
        .from('place_subscriptions')
        .delete()
        .eq('user_id', uid)
        .eq('place_id', placeId);
  }

  static Future<List<String>> fetchModeratorUserIds(String placeId) async {
    final c = _c;
    if (c == null) {
      return <String>[];
    }
    try {
      final List<dynamic> rows = await c
          .from('place_moderators')
          .select('user_id')
          .eq('place_id', placeId);
      return rows
          .cast<Map<String, dynamic>>()
          .map((Map<String, dynamic> m) => m['user_id']?.toString() ?? '')
          .where((String s) => s.isNotEmpty)
          .toList();
    } on Exception {
      return <String>[];
    }
  }

  static Future<bool> canModeratePlace(
    String placeId, {
    required bool isDbAdmin,
    required List<String> moderatorIds,
    String? ownerId,
  }) async {
    final String? me = _c?.auth.currentUser?.id;
    if (me == null) {
      return false;
    }
    if (isDbAdmin) {
      return true;
    }
    if (ownerId != null && ownerId == me) {
      return true;
    }
    return moderatorIds.contains(me);
  }

  static Future<String> uploadPlaceImage(XFile file) async {
    final c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    final String? uid = c.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('Нет сессии');
    }
    final String name = file.name;
    final int dot = name.lastIndexOf('.');
    final String ext = dot >= 0 && dot < name.length - 1
        ? name.substring(dot + 1).toLowerCase()
        : 'jpg';
    final String path =
        'places/$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final String contentType = switch (ext) {
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    final bucket = c.storage.from(CityDataService.cityMediaBucket);
    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      await bucket.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(upsert: true, contentType: contentType),
      );
    } else {
      await bucket.upload(
        path,
        File(file.path),
        fileOptions: FileOptions(upsert: true, contentType: contentType),
      );
    }
    return bucket.getPublicUrl(path);
  }

  static Future<String> createPlace({
    required String title,
    String? photoUrl,
    String? coverUrl,
  }) async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      throw StateError('Нет сессии');
    }
    final Map<String, dynamic> row = await c
        .from('places')
        .insert(<String, dynamic>{
          'title': title.trim(),
          'owner_id': uid,
          if (photoUrl != null && photoUrl.isNotEmpty) 'photo_url': photoUrl,
          if (coverUrl != null && coverUrl.isNotEmpty) 'cover_url': coverUrl,
        })
        .select('id')
        .single();
    return row['id']?.toString() ?? '';
  }

  static Future<void> updatePlace(
    String placeId,
    Map<String, dynamic> patch,
  ) async {
    final c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    if (patch.isEmpty) {
      return;
    }
    patch['updated_at'] = DateTime.now().toUtc().toIso8601String();
    await c.from('places').update(patch).eq('id', placeId);
  }

  static Future<void> addModerator(String placeId, String userId) async {
    final c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    await c.from('place_moderators').insert(<String, dynamic>{
      'place_id': placeId,
      'user_id': userId,
    });
  }

  static Future<void> removeModerator(String placeId, String userId) async {
    final c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    await c
        .from('place_moderators')
        .delete()
        .eq('place_id', placeId)
        .eq('user_id', userId);
  }

  static Future<List<Map<String, dynamic>>> fetchPosts(String placeId) async {
    final c = _c;
    if (c == null) {
      return <Map<String, dynamic>>[];
    }
    try {
      final List<dynamic> res = await c
          .from('place_posts')
          .select()
          .eq('place_id', placeId)
          .order('created_at', ascending: false);
      return res.cast<Map<String, dynamic>>();
    } on Exception {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<Map<String, dynamic>> createPost({
    required String placeId,
    required String content,
    String? imageUrl,
    required bool notifySubscribers,
  }) async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      throw StateError('Нет сессии');
    }
    final Map<String, dynamic> row = await c
        .from('place_posts')
        .insert(<String, dynamic>{
          'place_id': placeId,
          'author_id': uid,
          'content': content.trim(),
          if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
          'notify_subscribers': notifySubscribers,
        })
        .select()
        .single();
    return row;
  }

  static Future<bool> isPostLikedByMe(String postId) async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      return false;
    }
    try {
      final Map<String, dynamic>? row = await c
          .from('place_post_likes')
          .select('post_id')
          .eq('post_id', postId)
          .eq('user_id', uid)
          .maybeSingle();
      return row != null;
    } on Exception {
      return false;
    }
  }

  static Future<void> likePost(String postId) async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      throw StateError('Нет сессии');
    }
    await c.from('place_post_likes').insert(<String, dynamic>{
      'post_id': postId,
      'user_id': uid,
    });
  }

  static Future<void> unlikePost(String postId) async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      throw StateError('Нет сессии');
    }
    await c
        .from('place_post_likes')
        .delete()
        .eq('post_id', postId)
        .eq('user_id', uid);
  }

  static Future<List<Map<String, dynamic>>> fetchComments(
    String postId,
  ) async {
    final c = _c;
    if (c == null) {
      return <Map<String, dynamic>>[];
    }
    try {
      final List<dynamic> res = await c
          .from('place_post_comments')
          .select()
          .eq('post_id', postId)
          .order('created_at', ascending: true);
      return res.cast<Map<String, dynamic>>();
    } on Exception {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> addComment(String postId, String text) async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      throw StateError('Нет сессии');
    }
    final String t = text.trim();
    if (t.isEmpty) {
      return;
    }
    await c.from('place_post_comments').insert(<String, dynamic>{
      'post_id': postId,
      'user_id': uid,
      'content': t,
    });
  }

  static Future<void> updateMyNotificationsEnabled(bool enabled) async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      throw StateError('Нет сессии');
    }
    await c.from('profiles').update(<String, dynamic>{
      'notifications_enabled': enabled,
    }).eq('id', uid);
  }

  static Future<void> updateMyFcmToken(String? token) async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      return;
    }
    await c.from('profiles').update(<String, dynamic>{
      'fcm_token': token,
    }).eq('id', uid);
  }
}
