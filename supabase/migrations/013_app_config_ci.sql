-- Конфиг для проверки обновлений APK (CI → GitHub Actions → Supabase REST).
-- Запись: только service_role (в обход RLS). Чтение: публично (anon + authenticated).

create table if not exists public.app_config (
  id text primary key default 'default',
  version_code int not null default 1,
  download_url text,
  updated_at timestamptz not null default now()
);

insert into public.app_config (id, version_code, download_url)
values ('default', 1, null)
on conflict (id) do nothing;

create or replace function public.app_config_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists tr_app_config_updated on public.app_config;
create trigger tr_app_config_updated
  before insert or update on public.app_config
  for each row execute function public.app_config_touch_updated_at();

alter table public.app_config enable row level security;

drop policy if exists p_app_config_select on public.app_config;
create policy p_app_config_select
  on public.app_config
  for select
  to anon, authenticated
  using (true);

-- Вставка/обновление из клиента идут через service_role (GitHub Actions), RLS обходится.
-- Не создаём policy INSERT/UPDATE для authenticated.

grant select on public.app_config to anon, authenticated;
grant all on public.app_config to service_role;
