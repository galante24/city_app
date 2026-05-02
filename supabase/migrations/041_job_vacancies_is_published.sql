-- Вакансии: публикация только после подтверждения администратором (is_published).

alter table public.job_vacancies
  add column if not exists is_published boolean not null default false;

comment on column public.job_vacancies.is_published is
  'Видна в общем списке после подтверждения админом; автор и админ видят черновик по RLS.';

-- Уже существующие записи остаются в ленте.
update public.job_vacancies
set is_published = true
where is_published is distinct from true;

-- Только админ может менять флаг публикации; при INSERT не-админ всегда черновик.
create or replace function public.job_vacancies_guard_publish()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin boolean;
begin
  select coalesce(p.is_admin, false)
  into v_admin
  from public.profiles p
  where p.id = auth.uid();

  if tg_op = 'INSERT' then
    if not coalesce(v_admin, false) then
      new.is_published := false;
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if new.is_published is distinct from old.is_published then
      if not coalesce(v_admin, false) then
        raise exception 'is_published: только администратор может менять публикацию';
      end if;
    end if;
    return new;
  end if;

  return new;
end;
$$;

drop trigger if exists job_vacancies_guard_publish_trg on public.job_vacancies;
create trigger job_vacancies_guard_publish_trg
  before insert or update on public.job_vacancies
  for each row
  execute function public.job_vacancies_guard_publish();

drop policy if exists "job_vacancies read auth" on public.job_vacancies;
create policy "job_vacancies read auth"
  on public.job_vacancies
  for select
  to authenticated
  using (
    is_published = true
    or author_id = auth.uid()
    or exists (
      select 1
      from public.profiles p
      where p.id = auth.uid() and p.is_admin = true
    )
  );

drop policy if exists "job_vacancies insert own" on public.job_vacancies;
create policy "job_vacancies insert own"
  on public.job_vacancies
  for insert
  to authenticated
  with check (author_id = auth.uid());
