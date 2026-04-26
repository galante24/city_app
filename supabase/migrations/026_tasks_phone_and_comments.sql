-- Задачи (объявления): телефон для звонка + публичные комментарии.

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  description text not null,
  created_at timestamptz not null default now()
);

alter table public.tasks add column if not exists phone text;

create index if not exists tasks_created_at_idx on public.tasks (created_at desc);
create index if not exists tasks_author_idx on public.tasks (author_id);

create table if not exists public.task_comments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  text text not null,
  created_at timestamptz not null default now()
);

create index if not exists task_comments_task_idx
  on public.task_comments (task_id, created_at);

alter table public.tasks enable row level security;
alter table public.task_comments enable row level security;

drop policy if exists "tasks read auth" on public.tasks;
create policy "tasks read auth" on public.tasks
  for select to authenticated using (true);

drop policy if exists "tasks insert own" on public.tasks;
create policy "tasks insert own" on public.tasks
  for insert to authenticated
  with check (author_id = auth.uid());

drop policy if exists "tasks update own or admin" on public.tasks;
create policy "tasks update own or admin" on public.tasks
  for update to authenticated
  using (
    author_id = auth.uid()
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true)
  )
  with check (
    author_id = auth.uid()
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true)
  );

drop policy if exists "tasks delete own or admin" on public.tasks;
create policy "tasks delete own or admin" on public.tasks
  for delete to authenticated
  using (
    author_id = auth.uid()
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true)
  );

drop policy if exists "task_comments read auth" on public.task_comments;
create policy "task_comments read auth" on public.task_comments
  for select to authenticated using (true);

drop policy if exists "task_comments insert own" on public.task_comments;
create policy "task_comments insert own" on public.task_comments
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "task_comments delete own or admin" on public.task_comments;
create policy "task_comments delete own or admin" on public.task_comments
  for delete to authenticated
  using (
    user_id = auth.uid()
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true)
  );
