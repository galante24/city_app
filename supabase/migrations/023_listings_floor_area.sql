-- Площадь (квадратура): в БД только цифры; отображение с суффиксом в приложении.

alter table public.dacha_listings
  add column if not exists floor_area text not null default '';
alter table public.house_listings
  add column if not exists floor_area text not null default '';
alter table public.apartment_listings
  add column if not exists floor_area text not null default '';
alter table public.land_listings
  add column if not exists floor_area text not null default '';
alter table public.commercial_listings
  add column if not exists floor_area text not null default '';
alter table public.garage_listings
  add column if not exists floor_area text not null default '';
