-- Текст «О себе» в профиле (виден собеседникам по политике p_profiles_read_chat_partners).

alter table public.profiles
  add column if not exists about text;

comment on column public.profiles.about is 'О себе; отображается в профиле в чате у партнёров';
