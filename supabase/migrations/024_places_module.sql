-- Модуль «Заведения»: места, модераторы, подписки, посты, лайки, комментарии.
-- Поиск модераторов в приложении по profiles.username (ник).

-- ---------- profiles ----------
alter table public.profiles add column if not exists fcm_token text;
alter table public.profiles add column if not exists notifications_enabled boolean not null default true;
comment on column public.profiles.fcm_token is 'FCM токен устройства для push (опционально)';
comment on column public.profiles.notifications_enabled is 'Глобально принимать push по заведениям';

-- ---------- places ----------
create table if not exists public.places (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  photo_url text,
  cover_url text,
  description text not null default '',
  menu text not null default '',
  promotions text not null default '',
  news text not null default '',
  phone text not null default '',
  owner_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists places_owner_idx on public.places (owner_id);
create index if not exists places_created_idx on public.places (created_at desc);

-- ---------- place_moderators ----------
create table if not exists public.place_moderators (
  place_id uuid not null references public.places (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (place_id, user_id)
);
create index if not exists place_moderators_user_idx on public.place_moderators (user_id);

-- ---------- place_subscriptions ----------
create table if not exists public.place_subscriptions (
  user_id uuid not null references auth.users (id) on delete cascade,
  place_id uuid not null references public.places (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, place_id)
);
create index if not exists place_subscriptions_place_idx on public.place_subscriptions (place_id);

-- ---------- place_posts (лента новостей/акций) ----------
create table if not exists public.place_posts (
  id uuid primary key default gen_random_uuid(),
  place_id uuid not null references public.places (id) on delete cascade,
  author_id uuid not null references auth.users (id) on delete cascade,
  content text not null default '',
  image_url text,
  likes_count int not null default 0,
  notify_subscribers boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists place_posts_place_idx on public.place_posts (place_id, created_at desc);

-- ---------- place_post_likes ----------
create table if not exists public.place_post_likes (
  post_id uuid not null references public.place_posts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create or replace function public.sync_place_post_likes_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.place_posts
      set likes_count = coalesce(likes_count, 0) + 1
      where id = new.post_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.place_posts
      set likes_count = greatest(0, coalesce(likes_count, 0) - 1)
      where id = old.post_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_place_post_likes_ai on public.place_post_likes;
create trigger trg_place_post_likes_ai
  after insert on public.place_post_likes
  for each row execute function public.sync_place_post_likes_count();

drop trigger if exists trg_place_post_likes_ad on public.place_post_likes;
create trigger trg_place_post_likes_ad
  after delete on public.place_post_likes
  for each row execute function public.sync_place_post_likes_count();

-- ---------- place_post_comments ----------
create table if not exists public.place_post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.place_posts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now()
);
create index if not exists place_post_comments_post_idx
  on public.place_post_comments (post_id, created_at);

-- ---------- Helpers ----------
create or replace function public.is_profiles_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.is_admin = true
  );
$$;

create or replace function public.can_moderate_place(p_place uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_profiles_admin()
    or exists (
      select 1 from public.place_moderators pm
      where pm.place_id = p_place and pm.user_id = auth.uid()
    );
$$;

-- ---------- RLS ----------
alter table public.places enable row level security;
alter table public.place_moderators enable row level security;
alter table public.place_subscriptions enable row level security;
alter table public.place_posts enable row level security;
alter table public.place_post_likes enable row level security;
alter table public.place_post_comments enable row level security;

-- places
drop policy if exists "places read auth" on public.places;
create policy "places read auth" on public.places
  for select to authenticated using (true);

drop policy if exists "places insert admin" on public.places;
create policy "places insert admin" on public.places
  for insert to authenticated
  with check (public.is_profiles_admin());

drop policy if exists "places update mod" on public.places;
create policy "places update mod" on public.places
  for update to authenticated
  using (public.can_moderate_place(id))
  with check (public.can_moderate_place(id));

drop policy if exists "places delete admin" on public.places;
create policy "places delete admin" on public.places
  for delete to authenticated
  using (public.is_profiles_admin());

-- place_moderators
drop policy if exists "place_mod read auth" on public.place_moderators;
create policy "place_mod read auth" on public.place_moderators
  for select to authenticated using (true);

drop policy if exists "place_mod insert admin" on public.place_moderators;
create policy "place_mod insert admin" on public.place_moderators
  for insert to authenticated
  with check (public.is_profiles_admin());

drop policy if exists "place_mod delete admin" on public.place_moderators;
create policy "place_mod delete admin" on public.place_moderators
  for delete to authenticated
  using (public.is_profiles_admin());

-- place_subscriptions
drop policy if exists "place_sub read own or mod" on public.place_subscriptions;
create policy "place_sub read own or mod" on public.place_subscriptions
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.can_moderate_place(place_id)
    or public.is_profiles_admin()
  );

drop policy if exists "place_sub insert own" on public.place_subscriptions;
create policy "place_sub insert own" on public.place_subscriptions
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "place_sub delete own" on public.place_subscriptions;
create policy "place_sub delete own" on public.place_subscriptions
  for delete to authenticated
  using (user_id = auth.uid());

-- place_posts
drop policy if exists "place_posts read auth" on public.place_posts;
create policy "place_posts read auth" on public.place_posts
  for select to authenticated using (true);

drop policy if exists "place_posts insert mod" on public.place_posts;
create policy "place_posts insert mod" on public.place_posts
  for insert to authenticated
  with check (
    author_id = auth.uid()
    and public.can_moderate_place(place_id)
  );

drop policy if exists "place_posts update mod" on public.place_posts;
create policy "place_posts update mod" on public.place_posts
  for update to authenticated
  using (public.can_moderate_place(place_id))
  with check (public.can_moderate_place(place_id));

drop policy if exists "place_posts delete mod" on public.place_posts;
create policy "place_posts delete mod" on public.place_posts
  for delete to authenticated
  using (public.can_moderate_place(place_id));

-- place_post_likes
drop policy if exists "place_likes read" on public.place_post_likes;
create policy "place_likes read" on public.place_post_likes
  for select to authenticated using (true);

drop policy if exists "place_likes insert own" on public.place_post_likes;
create policy "place_likes insert own" on public.place_post_likes
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "place_likes delete own" on public.place_post_likes;
create policy "place_likes delete own" on public.place_post_likes
  for delete to authenticated
  using (user_id = auth.uid());

-- place_post_comments
drop policy if exists "place_comments read" on public.place_post_comments;
create policy "place_comments read" on public.place_post_comments
  for select to authenticated using (true);

drop policy if exists "place_comments insert own" on public.place_post_comments;
create policy "place_comments insert own" on public.place_post_comments
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "place_comments delete own" on public.place_post_comments;
create policy "place_comments delete own" on public.place_post_comments
  for delete to authenticated
  using (user_id = auth.uid() or public.is_profiles_admin());

-- ---------- Storage city_media: places/<uid>/... ----------
drop policy if exists "city media places insert own" on storage.objects;
create policy "city media places insert own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'places'
    and split_part(name, '/', 2) = auth.uid()::text
  );

drop policy if exists "city media places update own" on storage.objects;
create policy "city media places update own" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'places'
    and split_part(name, '/', 2) = auth.uid()::text
  )
  with check (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'places'
    and split_part(name, '/', 2) = auth.uid()::text
  );

drop policy if exists "city media places delete own" on storage.objects;
create policy "city media places delete own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'places'
    and split_part(name, '/', 2) = auth.uid()::text
  );
