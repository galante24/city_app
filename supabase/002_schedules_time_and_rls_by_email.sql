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

-- Вставка новостей: только sranometr@gmail.com
create policy "news admin insert by email" on public.news
  for insert to authenticated
  with check (
    lower(coalesce(auth.jwt() ->> 'email', '')) = 'sranometr@gmail.com'
  );

-- Обновление парома
create policy "schedules admin update by email" on public.schedules
  for update to authenticated
  using (
    lower(coalesce(auth.jwt() ->> 'email', '')) = 'sranometr@gmail.com'
  )
  with check (
    lower(coalesce(auth.jwt() ->> 'email', '')) = 'sranometr@gmail.com'
  );

-- Картинки к новостям
create policy "admin upload news images by email" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'news-images' and
    lower(coalesce(auth.jwt() ->> 'email', '')) = 'sranometr@gmail.com'
  );
