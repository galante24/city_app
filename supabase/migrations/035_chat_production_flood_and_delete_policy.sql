-- Production: анти-флуд, удаление только автором, индексы, соответствие схемы chats / members / messages.
-- Таблицы: public.conversations (= chats), public.conversation_participants (= chat_members), public.chat_messages (= messages).
-- RLS на чтение/вставку уже заданы в 010/034; здесь: триггер флуда, soft-delete только автор, индексы.

-- ---------------------------------------------------------------------------
-- Анти-флуд: не более [k] сообщений от одного пользователя в скользящем окне 1 мин (глобально).
-- ---------------------------------------------------------------------------
create or replace function public.enforce_chat_message_flood()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  recent int;
  k constant int := 30;
begin
  if new.sender_id is distinct from auth.uid() then
    raise exception 'sender_mismatch' using errcode = 'P0001';
  end if;
  select count(*)::int into recent
  from public.chat_messages
  where sender_id = new.sender_id
    and created_at > now() - interval '1 minute';
  if recent >= k then
    raise exception 'chat_rate_limited' using errcode = 'P0001', hint = 'too_many_messages';
  end if;
  return new;
end;
$$;

drop trigger if exists tr_chat_messages_flood on public.chat_messages;
create trigger tr_chat_messages_flood
  before insert on public.chat_messages
  for each row execute function public.enforce_chat_message_flood();

create index if not exists chat_messages_sender_created_idx
  on public.chat_messages (sender_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Мягкое удаление: только автор сообщения (в т.ч. в группах — без «модератор удаляет чужие»).
-- ---------------------------------------------------------------------------
create or replace function public.soft_delete_group_message(p_message_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := auth.uid();
  cid uuid;
  s uuid;
begin
  if me is null then
    raise exception 'not auth' using errcode = 'P0001';
  end if;
  select m.conversation_id, m.sender_id
  into cid, s
  from public.chat_messages m
  where m.id = p_message_id;
  if cid is null then
    return;
  end if;
  if s is null or s <> me then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;
  if not public.user_in_conversation(cid) then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;
  update public.chat_messages
  set
    deleted_at = now(),
    deleted_by = me,
    body = ''
  where id = p_message_id;
end;
$$;

-- Удаление сообщений — только через RPC [soft_delete_group_message] (мягкое), не прямой DELETE.
revoke delete on public.chat_messages from authenticated;
