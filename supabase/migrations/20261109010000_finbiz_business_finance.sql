begin;

do $$
begin
  if exists (
    select 1
    from public.businesses
    group by owner_id
    having count(*) > 1
  ) then
    raise exception
      'Migration dihentikan: terdapat lebih dari satu bisnis untuk satu pemilik. Tinjau data businesses.owner_id terlebih dahulu.';
  end if;
end;
$$;

create unique index if not exists businesses_owner_id_unique
  on public.businesses(owner_id);

alter table public.profiles
  add column if not exists updated_by uuid references public.profiles(id) on delete set null;

alter table public.businesses
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists created_by uuid references public.profiles(id) on delete set null,
  add column if not exists updated_by uuid references public.profiles(id) on delete set null;

insert into public.businesses (owner_id, business_name)
select p.id,
       coalesce(nullif(trim(p.full_name), ''), 'Bisnis FinBiz') || ' - FinBiz'
from public.profiles p
where not exists (
  select 1 from public.businesses b where b.owner_id = p.id
)
on conflict (owner_id) do nothing;

create table if not exists public.business_settings (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  currency_code text not null default 'IDR'
    check (currency_code ~ '^[A-Z]{3}$'),
  time_zone text not null default 'Asia/Jakarta',
  fiscal_start_month smallint not null default 1
    check (fiscal_start_month between 1 and 12),
  preferences jsonb not null default '{}'::jsonb
    check (jsonb_typeof(preferences) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null
);

insert into public.business_settings (business_id)
select b.id from public.businesses b
on conflict (business_id) do nothing;

create table if not exists public.cash_accounts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  account_type text not null
    check (account_type in ('cash', 'bank', 'e_wallet', 'other')),
  opening_balance numeric(18, 2) not null default 0
    check (opening_balance >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  unique (id, business_id)
);

create unique index if not exists cash_accounts_business_name_unique
  on public.cash_accounts (business_id, lower(name));

insert into public.cash_accounts (business_id, name, account_type)
select b.id, 'Kas utama', 'cash'
from public.businesses b
on conflict (business_id, (lower(name))) do nothing;

alter table public.categories
  add column if not exists is_global boolean not null default false,
  add column if not exists created_by uuid references public.profiles(id) on delete set null,
  add column if not exists updated_by uuid references public.profiles(id) on delete set null;

update public.categories c
set business_id = b.id
from public.businesses b
where c.business_id is null
  and c.user_id = b.owner_id;

update public.categories c
set user_id = b.owner_id
from public.businesses b
where c.user_id is null
  and c.business_id = b.id;

update public.categories
set is_global = true
where user_id is null and business_id is null;

alter table public.categories
  drop constraint if exists categories_owner_scope;

alter table public.transactions
  add column if not exists status text not null default 'posted',
  add column if not exists cash_account_id uuid,
  add column if not exists created_by uuid references public.profiles(id) on delete set null,
  add column if not exists updated_by uuid references public.profiles(id) on delete set null;

alter table public.budgets
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists created_by uuid references public.profiles(id) on delete set null,
  add column if not exists updated_by uuid references public.profiles(id) on delete set null;

alter table public.savings
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists status text not null default 'active'
    check (status in ('active', 'completed', 'cancelled')),
  add column if not exists created_by uuid references public.profiles(id) on delete set null,
  add column if not exists updated_by uuid references public.profiles(id) on delete set null;

alter table public.debts
  add column if not exists business_id uuid references public.businesses(id) on delete cascade,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists created_by uuid references public.profiles(id) on delete set null,
  add column if not exists updated_by uuid references public.profiles(id) on delete set null;

update public.transactions t
set business_id = b.id
from public.businesses b
where t.business_id is null and t.user_id = b.owner_id;

update public.budgets t
set business_id = b.id
from public.businesses b
where t.business_id is null and t.user_id = b.owner_id;

update public.savings t
set business_id = b.id
from public.businesses b
where t.business_id is null and t.user_id = b.owner_id;

update public.debts t
set business_id = b.id
from public.businesses b
where t.business_id is null and t.user_id = b.owner_id;

update public.transactions t
set cash_account_id = a.id
from public.cash_accounts a
where t.cash_account_id is null and t.business_id = a.business_id;

update public.transactions
set status = 'posted'
where status is null;

update public.savings
set status = 'active'
where status is null;

do $$
begin
  if exists (
    select 1 from public.transactions where business_id is null
  ) or exists (
    select 1 from public.budgets where business_id is null
  ) or exists (
    select 1 from public.savings where business_id is null
  ) or exists (
    select 1 from public.debts where business_id is null
  ) then
    raise exception
      'Migration dihentikan: ada data keuangan tanpa pemilik bisnis yang valid.';
  end if;

  if exists (
    select 1
    from public.transactions t
    join public.categories c on c.id = t.category_id
    where t.category_id is not null
      and not c.is_global
      and c.business_id is distinct from t.business_id
  ) then
    raise exception
      'Migration dihentikan: transaksi merujuk kategori bisnis lain.';
  end if;

  if exists (
    select 1
    from public.categories c
    join public.businesses b on b.id = c.business_id
    where not c.is_global and c.user_id is distinct from b.owner_id
  ) or exists (
    select 1
    from public.transactions t
    join public.businesses b on b.id = t.business_id
    where t.user_id is distinct from b.owner_id
  ) or exists (
    select 1
    from public.budgets t
    join public.businesses b on b.id = t.business_id
    where t.user_id is distinct from b.owner_id
  ) or exists (
    select 1
    from public.savings t
    join public.businesses b on b.id = t.business_id
    where t.user_id is distinct from b.owner_id
  ) or exists (
    select 1
    from public.debts t
    join public.businesses b on b.id = t.business_id
    where t.user_id is distinct from b.owner_id
  ) or exists (
    select 1
    from public.notifications n
    join public.businesses b on b.id = n.business_id
    where n.user_id is distinct from b.owner_id
  ) then
    raise exception
      'Migration dihentikan: data lama memiliki user_id yang tidak sesuai dengan pemilik business_id.';
  end if;

  if exists (
    select 1
    from public.transactions t
    left join public.cash_accounts a
      on a.id = t.cash_account_id and a.business_id = t.business_id
    where a.id is null
  ) then
    raise exception
      'Migration dihentikan: transaksi merujuk rekening kas yang tidak sesuai bisnisnya.';
  end if;
end;
$$;

alter table public.transactions
  alter column business_id set not null,
  alter column cash_account_id set not null,
  alter column status set not null;

alter table public.budgets
  alter column business_id set not null;

alter table public.savings
  alter column business_id set not null,
  alter column status set not null;

alter table public.debts
  alter column business_id set not null;

alter table public.categories
  alter column is_global set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.transactions'::regclass
      and conname = 'transactions_status_valid'
  ) then
    alter table public.transactions
      add constraint transactions_status_valid
      check (status in ('draft', 'posted', 'voided'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.categories'::regclass
      and conname = 'categories_business_scope_valid'
  ) then
    alter table public.categories
      add constraint categories_business_scope_valid
      check (
        (is_global and user_id is null and business_id is null)
        or (not is_global and user_id is not null and business_id is not null)
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.transactions'::regclass
      and conname = 'transactions_cash_account_business_fk'
  ) then
    alter table public.transactions
      add constraint transactions_cash_account_business_fk
      foreign key (cash_account_id, business_id)
      references public.cash_accounts(id, business_id);
  end if;
end;
$$;

create unique index if not exists transactions_id_business_unique
  on public.transactions (id, business_id);
create unique index if not exists categories_id_business_unique
  on public.categories (id, business_id);
create unique index if not exists debts_id_business_unique
  on public.debts (id, business_id);

do $$
declare
  relation_kind "char";
begin
  select c.relkind into relation_kind
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'savings_goals';

  if relation_kind is null or relation_kind = 'v' then
    execute $view$
      create or replace view public.savings_goals
      with (security_invoker = true)
      as
      select
        id, business_id, user_id, target_name, target_amount, current_amount,
        target_date, status, created_at, updated_at, created_by, updated_by
      from public.savings
    $view$;
  else
    raise exception
      'Relation public.savings_goals already exists and is not a view; migration stopped to preserve it.';
  end if;
end;
$$;

create table if not exists public.account_transfers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  from_cash_account_id uuid not null,
  to_cash_account_id uuid not null,
  amount numeric(18, 2) not null check (amount > 0),
  status text not null default 'posted'
    check (status in ('draft', 'posted', 'voided')),
  transfer_date timestamptz not null default now(),
  description text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  check (from_cash_account_id <> to_cash_account_id),
  foreign key (from_cash_account_id, business_id)
    references public.cash_accounts(id, business_id),
  foreign key (to_cash_account_id, business_id)
    references public.cash_accounts(id, business_id)
);

create table if not exists public.debt_payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  debt_id uuid not null,
  cash_account_id uuid not null,
  principal_amount numeric(18, 2) not null default 0 check (principal_amount >= 0),
  interest_amount numeric(18, 2) not null default 0 check (interest_amount >= 0),
  fee_amount numeric(18, 2) not null default 0 check (fee_amount >= 0),
  payment_date timestamptz not null default now(),
  status text not null default 'posted'
    check (status in ('draft', 'posted', 'voided')),
  description text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  check (principal_amount + interest_amount + fee_amount > 0),
  foreign key (debt_id, business_id) references public.debts(id, business_id),
  foreign key (cash_account_id, business_id)
    references public.cash_accounts(id, business_id)
);

create table if not exists public.transaction_attachments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  transaction_id uuid not null,
  storage_path text not null unique,
  original_name text not null,
  content_type text not null
    check (content_type in ('image/jpeg', 'image/png', 'image/webp', 'application/pdf')),
  byte_size bigint not null check (byte_size between 1 and 10485760),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  foreign key (transaction_id, business_id)
    references public.transactions(id, business_id) on delete cascade
);

create table if not exists public.recurring_transactions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  category_id uuid references public.categories(id) on delete set null,
  cash_account_id uuid not null,
  transaction_type text not null check (transaction_type in ('income', 'expense')),
  amount numeric(18, 2) not null check (amount > 0),
  title text not null check (length(trim(title)) > 0),
  description text not null default '',
  frequency text not null check (frequency in ('daily', 'weekly', 'monthly', 'yearly')),
  next_run_at timestamptz not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  foreign key (cash_account_id, business_id)
    references public.cash_accounts(id, business_id)
);

create table if not exists public.import_jobs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'queued'
    check (status in ('queued', 'processing', 'completed', 'failed', 'cancelled')),
  source_path text not null,
  result jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null
);

create table if not exists public.export_jobs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'queued'
    check (status in ('queued', 'processing', 'completed', 'failed', 'cancelled')),
  format text not null check (format in ('csv', 'xlsx', 'pdf')),
  result_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null
);

create table if not exists public.cash_reconciliations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  cash_account_id uuid not null,
  statement_balance numeric(18, 2) not null,
  calculated_balance numeric(18, 2) not null,
  difference numeric(18, 2) generated always as
    (statement_balance - calculated_balance) stored,
  reconciled_at timestamptz not null default now(),
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  foreign key (cash_account_id, business_id)
    references public.cash_accounts(id, business_id)
);

create table if not exists public.financial_periods (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  period_name text not null check (length(trim(period_name)) > 0),
  start_date date not null,
  end_date date not null,
  status text not null default 'open' check (status in ('open', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  check (end_date >= start_date),
  unique (business_id, period_name)
);

create table if not exists public.correction_requests (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  transaction_id uuid not null,
  proposed_data jsonb not null check (jsonb_typeof(proposed_data) = 'object'),
  reason text not null check (length(trim(reason)) > 0),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  review_notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  foreign key (transaction_id, business_id)
    references public.transactions(id, business_id)
);

alter table public.audit_logs
  add column if not exists business_id uuid references public.businesses(id) on delete set null,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists created_by uuid references public.profiles(id) on delete set null,
  add column if not exists updated_by uuid references public.profiles(id) on delete set null;

alter table public.notifications
  add column if not exists business_id uuid references public.businesses(id) on delete cascade,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists created_by uuid references public.profiles(id) on delete set null,
  add column if not exists updated_by uuid references public.profiles(id) on delete set null;

update public.notifications n
set business_id = b.id
from public.businesses b
where n.business_id is null and n.user_id = b.owner_id;

alter table public.notifications
  alter column business_id set not null;

create table if not exists public.reminders (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (length(trim(title)) > 0),
  message text not null default '',
  remind_at timestamptz not null,
  is_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null
);

create table if not exists public.system_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(trim(title)) > 0),
  message text not null,
  is_published boolean not null default false,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null
);

create table if not exists public.security_events (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  business_id uuid references public.businesses(id) on delete set null,
  event_type text not null check (length(trim(event_type)) > 0),
  details jsonb not null default '{}'::jsonb
    check (jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default now()
);

create index if not exists transactions_business_status_date_idx
  on public.transactions (business_id, status, transaction_date desc);
create index if not exists budgets_business_period_idx
  on public.budgets (business_id, start_date, end_date);
create index if not exists savings_business_created_idx
  on public.savings (business_id, created_at desc);
create index if not exists debts_business_due_idx
  on public.debts (business_id, due_date);
create index if not exists notifications_business_created_idx
  on public.notifications (business_id, created_at desc);
create index if not exists categories_business_idx
  on public.categories (business_id, name);
create index if not exists cash_accounts_business_idx
  on public.cash_accounts (business_id, is_active);
create index if not exists transfers_business_date_idx
  on public.account_transfers (business_id, transfer_date desc);
create index if not exists debt_payments_business_date_idx
  on public.debt_payments (business_id, payment_date desc);
create index if not exists attachments_transaction_idx
  on public.transaction_attachments (transaction_id);
create index if not exists recurring_transactions_due_idx
  on public.recurring_transactions (business_id, next_run_at)
  where is_active;
create index if not exists import_jobs_business_created_idx
  on public.import_jobs (business_id, created_at desc);
create index if not exists export_jobs_business_created_idx
  on public.export_jobs (business_id, created_at desc);
create index if not exists reconciliations_business_date_idx
  on public.cash_reconciliations (business_id, reconciled_at desc);
create index if not exists correction_requests_business_status_idx
  on public.correction_requests (business_id, status, created_at desc);
create index if not exists reminders_business_due_idx
  on public.reminders (business_id, remind_at)
  where not is_completed;
create index if not exists security_events_created_idx
  on public.security_events (created_at desc);

create or replace function public.owns_business(target_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.businesses b
    where b.id = target_business_id and b.owner_id = (select auth.uid())
  )
$$;

create or replace function public.can_read_business(target_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.owns_business(target_business_id)
    or public.has_app_role(array['admin', 'creator'])
$$;

create or replace function public.enforce_business_context()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  caller_role text;
  owner_business_id uuid;
  supplied_business_id uuid;
  data jsonb;
begin
  if caller_id is null then
    return new;
  end if;

  caller_role := public.current_app_role();
  data := to_jsonb(new);

  if tg_table_name = 'correction_requests'
     and tg_op = 'UPDATE'
     and caller_role in ('admin', 'creator') then
    if data ->> 'status' not in ('approved', 'rejected') then
      raise exception 'Correction review must be approved or rejected';
    end if;
    data := data || jsonb_build_object(
      'reviewed_by', caller_id,
      'reviewed_at', now(),
      'updated_by', caller_id
    );
    new := jsonb_populate_record(new, data);
    insert into public.audit_logs (
      actor_id, target_user_id, business_id, action, details
    )
    values (
      caller_id,
      new.user_id,
      new.business_id,
      'correction_request_reviewed',
      jsonb_build_object('request_id', new.id, 'status', new.status)
    );
    return new;
  end if;

  if tg_table_name = 'notifications'
     and tg_op = 'INSERT'
     and caller_role = 'admin' then
    if not exists (
      select 1
      from public.businesses b
      where b.id = (data ->> 'business_id')::uuid
        and b.owner_id = (data ->> 'user_id')::uuid
    ) then
      raise exception 'Notification target must own the selected business';
    end if;
    data := data || jsonb_build_object(
      'created_by', caller_id,
      'updated_by', caller_id
    );
    new := jsonb_populate_record(new, data);
    return new;
  end if;

  if caller_role = 'creator' then
    if tg_table_name = 'categories'
       and coalesce((data ->> 'is_global')::boolean, false) then
      if tg_op = 'INSERT' then
        data := data || jsonb_build_object(
          'created_by', caller_id,
          'updated_by', caller_id
        );
      else
        data := data || jsonb_build_object('updated_by', caller_id);
      end if;
      new := jsonb_populate_record(new, data);
      return new;
    end if;
    if tg_op = 'INSERT' then
      data := data || jsonb_build_object(
        'created_by', caller_id,
        'updated_by', caller_id
      );
    else
      data := data || jsonb_build_object('updated_by', caller_id);
    end if;
    new := jsonb_populate_record(new, data);
    return new;
  end if;

  select b.id into owner_business_id
  from public.businesses b
  where b.owner_id = caller_id;

  if owner_business_id is null then
    raise exception 'Business profile is not configured';
  end if;

  if tg_table_name = 'categories'
     and coalesce((data ->> 'is_global')::boolean, false) then
    if caller_role <> 'admin' then
      raise exception 'Only Admin or Creator may manage global categories';
    end if;
    if tg_op = 'INSERT' then
      data := data || jsonb_build_object(
        'created_by', caller_id,
        'updated_by', caller_id
      );
    else
      data := data || jsonb_build_object('updated_by', caller_id);
    end if;
    new := jsonb_populate_record(new, data);
    return new;
  end if;

  supplied_business_id := nullif(data ->> 'business_id', '')::uuid;
  if supplied_business_id is not null
     and supplied_business_id <> owner_business_id then
    raise exception 'Business does not belong to the current user';
  end if;

  data := data || jsonb_build_object('business_id', owner_business_id);
  if data ? 'user_id' then
    data := data || jsonb_build_object('user_id', caller_id);
  end if;
  if tg_op = 'INSERT' then
    data := data || jsonb_build_object('created_by', caller_id);
  end if;
  data := data || jsonb_build_object('updated_by', caller_id);

  if tg_table_name = 'transactions' and data ->> 'cash_account_id' is null then
    select a.id into supplied_business_id
    from public.cash_accounts a
    where a.business_id = owner_business_id and a.is_active
    order by a.created_at, a.id
    limit 1;
    if supplied_business_id is null then
      raise exception 'No active cash account is configured';
    end if;
    data := data || jsonb_build_object('cash_account_id', supplied_business_id);
  end if;

  if tg_table_name in ('transactions', 'budgets', 'recurring_transactions')
     and data ->> 'category_id' is not null
     and not exists (
       select 1 from public.categories c
       where c.id = (data ->> 'category_id')::uuid
         and (c.is_global or c.business_id = owner_business_id)
     ) then
    raise exception 'Category does not belong to this business';
  end if;

  if tg_table_name = 'transaction_attachments'
     and split_part(data ->> 'storage_path', '/', 1) <> owner_business_id::text then
    raise exception 'Attachment path must be scoped to this business';
  end if;

  new := jsonb_populate_record(new, data);
  return new;
end;
$$;

create or replace function public.audit_transaction_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is not null then
    insert into public.audit_logs (
      actor_id, target_user_id, business_id, action, details
    )
    values (
      (select auth.uid()),
      new.user_id,
      new.business_id,
      case when tg_op = 'INSERT' then 'transaction_created' else 'transaction_updated' end,
      jsonb_build_object(
        'transaction_id', new.id,
        'status', new.status,
        'amount', new.amount,
        'transaction_type', new.transaction_type,
        'old_status', case when tg_op = 'UPDATE' then old.status else null end
      )
    );
  end if;
  return new;
end;
$$;

create or replace function public.admin_upsert_global_category(
  target_category_id uuid,
  category_name text,
  category_type text,
  category_icon text default 'category',
  category_color bigint default 4284513675
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  saved_category_id uuid;
begin
  if actor_id is null
     or not public.has_app_role(array['admin', 'creator']) then
    raise exception 'Only Admin or Creator may manage global categories';
  end if;
  if nullif(trim(category_name), '') is null
     or category_type not in ('income', 'expense')
     or category_color < 0
     or category_color > 4294967295 then
    raise exception 'Invalid global category data';
  end if;

  if target_category_id is null then
    insert into public.categories (
      user_id, business_id, is_global, name, type, icon_name, color_value,
      created_by, updated_by
    )
    values (
      null, null, true, trim(category_name), category_type, category_icon,
      category_color, actor_id, actor_id
    )
    returning id into saved_category_id;
  else
    update public.categories
    set name = trim(category_name),
        type = category_type,
        icon_name = category_icon,
        color_value = category_color,
        updated_by = actor_id
    where id = target_category_id and is_global
    returning id into saved_category_id;
    if saved_category_id is null then
      raise exception 'Global category was not found';
    end if;
  end if;

  insert into public.audit_logs (actor_id, action, details)
  values (
    actor_id,
    case when target_category_id is null
      then 'global_category_created' else 'global_category_updated' end,
    jsonb_build_object('category_id', saved_category_id)
  );
  return saved_category_id;
end;
$$;

create or replace function public.admin_delete_global_category(
  target_category_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
begin
  if actor_id is null
     or not public.has_app_role(array['admin', 'creator']) then
    raise exception 'Only Admin or Creator may manage global categories';
  end if;

  delete from public.categories
  where id = target_category_id and is_global;
  if not found then
    raise exception 'Global category was not found';
  end if;

  insert into public.audit_logs (actor_id, action, details)
  values (
    actor_id,
    'global_category_deleted',
    jsonb_build_object('category_id', target_category_id)
  );
end;
$$;

create or replace function public.admin_send_notification(
  target_business_id uuid,
  target_user_id uuid,
  notification_title text,
  notification_message text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  new_notification_id uuid;
begin
  if actor_id is null
     or not public.has_app_role(array['admin', 'creator']) then
    raise exception 'Only Admin or Creator may send notifications';
  end if;
  if nullif(trim(notification_title), '') is null then
    raise exception 'Notification title is required';
  end if;

  insert into public.notifications (
    user_id, business_id, title, message, created_by, updated_by
  )
  values (
    target_user_id, target_business_id, trim(notification_title),
    coalesce(notification_message, ''), actor_id, actor_id
  )
  returning id into new_notification_id;

  insert into public.audit_logs (
    actor_id, target_user_id, business_id, action, details
  )
  values (
    actor_id, target_user_id, target_business_id, 'notification_sent',
    jsonb_build_object('notification_id', new_notification_id)
  );
  return new_notification_id;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_business_id uuid;
begin
  insert into public.profiles (id, full_name, email, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    lower(new.email),
    'user'
  )
  on conflict (id) do nothing;

  insert into public.businesses (owner_id, business_name)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), 'Bisnis FinBiz')
      || ' - FinBiz'
  )
  on conflict (owner_id) do nothing;

  select b.id into new_business_id
  from public.businesses b
  where b.owner_id = new.id;

  insert into public.business_settings (business_id)
  values (new_business_id)
  on conflict (business_id) do nothing;

  insert into public.cash_accounts (business_id, name, account_type)
  values (new_business_id, 'Kas utama', 'cash')
  on conflict (business_id, (lower(name))) do nothing;

  insert into public.categories (user_id, business_id, name, type, icon_name, color_value)
  values
    (new.id, new_business_id, 'Makanan & Minuman', 'expense', 'restaurant', 4292617766),
    (new.id, new_business_id, 'Perumahan', 'expense', 'home', 4279646815),
    (new.id, new_business_id, 'Transportasi', 'expense', 'directions_car', 4281902555),
    (new.id, new_business_id, 'Gaji', 'income', 'trending_up', 4279673674),
    (new.id, new_business_id, 'Tabungan', 'income', 'savings', 4281902555);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.ensure_current_profile()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  auth_email text;
  auth_full_name text;
  caller_business_id uuid;
begin
  if caller_id is null then
    raise exception 'Authentication required';
  end if;

  select lower(u.email),
         coalesce(u.raw_user_meta_data ->> 'full_name', '')
  into auth_email, auth_full_name
  from auth.users u
  where u.id = caller_id;

  if auth_email is null then
    raise exception 'Authenticated user was not found';
  end if;

  insert into public.profiles (id, email, full_name, role)
  values (caller_id, auth_email, auth_full_name, 'user')
  on conflict (id) do nothing;

  select b.id into caller_business_id
  from public.businesses b
  where b.owner_id = caller_id;

  if caller_business_id is null then
    insert into public.businesses (owner_id, business_name)
    values (
      caller_id,
      coalesce(nullif(trim(auth_full_name), ''), 'Bisnis FinBiz') || ' - FinBiz'
    )
    on conflict (owner_id) do nothing;

    select b.id into caller_business_id
    from public.businesses b
    where b.owner_id = caller_id;
  end if;

  insert into public.business_settings (business_id)
  values (caller_business_id)
  on conflict (business_id) do nothing;

  insert into public.cash_accounts (business_id, name, account_type)
  values (caller_business_id, 'Kas utama', 'cash')
  on conflict (business_id, (lower(name))) do nothing;

  insert into public.categories (
    user_id, business_id, name, type, icon_name, color_value
  )
  select caller_id, caller_business_id, defaults.name, defaults.type,
         defaults.icon_name, defaults.color_value
  from (
    values
      ('Makanan & Minuman', 'expense', 'restaurant', 4292617766::bigint),
      ('Perumahan', 'expense', 'home', 4279646815::bigint),
      ('Transportasi', 'expense', 'directions_car', 4281902555::bigint),
      ('Gaji', 'income', 'trending_up', 4279673674::bigint),
      ('Tabungan', 'income', 'savings', 4281902555::bigint)
  ) as defaults(name, type, icon_name, color_value)
  where not exists (
    select 1
    from public.categories c
    where c.business_id = caller_business_id
      and c.name = defaults.name
      and c.type = defaults.type
  );
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'business_settings', 'categories', 'transactions', 'budgets', 'savings',
    'debts', 'cash_accounts', 'account_transfers', 'debt_payments',
    'transaction_attachments', 'recurring_transactions', 'import_jobs',
    'export_jobs', 'cash_reconciliations', 'financial_periods',
    'correction_requests', 'notifications', 'reminders'
  ]
  loop
    execute format('drop trigger if exists %I on public.%I',
      table_name || '_business_context', table_name);
    execute format(
      'create trigger %I before insert or update on public.%I for each row execute function public.enforce_business_context()',
      table_name || '_business_context', table_name
    );
    execute format('drop trigger if exists %I on public.%I',
      table_name || '_touch_updated_at', table_name);
    execute format(
      'create trigger %I before update on public.%I for each row execute function public.touch_updated_at()',
      table_name || '_touch_updated_at', table_name
    );
  end loop;
end;
$$;

drop trigger if exists transactions_audit_change on public.transactions;
create trigger transactions_audit_change
after insert or update on public.transactions
for each row execute function public.audit_transaction_change();

create or replace view public.cash_account_balances
with (security_invoker = true)
as
select
  a.id as cash_account_id,
  a.business_id,
  a.name,
  a.account_type,
  a.is_active,
  a.opening_balance
    + coalesce(t.transaction_balance, 0)
    + coalesce(x.transfer_balance, 0)
    + coalesce(d.debt_payment_balance, 0) as balance
from public.cash_accounts a
left join lateral (
  select sum(
    case t.transaction_type
      when 'income' then t.amount
      when 'expense' then -t.amount
      else 0
    end
  ) as transaction_balance
  from public.transactions t
  where t.cash_account_id = a.id
    and t.business_id = a.business_id
    and t.status = 'posted'
) t on true
left join lateral (
  select sum(
    case
      when x.from_cash_account_id = a.id then -x.amount
      when x.to_cash_account_id = a.id then x.amount
      else 0
    end
  ) as transfer_balance
  from public.account_transfers x
  where x.business_id = a.business_id and x.status = 'posted'
) x on true
left join lateral (
  select sum(
    case
      when debt.type = 'payable'
        then -(p.principal_amount + p.interest_amount + p.fee_amount)
      else p.principal_amount + p.interest_amount + p.fee_amount
    end
  ) as debt_payment_balance
  from public.debt_payments p
  join public.debts debt on debt.id = p.debt_id
    and debt.business_id = p.business_id
  where p.cash_account_id = a.id
    and p.business_id = a.business_id
    and p.status = 'posted'
) d on true;

drop policy if exists businesses_access on public.businesses;
alter table public.profiles enable row level security;
alter table public.businesses enable row level security;
alter table public.categories enable row level security;
drop policy if exists businesses_read on public.businesses;
drop policy if exists businesses_insert on public.businesses;
drop policy if exists businesses_update on public.businesses;
drop policy if exists businesses_delete on public.businesses;
create policy businesses_read on public.businesses
for select to authenticated
using (
  owner_id = (select auth.uid())
  or public.has_app_role(array['admin', 'creator'])
);
create policy businesses_insert on public.businesses
for insert to authenticated
with check (
  owner_id = (select auth.uid())
  or public.has_app_role(array['creator'])
);
create policy businesses_update on public.businesses
for update to authenticated
using (
  owner_id = (select auth.uid())
  or public.has_app_role(array['creator'])
)
with check (
  owner_id = (select auth.uid())
  or public.has_app_role(array['creator'])
);
create policy businesses_delete on public.businesses
for delete to authenticated
using (public.has_app_role(array['creator']));

drop policy if exists categories_access on public.categories;
drop policy if exists categories_read on public.categories;
drop policy if exists categories_insert on public.categories;
drop policy if exists categories_update on public.categories;
drop policy if exists categories_delete on public.categories;
create policy categories_read on public.categories
for select to authenticated
using (
  is_global
  or public.can_read_business(business_id)
);
create policy categories_insert on public.categories
for insert to authenticated
with check (
  (not is_global and public.owns_business(business_id))
  or public.has_app_role(array['creator'])
);
create policy categories_update on public.categories
for update to authenticated
using (
  (not is_global and public.owns_business(business_id))
  or public.has_app_role(array['creator'])
)
with check (
  (not is_global and public.owns_business(business_id))
  or public.has_app_role(array['creator'])
);
create policy categories_delete on public.categories
for delete to authenticated
using (
  (not is_global and public.owns_business(business_id))
  or public.has_app_role(array['creator'])
);

drop policy if exists transactions_access on public.transactions;
drop policy if exists budgets_access on public.budgets;
drop policy if exists savings_access on public.savings;
drop policy if exists debts_access on public.debts;
drop policy if exists notifications_access on public.notifications;
drop policy if exists notifications_update on public.notifications;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'business_settings', 'transactions', 'budgets', 'savings', 'debts',
    'cash_accounts', 'account_transfers', 'debt_payments',
    'transaction_attachments', 'recurring_transactions', 'import_jobs',
    'export_jobs', 'cash_reconciliations', 'financial_periods',
    'notifications', 'reminders'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on table public.%I from public, anon, authenticated', table_name);
    execute format('grant select, insert, update, delete on table public.%I to authenticated', table_name);
    execute format('drop policy if exists %I on public.%I',
      table_name || '_read', table_name);
    execute format('drop policy if exists %I on public.%I',
      table_name || '_insert', table_name);
    execute format('drop policy if exists %I on public.%I',
      table_name || '_update', table_name);
    execute format('drop policy if exists %I on public.%I',
      table_name || '_delete', table_name);
    execute format(
      'create policy %I on public.%I for select to authenticated using (public.can_read_business(business_id))',
      table_name || '_read', table_name
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated with check (public.owns_business(business_id) or public.has_app_role(array[''creator'']))',
      table_name || '_insert', table_name
    );
    execute format(
      'create policy %I on public.%I for update to authenticated using (public.owns_business(business_id) or public.has_app_role(array[''creator''])) with check (public.owns_business(business_id) or public.has_app_role(array[''creator'']))',
      table_name || '_update', table_name
    );
    execute format(
      'create policy %I on public.%I for delete to authenticated using (public.has_app_role(array[''creator'']))',
      table_name || '_delete', table_name
    );
  end loop;
end;
$$;

drop policy if exists audit_logs_select on public.audit_logs;
drop policy if exists audit_logs_admin_read on public.audit_logs;
create policy audit_logs_admin_read on public.audit_logs
for select to authenticated
using (public.has_app_role(array['admin', 'creator']));

alter table public.audit_logs enable row level security;
revoke all on public.audit_logs from public, anon, authenticated;
grant select on public.audit_logs to authenticated;

alter table public.security_events enable row level security;
revoke all on public.security_events from public, anon, authenticated;
grant select on public.security_events to authenticated;
drop policy if exists security_events_creator_read on public.security_events;
create policy security_events_creator_read on public.security_events
for select to authenticated
using (public.has_app_role(array['creator']));

alter table public.system_announcements enable row level security;
revoke all on public.system_announcements from public, anon, authenticated;
grant select, insert, update, delete on public.system_announcements to authenticated;
drop policy if exists announcements_read on public.system_announcements;
drop policy if exists announcements_admin_insert on public.system_announcements;
drop policy if exists announcements_admin_update on public.system_announcements;
drop policy if exists announcements_admin_delete on public.system_announcements;
create policy announcements_read on public.system_announcements
for select to authenticated
using (
  is_published or public.has_app_role(array['admin', 'creator'])
);
create policy announcements_admin_insert on public.system_announcements
for insert to authenticated
with check (public.has_app_role(array['admin', 'creator']));
create policy announcements_admin_update on public.system_announcements
for update to authenticated
using (public.has_app_role(array['admin', 'creator']))
with check (public.has_app_role(array['admin', 'creator']));
create policy announcements_admin_delete on public.system_announcements
for delete to authenticated
using (public.has_app_role(array['admin', 'creator']));

drop trigger if exists system_announcements_touch_updated_at
  on public.system_announcements;
create trigger system_announcements_touch_updated_at
before update on public.system_announcements
for each row execute function public.touch_updated_at();

alter table public.correction_requests enable row level security;
revoke all on public.correction_requests from public, anon, authenticated;
grant select, insert on public.correction_requests to authenticated;
grant update (status, reviewed_by, reviewed_at, review_notes, updated_by)
  on public.correction_requests to authenticated;
drop policy if exists correction_requests_read on public.correction_requests;
drop policy if exists correction_requests_submit on public.correction_requests;
drop policy if exists correction_requests_review on public.correction_requests;
create policy correction_requests_read on public.correction_requests
for select to authenticated
using (
  user_id = (select auth.uid())
  or public.has_app_role(array['admin', 'creator'])
);
create policy correction_requests_submit on public.correction_requests
for insert to authenticated
with check (
  user_id = (select auth.uid())
  and public.owns_business(business_id)
);
create policy correction_requests_review on public.correction_requests
for update to authenticated
using (public.has_app_role(array['admin', 'creator']))
with check (public.has_app_role(array['admin', 'creator']));

revoke all on function public.owns_business(uuid) from public, anon, authenticated;
revoke all on function public.can_read_business(uuid) from public, anon, authenticated;
grant execute on function public.owns_business(uuid) to authenticated;
grant execute on function public.can_read_business(uuid) to authenticated;
revoke all on function public.admin_upsert_global_category(uuid, text, text, text, bigint)
  from public, anon, authenticated;
revoke all on function public.admin_delete_global_category(uuid)
  from public, anon, authenticated;
revoke all on function public.admin_send_notification(uuid, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.admin_upsert_global_category(uuid, text, text, text, bigint)
  to authenticated;
grant execute on function public.admin_delete_global_category(uuid)
  to authenticated;
grant execute on function public.admin_send_notification(uuid, uuid, text, text)
  to authenticated;
revoke all on function public.enforce_business_context() from public, anon, authenticated;
revoke all on function public.audit_transaction_change() from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.ensure_current_profile() from public, anon, authenticated;
grant execute on function public.ensure_current_profile() to authenticated;
grant select on public.cash_account_balances to authenticated;
grant select, insert, update, delete on public.savings_goals to authenticated;

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'transaction-receipts',
  'transaction-receipts',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists transaction_receipts_read on storage.objects;
create policy transaction_receipts_read on storage.objects
for select to authenticated
using (
  bucket_id = 'transaction-receipts'
  and (
    public.owns_business(
      case
        when split_part(name, '/', 1) ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then split_part(name, '/', 1)::uuid
        else null
      end
    )
    or public.has_app_role(array['admin', 'creator'])
  )
);

drop policy if exists transaction_receipts_insert on storage.objects;
create policy transaction_receipts_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'transaction-receipts'
  and (
    public.owns_business(
      case
        when split_part(name, '/', 1) ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then split_part(name, '/', 1)::uuid
        else null
      end
    )
    or public.has_app_role(array['creator'])
  )
);

drop policy if exists transaction_receipts_delete on storage.objects;
create policy transaction_receipts_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'transaction-receipts'
  and (
    public.owns_business(
      case
        when split_part(name, '/', 1) ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then split_part(name, '/', 1)::uuid
        else null
      end
    )
    or public.has_app_role(array['creator'])
  )
);

commit;
