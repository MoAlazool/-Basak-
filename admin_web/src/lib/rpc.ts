/**
 * Server functions that may not exist yet. The dashboard is deployed on its own
 * schedule, so for a while it can meet a database that does not have a function
 * it knows about; it then does the same job the older way.
 */

/** PostgREST's code for "no function with this name and these parameters". */
const MISSING_FUNCTION = 'PGRST202';
/** How long a function is taken as missing before it is asked for again. */
const RETRY_AFTER = 5 * 60 * 1000;

const missingSince = new Map<string, number>();

interface Failure { code?: string; message: string }
type Answer<T> = { data: T | null; error: Failure | null };

/**
 * `call`'s answer, or `fallback`'s when the function is not in the database.
 * Any other failure is thrown as it is (the server's messages are written for
 * the admin). A function found missing is not asked for again for a few
 * minutes, so the older way does not cost a failed request every time.
 */
export async function rpcOr<T>(
  name: string, call: () => PromiseLike<Answer<T>>, fallback: () => Promise<T>, now: () => number = Date.now,
): Promise<T> {
  const since = missingSince.get(name);
  if (since !== undefined && now() - since < RETRY_AFTER) return fallback();
  const { data, error } = await call();
  if (!error) {
    missingSince.delete(name);
    return data as T;
  }
  if (error.code !== MISSING_FUNCTION) throw new Error(error.message);
  missingSince.set(name, now());
  return fallback();
}

/** For tests. */
export const forgetMissingFunctions = () => missingSince.clear();
