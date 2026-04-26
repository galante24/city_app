-- Администратор БД (RLS): пользователь с email kill.pro15@mail.ru
update public.profiles p
set is_admin = true
from auth.users u
where p.id = u.id
  and lower(trim(u.email)) = lower(trim('kill.pro15@mail.ru'));
