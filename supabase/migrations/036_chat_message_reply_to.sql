-- Reply-to (как в Telegram): ссылка на сообщение в этой беседе + снимок для превью.

alter table public.chat_messages
  add column if not exists reply_to_message_id uuid
    references public.chat_messages (id) on delete set null;

alter table public.chat_messages
  add column if not exists reply_snippet text;

alter table public.chat_messages
  add column if not exists reply_author_id uuid
    references auth.users (id) on delete set null;

alter table public.chat_messages
  add column if not exists reply_author_label text;

comment on column public.chat_messages.reply_to_message_id is 'Сообщение, на которое дан ответ (та же беседа)';
comment on column public.chat_messages.reply_snippet is 'Краткий текст/подпись оригинала на момент ответа';
comment on column public.chat_messages.reply_author_id is 'Автор оригинала';
comment on column public.chat_messages.reply_author_label is 'Подпись автора оригинала на момент ответа';

create index if not exists chat_messages_reply_to_idx
  on public.chat_messages (reply_to_message_id)
  where reply_to_message_id is not null;

-- Ответ должен ссылаться на сообщение той же беседы.
create or replace function public.chat_message_enforce_reply_in_thread()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.reply_to_message_id is null then
    return new;
  end if;
  if not exists (
    select 1
    from public.chat_messages o
    where o.id = new.reply_to_message_id
      and o.conversation_id = new.conversation_id
  ) then
    raise exception 'reply_not_in_conversation' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists tr_chat_message_reply_in_thread on public.chat_messages;
create trigger tr_chat_message_reply_in_thread
  before insert or update of reply_to_message_id, conversation_id
  on public.chat_messages
  for each row
  execute function public.chat_message_enforce_reply_in_thread();

-- Превью в списке бесед: с учётом ответа.
create or replace function public.on_chat_message_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  preview text;
  body_excerpt text;
  reply_bit text;
begin
  if new.body like '!img:%' then
    body_excerpt := '📷 Фото';
  elsif new.body like '!file:b64:%' then
    body_excerpt := '📎 Файл';
  else
    body_excerpt := left(coalesce(new.body, ''), 120);
  end if;

  if new.reply_to_message_id is not null
     and new.reply_snippet is not null
     and btrim(new.reply_snippet) <> '' then
    reply_bit := '↩ ';
    if new.reply_author_label is not null
       and btrim(new.reply_author_label) <> '' then
      reply_bit := reply_bit || left(btrim(new.reply_author_label), 32) || ': ';
    end if;
    reply_bit := reply_bit || left(btrim(new.reply_snippet), 100);
  else
    reply_bit := null;
  end if;

  if reply_bit is not null then
    preview := left(reply_bit, 200);
  elsif new.forwarded_from_label is not null
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
