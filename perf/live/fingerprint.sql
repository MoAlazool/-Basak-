-- Deterministic schema fingerprint of the Basak application schema (public), plus
-- the pieces of other schemas Basak relies on. Read-only. Compare before/after.
with
t as (select string_agg(c.relname || ':' || c.relkind::text, ',' order by c.relname) s, count(*) n
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relkind in ('r','p','v','m')),
col as (select string_agg(format('%s.%s:%s:%s:%s', c.relname, a.attname, format_type(a.atttypid, a.atttypmod), a.attnotnull, pg_get_expr(d.adbin, d.adrelid)), ',' order by c.relname, a.attnum) s, count(*) n
        from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace
        left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
        where n.nspname = 'public' and c.relkind in ('r','p','v','m') and a.attnum > 0 and not a.attisdropped),
con as (select string_agg(conrelid::regclass || ':' || conname || ':' || pg_get_constraintdef(c.oid), ',' order by conrelid::regclass::text, conname) s, count(*) n
        from pg_constraint c join pg_namespace n on n.oid = c.connamespace where n.nspname = 'public'),
idx as (select string_agg(indexdef, ',' order by indexname) s, count(*) n from pg_indexes where schemaname = 'public'),
fn as (select string_agg(pg_get_functiondef(p.oid), ',' order by p.proname, pg_get_function_identity_arguments(p.oid)) s, count(*) n
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.prokind in ('f','p')),
trg as (select string_agg(pg_get_triggerdef(t.oid), ',' order by t.tgrelid::regclass::text, t.tgname) s, count(*) n
        from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
        where not t.tgisinternal and n.nspname in ('public','storage','auth')),
pol as (select string_agg(format('%s.%s:%s:%s:%s:%s:%s', schemaname, tablename, policyname, cmd, roles, qual, with_check), ',' order by schemaname, tablename, policyname) s, count(*) n
        from pg_policies where schemaname in ('public','storage','realtime')),
vw as (select string_agg(c.relname || ':' || pg_get_viewdef(c.oid), ',' order by c.relname) s, count(*) n
       from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind in ('v','m')),
typ as (select string_agg(t.typname || ':' || coalesce((select string_agg(enumlabel, '|' order by enumsortorder) from pg_enum e where e.enumtypid = t.oid), ''), ',' order by t.typname) s, count(*) n
        from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typtype in ('e','d','c') and not exists (select 1 from pg_class c where c.reltype = t.oid)),
ext as (select string_agg(extname || ':' || extversion, ',' order by extname) s, count(*) n from pg_extension),
pub as (select string_agg(schemaname || '.' || tablename, ',' order by schemaname, tablename) s, count(*) n from pg_publication_tables where pubname = 'supabase_realtime'),
cr as (select string_agg(jobname || ':' || schedule || ':' || command, ',' order by jobname) s, count(*) n from cron.job),
grt as (select string_agg(format('%s:%s:%s', table_name, grantee, privilege_type), ',' order by table_name, grantee, privilege_type) s, count(*) n
        from information_schema.role_table_grants where table_schema = 'public'),
bk as (select string_agg(id || ':' || public::text || ':' || coalesce(file_size_limit::text,''), ',' order by id) s, count(*) n from storage.buckets)
select k, n, md5(coalesce(s, '')) hash from (
  select 'tables' k, n, s from t union all select 'columns', n, s from col union all select 'constraints', n, s from con
  union all select 'indexes', n, s from idx union all select 'functions', n, s from fn union all select 'triggers', n, s from trg
  union all select 'policies', n, s from pol union all select 'views', n, s from vw union all select 'types', n, s from typ
  union all select 'extensions', n, s from ext union all select 'realtime_publication', n, s from pub
  union all select 'cron', n, s from cr union all select 'grants', n, s from grt union all select 'buckets', n, s from bk) x
order by k;
