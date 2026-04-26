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
