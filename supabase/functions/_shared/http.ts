// What every browser- or app-facing function answers with: CORS, JSON, errors.

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

/** An error with an HTTP status: 401 = not signed in / invalid session, 403 = not allowed. */
export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

export function errorStatus(error: unknown): number {
  return error instanceof HttpError ? error.status : 400;
}

export function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/** Readable message for thrown Errors and for PostgREST / Auth error objects. */
export function errorMessage(error: unknown, fallback: string): string {
  if (error && typeof error === 'object' && 'message' in error) {
    const message = String((error as { message?: unknown }).message ?? '').trim();
    if (message) return message;
  }
  return fallback;
}

/** The answer to a CORS preflight or a wrong method; null for the POST the function serves. */
export function preflight(request: Request): Response | null {
  if (request.method === 'OPTIONS') return new Response('ok', { status: 200, headers: corsHeaders });
  if (request.method !== 'POST') return jsonResponse({ error: 'طريقة الطلب غير مدعومة.' }, 405);
  return null;
}

/**
 * Runs independent steps at the same time and waits for all of them. When
 * several fail, the error of the earliest one in the list is thrown, so the
 * caller sees the same error as if the steps had run one after another.
 */
export async function together<T extends readonly unknown[]>(
  steps: { [K in keyof T]: PromiseLike<T[K]> },
): Promise<T> {
  const settled = await Promise.allSettled(steps as readonly PromiseLike<unknown>[]);
  for (const result of settled) if (result.status === 'rejected') throw result.reason;
  return settled.map((result) => (result as PromiseFulfilledResult<unknown>).value) as unknown as T;
}
