-- Модуль "Посты": CRUD + RLS для приложения city_app.

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  content text not null,
  created_at timestamptz not null default now(),
  user_id uuid not null references auth.users (id) on delete cascade
);

create index if not exists posts_created_at_desc_idx on public.posts (created_at desc);
create index if not exists posts_user_id_idx on public.posts (user_id);

alter table public.posts enable row level security;

drop policy if exists "posts select authenticated" on public.posts;
create policy "posts select authenticated"
  on public.posts
  for select
  using ( auth.role () = 'authenticated' );

drop policy if exists "posts insert own row" on public.posts;
create policy "posts insert own row"
  on public.posts
  for insert
  with check (
    auth.role () = 'authenticated'
    and auth.uid () is not null
    and auth.uid () = user_id
  );

drop policy if exists "posts update own row" on public.posts;
create policy "posts update own row"
  on public.posts
  for update
  using ( auth.uid () = user_id )
  with check ( auth.uid () = user_id );

drop policy if exists "posts delete own row" on public.posts;
create policy "posts delete own row"
  on public.posts
  for delete
  using ( auth.uid () = user_id );

-- Realtime: на hosted проектах publication часто FOR ALL TABLES — ADD TABLE запрещён.
do $pub$
begin
  if exists (
    select 1
    from pg_publication p
    where p.pubname = 'supabase_realtime'
      and not p.puballtables
  )
  and not exists (
    select 1
    from pg_publication_tables t
    where t.pubname = 'supabase_realtime'
      and t.schemaname = 'public'
      and t.tablename = 'posts'
  ) then
    alter publication supabase_realtime add table public.posts;
  end if;
exception
  when others then
    null;
end $pub$;

-- Seed: три поста — один раз, если таблица ещё пуста (повторный db push без дублей).
insert into public.posts (title, content, user_id)
select
  t.title::text,
  t.body::text,
  u.user_id::uuid
from (
  select id as user_id
  from auth.users
  order by created_at asc
  limit 1
) u
cross join lateral (
  values
    ('Первый тестовый пост', 'Содержание первого seed-поста. Добро пожаловать.'),
    ('Новости приложения', 'Второй демонстрационный текст для проверки ленты.'),
    ('Объявление', 'Третий пост — удалить или изменить можете вы сами после входа.')
) as t(title, body)
where u.user_id is not null
  and not exists (select 1 from public.posts limit 1);
