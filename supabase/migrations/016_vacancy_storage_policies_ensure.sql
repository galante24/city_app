-- Если ранее применялась 014 с условием name LIKE, пересобираем политики (split_part).
-- Идемпотентно: подходит и для «чистой» БД.

drop policy if exists "city media vacancies insert own" on storage.objects;
create policy "city media vacancies insert own"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'vacancies'
    and split_part(name, '/', 2) = auth.uid()::text
  );

drop policy if exists "city media vacancies update own" on storage.objects;
create policy "city media vacancies update own"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'vacancies'
    and split_part(name, '/', 2) = auth.uid()::text
  )
  with check (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'vacancies'
    and split_part(name, '/', 2) = auth.uid()::text
  );

drop policy if exists "city media vacancies delete own" on storage.objects;
create policy "city media vacancies delete own"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'vacancies'
    and split_part(name, '/', 2) = auth.uid()::text
  );
