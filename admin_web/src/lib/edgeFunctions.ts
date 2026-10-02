import { FunctionsFetchError, FunctionsHttpError, FunctionsRelayError } from '@supabase/supabase-js';
import { supabase } from './supabase';

/**
 * Calls a Supabase Edge Function and turns its failures into a readable Arabic message.
 * - HTTP errors: shows the `error` text returned by the function itself.
 * - Fetch/CORS errors: the function is usually not deployed (or blocked by JWT verification).
 */
export async function invokeEdgeFunction<T = unknown>(name: string, body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke(name, { body });
  if (!error) return data as T;

  if (error instanceof FunctionsHttpError) {
    let message = '';
    try {
      const payload = await error.context.json();
      message = typeof payload?.error === 'string' ? payload.error : '';
    } catch {
      try { message = await error.context.text(); } catch { /* ignore */ }
    }
    throw new Error(message || `فشل تنفيذ العملية (HTTP ${error.context?.status ?? ''}).`);
  }
  if (error instanceof FunctionsFetchError) {
    throw new Error(
      `تعذر الاتصال بوظيفة الخادم "${name}". تأكد من نشرها على Supabase (supabase functions deploy ${name} --no-verify-jwt) ومن اتصال الإنترنت.`,
    );
  }
  if (error instanceof FunctionsRelayError) {
    throw new Error('خطأ مؤقت في خادم Supabase. حاول مرة أخرى بعد قليل.');
  }
  throw error;
}
