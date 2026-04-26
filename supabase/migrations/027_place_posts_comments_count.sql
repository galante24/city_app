-- Счётчик комментариев к постам заведений.

alter table public.place_posts
  add column if not exists comments_count int not null default 0;

create or replace function public.sync_place_post_comments_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.place_posts
      set comments_count = coalesce(comments_count, 0) + 1
      where id = new.post_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.place_posts
      set comments_count = greatest(0, coalesce(comments_count, 0) - 1)
      where id = old.post_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_place_post_comments_ai on public.place_post_comments;
create trigger trg_place_post_comments_ai
  after insert on public.place_post_comments
  for each row execute function public.sync_place_post_comments_count();

drop trigger if exists trg_place_post_comments_ad on public.place_post_comments;
create trigger trg_place_post_comments_ad
  after delete on public.place_post_comments
  for each row execute function public.sync_place_post_comments_count();

update public.place_posts p
set comments_count = coalesce((
  select count(*)::int
  from public.place_post_comments c
  where c.post_id = p.id
), 0);
