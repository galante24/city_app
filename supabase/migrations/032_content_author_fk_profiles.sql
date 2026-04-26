-- Единые связи автора с public.profiles для встраивания профиля в PostgREST (select с author:profiles!...).

alter table public.job_vacancies
  drop constraint if exists job_vacancies_author_id_fkey;
alter table public.job_vacancies
  add constraint job_vacancies_author_id_fkey
    foreign key (author_id) references public.profiles (id) on delete cascade;

alter table public.tasks
  drop constraint if exists tasks_author_id_fkey;
alter table public.tasks
  add constraint tasks_author_id_fkey
    foreign key (author_id) references public.profiles (id) on delete cascade;

alter table public.place_posts
  drop constraint if exists place_posts_author_id_fkey;
alter table public.place_posts
  add constraint place_posts_author_id_fkey
    foreign key (author_id) references public.profiles (id) on delete cascade;

alter table public.task_comments
  drop constraint if exists task_comments_user_id_fkey;
alter table public.task_comments
  add constraint task_comments_user_id_fkey
    foreign key (user_id) references public.profiles (id) on delete cascade;

alter table public.place_post_comments
  drop constraint if exists place_post_comments_user_id_fkey;
alter table public.place_post_comments
  add constraint place_post_comments_user_id_fkey
    foreign key (user_id) references public.profiles (id) on delete cascade;
