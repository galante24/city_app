-- Убирает бесконечную рекурсию в RLS: политика на conversation_participants
-- читала ту же таблицу в подзапросе. Проверка — через SECURITY DEFINER, без RLS.
create or replace function public.user_in_conversation(p_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.conversation_participants
    where conversation_id = p_conversation_id
      and user_id = auth.uid()
  );
$$;

revoke all on function public.user_in_conversation(uuid) from public;
grant execute on function public.user_in_conversation(uuid) to authenticated;

drop policy if exists p_cpart_select on public.conversation_participants;
create policy p_cpart_select
  on public.conversation_participants
  for select
  to authenticated
  using (public.user_in_conversation(conversation_id));

drop policy if exists p_conv_select on public.conversations;
create policy p_conv_select
  on public.conversations
  for select
  to authenticated
  using (public.user_in_conversation(id));

drop policy if exists p_cmsg_select on public.chat_messages;
create policy p_cmsg_select
  on public.chat_messages
  for select
  to authenticated
  using (public.user_in_conversation(conversation_id));

drop policy if exists p_cmsg_insert on public.chat_messages;
create policy p_cmsg_insert
  on public.chat_messages
  for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and public.user_in_conversation(conversation_id)
  );
