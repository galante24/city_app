-- Заменяет 033: убирает profiles SELECT для всех (using true) и вводит узкие правила.
-- + блокировки DM, + find_user_id_by_email только «свой email».

-- ---------------------------------------------------------------------------
-- user_blocks: взаимная блокировка (ни один не может открыть личный чат с другим).
-- ---------------------------------------------------------------------------
create table if not exists public.user_blocks (
  blocker_id uuid not null references auth.users (id) on delete cascade,
  blocked_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint user_blocks_no_self check (blocker_id <> blocked_id)
);

create index if not exists user_blocks_blocked_idx
  on public.user_blocks (blocked_id);

alter table public.user_blocks enable row level security;

drop policy if exists "user_blocks read own" on public.user_blocks;
create policy "user_blocks read own"
  on public.user_blocks
  for select
  to authenticated
  using (blocker_id = auth.uid() or blocked_id = auth.uid());

drop policy if exists "user_blocks insert self as blocker" on public.user_blocks;
create policy "user_blocks insert self as blocker"
  on public.user_blocks
  for insert
  to authenticated
  with check (blocker_id = auth.uid());

drop policy if exists "user_blocks delete own as blocker" on public.user_blocks;
create policy "user_blocks delete own as blocker"
  on public.user_blocks
  for delete
  to authenticated
  using (blocker_id = auth.uid());

grant select, insert, delete on public.user_blocks to authenticated;

-- ---------------------------------------------------------------------------
-- Видимость чужой строки profiles: сам, общая беседа, публичный «автор/участник» в модуле, админ.
-- ---------------------------------------------------------------------------
create or replace function public.profile_is_readable_by_me(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    p_id is not null
    and (
      p_id = auth.uid()
      or exists (
        select 1
        from public.conversation_participants a
        join public.conversation_participants b
          on b.conversation_id = a.conversation_id
        where a.user_id = auth.uid()
          and b.user_id = p_id
      )
      or exists (select 1 from public.tasks t where t.author_id = p_id)
      or exists (select 1 from public.task_comments tc where tc.user_id = p_id)
      or exists (select 1 from public.place_posts pp where pp.author_id = p_id)
      or exists (select 1 from public.place_post_comments pc where pc.user_id = p_id)
      or exists (select 1 from public.job_vacancies j where j.author_id = p_id)
      or exists (select 1 from public.place_moderators pm where pm.user_id = p_id)
      or exists (select 1 from public.dacha_listings x where x.author_id = p_id)
      or exists (select 1 from public.house_listings x where x.author_id = p_id)
      or exists (select 1 from public.apartment_listings x where x.author_id = p_id)
      or exists (select 1 from public.land_listings x where x.author_id = p_id)
      or exists (select 1 from public.commercial_listings x where x.author_id = p_id)
      or exists (select 1 from public.garage_listings x where x.author_id = p_id)
    );
$$;

-- ---------------------------------------------------------------------------
-- RLS profiles: убрать глобальное чтение (033) и дублирующие политики.
-- ---------------------------------------------------------------------------
drop policy if exists "profiles social read authenticated" on public.profiles;
drop policy if exists p_profiles_read_chat_partners on public.profiles;
drop policy if exists "profiles self read" on public.profiles;

create policy "profiles select scoped"
  on public.profiles
  for select
  to authenticated
  using (
    public.profile_is_readable_by_me(id)
    or public.is_profiles_admin()
  );

-- Саморид без JWT (анон) по-прежнему не увидит чужие профили: auth.uid() is null.
-- Политика только для authenticated — совпадает с типичным использованием PostgREST с Bearer.

-- ---------------------------------------------------------------------------
-- email → uuid: только подтверждение «это мой email», без поиска чужих.
-- ---------------------------------------------------------------------------
create or replace function public.find_user_id_by_email(lookup text)
returns uuid
language sql
stable
security definer
set search_path = auth, public, pg_temp
as $$
  select u.id
  from auth.users u
  where u.id = auth.uid()
    and u.email is not null
    and lower(u.email) = lower(btrim(lookup))
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- Личный чат: нельзя создать при взаимной блокировке.
-- (Схема как в 007_group_chats_username: is_group, created_by, role у участников.)
-- ---------------------------------------------------------------------------
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
  if exists (
    select 1
    from public.user_blocks ub
    where (ub.blocker_id = p_other and ub.blocked_id = me)
       or (ub.blocker_id = me and ub.blocked_id = p_other)
  ) then
    raise exception 'blocked' using errcode = 'P0001';
  end if;
  pair := case
    when me::text < p_other::text then me::text || '|' || p_other::text
    else p_other::text || '|' || me::text
  end;
  select c.id
  into conv
  from public.conversations c
  where c.is_direct
    and c.direct_pair_key = pair
  limit 1;
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
