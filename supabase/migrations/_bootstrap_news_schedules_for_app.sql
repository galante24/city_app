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
