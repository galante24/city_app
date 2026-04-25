-- Текст новости (поле «Текст» в форме на главной)
alter table public.news add column if not exists body text;
