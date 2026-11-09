-- Run only from the Supabase SQL Editor as a trusted database administrator.
-- First create/find the Auth user in Authentication > Users. This script never
-- inserts into auth.users and never changes or stores an Auth password.
begin;

do $$
declare
  creator_id uuid;
  auth_email text;
  auth_full_name text;
  creator_business_id uuid;
  auth_user_count integer;
  profile_was_ready boolean;
begin
  select count(*)
  into auth_user_count
  from auth.users u
  where lower(u.email) = 'adminfinbiz@gmail.com';

  if auth_user_count = 0 then
    raise exception
      'Akun Auth adminfinbiz@gmail.com belum ada. Buat satu kali di Authentication > Users, lalu jalankan ulang.';
  end if;
  if auth_user_count <> 1 then
    raise exception
      'Ditemukan lebih dari satu akun Auth untuk email Creator. Hentikan provisioning dan tinjau akun secara manual.';
  end if;
  select u.id, lower(u.email),
         coalesce(u.raw_user_meta_data ->> 'full_name', '')
  into creator_id, auth_email, auth_full_name
  from auth.users u
  where lower(u.email) = 'adminfinbiz@gmail.com';

  if auth_email is distinct from 'adminfinbiz@gmail.com' then
    raise exception 'Email akun Auth tidak sesuai dengan akun Creator yang diharapkan.';
  end if;
  if exists (
    select 1
    from public.profiles p
    where lower(p.email) = 'adminfinbiz@gmail.com'
      and p.id <> creator_id
  ) then
    raise exception
      'Email Creator sudah terhubung ke UUID profil lain. Tidak ada perubahan dilakukan; tinjau relasi secara manual.';
  end if;

  select exists (
    select 1
    from public.profiles p
    join public.businesses b on b.owner_id = p.id
    join public.business_settings s on s.business_id = b.id
    join public.cash_accounts a on a.business_id = b.id
    where p.id = creator_id
      and p.email = auth_email
      and p.role = 'creator'
  )
  into profile_was_ready;

  insert into public.profiles (
    id, full_name, email, role, must_change_password
  )
  values (
    creator_id,
    coalesce(nullif(trim(auth_full_name), ''), 'FinBiz Creator'),
    auth_email,
    'creator',
    true
  )
  on conflict (id) do update
  set email = excluded.email,
      full_name = case
        when trim(public.profiles.full_name) = ''
          then excluded.full_name
        else public.profiles.full_name
      end,
      role = 'creator',
      updated_at = now();

  select b.id into creator_business_id
  from public.businesses b
  where b.owner_id = creator_id;

  if creator_business_id is null then
    insert into public.businesses (owner_id, business_name)
    values (creator_id, 'FinBiz')
    on conflict (owner_id) do nothing;

    select b.id into creator_business_id
    from public.businesses b
    where b.owner_id = creator_id;
  end if;

  if creator_business_id is null then
    raise exception
      'Profil Creator berhasil ditautkan, tetapi bisnis Creator tidak dapat diprovisikan.';
  end if;

  insert into public.business_settings (business_id)
  values (creator_business_id)
  on conflict (business_id) do nothing;

  insert into public.cash_accounts (business_id, name, account_type)
  values (creator_business_id, 'Kas utama', 'cash')
  on conflict (business_id, (lower(name))) do nothing;

  if not profile_was_ready then
    insert into public.audit_logs (
      actor_id, target_user_id, business_id, action, details
    )
    values (
      creator_id, creator_id, creator_business_id, 'creator_bootstrapped',
      jsonb_build_object('email', auth_email)
    );
  end if;
end
$$;

commit;
