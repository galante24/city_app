/// Черновой REST-контракт для VPS: те же сущности, что и `chat_messages` в Supabase.
///
/// **База:** `API_BASE_URL` (без `/` в конце). Заголовок: `Authorization: Bearer <access_token>`.
///
/// Модель сообщения (JSON) — плоский объект, ключи как в [ChatMessage.toMap]:
/// - `id` (uuid), `conversation_id`, `sender_id`, `body`, `created_at` (ISO-8601)
/// - `message_type`: `text` | `image` | `voice` (опционально, по умолчанию text)
/// - `media_url`, `media_duration_ms` — для `voice` / `image` (см. VPS)
///
/// **POST** `/v1/upload/voice` (multipart, поле `file`) — только с JWT; ответ `{ url, path, size, mime }`.
/// Далее **POST** `/v1/conversations/{id}/messages` с `message_type: voice`, `media_url: path` (`/v1/media/voice/...`).
///
/// ## Примеры
///
/// **GET** `/v1/conversations/{conversationId}/messages?limit=50&before=ISO8601`  
/// Ответ: `{ "items": [ { ...message }, ... ] }`  
/// Сортировка: от **нового к старому** (как сейчас в Supabase `order desc` + флип в UI).
///
/// **GET** `/v1/conversations/{conversationId}/messages/{messageId}`  
/// Ответ: одно сообщение или 404.
///
/// **POST** `/v1/conversations/{conversationId}/messages`  
/// Тело: `{ "body": "...", "forwarded_from_user_id"?: "...", ... }` (без `sender_id` — с сервера по токену).  
/// Ответ: `{ "message": { ... } }` с 201.
///
/// **POST** (или **DELETE**) `/v1/messages/{messageId}/soft-delete`  
/// Соответствие RPC `soft_delete_group_message`.
///
/// **WebSocket / SSE** (по желанию): `{ "event": "insert|update|delete", "conversation_id": "...", "record": { ... } }`  
/// → маппинг в [ChatMessageRowEvent] на клиенте.
///
/// Ключи и семантика должны совпадать с Supabase, чтобы [ChatMessage.fromMap] не различал источник.
library;

class ChatMessagesRestContract {
  const ChatMessagesRestContract._();
}
