-- Чтение чужих profiles для UI авторов (вкладываемый author:profiles в PostgREST).
-- Политика «все у всех» заменена на 034_profiles_rls_hardening.sql (см. profile_is_readable_by_me).
-- Политики объединяются через OR; не запрашивайте в клиенте fcm_token и пр. для чужих id.

drop policy if exists "profiles social read authenticated" on public.profiles;
create policy "profiles social read authenticated"
  on public.profiles
  for select
  to authenticated
  using (true);
