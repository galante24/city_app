-- Объявления гаражей: те же правила, что у job_vacancies (автор / админ).

create table if not exists public.garage_listings (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  description text not null,
  price text not null default '',
  garage_address text not null default '',
  contact_phone text not null,
  image_url text,
  created_at timestamptz not null default now()
);

create index if not exists garage_listings_created_at_idx
  on public.garage_listings (created_at desc);
create index if not exists garage_listings_author_idx
  on public.garage_listings (author_id);

alter table public.garage_listings enable row level security;

drop policy if exists "garage_listings read auth" on public.garage_listings;
create policy "garage_listings read auth"
  on public.garage_listings
  for select
  to authenticated
  using (true);

drop policy if exists "garage_listings insert own" on public.garage_listings;
create policy "garage_listings insert own"
  on public.garage_listings
  for insert
  to authenticated
  with check (author_id = auth.uid());

drop policy if exists "garage_listings update own or admin" on public.garage_listings;
create policy "garage_listings update own or admin"
  on public.garage_listings
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

drop policy if exists "garage_listings delete own or admin" on public.garage_listings;
create policy "garage_listings delete own or admin"
  on public.garage_listings
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

-- Фото в city_media: путь garages/<uid>/...
drop policy if exists "city media garages insert own" on storage.objects;
create policy "city media garages insert own"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'garages'
    and split_part(name, '/', 2) = auth.uid()::text
  );

drop policy if exists "city media garages update own" on storage.objects;
create policy "city media garages update own"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'garages'
    and split_part(name, '/', 2) = auth.uid()::text
  )
  with check (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'garages'
    and split_part(name, '/', 2) = auth.uid()::text
  );

drop policy if exists "city media garages delete own" on storage.objects;
create policy "city media garages delete own"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'city_media'
    and split_part(name, '/', 1) = 'garages'
    and split_part(name, '/', 2) = auth.uid()::text
  );
