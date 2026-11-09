-- Read-only integrity and security audit. Run after applying both schema migrations.
-- Findings require review; this script never deletes or changes application data.
with findings as (
  select
    'profile_without_auth_user'::text as finding,
    p.id::text as record_id,
    jsonb_build_object('email', p.email, 'role', p.role) as details
  from public.profiles p
  left join auth.users u on u.id = p.id
  where u.id is null

  union all

  select
    'profile_email_mismatch',
    p.id::text,
    jsonb_build_object(
      'profile_email', p.email,
      'auth_email', u.email
    )
  from public.profiles p
  join auth.users u on u.id = p.id
  where lower(p.email) is distinct from lower(u.email)

  union all

  select
    'duplicate_profile_email',
    lower(email),
    jsonb_build_object('profile_ids', jsonb_agg(id), 'count', count(*))
  from public.profiles
  group by lower(email)
  having count(*) > 1

  union all

  select
    'business_without_profile_owner',
    b.id::text,
    jsonb_build_object('owner_id', b.owner_id)
  from public.businesses b
  left join public.profiles p on p.id = b.owner_id
  where p.id is null

  union all

  select
    'owner_with_multiple_businesses',
    owner_id::text,
    jsonb_build_object('business_ids', jsonb_agg(id), 'count', count(*))
  from public.businesses
  group by owner_id
  having count(*) > 1

  union all

  select
    'business_missing_settings',
    b.id::text,
    jsonb_build_object('owner_id', b.owner_id, 'business_name', b.business_name)
  from public.businesses b
  left join public.business_settings s on s.business_id = b.id
  where s.business_id is null

  union all

  select
    'business_missing_cash_account',
    b.id::text,
    jsonb_build_object('owner_id', b.owner_id, 'business_name', b.business_name)
  from public.businesses b
  where not exists (
    select 1 from public.cash_accounts a where a.business_id = b.id
  )

  union all

  select
    'finance_user_does_not_own_business',
    t.id::text,
    jsonb_build_object(
      'table', 'transactions',
      'user_id', t.user_id,
      'business_owner_id', b.owner_id
    )
  from public.transactions t
  join public.businesses b on b.id = t.business_id
  where t.user_id is distinct from b.owner_id

  union all

  select
    'transaction_cash_account_business_mismatch',
    t.id::text,
    jsonb_build_object(
      'business_id', t.business_id,
      'cash_account_id', t.cash_account_id
    )
  from public.transactions t
  where not exists (
    select 1
    from public.cash_accounts a
    where a.id = t.cash_account_id and a.business_id = t.business_id
  )

  union all

  select
    'transaction_category_business_mismatch',
    t.id::text,
    jsonb_build_object(
      'business_id', t.business_id,
      'category_id', c.id,
      'category_business_id', c.business_id
    )
  from public.transactions t
  join public.categories c on c.id = t.category_id
  where not c.is_global and c.business_id is distinct from t.business_id

  union all

  select
    'duplicate_business_categories',
    c.business_id::text,
    jsonb_build_object(
      'name', lower(trim(c.name)),
      'type', c.type,
      'category_ids', jsonb_agg(c.id),
      'used_by_transactions', count(distinct t.id)
    )
  from public.categories c
  left join public.transactions t on t.category_id = c.id
  where not c.is_global
  group by c.business_id, lower(trim(c.name)), c.type
  having count(*) > 1

  union all

  select
    'attachment_metadata_without_storage_object',
    a.id::text,
    jsonb_build_object(
      'business_id', a.business_id,
      'transaction_id', a.transaction_id,
      'storage_path', a.storage_path
    )
  from public.transaction_attachments a
  left join storage.objects o
    on o.bucket_id = 'transaction-receipts' and o.name = a.storage_path
  where o.id is null

  union all

  select
    'receipt_storage_object_without_metadata',
    o.name,
    jsonb_build_object('bucket_id', o.bucket_id, 'created_at', o.created_at)
  from storage.objects o
  left join public.transaction_attachments a on a.storage_path = o.name
  where o.bucket_id = 'transaction-receipts' and a.id is null

  union all

  select
    'duplicate_rls_policies',
    schemaname || '.' || tablename || ':' || policyname,
    jsonb_build_object(
      'command', cmd,
      'roles', roles,
      'using', qual,
      'with_check', with_check
    )
  from (
    select
      schemaname,
      tablename,
      policyname,
      cmd,
      roles,
      qual,
      with_check,
      count(*) over (
        partition by schemaname, tablename, cmd, roles, qual, with_check
      ) as duplicate_count
    from pg_policies
    where schemaname in ('public', 'storage')
  ) policies
  where duplicate_count > 1

  union all

  select
    'security_definer_without_fixed_search_path',
    n.nspname || '.' || p.proname || '(' ||
      pg_get_function_identity_arguments(p.oid) || ')',
    jsonb_build_object('function', p.oid::regprocedure::text)
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prosecdef
    and not coalesce(array_to_string(p.proconfig, ','), '') like '%search_path%'

  union all

  select
    'duplicate_non_primary_indexes',
    schemaname || '.' || tablename,
    jsonb_build_object(
      'index_definition', indexdef,
      'index_names', jsonb_agg(indexname),
      'count', count(*)
    )
  from pg_indexes i
  where schemaname = 'public'
    and not exists (
      select 1
      from pg_index x
      where x.indexrelid = i.indexname::regclass
        and x.indisprimary
    )
  group by schemaname, tablename, indexdef
  having count(*) > 1
)
select finding, record_id, details
from findings
order by finding, record_id;
