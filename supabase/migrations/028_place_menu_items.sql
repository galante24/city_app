-- Цифровое меню заведений (витрина позиций).

create table if not exists public.menu_items (
  id uuid primary key default gen_random_uuid(),
  place_id uuid not null references public.places (id) on delete cascade,
  title text not null default '',
  description text not null default '',
  category text not null default '',
  price numeric(12, 2) not null default 0,
  old_price numeric(12, 2),
  photo_url text,
  is_available boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists menu_items_place_category_idx
  on public.menu_items (place_id, category, created_at desc);

alter table public.menu_items enable row level security;

drop policy if exists "menu_items read auth" on public.menu_items;
create policy "menu_items read auth" on public.menu_items
  for select to authenticated using (true);

drop policy if exists "menu_items insert mod" on public.menu_items;
create policy "menu_items insert mod" on public.menu_items
  for insert to authenticated
  with check (public.can_moderate_place(place_id));

drop policy if exists "menu_items update mod" on public.menu_items;
create policy "menu_items update mod" on public.menu_items
  for update to authenticated
  using (public.can_moderate_place(place_id))
  with check (public.can_moderate_place(place_id));

drop policy if exists "menu_items delete mod" on public.menu_items;
create policy "menu_items delete mod" on public.menu_items
  for delete to authenticated
  using (public.can_moderate_place(place_id));
