-- Сид парома: на экране «Расписание» ожидается строка с id = 00000000-0000-0000-0000-000000000001
insert into public.schedules (id, title, status_text, is_running, time_text, updated_at)
values (
  '00000000-0000-0000-0000-000000000001',
  'Паром',
  'Паром ходит по расписанию',
  true,
  null,
  now()
)
on conflict (id) do update set
  title = coalesce(nullif(trim(excluded.title), ''), public.schedules.title),
  status_text = coalesce(nullif(trim(excluded.status_text), ''), public.schedules.status_text);
