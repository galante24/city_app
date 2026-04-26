-- Подработка: вознаграждение и ответы в комментариях.

alter table public.tasks
  add column if not exists price numeric(12, 2);

comment on column public.tasks.price is 'Сумма вознаграждения (руб.), необязательно';

alter table public.task_comments
  add column if not exists parent_id uuid references public.task_comments (id) on delete set null;

create index if not exists task_comments_parent_idx
  on public.task_comments (parent_id);
