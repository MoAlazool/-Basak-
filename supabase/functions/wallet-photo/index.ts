import { serviceClient } from '../_shared/clients.ts';
import '../_shared/wallet/artwork.ts'; // the picture decoder
import { portraitForToken } from '../_shared/wallet/photo.ts';

// Serves ONE thing: a small portrait of a student, for Google Wallet's details
// view, at  .../wallet-photo/<token>.jpg
//
// Google can only show an image it fetches from a link, and a student photo
// must not sit behind a guessable one. So the link carries a 256-bit random
// token that exists only on that student's Google card. The token is replaced
// when the photo changes and disappears with the card or the account; a wrong
// or old token gets a plain 404. The original file and its storage path are
// never exposed: only a 480px copy is returned.

const notFound = () => new Response(null, { status: 404 });

Deno.serve(async (request: Request) => {
  try {
    if (request.method !== 'GET' && request.method !== 'HEAD') return new Response(null, { status: 405 });
    const token = new URL(request.url).pathname.match(/\/([0-9a-f]{64})\.jpg$/)?.[1];
    if (!token) return notFound();

    const jpeg = await portraitForToken(serviceClient(), token);
    if (!jpeg) return notFound();
    return new Response(request.method === 'HEAD' ? null : jpeg.slice().buffer, {
      status: 200,
      headers: {
        'Content-Type': 'image/jpeg',
        'Content-Length': String(jpeg.length),
        // The link is the secret: keep it out of shared caches and search engines.
        'Cache-Control': 'private, max-age=300',
        'X-Robots-Tag': 'noindex',
      },
    });
  } catch (error) {
    console.error('wallet-photo', error);
    return new Response(null, { status: 500 });
  }
});
