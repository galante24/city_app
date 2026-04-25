-- Имя в профиле (чтение в приложении из public.profiles)
alter table public.profiles add column if not exists first_name text;

-- При обновлении user_metadata (например после signUp) можно синхронизировать вручную
-- либо добавить триггер по необходимости.
