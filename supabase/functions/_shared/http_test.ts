// deno test supabase/functions/_shared/
import { assertEquals, assertRejects } from 'jsr:@std/assert@1';
import { errorMessage, errorStatus, HttpError, preflight, together } from './http.ts';
import { isEgyptianMobile, loginEmail, normalizeEgyptianPhone } from './phone.ts';

const later = <T>(ms: number, value: T, fail = false) =>
  new Promise<T>((resolve, reject) => setTimeout(() => fail ? reject(value) : resolve(value), ms));

Deno.test('steps run together and come back in their own order', async () => {
  const events: string[] = [];
  const step = async (name: string, ms: number) => {
    events.push(`start ${name}`);
    await later(ms, null);
    events.push(`end ${name}`);
    return name;
  };
  assertEquals(await together([step('slow', 15), step('fast', 1)]), ['slow', 'fast']);
  assertEquals(events, ['start slow', 'start fast', 'end fast', 'end slow']);
});

Deno.test('when several steps fail, the first in the list is the error reported', async () => {
  const error = await assertRejects(() => together([later(20, new HttpError(404, 'first'), true), later(1, new Error('second'), true)]));
  assertEquals((error as Error).message, 'first');
});

Deno.test('preflight answers OPTIONS and refuses anything but POST', async () => {
  assertEquals(preflight(new Request('http://local/fn', { method: 'OPTIONS' }))?.status, 200);
  const wrong = preflight(new Request('http://local/fn', { method: 'GET' }));
  assertEquals(wrong?.status, 405);
  assertEquals(typeof (await wrong!.json()).error, 'string');
  assertEquals(preflight(new Request('http://local/fn', { method: 'POST' })), null);
});

Deno.test('errors keep their status and a readable message', () => {
  assertEquals(errorStatus(new HttpError(403, 'no')), 403);
  assertEquals(errorStatus(new Error('x')), 400);
  assertEquals(errorMessage({ message: 'from PostgREST', code: '23505' }, 'fallback'), 'from PostgREST');
  assertEquals(errorMessage(null, 'fallback'), 'fallback');
});

Deno.test('phone numbers are written the way the database stores them', () => {
  for (const written of ['01012345678', '1012345678', '+20 101 234 5678', '201012345678', '٠١٠١٢٣٤٥٦٧٨', '010-1234-5678']) {
    assertEquals(normalizeEgyptianPhone(written), '01012345678', written);
  }
  assertEquals(isEgyptianMobile('01012345678'), true);
  for (const wrong of ['', '0101234567', '01312345678', '010123456789', '02012345678']) {
    assertEquals(isEgyptianMobile(normalizeEgyptianPhone(wrong)), false, wrong);
  }
  assertEquals(loginEmail('01012345678'), '01012345678@busak.app');
});
