import { NextRequest, NextResponse } from 'next/server';
import { getDb } from '@/lib/mongodb';
import { head } from '@vercel/blob';
import { UserDoc } from '@/types/UserDoc';

interface UploadCompletePayload {
  blob: {
    url: string;
    downloadUrl: string;
    pathname: string;
    contentType?: string;
    contentDisposition: string;
  };
  tokenPayload?: string;
}

export async function POST(req: NextRequest): Promise<NextResponse> {
  try {
    const payload = (await req.json()) as UploadCompletePayload;

    if (!payload.blob || !payload.blob.url) {
      console.error('Invalid webhook payload: missing blob.url');
      return NextResponse.json({ error: 'Invalid payload' }, { status: 400 });
    }

    // Parse metadata from token payload
    const tokenPayload = payload.tokenPayload
      ? (JSON.parse(payload.tokenPayload) as { userId?: string; origName?: string; userEmail?: string; contentType?: string })
      : null;

    if (!tokenPayload?.userId) {
      console.error('Invalid webhook payload: missing userId in tokenPayload');
      return NextResponse.json({ error: 'Missing userId in token' }, { status: 400 });
    }

    // Get file size from blob metadata
    const blobMetadata = await head(payload.blob.url);
    const fileSize = blobMetadata.size;

    // Insert file metadata into MongoDB and update user storage
    const db = await getDb();

    const result = await db.collection('files').insertOne({
      user_id: tokenPayload.userId,
      name: tokenPayload.origName || payload.blob.pathname,
      url: payload.blob.url,
      download_url: payload.blob.downloadUrl,
      size: fileSize,
      content_type: tokenPayload.contentType || payload.blob.contentType,
      created_at: new Date().toISOString(),
      status: 'complete',
    });

    // Update user's storage usage
    await db.collection<UserDoc>('users').updateOne(
      { _id: tokenPayload.userId },
      { $inc: { used: fileSize } }
    );

    console.log(`File uploaded successfully: ${payload.blob.pathname} (id: ${result.insertedId}, size: ${fileSize})`);

    return NextResponse.json({ success: true, fileId: result.insertedId });
  } catch (error: any) {
    console.error('Upload completion webhook failed:', error);
    return NextResponse.json({ error: error.message ?? 'Webhook processing failed' }, { status: 400 });
  }
}
