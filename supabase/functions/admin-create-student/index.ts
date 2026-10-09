import { requireAdmin } from '../_shared/admin-auth.ts';
import { createStudent } from '../_shared/create-student.ts';
import { errorMessage, errorStatus, jsonResponse, preflight } from '../_shared/http.ts';

Deno.serve(async (request: Request) => {
  const early = preflight(request);
  if (early) return early;

  try {
    const context = await requireAdmin(request);
    return await createStudent(context, await request.json());
  } catch (error) {
    return jsonResponse({ error: errorMessage(error, 'تعذر إضافة الطالب.') }, errorStatus(error));
  }
});
