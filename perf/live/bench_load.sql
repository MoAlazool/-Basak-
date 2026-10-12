-- Load-test helpers for the live concurrency benchmark (docs/audit/2026-10-CAPACITY.md,
-- section 3). Run after perf/live/bench.sql, in the same throw-away `bench` schema;
-- dropped with it. The VUs run in the Edge Function perf/live/bench-load, fired
-- from here with pg_net; each invocation returns counters and latency histograms
-- that load_report merges.
--
--   bench.load_session  signed-in benchmark accounts (filled by bench-admin's
--                       "sessions" action; tokens expire after an hour)
--   bench.load_fire     starts one stage: N VUs, ramp / hold / ramp-down, think time
--   bench.load_report   merges a stage ('hold' window or 'all')
--   bench.server_snap   what the database shows of itself during a stage

CREATE TABLE IF NOT EXISTS bench.load_session (id uuid PRIMARY KEY, role text NOT NULL, company_id uuid, ctx jsonb NOT NULL, token text, expires_at timestamptz);
CREATE TABLE IF NOT EXISTS bench.load_run (run text, stage text, scenario text, vus int, invocations int, started_at timestamptz, t0 timestamptz, ramp_s int, hold_s int, down_s int, req_ids bigint[], notes jsonb, PRIMARY KEY (run, stage));
CREATE TABLE IF NOT EXISTS bench.load_server (run text, stage text, at timestamptz DEFAULT clock_timestamp(), kind text, data jsonb);

-- Fire one stage: N VUs split into invocations of at most p_per VUs, role mix 90/7/3.
CREATE OR REPLACE FUNCTION bench.load_fire(p_run text, p_stage text, p_mode text, p_vus int, p_ramp int, p_hold int, p_down int,
                                           p_think numeric[] DEFAULT '{3,8}', p_per int DEFAULT 25, p_lead_s int DEFAULT 8)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_t0 bigint := (extract(epoch FROM clock_timestamp()) * 1000)::bigint + p_lead_s * 1000;
  v_today date := public.cairo_today();
  v_week_from date := v_today - ((extract(dow FROM v_today)::int + 1) % 7);
  v_inv int := ceil(p_vus::numeric / p_per)::int;
  v_ids bigint[] := '{}';
  v_secret text := (SELECT dispatch_secret FROM public.push_runtime WHERE id);
  v_req bigint;
  i int;
BEGIN
  CREATE TEMP TABLE lf_vu ON COMMIT DROP AS
  WITH pool AS (
    SELECT s.*, row_number() OVER (PARTITION BY role ORDER BY md5(id::text || p_stage)) rn,
           count(*) OVER (PARTITION BY role) cnt
    FROM bench.load_session s WHERE token IS NOT NULL AND expires_at > now() + interval '3 minutes'
  ), slots AS (
    SELECT g AS k,
      CASE WHEN p_mode = 'scan' THEN 'supervisor'
           WHEN (g % 100) < 90 THEN 'student' WHEN (g % 100) < 97 THEN 'supervisor' ELSE 'company_admin' END AS role,
      (p_mode = 'scan' AND g % 4 = 3) AS reader
    FROM generate_series(0, p_vus - 1) g
  )
  SELECT sl.k, sl.reader, jsonb_build_object('role', p.role, 'id', p.id, 'token', p.token, 'ctx', p.ctx, 'reader', sl.reader) AS vu
  FROM slots sl
  JOIN LATERAL (SELECT * FROM pool WHERE pool.role = sl.role AND pool.rn = 1 + (sl.k % pool.cnt)) p ON true;

  FOR i IN 0 .. v_inv - 1 LOOP
    SELECT net.http_post(
      url := 'https://hnwpkkryxovhmsrokdsd.supabase.co/functions/v1/bench-load',
      body := jsonb_build_object('inv', i, 'mode', p_mode, 't0', v_t0, 'ramp_s', p_ramp, 'hold_s', p_hold, 'down_s', p_down,
        'think', to_jsonb(p_think), 'today', v_today, 'week_from', v_week_from, 'week_to', v_week_from + 6,
        'from30', v_today - 29, 'timeout_ms', 10000,
        'vus', (SELECT jsonb_agg(vu ORDER BY k) FROM lf_vu WHERE k % v_inv = i)),
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-dispatch-secret', v_secret),
      timeout_milliseconds := 170000) INTO v_req;
    v_ids := v_ids || v_req;
  END LOOP;
  INSERT INTO bench.load_run (run, stage, scenario, vus, invocations, started_at, t0, ramp_s, hold_s, down_s, req_ids, notes)
  VALUES (p_run, p_stage, p_mode, p_vus, v_inv, clock_timestamp(), to_timestamp(v_t0 / 1000.0), p_ramp, p_hold, p_down, v_ids,
          jsonb_build_object('think', p_think, 'per_invocation', p_per))
  ON CONFLICT (run, stage) DO UPDATE SET started_at = EXCLUDED.started_at, t0 = EXCLUDED.t0, req_ids = EXCLUDED.req_ids,
    vus = EXCLUDED.vus, invocations = EXCLUDED.invocations, notes = EXCLUDED.notes;
  RETURN jsonb_build_object('stage', p_stage, 'vus', p_vus, 'invocations', v_inv, 't0', to_timestamp(v_t0 / 1000.0),
    'ends_after', to_timestamp(v_t0 / 1000.0) + make_interval(secs => p_ramp + p_hold + p_down));
END;
$$;

-- Percentile from merged log-buckets (bucket k = [1.1^k, 1.1^(k+1)) ms; reports the bucket's upper edge).
CREATE OR REPLACE FUNCTION bench.hist_pct(h jsonb, q numeric) RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
  WITH b AS (SELECT key::int k, value::bigint n FROM jsonb_each_text(h)),
  t AS (SELECT sum(n) tot FROM b),
  c AS (SELECT k, sum(n) OVER (ORDER BY k) cum FROM b)
  SELECT round(power(1.1, min(k) + 1)::numeric, 0) FROM c, t WHERE c.cum >= q * t.tot
$$;

-- Merge the invocations of a stage. p_part: 'hold' (sustained window) or 'all'.
CREATE OR REPLACE FUNCTION bench.load_report(p_run text, p_stage text, p_part text DEFAULT 'hold') RETURNS jsonb LANGUAGE sql STABLE AS $$
  WITH r AS (SELECT * FROM bench.load_run WHERE run = p_run AND stage = p_stage),
  resp AS (
    SELECT h.id, h.status_code, h.timed_out, h.error_msg,
           CASE WHEN h.status_code = 200 THEN h.content::jsonb END AS c
    FROM r, unnest(r.req_ids) rid JOIN net._http_response h ON h.id = rid
  ),
  ep AS (
    SELECT e.key AS name, e.value AS s FROM resp, jsonb_each(resp.c -> p_part) e WHERE resp.c IS NOT NULL
  ),
  per AS (
    SELECT name, sum((s->>'n')::bigint) n, sum((s->>'ok')::bigint) ok, sum((s->>'c4')::bigint) c4, sum((s->>'c429')::bigint) c429,
           sum((s->>'c5')::bigint) c5, sum((s->>'to')::bigint) tmo, sum((s->>'conn')::bigint) conn, sum((s->>'bytes')::bigint) bytes,
           (SELECT jsonb_object_agg(k, n) FROM (SELECT hh.key k, sum(hh.value::bigint) n FROM ep e2, jsonb_each_text(e2.s->'h') hh
                                                  WHERE e2.name = ep.name GROUP BY hh.key) z) h
    FROM ep GROUP BY name
  ),
  tot_h AS (SELECT jsonb_object_agg(k, n) h FROM (SELECT hh.key k, sum(hh.value::bigint) n FROM ep, jsonb_each_text(ep.s->'h') hh GROUP BY hh.key) z),
  tot AS (SELECT sum(n) n, sum(ok) ok, sum(c4) c4, sum(c429) c429, sum(c5) c5, sum(tmo) tmo, sum(conn) conn, sum(bytes) bytes FROM per),
  secs AS (SELECT CASE WHEN p_part = 'hold' THEN (SELECT hold_s FROM r) ELSE (SELECT ramp_s + hold_s + down_s FROM r) END::numeric AS s),
  scans AS (SELECT jsonb_object_agg(k, n) j FROM (SELECT sr.key k, sum(sr.value::bigint) n FROM resp, jsonb_each_text(resp.c->'scan_results') sr GROUP BY 1) z)
  SELECT jsonb_build_object(
    'stage', p_stage, 'part', p_part, 'mode', (SELECT scenario FROM r), 'vus_planned', (SELECT vus FROM r),
    'invocations', (SELECT invocations FROM r),
    'inv_returned', (SELECT count(*) FROM resp WHERE c IS NOT NULL),
    'inv_failed', (SELECT count(*) FROM resp WHERE c IS NULL),
    'inv_errors', (SELECT jsonb_agg(DISTINCT coalesce(error_msg, status_code::text)) FROM resp WHERE c IS NULL),
    'inv_cut', (SELECT count(*) FROM resp WHERE (c->>'cut')::boolean),
    'vus_active_max', (SELECT sum((c->>'max_active')::int) FROM resp),
    'requests', t.n, 'ok', t.ok, 'rps', round(t.n / s.s, 1), 'ok_rps', round(t.ok / s.s, 1),
    'error_pct', round(100.0 * (t.n - t.ok) / NULLIF(t.n, 0), 2),
    'http4xx', t.c4, 'http429', t.c429, 'http5xx', t.c5, 'timeouts', t.tmo, 'conn_fail', t.conn,
    'mb', round(t.bytes / 1048576.0, 2), 'kb_s', round(t.bytes / 1024.0 / s.s, 1),
    'p50', bench.hist_pct(th.h, 0.5), 'p95', bench.hist_pct(th.h, 0.95), 'p99', bench.hist_pct(th.h, 0.99),
    'max', (SELECT round(power(1.1, max(key::int) + 1)::numeric) FROM jsonb_each(th.h)),
    'scan_results', (SELECT j FROM scans),
    'endpoints', (SELECT jsonb_object_agg(name, jsonb_build_object('n', n, 'err', n - ok, 'c4', c4, 'c429', c429, 'c5', c5, 'to', tmo,
                    'p50', bench.hist_pct(h, 0.5), 'p95', bench.hist_pct(h, 0.95), 'p99', bench.hist_pct(h, 0.99))) FROM per))
  FROM tot t, secs s, tot_h th
$$;

-- Server-side snapshot (what the project exposes).
CREATE OR REPLACE FUNCTION bench.server_snap(p_run text, p_stage text, p_kind text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v jsonb;
BEGIN
  v := jsonb_build_object(
    'db_bytes', pg_database_size(current_database()),
    'conns', (SELECT jsonb_object_agg(coalesce(state, 'null'), n) FROM (SELECT state, count(*) n FROM pg_stat_activity WHERE datname = current_database() GROUP BY 1) x),
    'conns_by_user', (SELECT jsonb_object_agg(coalesce(usename, '?'), n) FROM (SELECT usename, count(*) n FROM pg_stat_activity WHERE datname = current_database() GROUP BY 1) x),
    'waits', (SELECT jsonb_object_agg(w, n) FROM (SELECT coalesce(wait_event_type || ':' || wait_event, 'cpu') w, count(*) n FROM pg_stat_activity WHERE state = 'active' AND datname = current_database() GROUP BY 1) x),
    'db', (SELECT jsonb_build_object('xact_commit', xact_commit, 'xact_rollback', xact_rollback, 'blks_read', blks_read, 'blks_hit', blks_hit,
             'deadlocks', deadlocks, 'temp_bytes', temp_bytes, 'tup_inserted', tup_inserted, 'tup_updated', tup_updated, 'conflicts', conflicts)
           FROM pg_stat_database WHERE datname = current_database()),
    'max_connections', current_setting('max_connections')::int);
  INSERT INTO bench.load_server (run, stage, kind, data) VALUES (p_run, p_stage, p_kind, v);
  RETURN v;
END;
$$;
