-- RLS: второй админский email из приложения (см. kAdministratorEmails).
update public.profiles p
set is_admin = true
from auth.users u
where p.id = u.id
  and lower(trim(u.email)) = lower(trim('sranometrr@gmail.com'));
