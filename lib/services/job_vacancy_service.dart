import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_ready.dart';
import 'city_data_service.dart';

class JobVacancyService {
  JobVacancyService._();

  static SupabaseClient? get _c {
    if (!supabaseAppReady) {
      return null;
    }
    return Supabase.instance.client;
  }

  static const String _table = 'job_vacancies';

  static const String _selectWithAuthor = '''
*,
author:profiles!job_vacancies_author_id_fkey(
  id,
  first_name,
  last_name,
  username,
  avatar_url
)
''';

  static Future<List<Map<String, dynamic>>> fetchAll() async {
    final c = _c;
    if (c == null) {
      return <Map<String, dynamic>>[];
    }
    try {
      final List<dynamic> res = await c
          .from(_table)
          .select(_selectWithAuthor)
          .order('created_at', ascending: false);
      return res.cast<Map<String, dynamic>>();
    } on Exception {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<String> uploadVacancyImage(XFile file) async {
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
        'vacancies/$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
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

  static Future<void> insert({
    required String title,
    required String description,
    required String salary,
    required String workAddress,
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
    await c.from(_table).insert(<String, dynamic>{
      'author_id': uid,
      'is_published': false,
      'title': title.trim(),
      'description': description.trim(),
      'salary': salary.trim(),
      'work_address': workAddress.trim(),
      'contact_phone': contactPhone.trim(),
      if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
    });
  }

  /// Только администратор (RLS + триггер в БД).
  static Future<void> setPublished(String id, {required bool published}) async {
    final c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    await c
        .from(_table)
        .update(<String, dynamic>{'is_published': published})
        .eq('id', id);
  }

  static Future<void> deleteById(String id) async {
    final c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    await c.from(_table).delete().eq('id', id);
  }
}
