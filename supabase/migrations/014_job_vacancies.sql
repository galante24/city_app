-- Вакансии: публикация авторизованными, удаление — автор или админ (profiles.is_admin).

create table if not exists public.job_vacancies (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  description text not null,
  salary text not null default '',
  work_address text not null default '',
  contact_phone text not null,
  image_url text,
  created_at timestamptz not null default now()
);

create index if not exists job_vacancies_created_at_idx
  on public.job_vacancies (created_at desc);
create index if not exists job_vacancies_author_idx
  on public.job_vacancies (author_id);

alter table public.job_vacancies enable row level security;

drop policy if exists "job_vacancies read auth" on public.job_vacancies;
create policy "job_vacancies read auth"
  on public.job_vacancies
  for select
  to authenticated
  using (true);

drop policy if exists "job_vacancies insert own" on public.job_vacancies;
create policy "job_vacancies insert own"
  on public.job_vacancies
  for insert
  to authenticated
  with check (author_id = auth.uid());

drop policy if exists "job_vacancies update own or admin" on public.job_vacancies;
create policy "job_vacancies update own or admin"
  on public.job_vacancies
  for update
  to authenticated
  using (
    author_id = auth.uid()
    or exists (
      select 1
      from public.profiles p
      where p.id = auth.uid() and p.is_admin = true
    )
  )
  with check (
    author_id = auth.uid()
    or exists (
      select 1
      from public.profiles p
      where p.id = auth.uid() and p.is_admin = true
    )
  );

drop policy if exists "job_vacancies delete own or admin" on public.job_vacancies;
create policy "job_vacancies delete own or admin"
  on public.job_vacancies
  for delete
  to authenticated
  using (
    author_id = auth.uid()
    or exists (
      select 1
      from public.profiles p
      where p.id = auth.uid() and p.is_admin = true
    )
  );

-- Фото в city_media: путь vacancies/<uid>/... (split_part — надёжнее, чем like с UUID)
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
