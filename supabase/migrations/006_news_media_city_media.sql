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
