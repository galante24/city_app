/// Отключает дублирующие баннеры из Supabase Realtime, когда FCM уже доставляет пуши.
class NotificationDeliveryPolicy {
  NotificationDeliveryPolicy._();

  static bool suppressRealtimeChatBanners = false;
}
