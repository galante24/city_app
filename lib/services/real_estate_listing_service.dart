import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_ready.dart';
import '../models/real_estate_listing_kind.dart';
import 'city_data_service.dart';

/// Объявления недвижимости для категорий с таблицей `*_listings` и полем `property_address`.
class RealEstateListingService {
  RealEstateListingService._();

  static SupabaseClient? get _c {
    if (!supabaseAppReady) {
      return null;
    }
    return Supabase.instance.client;
  }

  static String addressFromRow(Map<String, dynamic> m) {
    return (m['property_address'] as String? ?? '').trim();
  }

  static String floorAreaFromRow(Map<String, dynamic> m) {
    return (m['floor_area'] as String? ?? '').trim();
  }

  static Future<List<Map<String, dynamic>>> fetchAll(
    RealEstateListingKind kind,
  ) async {
    final c = _c;
    if (c == null) {
      return <Map<String, dynamic>>[];
    }
    try {
      final List<dynamic> res = await c
          .from(kind.tableName)
          .select()
          .order('created_at', ascending: false);
      return res.cast<Map<String, dynamic>>();
    } on Exception {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<String> uploadImage(
    RealEstateListingKind kind,
    XFile file,
  ) async {
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
        '${kind.storageFolder}/$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
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

  static Future<void> insert(
    RealEstateListingKind kind, {
    required String title,
    required String description,
    required String price,
    required String floorArea,
    required String propertyAddress,
    required String contactPhone,
    String? imageUrl,
  }) async {
    final c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    final String? uid = c.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('Нет сессии');
    }
    await c.from(kind.tableName).insert(<String, dynamic>{
      'author_id': uid,
      'title': title.trim(),
      'description': description.trim(),
      'price': price.trim(),
      'floor_area': floorArea.trim(),
      'property_address': propertyAddress.trim(),
      'contact_phone': contactPhone.trim(),
      if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
    });
  }

  static Future<void> deleteById(
    RealEstateListingKind kind,
    String id,
  ) async {
    final c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    await c.from(kind.tableName).delete().eq('id', id);
  }
}
