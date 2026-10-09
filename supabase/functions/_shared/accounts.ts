// Sign-in accounts (Supabase Auth) and the profile rows that belong to them.
//
// A profile row (students / supervisors / admins) has the account's id and is
// deleted with it (ON DELETE CASCADE), so "create the account, then the rows"
// is undone by deleting the account, and "delete the account" takes the rows.
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { HttpError } from './http.ts';

const ALREADY_USED = /already|registered|exists/i;
const NOT_FOUND = /not found|does not exist/i;

export interface NewLogin {
  email: string;
  password: string;
  metadata: Record<string, unknown>;
  /** Said (409) when the address already has an account. */
  takenMessage: string;
  /** Said when Auth gives no reason. */
  failedMessage: string;
}

/** Creates a confirmed sign-in account and returns its id. */
export async function createLogin(service: SupabaseClient, login: NewLogin): Promise<string> {
  const { data, error } = await service.auth.admin.createUser({
    email: login.email, password: login.password, email_confirm: true, user_metadata: login.metadata,
  });
  if (error || !data.user) {
    if (error && ALREADY_USED.test(error.message)) throw new HttpError(409, login.takenMessage);
    throw error ?? new Error(login.failedMessage);
  }
  return data.user.id;
}

/**
 * Removes an account that was created a moment ago and could not be finished.
 * Tried twice; if it still cannot be removed the id is logged (never the phone
 * or e-mail) so the leftover can be found. Returns whether it is gone.
 */
export async function removeUnfinishedLogin(service: SupabaseClient, userId: string, where: string): Promise<boolean> {
  let reason = '';
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const { error } = await service.auth.admin.deleteUser(userId);
      if (!error || NOT_FOUND.test(error.message)) return true;
      reason = error.message;
    } catch (error) {
      reason = error instanceof Error ? error.message : 'error';
    }
  }
  console.error(`${where}: an unfinished account could not be removed`, userId, reason.slice(0, 200));
  return false;
}

/**
 * Runs the steps that complete a new account. If any of them fails, in any
 * way, the account is removed again (and with it every row the steps managed
 * to insert), and the original error is thrown.
 */
export async function finishOrRemoveLogin<T>(
  service: SupabaseClient, userId: string, where: string, finish: () => Promise<T>,
): Promise<T> {
  try {
    return await finish();
  } catch (error) {
    await removeUnfinishedLogin(service, userId, where);
    throw error;
  }
}

/**
 * Deletes an account for good: the sign-in account (which signs it out
 * everywhere and cascades its profile row), then the profile row itself, for
 * the legacy rows that exist without a sign-in account.
 */
export async function deleteAccount(
  service: SupabaseClient, userId: string, profileTable: 'students' | 'supervisors' | 'admins',
): Promise<void> {
  const { error: authError } = await service.auth.admin.deleteUser(userId);
  if (authError && !NOT_FOUND.test(authError.message)) throw authError;
  const { error: rowError } = await service.from(profileTable).delete().eq('id', userId);
  if (rowError) throw rowError;
}

async function emptyFolder(service: SupabaseClient, bucket: string, folder: string): Promise<void> {
  // Always the first page: what was listed before is gone by now. The round
  // limit only stops a folder that refuses to empty from spinning forever.
  for (let round = 0; round < 50; round++) {
    const { data: files, error } = await service.storage.from(bucket).list(folder, { limit: 1000 });
    if (error) throw error;
    if (!files?.length) return;
    const { error: removeError } = await service.storage.from(bucket).remove(files.map((file) => `${folder}/${file.name}`));
    if (removeError) throw removeError;
    if (files.length < 1000) return;
  }
}

/** A student's photo and receipt images. Safe to repeat: a second run finds nothing left. */
export async function removeStudentFiles(service: SupabaseClient, studentId: string): Promise<void> {
  const results = await Promise.allSettled([
    emptyFolder(service, 'student-avatars', studentId),
    emptyFolder(service, 'receipts', studentId),
  ]);
  for (const result of results) if (result.status === 'rejected') throw result.reason;
}
