-- Очистка истории в личном чате и полное удаление беседы (участник / владелец группы)

create or replace function public.clear_conversation_history(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := auth.uid();
  is_g boolean;
begin
  if me is null then
    raise exception 'not auth' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.conversation_participants p
    where p.conversation_id = p_conversation_id and p.user_id = me
  ) then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;
  select c.is_group into is_g
  from public.conversations c
  where c.id = p_conversation_id;
  if coalesce(is_g, true) then
    raise exception 'not_direct' using errcode = 'P0001';
  end if;
  delete from public.chat_messages where conversation_id = p_conversation_id;
  update public.conversations
  set
    last_message_at = null,
    last_message_preview = null,
    updated_at = now()
  where id = p_conversation_id;
end;
$$;

-- Личный: любой участник. Группа: только участник с role = 'owner' (удаляет группу для всех)
create or replace function public.delete_conversation_completely(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := auth.uid();
  is_g boolean;
  r text;
begin
  if me is null then
    raise exception 'not auth' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.conversation_participants p
    where p.conversation_id = p_conversation_id and p.user_id = me
  ) then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;
  select c.is_group into is_g
  from public.conversations c
  where c.id = p_conversation_id;
  if is_g is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if is_g then
    select p.role into r
    from public.conversation_participants p
    where p.conversation_id = p_conversation_id and p.user_id = me;
    if r is distinct from 'owner' then
      raise exception 'only_owner' using errcode = 'P0001';
    end if;
  end if;
  delete from public.conversations where id = p_conversation_id;
end;
$$;

grant execute on function public.clear_conversation_history(uuid) to authenticated;
grant execute on function public.delete_conversation_completely(uuid) to authenticated;
