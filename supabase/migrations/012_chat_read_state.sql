-- =============================================================================
-- ПОЛНАЯ САМОДОСТАТОЧНАЯ ЗАМЕНА: вставьте весь файл в Supabase SQL Editor и Run.
-- Зависимости: public.conversation_participants, public.chat_messages (в т.ч.
-- deleted_at), public.user_in_conversation(uuid) — как в миграциях чатов.
-- Идемпотентно: add column if not exists, create or replace, grant/revoke.
-- Realtime: при публикации supabase_realtime в режиме FOR ALL TABLES — ок;
-- иначе включите chat_messages и conversation_participants в Dashboard → Realtime.
-- =============================================================================

alter table public.conversation_participants
  add column if not exists last_read_at timestamptz;

-- ---------------------------------------------------------------------------
-- mark_conversation_read: курсор = время последнего видимого сообщения (или now).
-- ---------------------------------------------------------------------------
create or replace function public.mark_conversation_read(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'not auth' using errcode = 'P0001';
  end if;
  if not public.user_in_conversation(p_conversation_id) then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;
  update public.conversation_participants cp
  set last_read_at = coalesce(
    (select max(m.created_at) from public.chat_messages m
     where m.conversation_id = p_conversation_id
       and m.deleted_at is null),
    now()
  )
  where cp.conversation_id = p_conversation_id
    and cp.user_id = auth.uid();
end;
$$;

revoke all on function public.mark_conversation_read(uuid) from public;
grant execute on function public.mark_conversation_read(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Есть ли у текущего пользователя непрочитанные входящие (для бейджа).
-- ---------------------------------------------------------------------------
create or replace function public.has_unread_messages_for_me()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.conversation_participants cp
    join public.chat_messages m
      on m.conversation_id = cp.conversation_id
    where cp.user_id = auth.uid()
      and m.sender_id <> auth.uid()
      and m.deleted_at is null
      and m.created_at > coalesce(cp.last_read_at, to_timestamp(0) at time zone 'utc')
  );
$$;

revoke all on function public.has_unread_messages_for_me() from public;
grant execute on function public.has_unread_messages_for_me() to authenticated;

-- ---------------------------------------------------------------------------
-- id бесед с непрочитанным (для списка чатов).
-- ---------------------------------------------------------------------------
create or replace function public.get_unread_conversation_ids()
returns uuid[]
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    array(
      select distinct m.conversation_id
      from public.conversation_participants cp
      join public.chat_messages m
        on m.conversation_id = cp.conversation_id
      where cp.user_id = auth.uid()
        and m.sender_id <> auth.uid()
        and m.deleted_at is null
        and m.created_at > coalesce(cp.last_read_at, to_timestamp(0) at time zone 'utc')
    ),
    '{}'::uuid[]
  );
$$;

revoke all on function public.get_unread_conversation_ids() from public;
grant execute on function public.get_unread_conversation_ids() to authenticated;

-- Realtime: если публикация supabase_realtime в режиме FOR ALL TABLES, отдельно
-- таблицу в publication добавлять не нужно. Иначе: Dashboard → Realtime / SQL.
