import { handleUpload, type HandleUploadBody } from '@vercel/blob/client';
import { NextRequest, NextResponse } from 'next/server';
import { verifyDroppToken } from '@/lib/jwt';
import { getDb } from '@/lib/mongodb';

function authOrThrow(req: NextRequest) {
  const authz = req.headers.get('authorization') || '';
  const token = authz.startsWith('Bearer ') ? authz.slice(7) : req.cookies.get('dropp_session')?.value;
  if (!token) throw new Error('Unauthorized');
  return verifyDroppToken(token);
}

export async function OPTIONS() {
  return new NextResponse(null, { status: 204 });
}

export async function POST(req: NextRequest): Promise<NextResponse> {
  // The body is the opaque payload from the client helper
  const body = (await req.json()) as HandleUploadBody;

  try {
    const jsonResponse = await handleUpload({
      request: req,
      body,

      // Called before issuing the client token – authenticate & shape constraints here.
      onBeforeGenerateToken: async (pathname /*, clientPayload */) => {
        const claims = authOrThrow(req);

        // Only images + common docs here as example; expand as needed.
        return {
          allowedContentTypes: [
            'image/jpeg', 'image/png', 'image/webp',
            'application/pdf',
            'text/plain'
          ],
          addRandomSuffix: true,
          // tokenPayload is sent back to us in onUploadCompleted
          tokenPayload: JSON.stringify({ userId: claims.sub, origName: pathname }),
          // access: 'public' | 'private' (default is private; choose explicitly if needed)
        };
      },

      // Called by Vercel API after the browser upload finishes.
      onUploadCompleted: async ({ blob, tokenPayload }) => {
        const payload = JSON.parse(tokenPayload || '{}') as { userId?: string; origName?: string };
        if (!payload.userId) throw new Error('Missing userId');

        const db = await getDb();
        await db.collection('files').insertOne({
          user_id: payload.userId,
          name: payload.origName || blob.pathname,
          url: blob.url,
          size: blob.size,
          content_type: blob.contentType,
          created_at: new Date().toISOString(),
          status: 'complete',
        });
      },
    });

    return NextResponse.json(jsonResponse);
  } catch (error: any) {
    console.error(error);
    // The Vercel webhook will retry if non-200 – make errors explicit
    return NextResponse.json({ error: error.message ?? 'Upload failed' }, { status: 400 });
  }
}
