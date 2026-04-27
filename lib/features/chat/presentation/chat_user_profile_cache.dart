import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../services/city_data_service.dart';

/// Кэш [CityDataService.fetchProfileRow] по `userId` + [ValueNotifier] на id,
/// чтобы не строить [FutureBuilder] на каждую ячейку [ListView].
class ChatUserProfileCache {
  ChatUserProfileCache._();
  static final ChatUserProfileCache I = ChatUserProfileCache._();

  final Map<String, ValueNotifier<Map<String, dynamic>?>> _row =
      <String, ValueNotifier<Map<String, dynamic>?>>{};
  final Set<String> _inFlight = <String>{};

  /// Подписка на одну строку профиля; при первом обращении стартует загрузка.
  ValueNotifier<Map<String, dynamic>?> listenable(String userId) {
    if (userId.isEmpty) {
      return ValueNotifier<Map<String, dynamic>?>(null);
    }
    final ValueNotifier<Map<String, dynamic>?> n = _row.putIfAbsent(
      userId,
      () => ValueNotifier<Map<String, dynamic>?>(null),
    );
    _scheduleLoad(userId, n);
    return n;
  }

  /// Догрузка списка id (например после смены состава ленты), без сети в [itemBuilder].
  void prefetch(Iterable<String> userIds) {
    for (final String id in userIds) {
      if (id.isEmpty) {
        continue;
      }
      final ValueNotifier<Map<String, dynamic>?> n = _row.putIfAbsent(
        id,
        () => ValueNotifier<Map<String, dynamic>?>(null),
      );
      _scheduleLoad(id, n);
    }
  }

  void _scheduleLoad(
    String userId,
    ValueNotifier<Map<String, dynamic>?> target,
  ) {
    if (target.value != null) {
      return;
    }
    if (_inFlight.contains(userId)) {
      return;
    }
    _inFlight.add(userId);
    unawaited(_load(userId, target));
  }

  Future<void> _load(
    String userId,
    ValueNotifier<Map<String, dynamic>?> target,
  ) async {
    try {
      final Map<String, dynamic>? r =
          await CityDataService.fetchProfileRow(userId);
      if (target.value != null) {
        return;
      }
      target.value = r ?? <String, dynamic>{};
    } finally {
      _inFlight.remove(userId);
    }
  }
}
