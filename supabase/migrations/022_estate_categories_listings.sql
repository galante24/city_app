-- Объявления: дача, дом, квартира, участок, коммерция (поле property_address).
-- Правила как у garage_listings / job_vacancies.

-- ---------- Дача ----------
create table if not exists public.dacha_listings (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  description text not null,
  price text not null default '',
  property_address text not null default '',
  contact_phone text not null,
  image_url text,
  created_at timestamptz not null default now()
);
create index if not exists dacha_listings_created_at_idx
  on public.dacha_listings (created_at desc);
create index if not exists dacha_listings_author_idx
  on public.dacha_listings (author_id);
alter table public.dacha_listings enable row level security;
drop policy if exists "dacha_listings read auth" on public.dacha_listings;
create policy "dacha_listings read auth" on public.dacha_listings for select to authenticated using (true);
drop policy if exists "dacha_listings insert own" on public.dacha_listings;
create policy "dacha_listings insert own" on public.dacha_listings for insert to authenticated with check (author_id = auth.uid());
drop policy if exists "dacha_listings update own or admin" on public.dacha_listings;
create policy "dacha_listings update own or admin" on public.dacha_listings for update to authenticated
  using (author_id = auth.uid() or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true))
  with check (author_id = auth.uid() or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));
drop policy if exists "dacha_listings delete own or admin" on public.dacha_listings;
create policy "dacha_listings delete own or admin" on public.dacha_listings for delete to authenticated
  using (author_id = auth.uid() or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));

-- ---------- Дом ----------
create table if not exists public.house_listings (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  description text not null,
  price text not null default '',
  property_address text not null default '',
  contact_phone text not null,
  image_url text,
  created_at timestamptz not null default now()
);
create index if not exists house_listings_created_at_idx on public.house_listings (created_at desc);
create index if not exists house_listings_author_idx on public.house_listings (author_id);
alter table public.house_listings enable row level security;
drop policy if exists "house_listings read auth" on public.house_listings;
create policy "house_listings read auth" on public.house_listings for select to authenticated using (true);
drop policy if exists "house_listings insert own" on public.house_listings;
create policy "house_listings insert own" on public.house_listings for insert to authenticated with check (author_id = auth.uid());
drop policy if exists "house_listings update own or admin" on public.house_listings;
create policy "house_listings update own or admin" on public.house_listings for update to authenticated
  using (author_id = auth.uid() or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true))
  with check (author_id = auth.uid() or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));
drop policy if exists "house_listings delete own or admin" on public.house_listings;
create policy "house_listings delete own or admin" on public.house_listings for delete to authenticated
  using (author_id = auth.uid() or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));

-- ---------- Квартира ----------
create table if not exists public.apartment_listings (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  description text not null,
  price text not null default '',
  property_address text not null default '',
  contact_phone text not null,
  image_url text,
  created_at timestamptz not null default now()
);
create index if not exists apartment_listings_created_at_idx on public.apartment_listings (created_at desc);
create index if not exists apartment_listings_author_idx on public.apartment_listings (author_id);
alter table public.apartment_listings enable row level security;
drop policy if exists "apartment_listings read auth" on public.apartment_listings;
create policy "apartment_listings read auth" on public.apartment_listings for select to authenticated using (true);
drop policy if exists "apartment_listings insert own" on public.apartment_listings;
create policy "apartment_listings insert own" on public.apartment_listings for insert to authenticated with check (author_id = auth.uid());
drop policy if exists "apartment_listings update own or admin" on public.apartment_listings;
create policy "apartment_listings update own or admin" on public.apartment_listings for update to authenticated
  using (author_id = auth.uid() or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true))
  with check (author_id = auth.uid() or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));
drop policy if exists "apartment_listings delete own or admin" on public.apartment_listings;
create policy "apartment_listings delete own or admin" on public.apartment_listings for delete to authenticated
  using (author_id = auth.uid() or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));

-- ---------- Участок ----------
create table if not exists public.land_listings (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  description text not null,
  price text not null default '',
  property_address text not null default '',
  contact_phone text not null,
  image_url text,
  created_at timestamptz not null default now()
);
create index if not exists land_listings_created_at_idx on public.land_listings (created_at desc);
create index if not exists land_listings_author_idx on public.land_listings (author_id);
alter table public.land_listings enable row level security;
drop policy if exists "land_listings read auth" on public.land_listings;
create policy "land_listings read auth" on public.land_listings for select to authenticated using (true);
drop policy if exists "land_listings insert own" on public.land_listings;
create policy "land_listings insert own" on public.land_listings for insert to authenticated with check (author_id = auth.uid());
drop policy if exists "land_listings update own or admin" on public.land_listings;
create policy "land_listings update own or admin" on public.land_listings for update to authenticated
  using (author_id = auth.uid() or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true))
  with check (author_id = auth.uid() or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));
drop policy if exists "land_listings delete own or admin" on public.land_listings;
create policy "land_listings delete own or admin" on public.land_listings for delete to authenticated
  using (author_id = auth.uid() or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));

-- ---------- Коммерческая ----------
create table if not exists public.commercial_listings (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  description text not null,
  price text not null default '',
  property_address text not null default '',
  contact_phone text not null,
  image_url text,
  created_at timestamptz not null default now()
);
create index if not exists commercial_listings_created_at_idx on public.commercial_listings (created_at desc);
create index if not exists commercial_listings_author_idx on public.commercial_listings (author_id);
alter table public.commercial_listings enable row level security;
drop policy if exists "commercial_listings read auth" on public.commercial_listings;
create policy "commercial_listings read auth" on public.commercial_listings for select to authenticated using (true);
drop policy if exists "commercial_listings insert own" on public.commercial_listings;
create policy "commercial_listings insert own" on public.commercial_listings for insert to authenticated with check (author_id = auth.uid());
drop policy if exists "commercial_listings update own or admin" on public.commercial_listings;
create policy "commercial_listings update own or admin" on public.commercial_listings for update to authenticated
  using (author_id = auth.uid() or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true))
  with check (author_id = auth.uid() or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));
drop policy if exists "commercial_listings delete own or admin" on public.commercial_listings;
create policy "commercial_listings delete own or admin" on public.commercial_listings for delete to authenticated
  using (author_id = auth.uid() or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));

-- ---------- Storage city_media ----------
drop policy if exists "city media dachas insert own" on storage.objects;
create policy "city media dachas insert own" on storage.objects for insert to authenticated
  with check (bucket_id = 'city_media' and split_part(name, '/', 1) = 'dachas' and split_part(name, '/', 2) = auth.uid()::text);
drop policy if exists "city media dachas update own" on storage.objects;
create policy "city media dachas update own" on storage.objects for update to authenticated
  using (bucket_id = 'city_media' and split_part(name, '/', 1) = 'dachas' and split_part(name, '/', 2) = auth.uid()::text)
  with check (bucket_id = 'city_media' and split_part(name, '/', 1) = 'dachas' and split_part(name, '/', 2) = auth.uid()::text);
drop policy if exists "city media dachas delete own" on storage.objects;
create policy "city media dachas delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'city_media' and split_part(name, '/', 1) = 'dachas' and split_part(name, '/', 2) = auth.uid()::text);

drop policy if exists "city media houses insert own" on storage.objects;
create policy "city media houses insert own" on storage.objects for insert to authenticated
  with check (bucket_id = 'city_media' and split_part(name, '/', 1) = 'houses' and split_part(name, '/', 2) = auth.uid()::text);
drop policy if exists "city media houses update own" on storage.objects;
create policy "city media houses update own" on storage.objects for update to authenticated
  using (bucket_id = 'city_media' and split_part(name, '/', 1) = 'houses' and split_part(name, '/', 2) = auth.uid()::text)
  with check (bucket_id = 'city_media' and split_part(name, '/', 1) = 'houses' and split_part(name, '/', 2) = auth.uid()::text);
drop policy if exists "city media houses delete own" on storage.objects;
create policy "city media houses delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'city_media' and split_part(name, '/', 1) = 'houses' and split_part(name, '/', 2) = auth.uid()::text);

drop policy if exists "city media apartments insert own" on storage.objects;
create policy "city media apartments insert own" on storage.objects for insert to authenticated
  with check (bucket_id = 'city_media' and split_part(name, '/', 1) = 'apartments' and split_part(name, '/', 2) = auth.uid()::text);
drop policy if exists "city media apartments update own" on storage.objects;
create policy "city media apartments update own" on storage.objects for update to authenticated
  using (bucket_id = 'city_media' and split_part(name, '/', 1) = 'apartments' and split_part(name, '/', 2) = auth.uid()::text)
  with check (bucket_id = 'city_media' and split_part(name, '/', 1) = 'apartments' and split_part(name, '/', 2) = auth.uid()::text);
drop policy if exists "city media apartments delete own" on storage.objects;
create policy "city media apartments delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'city_media' and split_part(name, '/', 1) = 'apartments' and split_part(name, '/', 2) = auth.uid()::text);

drop policy if exists "city media land plots insert own" on storage.objects;
create policy "city media land plots insert own" on storage.objects for insert to authenticated
  with check (bucket_id = 'city_media' and split_part(name, '/', 1) = 'land_plots' and split_part(name, '/', 2) = auth.uid()::text);
drop policy if exists "city media land plots update own" on storage.objects;
create policy "city media land plots update own" on storage.objects for update to authenticated
  using (bucket_id = 'city_media' and split_part(name, '/', 1) = 'land_plots' and split_part(name, '/', 2) = auth.uid()::text)
  with check (bucket_id = 'city_media' and split_part(name, '/', 1) = 'land_plots' and split_part(name, '/', 2) = auth.uid()::text);
drop policy if exists "city media land plots delete own" on storage.objects;
create policy "city media land plots delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'city_media' and split_part(name, '/', 1) = 'land_plots' and split_part(name, '/', 2) = auth.uid()::text);

drop policy if exists "city media commercial listings insert own" on storage.objects;
create policy "city media commercial listings insert own" on storage.objects for insert to authenticated
  with check (bucket_id = 'city_media' and split_part(name, '/', 1) = 'commercial_listings' and split_part(name, '/', 2) = auth.uid()::text);
drop policy if exists "city media commercial listings update own" on storage.objects;
create policy "city media commercial listings update own" on storage.objects for update to authenticated
  using (bucket_id = 'city_media' and split_part(name, '/', 1) = 'commercial_listings' and split_part(name, '/', 2) = auth.uid()::text)
  with check (bucket_id = 'city_media' and split_part(name, '/', 1) = 'commercial_listings' and split_part(name, '/', 2) = auth.uid()::text);
drop policy if exists "city media commercial listings delete own" on storage.objects;
create policy "city media commercial listings delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'city_media' and split_part(name, '/', 1) = 'commercial_listings' and split_part(name, '/', 2) = auth.uid()::text);
