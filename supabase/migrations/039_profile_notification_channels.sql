-- Каналы push / уведомлений в profiles (клиент + Edge Functions).
alter table public.profiles
  add column if not exists notify_chat_messages boolean not null default true;
alter table public.profiles
  add column if not exists notify_feed_engagement boolean not null default true;
alter table public.profiles
  add column if not exists notify_news_feed boolean not null default true;

comment on column public.profiles.notify_chat_messages is
  'Push и баннеры: новые сообщения в чатах';
comment on column public.profiles.notify_feed_engagement is
  'Push: лайки и комментарии в ленте, упоминания в задачах (социальное вовлечение)';
comment on column public.profiles.notify_news_feed is
  'Push: новости СМИ/важное; подписчики заведений (notify-place-post)';
