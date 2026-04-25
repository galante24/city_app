-- =============================================================================
-- ВСЁ В ОДНОМ: база чатов (conversations) + группы, @username, ник при регистрации.
-- Запуск, если: нет public.conversations ИЛИ не кидали chats_messaging.sql.
-- Нужен только public.profiles и auth.users (как в 001_init). Без раздела публикации.
-- Supabase: SQL → вставить ВЕСЬ файл с 1-й строки → Run.
-- =============================================================================

create extension if not exists pgcrypto;

-- ---------- Как в chats_messaging: телефон, таблицы чатов ----------
alter table public.profiles
  add column if not exists phone_e164 text;
create unique index if not exists profiles_phone_e164_key
  on public.profiles (phone_e164)
  where phone_e164 is not null and btrim(phone_e164) <> '';

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

grant execute on function public.find_user_id_by_phone_e164(text) to authenticated;
grant execute on function public.find_user_id_by_email(text) to authenticated;

-- RLS (чаты)
alter table public.conversations enable row level security;
alter table public.conversation_participants enable row level security;
alter table public.chat_messages enable row level security;

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
-- Группы, username, RPC (get_or_create_direct_conversation — одна «полная» версия)
-- =============================================================================
alter table public.profiles
  add column if not exists first_name text;
alter table public.profiles
  add column if not exists last_name text;
alter table public.profiles
  add column if not exists username text;
create unique index if not exists profiles_username_lower_key
  on public.profiles (lower(username::text))
  where username is not null and btrim(username::text) <> '';

alter table public.conversations
  add column if not exists is_group boolean not null default false;
alter table public.conversations
  add column if not exists group_name text;
alter table public.conversations
  add column if not exists is_open boolean;
alter table public.conversations
  add column if not exists created_by uuid references auth.users (id) on delete set null;

update public.conversations
set
  is_group = false
where is_group is null;
update public.conversations
set is_group = is_direct is not true
where (group_name is not null or created_by is not null) and is_group is not true;

alter table public.conversation_participants
  add column if not exists role text not null default 'member';

update public.conversation_participants p
set role = 'member'
from public.conversations c
where c.id = p.conversation_id
  and coalesce(c.is_direct, true) = true
  and p.role = 'member';

alter table public.chat_messages
  add column if not exists deleted_at timestamptz;
alter table public.chat_messages
  add column if not exists deleted_by uuid references auth.users (id) on delete set null;

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
  insert into public.conversations (is_direct, is_group, direct_pair_key, updated_at, created_at, created_by)
  values (true, false, pair, now(), now(), me)
  returning id into conv;
  insert into public.conversation_participants (conversation_id, user_id, role)
  values
    (conv, me, 'member'),
    (conv, p_other, 'member');
  return conv;
end;
$$;

create or replace function public.set_my_username(p_username text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := auth.uid();
  u text := lower(btrim(p_username));
begin
  if me is null then
    raise exception 'not auth' using errcode = 'P0001';
  end if;
  if u is null or u = '' then
    update public.profiles set username = null where id = me;
    return;
  end if;
  if u !~ '^[a-z0-9_]{3,32}$' then
    raise exception 'invalid_username' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.profiles p where p.id <> me and lower(p.username) = u) then
    raise exception 'username_taken' using errcode = 'P0001';
  end if;
  update public.profiles set username = u where id = me;
end;
$$;

create or replace function public.create_group_conversation(p_title text, p_is_open boolean)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := auth.uid();
  conv uuid;
  t text := btrim(p_title);
begin
  if me is null then
    raise exception 'not auth' using errcode = 'P0001';
  end if;
  if t = '' or length(t) > 120 then
    raise exception 'bad_title' using errcode = 'P0001';
  end if;
  insert into public.conversations (
    is_direct, is_group, direct_pair_key, group_name, is_open, created_by, created_at, updated_at
  ) values (
    false, true, null, t, p_is_open, me, now(), now()
  )
  returning id into conv;
  insert into public.conversation_participants (conversation_id, user_id, role)
  values (conv, me, 'owner');
  return conv;
end;
$$;

create or replace function public._can_add_to_group(p_conv uuid, p_actor uuid)
returns boolean
language sql
stable
as $$
  select
    case
      when c.is_open then exists (
        select 1 from public.conversation_participants p
        where p.conversation_id = p_conv and p.user_id = p_actor
      )
      else exists (
        select 1 from public.conversation_participants p
        where p.conversation_id = p_conv
          and p.user_id = p_actor
          and p.role in ('owner', 'moderator')
      )
    end
  from public.conversations c
  where c.id = p_conv and c.is_group
$$;

create or replace function public.add_group_participant(p_conversation_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := auth.uid();
begin
  if me is null or p_user_id is null then
    raise exception 'invalid' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.conversations c
    where c.id = p_conversation_id and c.is_group
  ) then
    raise exception 'not_group' using errcode = 'P0001';
  end if;
  if not public._can_add_to_group(p_conversation_id, me) then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;
  if p_user_id = me then
    return;
  end if;
  insert into public.conversation_participants (conversation_id, user_id, role)
  values (p_conversation_id, p_user_id, 'member')
  on conflict (conversation_id, user_id) do nothing;
end;
$$;

create or replace function public.remove_group_participant(p_conversation_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := auth.uid();
  me_role text;
  tgt_role text;
  is_g boolean;
begin
  if me is null or p_user_id is null then
    raise exception 'invalid' using errcode = 'P0001';
  end if;
  select c.is_group
  into is_g
  from public.conversations c
  where c.id = p_conversation_id;
  if not coalesce(is_g, false) then
    raise exception 'not_group' using errcode = 'P0001';
  end if;
  select p.role into me_role
  from public.conversation_participants p
  where p.conversation_id = p_conversation_id and p.user_id = me;
  select p.role into tgt_role
  from public.conversation_participants p
  where p.conversation_id = p_conversation_id and p.user_id = p_user_id;
  if tgt_role is null then
    raise exception 'not_in_chat' using errcode = 'P0001';
  end if;
  if p_user_id = me then
    delete from public.conversation_participants
    where conversation_id = p_conversation_id and user_id = me;
    return;
  end if;
  if me_role is null or me_role = 'member' then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;
  if tgt_role = 'owner' then
    raise exception 'cannot_remove_owner' using errcode = 'P0001';
  end if;
  if me_role = 'moderator' then
    if tgt_role in ('owner', 'moderator') then
      raise exception 'mod_cannot' using errcode = 'P0001';
    end if;
  end if;
  delete from public.conversation_participants
  where conversation_id = p_conversation_id and user_id = p_user_id;
end;
$$;

create or replace function public.set_group_moderator(p_conversation_id uuid, p_user_id uuid, p_moderator boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := auth.uid();
  owner_b uuid;
begin
  if me is null then
    raise exception 'not auth' using errcode = 'P0001';
  end if;
  select c.created_by into owner_b
  from public.conversations c
  where c.id = p_conversation_id and c.is_group;
  if owner_b is null or me <> owner_b then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;
  if p_user_id = owner_b then
    return;
  end if;
  update public.conversation_participants
  set role = case when p_moderator then 'moderator' else 'member' end
  where conversation_id = p_conversation_id
    and user_id = p_user_id
    and role <> 'owner';
end;
$$;

create or replace function public.soft_delete_group_message(p_message_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := auth.uid();
  cid uuid;
  r text;
  s uuid;
  is_g boolean;
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
  select c.is_group into is_g
  from public.conversations c
  where c.id = cid;
  if not coalesce(is_g, false) then
    if s <> me then
      raise exception 'forbidden' using errcode = 'P0001';
    end if;
  else
    select p.role into r
    from public.conversation_participants p
    where p.conversation_id = cid and p.user_id = me;
    if r is null then
      raise exception 'forbidden' using errcode = 'P0001';
    end if;
    if s <> me and r = 'member' then
      raise exception 'forbidden' using errcode = 'P0001';
    end if;
    if s <> me and r not in ('owner', 'moderator') then
      raise exception 'forbidden' using errcode = 'P0001';
    end if;
  end if;
  update public.chat_messages
  set
    deleted_at = now(),
    deleted_by = me,
    body = ''
  where id = p_message_id;
end;
$$;

create or replace function public.search_profiles_for_chat(p_query text, p_limit int default 20)
returns table (id uuid, first_name text, last_name text, username text)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    p.id,
    p.first_name,
    p.last_name,
    p.username
  from public.profiles p
  where
    btrim(p_query) <> ''
    and (
      coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '') ilike '%' || p_query || '%'
      or (p.username is not null and p.username ilike '%' || p_query || '%')
    )
  order by p.last_name, p.first_name
  limit least(coalesce(p_limit, 20), 50);
$$;

create or replace function public.list_direct_partner_user_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select distinct p2.user_id
  from public.conversation_participants p1
  join public.conversation_participants p2
    on p2.conversation_id = p1.conversation_id
  join public.conversations c on c.id = p1.conversation_id
  where p1.user_id = auth.uid()
    and c.is_direct
    and p2.user_id <> p1.user_id;
$$;

grant execute on function public.get_or_create_direct_conversation(uuid) to authenticated;
grant execute on function public.set_my_username(text) to authenticated;
grant execute on function public.create_group_conversation(text, boolean) to authenticated;
grant execute on function public.add_group_participant(uuid, uuid) to authenticated;
grant execute on function public.remove_group_participant(uuid, uuid) to authenticated;
grant execute on function public.set_group_moderator(uuid, uuid, boolean) to authenticated;
grant execute on function public.soft_delete_group_message(uuid) to authenticated;
grant execute on function public.search_profiles_for_chat(text, int) to authenticated;
grant execute on function public.list_direct_partner_user_ids() to authenticated;

drop policy if exists p_cmsg_update on public.chat_messages;

-- Случайный ник при регистрации
create or replace function public.internal_unique_random_username()
returns text
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  candidate text;
  i int := 0;
begin
  loop
    candidate := 'u' || substr(md5(random()::text || random()::text || clock_timestamp()::text), 1, 8);
    exit when not exists (
      select 1
      from public.profiles p
      where lower(nullif(btrim(p.username::text), '')) = candidate
    );
    i := i + 1;
    exit when i > 40;
  end loop;
  if i > 40 then
    candidate := 'u' || encode(gen_random_bytes(15), 'hex');
    candidate := left(candidate, 32);
  end if;
  return candidate;
end;
$$;

revoke all on function public.internal_unique_random_username() from public;
revoke all on function public.internal_unique_random_username() from anon, authenticated, service_role;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uname text;
begin
  uname := public.internal_unique_random_username();
  insert into public.profiles (id, username) values (new.id, uname)
  on conflict (id) do update set
    username = coalesce(
      nullif(btrim(public.profiles.username::text), ''),
      excluded.username
    );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

alter table public.profiles
  add column if not exists username text;
create unique index if not exists profiles_username_lower_key
  on public.profiles (lower(username::text))
  where username is not null and btrim(username::text) <> '';

do $fill$
declare
  r record;
  uname text;
begin
  for r in
    select id
    from public.profiles
    where username is null
       or btrim(username::text) = ''
  loop
    uname := public.internal_unique_random_username();
    update public.profiles
    set username = uname
    where id = r.id;
  end loop;
end;
$fill$;

-- =============================================================================
-- Профиль: birth_date, RLS UPDATE с WITH CHECK (телефон, ник, ФИО; см. 009)
-- first_name/last_name см. выше; last_name дублировать не нужно
-- =============================================================================
alter table public.profiles
  add column if not exists birth_date date;

drop policy if exists "profiles self update" on public.profiles;
create policy "profiles self update" on public.profiles
  for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

drop policy if exists "profiles self read" on public.profiles;
create policy "profiles self read" on public.profiles
  for select
  to authenticated
  using (auth.uid() = id);

-- =============================================================================
-- RLS: убрать рекурсию на conversation_participants (см. 010_fix_cpart_rls_recursion.sql)
-- =============================================================================
create or replace function public.user_in_conversation(p_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.conversation_participants
    where conversation_id = p_conversation_id
      and user_id = auth.uid()
  );
$$;
revoke all on function public.user_in_conversation(uuid) from public;
grant execute on function public.user_in_conversation(uuid) to authenticated;

drop policy if exists p_cpart_select on public.conversation_participants;
create policy p_cpart_select
  on public.conversation_participants
  for select
  to authenticated
  using (public.user_in_conversation(conversation_id));

drop policy if exists p_conv_select on public.conversations;
create policy p_conv_select
  on public.conversations
  for select
  to authenticated
  using (public.user_in_conversation(id));

drop policy if exists p_cmsg_select on public.chat_messages;
create policy p_cmsg_select
  on public.chat_messages
  for select
  to authenticated
  using (public.user_in_conversation(conversation_id));

drop policy if exists p_cmsg_insert on public.chat_messages;
create policy p_cmsg_insert
  on public.chat_messages
  for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and public.user_in_conversation(conversation_id)
  );

-- Проверка:
--   select to_regclass('public.conversations');
--   select id, username, birth_date from public.profiles limit 5;
-- Готово.
