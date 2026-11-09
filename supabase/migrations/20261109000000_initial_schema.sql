create extension if not exists pgcrypto with schema extensions;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text not null unique,
  role text not null default 'user' check (role in ('user', 'admin', 'creator')),
  avatar_url text,
  must_change_password boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.businesses (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  business_name text not null check (length(trim(business_name)) > 0),
  description text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade,
  business_id uuid references public.businesses(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  type text not null check (type in ('income', 'expense')),
  icon_name text not null default 'category',
  color_value bigint not null default 4284513675,
  created_at timestamptz not null default now(),
  constraint categories_owner_scope check (user_id is not null or business_id is not null)
);

create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  business_id uuid references public.businesses(id) on delete cascade,
  category_id uuid references public.categories(id) on delete set null,
  transaction_type text not null check (transaction_type in ('income', 'expense')),
  title text not null default '',
  amount numeric(18, 2) not null check (amount > 0),
  description text not null default '',
  transaction_date date not null default current_date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  business_id uuid references public.businesses(id) on delete cascade,
  category_id uuid references public.categories(id) on delete set null,
  amount numeric(18, 2) not null check (amount > 0),
  period text not null check (period in ('weekly', 'monthly', 'yearly')),
  start_date date not null,
  end_date date not null,
  created_at timestamptz not null default now(),
  constraint budgets_date_order check (end_date >= start_date)
);

create table if not exists public.savings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  business_id uuid references public.businesses(id) on delete cascade,
  target_name text not null check (length(trim(target_name)) > 0),
  target_amount numeric(18, 2) not null check (target_amount > 0),
  current_amount numeric(18, 2) not null default 0 check (current_amount >= 0),
  target_date date,
  created_at timestamptz not null default now(),
  constraint savings_progress check (current_amount <= target_amount)
);

create table if not exists public.debts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  contact text not null default '',
  amount numeric(18, 2) not null check (amount > 0),
  due_date date not null,
  type text not null check (type in ('payable', 'receivable')),
  description text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (length(trim(title)) > 0),
  message text not null default '',
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null check (length(trim(action)) > 0),
  target_user_id uuid references public.profiles(id) on delete set null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists businesses_owner_id_idx on public.businesses(owner_id);
create index if not exists categories_user_id_idx on public.categories(user_id);
create index if not exists categories_business_id_idx on public.categories(business_id);
create index if not exists transactions_user_date_idx
  on public.transactions(user_id, transaction_date desc);
create index if not exists transactions_business_date_idx
  on public.transactions(business_id, transaction_date desc);
create index if not exists transactions_category_id_idx on public.transactions(category_id);
create index if not exists budgets_user_period_idx on public.budgets(user_id, start_date, end_date);
create index if not exists savings_user_id_idx on public.savings(user_id);
create index if not exists debts_user_due_date_idx on public.debts(user_id, due_date);
create index if not exists notifications_user_created_idx
  on public.notifications(user_id, created_at desc);
create index if not exists audit_logs_actor_created_idx
  on public.audit_logs(actor_id, created_at desc);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
before update on public.profiles
for each row execute function public.touch_updated_at();

drop trigger if exists transactions_touch_updated_at on public.transactions;
create trigger transactions_touch_updated_at
before update on public.transactions
for each row execute function public.touch_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, email, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    lower(new.email),
    'user'
  )
  on conflict (id) do nothing;

  insert into public.categories (user_id, name, type, icon_name, color_value)
  values
    (new.id, 'Makanan & Minuman', 'expense', 'restaurant', 4292617766),
    (new.id, 'Perumahan', 'expense', 'home', 4279646815),
    (new.id, 'Transportasi', 'expense', 'directions_car', 4281902555),
    (new.id, 'Gaji', 'income', 'trending_up', 4279673674),
    (new.id, 'Tabungan', 'income', 'savings', 4281902555)
  on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

insert into public.profiles (id, full_name, email, role)
select
  u.id,
  coalesce(u.raw_user_meta_data ->> 'full_name', ''),
  lower(u.email),
  'user'
from auth.users u
where u.email is not null
on conflict (id) do nothing;

insert into public.categories (user_id, name, type, icon_name, color_value)
select p.id, defaults.name, defaults.type, defaults.icon_name, defaults.color_value
from public.profiles p
cross join (
  values
    ('Makanan & Minuman', 'expense', 'restaurant', 4292617766::bigint),
    ('Perumahan', 'expense', 'home', 4279646815::bigint),
    ('Transportasi', 'expense', 'directions_car', 4281902555::bigint),
    ('Gaji', 'income', 'trending_up', 4279673674::bigint),
    ('Tabungan', 'income', 'savings', 4281902555::bigint)
) as defaults(name, type, icon_name, color_value)
where not exists (
  select 1 from public.categories c
  where c.user_id = p.id and c.name = defaults.name and c.type = defaults.type
);

create or replace function public.current_app_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.role from public.profiles p where p.id = (select auth.uid())
$$;

create or replace function public.has_app_role(allowed_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.current_app_role() = any(allowed_roles), false)
$$;

create or replace function public.is_creator_user(target_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = target_id and p.role = 'creator'
  )
$$;

create or replace function public.guard_profile_role_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.role is distinct from old.role
     and current_user not in ('postgres', 'service_role')
     and coalesce(current_setting('app.allow_role_change', true), '') <> 'on' then
    raise exception 'Role changes must use the authorized role management function';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_guard_role_change on public.profiles;
create trigger profiles_guard_role_change
before update of role on public.profiles
for each row execute function public.guard_profile_role_change();

create or replace function public.set_user_role(target_user_id uuid, new_role text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null or not public.has_app_role(array['creator']) then
    raise exception 'Only a Creator may assign application roles';
  end if;
  if new_role not in ('user', 'admin', 'creator') then
    raise exception 'Invalid application role';
  end if;
  if target_user_id = (select auth.uid()) and new_role <> 'creator' then
    raise exception 'A Creator cannot remove their own Creator role';
  end if;

  perform set_config('app.allow_role_change', 'on', true);
  update public.profiles
  set role = new_role
  where id = target_user_id;

  if not found then
    raise exception 'Target profile does not exist';
  end if;

  insert into public.audit_logs (actor_id, action, target_user_id, details)
  values (
    (select auth.uid()),
    'set_user_role',
    target_user_id,
    jsonb_build_object('role', new_role)
  );
end;
$$;

create or replace function public.mark_password_changed()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;
  update public.profiles
  set must_change_password = false
  where id = (select auth.uid());
end;
$$;

create or replace function public.can_access_user(target_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select target_id = (select auth.uid())
    or public.has_app_role(array['creator'])
    or (
      public.has_app_role(array['admin'])
      and not public.is_creator_user(target_id)
    )
$$;

revoke all on function public.touch_updated_at() from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.guard_profile_role_change() from public, anon, authenticated;
revoke all on function public.current_app_role() from public, anon, authenticated;
revoke all on function public.has_app_role(text[]) from public, anon, authenticated;
revoke all on function public.is_creator_user(uuid) from public, anon, authenticated;
revoke all on function public.can_access_user(uuid) from public, anon, authenticated;
revoke all on function public.set_user_role(uuid, text) from public, anon, authenticated;
revoke all on function public.mark_password_changed() from public, anon, authenticated;

alter table public.profiles enable row level security;
alter table public.businesses enable row level security;
alter table public.categories enable row level security;
alter table public.transactions enable row level security;
alter table public.budgets enable row level security;
alter table public.savings enable row level security;
alter table public.debts enable row level security;
alter table public.notifications enable row level security;
alter table public.audit_logs enable row level security;

revoke all on public.profiles, public.businesses, public.categories,
  public.transactions, public.budgets, public.savings, public.debts,
  public.notifications, public.audit_logs from public, anon, authenticated;

grant select, insert on public.profiles to authenticated;
grant update (full_name, avatar_url) on public.profiles to authenticated;
grant select, insert, update, delete on public.businesses to authenticated;
grant select, insert, update, delete on public.categories to authenticated;
grant select, insert, update, delete on public.transactions to authenticated;
grant select, insert, update, delete on public.budgets to authenticated;
grant select, insert, update, delete on public.savings to authenticated;
grant select, insert, update, delete on public.debts to authenticated;
grant select, update on public.notifications to authenticated;
grant select on public.audit_logs to authenticated;

grant execute on function public.current_app_role() to authenticated;
grant execute on function public.has_app_role(text[]) to authenticated;
grant execute on function public.can_access_user(uuid) to authenticated;
grant execute on function public.set_user_role(uuid, text) to authenticated;
grant execute on function public.mark_password_changed() to authenticated;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
using (id = (select auth.uid()) or public.has_app_role(array['admin', 'creator']));

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

drop policy if exists profiles_update_admin on public.profiles;
create policy profiles_update_admin on public.profiles for update to authenticated
using (
  public.has_app_role(array['creator'])
  or (
    public.has_app_role(array['admin'])
    and id <> (select auth.uid())
    and public.can_access_user(id)
  )
)
with check (
  public.has_app_role(array['creator'])
  or (
    public.has_app_role(array['admin'])
    and id <> (select auth.uid())
    and public.can_access_user(id)
  )
);

drop policy if exists businesses_access on public.businesses;
create policy businesses_access on public.businesses for all to authenticated
using (
  owner_id = (select auth.uid())
  or public.has_app_role(array['creator'])
  or public.can_access_user(owner_id)
)
with check (
  owner_id = (select auth.uid())
  or public.has_app_role(array['creator'])
  or public.can_access_user(owner_id)
);

drop policy if exists categories_access on public.categories;
create policy categories_access on public.categories for all to authenticated
using (
  (user_id is null or public.can_access_user(user_id))
  and (business_id is null or exists (
    select 1 from public.businesses b where b.id = business_id
      and public.can_access_user(b.owner_id)
  ))
)
with check (
  (user_id is null or public.can_access_user(user_id))
  and (business_id is null or exists (
    select 1 from public.businesses b where b.id = business_id
      and public.can_access_user(b.owner_id)
  ))
);

drop policy if exists transactions_access on public.transactions;
create policy transactions_access on public.transactions for all to authenticated
using (public.can_access_user(user_id))
with check (
  public.can_access_user(user_id)
  and (
    business_id is null
    or exists (
      select 1 from public.businesses b
      where b.id = business_id and public.can_access_user(b.owner_id)
    )
  )
);

drop policy if exists budgets_access on public.budgets;
create policy budgets_access on public.budgets for all to authenticated
using (public.can_access_user(user_id))
with check (
  public.can_access_user(user_id)
  and (
    business_id is null
    or exists (
      select 1 from public.businesses b
      where b.id = business_id and public.can_access_user(b.owner_id)
    )
  )
);

drop policy if exists savings_access on public.savings;
create policy savings_access on public.savings for all to authenticated
using (public.can_access_user(user_id))
with check (
  public.can_access_user(user_id)
  and (
    business_id is null
    or exists (
      select 1 from public.businesses b
      where b.id = business_id and public.can_access_user(b.owner_id)
    )
  )
);

drop policy if exists debts_access on public.debts;
create policy debts_access on public.debts for all to authenticated
using (public.can_access_user(user_id))
with check (public.can_access_user(user_id));

drop policy if exists notifications_access on public.notifications;
create policy notifications_access on public.notifications for select to authenticated
using (public.can_access_user(user_id));
drop policy if exists notifications_update on public.notifications;
create policy notifications_update on public.notifications for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists audit_logs_select on public.audit_logs;
create policy audit_logs_select on public.audit_logs for select to authenticated
using (
  actor_id = (select auth.uid())
  or public.has_app_role(array['creator'])
  or (
    public.has_app_role(array['admin'])
    and (target_user_id is null or public.can_access_user(target_user_id))
  )
);
