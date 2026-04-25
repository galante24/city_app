-- =============================================================================
-- Случайный @username при регистрации (и backfill для профилей без ника).
-- Ники: 3–32 символа, [a-z0-9_], в БД в lower-case (как в set_my_username).
-- Рекомендуется после 007 (группы/чаты). Если 007 ещё не применяли — ниже
-- создаётся только колонка username; остальной функционал чатов из 007 нужен отдельно.
-- =============================================================================

alter table public.profiles
  add column if not exists username text;
create unique index if not exists profiles_username_lower_key
  on public.profiles (lower(username::text))
  where username is not null and btrim(username::text) <> '';

-- Генерация кандидата, не совпадающего с существующими (кроме NULL/пустых)
create or replace function public.internal_unique_random_username()
returns text
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  candidate text;
  i int := 0;
begin
  loop
    -- u + 8 hex = 9 символов, только [a-z0-9]
    candidate := 'u' || substr(md5(random()::text || random()::text || clock_timestamp()::text), 1, 8);
    exit when not exists (
      select 1
      from public.profiles p
      where lower(nullif(btrim(p.username::text), '')) = candidate
    );
    i := i + 1;
    exit when i > 40;
  end loop;
  if i > 40 then
    -- запас: до 32 символов
    candidate := 'u' || encode(gen_random_bytes(15), 'hex');
    candidate := left(candidate, 32);
  end if;
  return candidate;
end;
$$;

-- Не открывать в PostgREST API
revoke all on function public.internal_unique_random_username() from public;
revoke all on function public.internal_unique_random_username() from anon, authenticated, service_role;

-- Новый пользователь: сразу пишем username
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uname text;
begin
  uname := public.internal_unique_random_username();
  insert into public.profiles (id, username) values (new.id, uname)
  on conflict (id) do update set
    username = coalesce(
      nullif(btrim(public.profiles.username::text), ''),
      excluded.username
    );
  return new;
end;
$$;

-- Триггер уже из 001; пересоздаём на всякий случай
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Повтор перед backfill: если верхний ALTER не выполняли, колонка отсутствует
alter table public.profiles
  add column if not exists username text;
create unique index if not exists profiles_username_lower_key
  on public.profiles (lower(username::text))
  where username is not null and btrim(username::text) <> '';

-- Существующие профили без ника: один проход
do $fill$
declare
  r record;
  uname text;
begin
  for r in
    select id
    from public.profiles
    where username is null
       or btrim(username::text) = ''
  loop
    uname := public.internal_unique_random_username();
    update public.profiles
    set username = uname
    where id = r.id;
  end loop;
end;
$fill$;

-- Проверка: select id, username from public.profiles where username is null;
-- Готово.
