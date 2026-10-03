// Runs one Edge Function on PORT (Deno.serve without options binds 8000).
const port = Number(Deno.env.get('PORT'));
const original = Deno.serve.bind(Deno);
// deno-lint-ignore no-explicit-any
(Deno as any).serve = (handler: any) => original({ port, hostname: '127.0.0.1', onListen() {} }, handler);
await import(Deno.env.get('FN_ENTRY')!);
