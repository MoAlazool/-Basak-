// The two Supabase clients a function needs, made once per isolate, and the
// one way a caller's session is checked.
import { createClient, type SupabaseClient, type User } from 'https://esm.sh/@supabase/supabase-js@2';
import { HttpError } from './http.ts';

// No client here ever holds a session: every call names its own credentials.
const STATELESS = { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } };

function make(keyName: 'SUPABASE_SERVICE_ROLE_KEY' | 'SUPABASE_ANON_KEY'): SupabaseClient {
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get(keyName);
  if (!url || !key) throw new Error('إعدادات الخادم غير مكتملة.');
  return createClient(url, key, STATELESS);
}

let service: SupabaseClient | undefined;
let anon: SupabaseClient | undefined;

/** Full access. Only ever used after the caller has been identified and checked. */
export function serviceClient(): SupabaseClient {
  return service ??= make('SUPABASE_SERVICE_ROLE_KEY');
}

/** Used for one thing: asking Auth whose session token this is. */
export function anonClient(): SupabaseClient {
  return anon ??= make('SUPABASE_ANON_KEY');
}

/**
 * A client of its own for checking a password. Signing in stores the session
 * on the client, so this must never be one of the shared ones.
 */
export function passwordCheckClient(): SupabaseClient {
  return make('SUPABASE_ANON_KEY');
}

export interface Clients {
  anon: SupabaseClient;
  service: SupabaseClient;
}

export function bearerToken(request: Request): string | null {
  return request.headers.get('Authorization')?.replace(/^Bearer\s+/i, '').trim() || null;
}

/**
 * The signed-in user behind the request, as Auth itself reports it (so a
 * revoked session or a deleted account is refused). 401 otherwise.
 */
export async function requireUser(
  request: Request, messages: { missing: string; invalid: string }, client?: SupabaseClient,
): Promise<User> {
  const token = bearerToken(request);
  if (!token) throw new HttpError(401, messages.missing);
  const { data: { user }, error } = await (client ?? anonClient()).auth.getUser(token);
  if (error || !user) throw new HttpError(401, messages.invalid);
  return user;
}
