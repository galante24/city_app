-- Владелец заведения может то же, что модератор (меню, посты, поля места),
-- в т.ч. без строки в place_moderators — совпадает с клиентским PlaceService.canModeratePlace.
create or replace function public.can_moderate_place(p_place uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_profiles_admin()
    or exists (
      select 1 from public.places pl
      where pl.id = p_place and pl.owner_id = auth.uid()
    )
    or exists (
      select 1 from public.place_moderators pm
      where pm.place_id = p_place and pm.user_id = auth.uid()
    );
$$;
