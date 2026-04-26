-- Метаданные пересылки: кто автор оригинала (как в Telegram).

alter table public.chat_messages
  add column if not exists forwarded_from_user_id uuid references auth.users (id) on delete set null;

alter table public.chat_messages
  add column if not exists forwarded_from_label text;

comment on column public.chat_messages.forwarded_from_user_id is 'Автор оригинала при пересылке';
comment on column public.chat_messages.forwarded_from_label is 'Подпись автора оригинала на момент пересылки';

create or replace function public.on_chat_message_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  preview text;
  body_excerpt text;
begin
  if new.body like '!img:%' then
    body_excerpt := '📷 Фото';
  elsif new.body like '!file:b64:%' then
    body_excerpt := '📎 Файл';
  else
    body_excerpt := left(coalesce(new.body, ''), 120);
  end if;

  if new.forwarded_from_label is not null
     and btrim(new.forwarded_from_label) <> '' then
    preview := '↪ ' || btrim(new.forwarded_from_label) || ': ' || body_excerpt;
  else
    if new.body like '!img:%' then
      preview := '📷 Фото';
    elsif new.body like '!file:b64:%' then
      preview := '📎 Файл';
    else
      preview := left(coalesce(new.body, ''), 200);
    end if;
  end if;

  preview := left(preview, 200);

  update public.conversations
  set
    last_message_at = new.created_at,
    last_message_preview = preview,
    updated_at = new.created_at
  where id = new.conversation_id;
  return new;
end;
$$;
