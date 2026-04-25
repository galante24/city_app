-- Дата рождения, фамилия; явный WITH CHECK на обновление своего profiles (телефон, ник, ФИО)
alter table public.profiles
  add column if not exists last_name text;
alter table public.profiles
  add column if not exists birth_date date;

drop policy if exists "profiles self update" on public.profiles;
create policy "profiles self update" on public.profiles
  for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Чтение своей строки (без изменения смысла, явно для authenticated)
drop policy if exists "profiles self read" on public.profiles;
create policy "profiles self read" on public.profiles
  for select
  to authenticated
  using (auth.uid() = id);
