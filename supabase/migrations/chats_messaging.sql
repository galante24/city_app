-- =============================================================================
-- Чаты: таблицы, phone в profiles, RPC, RLS. Без ALTER PUBLICATION.
-- Согласовано с: lib/data/chat_service.dart, screens/chats_list_screen.dart
-- Выполните в Supabase SQL Editor (или добавьте к существующему скрипту).
-- =============================================================================

create extension if not exists pgcrypto;

-- Телефон E.164 для сопоставления с контактами телефона
alter table public.profiles
  add column if not exists phone_e164 text;
create unique index if not exists profiles_phone_e164_key
  on public.profiles (phone_e164)
  where phone_e164 is not null and btrim(phone_e164) <> '';

-- Беседы
create table if not exists public.conversations (
  id uuid not null default gen_random_uuid() primary key,
  is_direct boolean not null default true,
  direct_pair_key text,
  last_message_at timestamptz,
  last_message_preview text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists conversations_direct_pair_key_uidx
  on public.conversations (direct_pair_key)
  where direct_pair_key is not null;

create table if not exists public.conversation_participants (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  primary key (conversation_id, user_id)
);
create index if not exists conv_part_user_idx on public.conversation_participants (user_id);

create table if not exists public.chat_messages (
  id uuid not null default gen_random_uuid() primary key,
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id uuid not null references auth.users (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);
create index if not exists chat_messages_conv_created_idx
  on public.chat_messages (conversation_id, created_at desc);

-- Обновление превью беседы
create or replace function public.on_chat_message_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.conversations
  set
    last_message_at = new.created_at,
    last_message_preview = left(new.body, 200),
    updated_at = new.created_at
  where id = new.conversation_id;
  return new;
end;
$$;

drop trigger if exists tr_chat_message_touch on public.chat_messages;
create trigger tr_chat_message_touch
  after insert on public.chat_messages
  for each row execute function public.on_chat_message_insert();

-- Поиск пользователя
create or replace function public.find_user_id_by_phone_e164(p_phone text)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.id
  from public.profiles p
  where p.phone_e164 = btrim(p_phone)
  limit 1;
$$;

create or replace function public.find_user_id_by_email(lookup text)
returns uuid
language sql
stable
security definer
set search_path = auth, public, pg_temp
as $$
  select u.id
  from auth.users u
  where lower(u.email) = lower(btrim(lookup))
  limit 1;
$$;

-- Личный чат: одна беседа на пару
create or replace function public.get_or_create_direct_conversation(p_other uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := auth.uid();
  pair text;
  conv uuid;
begin
  if p_other is null or me is null then
    raise exception 'invalid' using errcode = 'P0001';
  end if;
  if p_other = me then
    raise exception 'self' using errcode = 'P0001';
  end if;
  pair := case
    when me::text < p_other::text then me::text || '|' || p_other::text
    else p_other::text || '|' || me::text
  end;
  select c.id
  into conv
  from public.conversations c
  where c.is_direct
    and c.direct_pair_key = pair;
  if conv is not null then
    return conv;
  end if;
  insert into public.conversations (is_direct, direct_pair_key, updated_at, created_at)
  values (true, pair, now(), now())
  returning id into conv;
  insert into public.conversation_participants (conversation_id, user_id)
  values
    (conv, me),
    (conv, p_other);
  return conv;
end;
$$;

grant execute on function public.find_user_id_by_phone_e164(text) to authenticated;
grant execute on function public.find_user_id_by_email(text) to authenticated;
grant execute on function public.get_or_create_direct_conversation(uuid) to authenticated;

-- RLS
alter table public.conversations enable row level security;
alter table public.conversation_participants enable row level security;
alter table public.chat_messages enable row level security;

-- Сброс старых политик (только наших имён, без дропа всех)
do $pp$
begin
  execute 'drop policy if exists p_conv_select on public.conversations';
  execute 'drop policy if exists p_cpart_select on public.conversation_participants';
  execute 'drop policy if exists p_cmsg_select on public.chat_messages';
  execute 'drop policy if exists p_cmsg_insert on public.chat_messages';
  execute 'drop policy if exists p_profiles_read_chat_partners on public.profiles';
end
$pp$;

create policy p_conv_select
  on public.conversations
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.conversation_participants p
      where p.conversation_id = conversations.id
        and p.user_id = auth.uid()
    )
  );

create policy p_cpart_select
  on public.conversation_participants
  for select
  to authenticated
  using (
    conversation_id in (
      select conversation_id
      from public.conversation_participants
      where user_id = auth.uid()
    )
  );

create policy p_cmsg_select
  on public.chat_messages
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.conversation_participants p
      where p.conversation_id = chat_messages.conversation_id
        and p.user_id = auth.uid()
    )
  );

create policy p_cmsg_insert
  on public.chat_messages
  for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and exists (
      select 1
      from public.conversation_participants p
      where p.conversation_id = chat_messages.conversation_id
        and p.user_id = auth.uid()
    )
  );

-- Собеседник может читать имя/тел. в профиле
create policy p_profiles_read_chat_partners
  on public.profiles
  for select
  to authenticated
  using (
    id in (
      select cp.user_id
      from public.conversation_participants cp
      where cp.conversation_id in (
        select p2.conversation_id
        from public.conversation_participants p2
        where p2.user_id = auth.uid()
      )
    )
  );

grant select on public.conversations to authenticated;
grant select, insert, update, delete on public.chat_messages to authenticated;
grant select on public.conversation_participants to authenticated;

-- =============================================================================
-- Готово. PUBLICATION supabase_realtime: если FOR ALL TABLES — отдельно ничего.
-- Realtime: при необходимости включите в Dashboard для public.chat_messages.
-- =============================================================================
