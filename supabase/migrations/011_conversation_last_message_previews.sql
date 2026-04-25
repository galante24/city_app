-- Последнее по времени сообщение по списку чатов (для списка, если last_message_preview пустой).
-- Только беседы, где auth.uid() участник (через user_in_conversation).
create or replace function public.conversation_last_message_previews(p_conv_ids uuid[])
returns table (conversation_id uuid, body_preview text, last_at timestamptz)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select distinct on (m.conversation_id)
    m.conversation_id,
    left(btrim(m.body), 200) as body_preview,
    m.created_at
  from public.chat_messages m
  where m.conversation_id = any(p_conv_ids)
    and m.deleted_at is null
    and public.user_in_conversation(m.conversation_id)
  order by m.conversation_id, m.created_at desc;
$$;

revoke all on function public.conversation_last_message_previews(uuid[]) from public;
grant execute on function public.conversation_last_message_previews(uuid[]) to authenticated;
