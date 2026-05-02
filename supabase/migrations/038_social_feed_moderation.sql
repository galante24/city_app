-- Социальная лента: роли, посты (категории + галерея), комментарии, лайки, уведомления,
-- жёсткое удаление строк + физическое удаление файлов storage (триггеры SECURITY DEFINER).

-- ---------- profiles: роли ленты (полный admin = is_profiles_admin) ----------
alter table public.profiles
  add column if not exists feed_role text not null default 'user'
    check (feed_role in ('user', 'moderator_news', 'moderator_important'));

comment on column public.profiles.feed_role is
  'Лента: user | moderator_news (СМИ) | moderator_important (Важные). Полный admin — is_admin.';

-- ---------- posts ----------
alter table public.posts
  add column if not exists category text not null default 'discussion'
    check (category in ('smi', 'administration', 'discussion'));

alter table public.posts
  add column if not exists image_urls text[] not null default '{}';

alter table public.posts
  add column if not exists likes_count integer not null default 0;

alter table public.posts
  add column if not exists comments_count integer not null default 0;

alter table public.posts
  add column if not exists updated_at timestamptz not null default now();

update public.posts set updated_at = created_at where updated_at is null;

alter table public.posts drop constraint if exists posts_user_id_fkey;
alter table public.posts
  add constraint posts_user_id_fkey
    foreign key (user_id) references public.profiles (id) on delete cascade;

create index if not exists posts_category_created_idx
  on public.posts (category, created_at desc);

-- ---------- feed_comments ----------
create table if not exists public.feed_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  parent_id uuid references public.feed_comments (id) on delete cascade,
  body text not null default '',
  image_urls text[] not null default '{}',
  likes_count integer not null default 0,
  created_at timestamptz not null default now()
);

alter table public.feed_comments
  add column if not exists likes_count integer not null default 0;

create index if not exists feed_comments_post_created_idx
  on public.feed_comments (post_id, created_at asc);

create index if not exists feed_comments_parent_idx
  on public.feed_comments (parent_id);

comment on table public.feed_comments is
  'Комментарии городской ленты (ответы через parent_id).';

-- ---------- feed_likes ----------
create table if not exists public.feed_likes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  target_type text not null check (target_type in ('post', 'comment')),
  target_id uuid not null,
  created_at timestamptz not null default now(),
  unique (user_id, target_type, target_id)
);

create index if not exists feed_likes_target_idx
  on public.feed_likes (target_type, target_id);

-- ---------- notifications ----------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  actor_id uuid references public.profiles (id) on delete set null,
  type text not null check (
    type in ('like_post', 'like_comment', 'comment_reply', 'repost')
  ),
  post_id uuid references public.posts (id) on delete cascade,
  comment_id uuid references public.feed_comments (id) on delete cascade,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists notifications_recipient_created_idx
  on public.notifications (recipient_id, created_at desc);

-- ---------- helpers ----------
create or replace function public.feed_effective_role()
returns text
language sql
stable
security invoker
set search_path = public
as $$
  select case
    when coalesce(public.is_profiles_admin(), false) then 'admin'
    else coalesce(
      (select p.feed_role from public.profiles p where p.id = auth.uid()),
      'user'
    )
  end;
$$;

create or replace function public.feed_storage_names_from_urls(urls text[])
returns text[]
language sql
immutable
as $$
  select coalesce(
    array_agg(distinct regexp_replace(trim(u), '^.*\/(?:object\/public\/)?city_media\/', ''))
      filter (where trim(u) <> ''),
    '{}'::text[]
  )
  from unnest(coalesce(urls, '{}'::text[])) as u;
$$;

-- updated_at на постах
create or replace function public.feed_touch_post_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_feed_posts_touch_updated on public.posts;
create trigger trg_feed_posts_touch_updated
  before update on public.posts
  for each row
  execute function public.feed_touch_post_updated_at();

-- Счётчики лайков (пост или комментарий)
create or replace function public.feed_after_feed_like_change()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    if new.target_type = 'post' then
      update public.posts
        set likes_count = likes_count + 1
        where id = new.target_id;
    else
      update public.feed_comments
        set likes_count = likes_count + 1
        where id = new.target_id;
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.target_type = 'post' then
      update public.posts
        set likes_count = greatest(likes_count - 1, 0)
        where id = old.target_id;
    else
      update public.feed_comments
        set likes_count = greatest(likes_count - 1, 0)
        where id = old.target_id;
    end if;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_feed_likes_ins on public.feed_likes;
drop trigger if exists trg_feed_likes_del on public.feed_likes;
create trigger trg_feed_likes_ins
  after insert on public.feed_likes
  for each row
  execute function public.feed_after_feed_like_change();

create trigger trg_feed_likes_del
  after delete on public.feed_likes
  for each row
  execute function public.feed_after_feed_like_change();

-- Счётчик комментариев у поста
create or replace function public.feed_bump_post_comments()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    update public.posts
      set comments_count = comments_count + 1
      where id = new.post_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.posts
      set comments_count = greatest(comments_count - 1, 0)
      where id = old.post_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_feed_comments_count_ins on public.feed_comments;
drop trigger if exists trg_feed_comments_count_del on public.feed_comments;
create trigger trg_feed_comments_count_ins
  after insert on public.feed_comments
  for each row
  execute function public.feed_bump_post_comments();

create trigger trg_feed_comments_count_del
  after delete on public.feed_comments
  for each row
  execute function public.feed_bump_post_comments();

-- Уведомления: лайк
create or replace function public.feed_notify_on_like()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recipient uuid;
  v_post uuid;
  v_kind text;
begin
  if new.target_type = 'post' then
    select p.user_id into v_recipient from public.posts p where p.id = new.target_id;
    v_post := new.target_id;
    v_kind := 'like_post';
  else
    select c.user_id, c.post_id into v_recipient, v_post
    from public.feed_comments c
    where c.id = new.target_id;
    v_kind := 'like_comment';
  end if;
  if v_recipient is null or v_recipient = new.user_id then
    return new;
  end if;
  insert into public.notifications (recipient_id, actor_id, type, post_id, comment_id, payload)
  values (
    v_recipient,
    new.user_id,
    v_kind::text,
    v_post,
    case when new.target_type = 'comment' then new.target_id else null end,
    '{}'::jsonb
  );
  return new;
end;
$$;

drop trigger if exists trg_feed_like_notify on public.feed_likes;
create trigger trg_feed_like_notify
  after insert on public.feed_likes
  for each row
  execute function public.feed_notify_on_like();

-- Ответ на комментарий
create or replace function public.feed_notify_on_comment_reply()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parent_author uuid;
begin
  if new.parent_id is null then
    return new;
  end if;
  select c.user_id into v_parent_author
  from public.feed_comments c
  where c.id = new.parent_id;
  if v_parent_author is null or v_parent_author = new.user_id then
    return new;
  end if;
  insert into public.notifications (recipient_id, actor_id, type, post_id, comment_id, payload)
  values (
    v_parent_author,
    new.user_id,
    'comment_reply',
    new.post_id,
    new.id,
    '{}'::jsonb
  );
  return new;
end;
$$;

drop trigger if exists trg_feed_comment_reply_notify on public.feed_comments;
create trigger trg_feed_comment_reply_notify
  after insert on public.feed_comments
  for each row
  execute function public.feed_notify_on_comment_reply();

-- Лайки комментария при удалении комментария
create or replace function public.feed_cleanup_likes_on_comment_delete()
returns trigger
language plpgsql
as $$
begin
  delete from public.feed_likes
  where target_type = 'comment' and target_id = old.id;
  return old;
end;
$$;

drop trigger if exists trg_feed_comment_del_likes on public.feed_comments;
create trigger trg_feed_comment_del_likes
  before delete on public.feed_comments
  for each row
  execute function public.feed_cleanup_likes_on_comment_delete();

-- Лайки поста при удалении поста
create or replace function public.feed_cleanup_likes_on_post_delete()
returns trigger
language plpgsql
as $$
begin
  delete from public.feed_likes
  where target_type = 'post' and target_id = old.id;
  return old;
end;
$$;

drop trigger if exists trg_feed_post_del_likes on public.posts;
create trigger trg_feed_post_del_likes
  before delete on public.posts
  for each row
  execute function public.feed_cleanup_likes_on_post_delete();

-- Физическое удаление файлов комментария
create or replace function public.feed_purge_comment_storage()
returns trigger
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v_names text[];
begin
  v_names := public.feed_storage_names_from_urls(old.image_urls);
  if cardinality(v_names) = 0 then
    return old;
  end if;
  delete from storage.objects o
  where o.bucket_id = 'city_media'
    and o.name = any (v_names)
    and split_part(o.name, '/', 1) = 'feed_media';
  return old;
end;
$$;

drop trigger if exists trg_feed_comment_purge_files on public.feed_comments;
create trigger trg_feed_comment_purge_files
  before delete on public.feed_comments
  for each row
  execute function public.feed_purge_comment_storage();

-- Физическое удаление файлов поста (комментарии и их файлы удаляются каскадом раньше)
create or replace function public.feed_purge_post_storage()
returns trigger
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v_names text[];
begin
  v_names := public.feed_storage_names_from_urls(old.image_urls);
  if cardinality(v_names) = 0 then
    return old;
  end if;
  delete from storage.objects o
  where o.bucket_id = 'city_media'
    and o.name = any (v_names)
    and split_part(o.name, '/', 1) = 'feed_media';
  return old;
end;
$$;

drop trigger if exists trg_feed_post_purge_files on public.posts;
create trigger trg_feed_post_purge_files
  before delete on public.posts
  for each row
  execute function public.feed_purge_post_storage();

-- ---------- storage: feed_media/<uid>/... ----------
drop policy if exists "city media feed insert own" on storage.objects;
create policy "city media feed insert own"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'feed_media'
    and split_part(name, '/', 2) = auth.uid()::text
  );

drop policy if exists "city media feed update own" on storage.objects;
create policy "city media feed update own"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'feed_media'
    and split_part(name, '/', 2) = auth.uid()::text
  )
  with check (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'feed_media'
    and split_part(name, '/', 2) = auth.uid()::text
  );

drop policy if exists "city media feed delete own" on storage.objects;
create policy "city media feed delete own"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'feed_media'
    and split_part(name, '/', 2) = auth.uid()::text
  );

-- ---------- RLS posts ----------
alter table public.posts enable row level security;

drop policy if exists "posts select authenticated" on public.posts;
drop policy if exists "posts insert own row" on public.posts;
drop policy if exists "posts update own row" on public.posts;
drop policy if exists "posts delete own row" on public.posts;
drop policy if exists "feed posts select auth" on public.posts;
drop policy if exists "feed posts insert by role" on public.posts;
drop policy if exists "feed posts update window" on public.posts;
drop policy if exists "feed posts delete by role" on public.posts;

create policy "feed posts select auth"
  on public.posts
  for select
  to authenticated
  using (true);

create policy "feed posts insert by role"
  on public.posts
  for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and (
      public.feed_effective_role() = 'admin'
      or (
        public.feed_effective_role() = 'moderator_news'
        and category = 'smi'
      )
      or (
        public.feed_effective_role() = 'moderator_important'
        and category = 'administration'
      )
      or (
        public.feed_effective_role() = 'user'
        and category = 'discussion'
      )
    )
  );

create policy "feed posts update window"
  on public.posts
  for update
  to authenticated
  using (
    public.is_profiles_admin()
    or (
      user_id = auth.uid()
      and created_at > now() - interval '10 minutes'
    )
  )
  with check (
    public.is_profiles_admin()
    or (
      user_id = auth.uid()
      and created_at > now() - interval '10 minutes'
    )
  );

create policy "feed posts delete by role"
  on public.posts
  for delete
  to authenticated
  using (
    public.feed_effective_role() = 'admin'
    or (
      public.feed_effective_role() = 'moderator_news'
      and category = 'smi'
    )
    or (
      public.feed_effective_role() = 'moderator_important'
      and category = 'administration'
    )
    or (
      user_id = auth.uid()
      and category = 'discussion'
    )
  );

-- ---------- RLS feed_comments ----------
alter table public.feed_comments enable row level security;

drop policy if exists "feed comments select" on public.feed_comments;
drop policy if exists "feed comments insert" on public.feed_comments;
drop policy if exists "feed comments delete" on public.feed_comments;

create policy "feed comments select"
  on public.feed_comments
  for select
  to authenticated
  using (true);

create policy "feed comments insert"
  on public.feed_comments
  for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "feed comments delete"
  on public.feed_comments
  for delete
  to authenticated
  using (
    user_id = auth.uid()
    or public.feed_effective_role() = 'admin'
    or exists (
      select 1
      from public.posts p
      where p.id = feed_comments.post_id
        and public.feed_effective_role() = 'moderator_news'
        and p.category = 'smi'
    )
    or exists (
      select 1
      from public.posts p
      where p.id = feed_comments.post_id
        and public.feed_effective_role() = 'moderator_important'
        and p.category = 'administration'
    )
  );

-- ---------- RLS feed_likes ----------
alter table public.feed_likes enable row level security;

drop policy if exists "feed likes select" on public.feed_likes;
drop policy if exists "feed likes insert own" on public.feed_likes;
drop policy if exists "feed likes delete own" on public.feed_likes;

create policy "feed likes select"
  on public.feed_likes
  for select
  to authenticated
  using (true);

create policy "feed likes insert own"
  on public.feed_likes
  for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "feed likes delete own"
  on public.feed_likes
  for delete
  to authenticated
  using (auth.uid() = user_id);

-- ---------- RLS notifications ----------
alter table public.notifications enable row level security;

drop policy if exists "notifications select own" on public.notifications;
drop policy if exists "notifications update own read" on public.notifications;
drop policy if exists "notifications insert repost" on public.notifications;

create policy "notifications select own"
  on public.notifications
  for select
  to authenticated
  using (recipient_id = auth.uid());

create policy "notifications update own read"
  on public.notifications
  for update
  to authenticated
  using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());

create policy "notifications insert repost"
  on public.notifications
  for insert
  to authenticated
  with check (
    type = 'repost'
    and actor_id = auth.uid()
    and recipient_id is not null
    and post_id is not null
  );

-- ---------- Realtime ----------
-- Пропуск ADD TABLE, если publication = FOR ALL TABLES (типично для Supabase Cloud).
do $$
begin
  if not exists (
    select 1 from pg_publication p
    where p.pubname = 'supabase_realtime' and not p.puballtables
  ) then
    return;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'feed_comments'
  ) then
    alter publication supabase_realtime add table public.feed_comments;
  end if;
exception
  when duplicate_object then null;
  when others then null;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_publication p
    where p.pubname = 'supabase_realtime' and not p.puballtables
  ) then
    return;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'feed_likes'
  ) then
    alter publication supabase_realtime add table public.feed_likes;
  end if;
exception
  when duplicate_object then null;
  when others then null;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_publication p
    where p.pubname = 'supabase_realtime' and not p.puballtables
  ) then
    return;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
exception
  when duplicate_object then null;
  when others then null;
end $$;

-- ---------- Синхронизация счётчиков (после миграции с пустыми likes) ----------
update public.posts p
set likes_count = coalesce((
  select count(*)::int from public.feed_likes l
  where l.target_type = 'post' and l.target_id = p.id
), 0);

update public.posts p
set comments_count = coalesce((
  select count(*)::int from public.feed_comments c
  where c.post_id = p.id
), 0);

update public.feed_comments c
set likes_count = coalesce((
  select count(*)::int from public.feed_likes l
  where l.target_type = 'comment' and l.target_id = c.id
), 0);
