-- Расширение app_config: человекочитаемая версия, единое поле apk_url, принудительное обновление.
-- Совместимо с CI (release.yml) и старыми полями version_code / download_url.

alter table public.app_config
  add column if not exists version text,
  add column if not exists apk_url text,
  add column if not exists force_update boolean not null default false;

comment on column public.app_config.version is 'Строка вида 1.0.3 (или 1.0.3+42) для UI';
comment on column public.app_config.apk_url is 'Прямая ссылка на APK для скачивания; приоритетнее download_url при наличии';
comment on column public.app_config.force_update is 'true — диалог без кнопки «Позже» и без закрытия свайпом';
