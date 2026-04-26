import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/profile_screen.dart';
import '../screens/public_user_profile_screen.dart';

/// Открыть профиль: свой — [ProfileScreen], чужой — [PublicUserProfileScreen].
void openUserProfile(
  BuildContext context,
  String userId, {
  String? fallbackName,
}) {
  final String? me = Supabase.instance.client.auth.currentUser?.id;
  if (me != null && me == userId) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => const ProfileScreen(),
      ),
    );
    return;
  }
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (BuildContext c) => PublicUserProfileScreen(
        userId: userId,
        fallbackTitle: fallbackName,
      ),
    ),
  );
}
