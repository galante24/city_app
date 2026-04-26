-- =============================================================================
-- ПОЛНАЯ СБОРКА СХЕМЫ ПРОЕКТА city_app (вставить в Supabase SQL Editor, выполнить целиком)
-- Состав: 001 → bootstrap → 002–006 → FINAL_all_in_one → 012 → 013
-- Идемпотентно где возможно. Зависимость: auth.users (Supabase Auth).
-- =============================================================================


-- >>>>>> BEGIN FILE: 001_init.sql <<<<<<

-- Выполните в Supabase → SQL → New query.
-- 1) После первого входа по SMS найдите UUID: select id, phone from auth.users;
-- 2) Сделайте себя админом:  update public.profiles set is_admin = true where id = '...';

-- Профили (флаг админа)
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  is_admin boolean not null default false,
  updated_at timestamptz
);

-- Старая БД могла создать profiles без is_admin — иначе INSERT ниже падает (42703).
alter table public.profiles
  add column if not exists is_admin boolean not null default false;

insert into public.profiles (id, is_admin)
select u.id, false from auth.users u
on conflict (id) do nothing;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Новости
create table if not exists public.news_posts (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  category text not null check (category in ('smi', 'administration', 'discussion')),
  author text not null,
  title text not null,
  image_url text,
  video_url text,
  likes int not null default 0,
  comments int not null default 0
);

-- Паром
create table if not exists public.ferry_status (
  id int primary key default 1,
  status_text text not null default 'Паром ходит по расписанию',
  is_running boolean not null default true,
  updated_at timestamptz
);

insert into public.ferry_status (id, status_text, is_running)
values (1, 'Паром ходит по расписанию', true)
on conflict (id) do nothing;

-- Хранилище картинок к новостям
insert into storage.buckets (id, name, public)
values ('news-images', 'news-images', true)
on conflict (id) do nothing;

-- RLS
alter table public.profiles enable row level security;
alter table public.news_posts enable row level security;
alter table public.ferry_status enable row level security;

-- policies profiles
drop policy if exists "profiles self read" on public.profiles;
create policy "profiles self read" on public.profiles
  for select using (auth.uid() = id);
drop policy if exists "profiles self update" on public.profiles;
create policy "profiles self update" on public.profiles
  for update using (auth.uid() = id);

-- news: чтение всем
drop policy if exists "news public read" on public.news_posts;
create policy "news public read" on public.news_posts
  for select using (true);
drop policy if exists "news admin insert" on public.news_posts;
create policy "news admin insert" on public.news_posts
  for insert to authenticated
  with check (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true)
  );

-- ferry: чтение всем
drop policy if exists "ferry public read" on public.ferry_status;
create policy "ferry public read" on public.ferry_status
  for select using (true);
drop policy if exists "ferry admin update" on public.ferry_status;
create policy "ferry admin update" on public.ferry_status
  for update to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));

-- storage
drop policy if exists "public read news images" on storage.objects;
create policy "public read news images" on storage.objects
  for select using (bucket_id = 'news-images');
drop policy if exists "admin upload news images" on storage.objects;
create policy "admin upload news images" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'news-images' and
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true)
  );

-- Пример демо-данных (замените при необходимости)
insert into public.news_posts (category, author, title, image_url, likes, comments)
select 'smi', 'СМИ «Город»', 'Новости подгружаются из Supabase', null, 0, 0
where not exists (select 1 from public.news_posts limit 1);



-- >>>>>> BEGIN FILE: _bootstrap_news_schedules_for_app.sql <<<<<<

-- Таблицы, которые ожидает Flutter (CityDataService) и миграции 002–006.
-- В 001_init были news_posts/ferry_status; приложение использует public.news + public.schedules.

create table if not exists public.schedules (
  id uuid primary key,
  title text,
  status_text text,
  is_running boolean not null default true,
  time_text text,
  updated_at timestamptz
);

-- Старые БД могли создать schedules с NOT NULL title без значения в seed-вставке.
alter table public.schedules
  add column if not exists title text;

insert into public.schedules (id, title, status_text, is_running) values
  (
    '00000000-0000-0000-0000-000000000001',
    'Паром',
    'Паром ходит по расписанию',
    true
  )
on conflict (id) do update set
  title = excluded.title,
  status_text = excluded.status_text,
  is_running = excluded.is_running;

create table if not exists public.news (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  category text not null,
  author text,
  title text not null,
  image_url text,
  video_url text,
  body text,
  media_url text,
  media_type text,
  likes int not null default 0,
  comments int not null default 0
);

alter table public.schedules enable row level security;
alter table public.news enable row level security;

drop policy if exists "schedules public read" on public.schedules;
create policy "schedules public read" on public.schedules
  for select using (true);

drop policy if exists "news public read" on public.news;
create policy "news public read" on public.news
  for select using (true);



-- >>>>>> BEGIN FILE: 002_schedules_time_and_rls_by_email.sql <<<<<<

-- Выполните в Supabase → SQL, если у вас таблицы `public.news` и `public.schedules`
-- (колонка времени + RLS по email администратора вместо profiles.is_admin).

-- Время/подпись для парома
alter table public.schedules add column if not exists time_text text;

-- Realtime: Database → Replication → включите public.news и public.schedules
-- (без репликации события postgres_changes на клиент не приходят)

-- RLS: снимаем старые admin-политики на is_admin и вешаем проверку email из JWT
drop policy if exists "news admin insert" on public.news;
drop policy if exists "news admin insert by email" on public.news;
drop policy if exists "ferry admin update" on public.schedules;
drop policy if exists "schedules admin update by email" on public.schedules;
drop policy if exists "admin upload news images" on storage.objects;
drop policy if exists "admin upload news images by email" on storage.objects;

-- Вставка новостей: только sranometrr@gmail.com
create policy "news admin insert by email" on public.news
  for insert to authenticated
  with check (
    lower(coalesce(auth.jwt() ->> 'email', '')) = 'sranometrr@gmail.com'
  );

-- Обновление парома
create policy "schedules admin update by email" on public.schedules
  for update to authenticated
  using (
    lower(coalesce(auth.jwt() ->> 'email', '')) = 'sranometrr@gmail.com'
  )
  with check (
    lower(coalesce(auth.jwt() ->> 'email', '')) = 'sranometrr@gmail.com'
  );

-- Картинки к новостям
create policy "admin upload news images by email" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'news-images' and
    lower(coalesce(auth.jwt() ->> 'email', '')) = 'sranometrr@gmail.com'
  );



-- >>>>>> BEGIN FILE: 003_news_add_body_if_missing.sql <<<<<<

-- Текст новости (поле «Текст» в форме на главной)
alter table public.news add column if not exists body text;



-- >>>>>> BEGIN FILE: 004_bus_schedules.sql <<<<<<

-- Таблица расписаний автобусов
create table if not exists public.bus_schedules (
  id uuid primary key default gen_random_uuid(),
  route_number text not null,
  destination text not null,
  departure_times jsonb not null default '[]'::jsonb,
  updated_at timestamptz
);

alter table public.bus_schedules enable row level security;

drop policy if exists "bus schedules public read" on public.bus_schedules;
create policy "bus schedules public read" on public.bus_schedules
  for select using (true);

drop policy if exists "bus schedules admin all" on public.bus_schedules;
create policy "bus schedules admin all" on public.bus_schedules
  for all to authenticated
  using (lower(coalesce(auth.jwt() ->> 'email', '')) = 'sranometrr@gmail.com')
  with check (lower(coalesce(auth.jwt() ->> 'email', '')) = 'sranometrr@gmail.com');

-- Realtime: включите public.bus_schedules в Database → Replication



-- >>>>>> BEGIN FILE: 005_profiles_first_name.sql <<<<<<

-- Имя в профиле (чтение в приложении из public.profiles)
alter table public.profiles add column if not exists first_name text;

-- При обновлении user_metadata (например после signUp) можно синхронизировать вручную
-- либо добавить триггер по необходимости.



-- >>>>>> BEGIN FILE: 006_news_media_city_media.sql <<<<<<

-- Колонки единого медиа в новостях
alter table public.news add column if not exists media_url text;
alter table public.news add column if not exists media_type text
  check (media_type is null or media_type in ('image', 'video'));

-- Бакет city_media
insert into storage.buckets (id, name, public)
values ('city_media', 'city_media', true)
on conflict (id) do nothing;

-- RLS: чтение для всех
drop policy if exists "city media public read" on storage.objects;
create policy "city media public read" on storage.objects
  for select using (bucket_id = 'city_media');

-- Загрузка только sranometrr@gmail.com
drop policy if exists "city media admin upload" on storage.objects;
create policy "city media admin upload" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'city_media' and
    lower(coalesce(auth.jwt() ->> 'email', '')) = 'sranometrr@gmail.com'
  );

drop policy if exists "city media admin update" on storage.objects;
create policy "city media admin update" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'city_media' and
    lower(coalesce(auth.jwt() ->> 'email', '')) = 'sranometrr@gmail.com'
  )
  with check (
    bucket_id = 'city_media' and
    lower(coalesce(auth.jwt() ->> 'email', '')) = 'sranometrr@gmail.com'
  );

-- Realtime: при необходимости добавьте public.news (уже может быть)



-- >>>>>> BEGIN FILE: FINAL_all_in_one_chats_and_groups.sql <<<<<<

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

-- =============================================================================
-- Список чатов: превью последнего сообщения (если колонки пустые), см. 011
-- =============================================================================
create or replace function public.conversation_last_message_previews(p_conv_ids uuid[])
returns table (conversation_id uuid, body_preview text, last_at timestamptz)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select distinct on (m.conversation_id)
    m.conversation_id,
    left(btrim(m.body), 200) as body_preview,
    m.created_at
  from public.chat_messages m
  where m.conversation_id = any(p_conv_ids)
    and m.deleted_at is null
    and public.user_in_conversation(m.conversation_id)
  order by m.conversation_id, m.created_at desc;
$$;

revoke all on function public.conversation_last_message_previews(uuid[]) from public;
grant execute on function public.conversation_last_message_previews(uuid[]) to authenticated;

-- Проверка:
--   select to_regclass('public.conversations');
--   select id, username, birth_date from public.profiles limit 5;
-- Готово.



-- >>>>>> BEGIN FILE: 012_chat_read_state.sql <<<<<<

-- =============================================================================
-- ПОЛНАЯ САМОДОСТАТОЧНАЯ ЗАМЕНА: вставьте весь файл в Supabase SQL Editor и Run.
-- Зависимости: public.conversation_participants, public.chat_messages (в т.ч.
-- deleted_at), public.user_in_conversation(uuid) — как в миграциях чатов.
-- Идемпотентно: add column if not exists, create or replace, grant/revoke.
-- Realtime: при публикации supabase_realtime в режиме FOR ALL TABLES — ок;
-- иначе включите chat_messages и conversation_participants в Dashboard → Realtime.
-- =============================================================================

alter table public.conversation_participants
  add column if not exists last_read_at timestamptz;

-- ---------------------------------------------------------------------------
-- mark_conversation_read: курсор = время последнего видимого сообщения (или now).
-- ---------------------------------------------------------------------------
create or replace function public.mark_conversation_read(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'not auth' using errcode = 'P0001';
  end if;
  if not public.user_in_conversation(p_conversation_id) then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;
  update public.conversation_participants cp
  set last_read_at = coalesce(
    (select max(m.created_at) from public.chat_messages m
     where m.conversation_id = p_conversation_id
       and m.deleted_at is null),
    now()
  )
  where cp.conversation_id = p_conversation_id
    and cp.user_id = auth.uid();
end;
$$;

revoke all on function public.mark_conversation_read(uuid) from public;
grant execute on function public.mark_conversation_read(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Есть ли у текущего пользователя непрочитанные входящие (для бейджа).
-- ---------------------------------------------------------------------------
create or replace function public.has_unread_messages_for_me()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.conversation_participants cp
    join public.chat_messages m
      on m.conversation_id = cp.conversation_id
    where cp.user_id = auth.uid()
      and m.sender_id <> auth.uid()
      and m.deleted_at is null
      and m.created_at > coalesce(cp.last_read_at, to_timestamp(0) at time zone 'utc')
  );
$$;

revoke all on function public.has_unread_messages_for_me() from public;
grant execute on function public.has_unread_messages_for_me() to authenticated;

-- ---------------------------------------------------------------------------
-- id бесед с непрочитанным (для списка чатов).
-- ---------------------------------------------------------------------------
create or replace function public.get_unread_conversation_ids()
returns uuid[]
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    array(
      select distinct m.conversation_id
      from public.conversation_participants cp
      join public.chat_messages m
        on m.conversation_id = cp.conversation_id
      where cp.user_id = auth.uid()
        and m.sender_id <> auth.uid()
        and m.deleted_at is null
        and m.created_at > coalesce(cp.last_read_at, to_timestamp(0) at time zone 'utc')
    ),
    '{}'::uuid[]
  );
$$;

revoke all on function public.get_unread_conversation_ids() from public;
grant execute on function public.get_unread_conversation_ids() to authenticated;

-- Realtime: если публикация supabase_realtime в режиме FOR ALL TABLES, отдельно
-- таблицу в publication добавлять не нужно. Иначе: Dashboard → Realtime / SQL.



-- >>>>>> BEGIN FILE: 013_app_config_ci.sql <<<<<<

-- Конфиг для проверки обновлений APK (CI → GitHub Actions → Supabase REST).
-- Запись: только service_role (в обход RLS). Чтение: публично (anon + authenticated).

create table if not exists public.app_config (
  id text primary key default 'default',
  version_code int not null default 1,
  download_url text,
  updated_at timestamptz not null default now()
);

insert into public.app_config (id, version_code, download_url)
values ('default', 1, null)
on conflict (id) do nothing;

create or replace function public.app_config_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists tr_app_config_updated on public.app_config;
create trigger tr_app_config_updated
  before insert or update on public.app_config
  for each row execute function public.app_config_touch_updated_at();

alter table public.app_config enable row level security;

drop policy if exists p_app_config_select on public.app_config;
create policy p_app_config_select
  on public.app_config
  for select
  to anon, authenticated
  using (true);

-- Вставка/обновление из клиента идут через service_role (GitHub Actions), RLS обходится.
-- Не создаём policy INSERT/UPDATE для authenticated.

grant select on public.app_config to anon, authenticated;
grant all on public.app_config to service_role;

