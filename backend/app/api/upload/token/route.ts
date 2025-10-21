import { generateClientTokenFromReadWriteToken } from '@vercel/blob/client';
import { NextRequest, NextResponse } from 'next/server';
import { verifyDroppToken } from '@/lib/jwt';

function authOrThrow(req: NextRequest) {
  const authz = req.headers.get('authorization') || '';
  const token = authz.startsWith('Bearer ') ? authz.slice(7) : req.cookies.get('dropp_session')?.value;
  if (!token) throw new Error('Unauthorized');
  return verifyDroppToken(token);
}

interface GenerateTokenRequest {
  filename: string;
  contentType?: string;
  maximumSizeInBytes?: number;
}

export async function OPTIONS() {
  return new NextResponse(null, { status: 204 });
}

export async function POST(req: NextRequest): Promise<NextResponse> {
  try {
    const claims = authOrThrow(req);
    const { filename, contentType, maximumSizeInBytes } = (await req.json()) as GenerateTokenRequest;

    if (!filename) {
      return NextResponse.json({ error: 'Filename is required' }, { status: 400 });
    }

    const token = process.env.BLOB_READ_WRITE_TOKEN;
    if (!token) {
      console.error('BLOB_READ_WRITE_TOKEN not configured');
      return NextResponse.json({ error: 'Upload service not configured' }, { status: 500 });
    }

    // Generate a client token with constraints
    const clientToken = await generateClientTokenFromReadWriteToken({
      token,
      pathname: filename,
      maximumSizeInBytes,
      allowedContentTypes: [
        'image/jpeg',
        'image/png',
        'image/webp',
        'application/pdf',
        'text/plain'
      ],
      addRandomSuffix: true,
      onUploadCompleted: {
        callbackUrl: `${process.env.NEXT_PUBLIC_BASE_URL || 'https://droppapi.yangm.tech'}/api/upload/complete`,
        tokenPayload: JSON.stringify({
          userId: claims.sub,
          origName: filename,
          userEmail: claims.email,
          contentType: contentType || 'application/octet-stream',
        }),
      },
    });

    return NextResponse.json({
      token: clientToken,
      uploadUrl: 'https://blob.vercelusercontent.com/upload',
    });
  } catch (error: any) {
    console.error('Token generation failed:', error);

    if (error.message === 'Unauthorized') {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    return NextResponse.json({ error: error.message ?? 'Token generation failed' }, { status: 400 });
  }
}
