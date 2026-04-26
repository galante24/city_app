-- Аватар в профиле + загрузка вложений в чат (storage city_media)

alter table public.profiles
  add column if not exists avatar_url text;

comment on column public.profiles.avatar_url is 'Публичный URL в city_media/avatars/<uid>/...';

-- avatars/<uid>/...
drop policy if exists "city media avatars insert own" on storage.objects;
create policy "city media avatars insert own"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'avatars'
    and split_part(name, '/', 2) = auth.uid()::text
  );

drop policy if exists "city media avatars update own" on storage.objects;
create policy "city media avatars update own"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'avatars'
    and split_part(name, '/', 2) = auth.uid()::text
  )
  with check (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'avatars'
    and split_part(name, '/', 2) = auth.uid()::text
  );

drop policy if exists "city media avatars delete own" on storage.objects;
create policy "city media avatars delete own"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'avatars'
    and split_part(name, '/', 2) = auth.uid()::text
  );

-- chat_media/<uid>/...
drop policy if exists "city media chat insert own" on storage.objects;
create policy "city media chat insert own"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'chat_media'
    and split_part(name, '/', 2) = auth.uid()::text
  );

drop policy if exists "city media chat update own" on storage.objects;
create policy "city media chat update own"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'chat_media'
    and split_part(name, '/', 2) = auth.uid()::text
  )
  with check (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'chat_media'
    and split_part(name, '/', 2) = auth.uid()::text
  );

drop policy if exists "city media chat delete own" on storage.objects;
create policy "city media chat delete own"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'chat_media'
    and split_part(name, '/', 2) = auth.uid()::text
  );
