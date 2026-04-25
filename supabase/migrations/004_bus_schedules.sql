-- Таблица расписаний автобусов
create table if not exists public.bus_schedules (
  id uuid primary key default gen_random_uuid(),
  route_number text not null,
  destination text not null,
  departure_times jsonb not null default '[]'::jsonb,
  updated_at timestamptz
);

alter table public.bus_schedules enable row level security;

drop policy if exists "bus schedules public read" on public.bus_schedules;
create policy "bus schedules public read" on public.bus_schedules
  for select using (true);

drop policy if exists "bus schedules admin all" on public.bus_schedules;
create policy "bus schedules admin all" on public.bus_schedules
  for all to authenticated
  using (lower(coalesce(auth.jwt() ->> 'email', '')) = 'sranometrr@gmail.com')
  with check (lower(coalesce(auth.jwt() ->> 'email', '')) = 'sranometrr@gmail.com');

-- Realtime: включите public.bus_schedules в Database → Replication
