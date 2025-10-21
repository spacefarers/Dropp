import { NextRequest, NextResponse } from 'next/server';
import { getDb } from '@/lib/mongodb';
import { UserDoc } from '@/types/UserDoc';

interface UploadCompleteWebhook {
  type: string;
  payload: {
    blob: {
      url: string;
      pathname: string;
      contentType?: string;
      contentDisposition: string;
      uploadedAt: string;
      size: number;
    };
    tokenPayload?: string;
    apiVersion: number;
  };
}

export async function POST(req: NextRequest): Promise<NextResponse> {
  try {
    const webhook = (await req.json()) as UploadCompleteWebhook;
    console.log('Webhook payload received:', JSON.stringify(webhook, null, 2));

    if (!webhook.payload?.blob) {
      console.error('Invalid webhook payload: missing blob');
      return NextResponse.json({ error: 'Invalid payload' }, { status: 400 });
    }

    const { blob, tokenPayload: tokenPayloadStr } = webhook.payload;

    // Parse metadata from token payload
    const tokenPayload = tokenPayloadStr
      ? (JSON.parse(tokenPayloadStr) as { userId?: string; origName?: string; userEmail?: string; contentType?: string })
      : null;

    if (!tokenPayload?.userId) {
      console.error('Invalid webhook payload: missing userId in tokenPayload');
      return NextResponse.json({ error: 'Missing userId in token' }, { status: 400 });
    }

    // Get file size from blob (already included in webhook payload)
    const fileSize = blob.size;

    // Insert file metadata into MongoDB and update user storage
    const db = await getDb();

    const result = await db.collection('files').insertOne({
      user_id: tokenPayload.userId,
      name: tokenPayload.origName || blob.pathname,
      url: blob.url,
      download_url: blob.url, // Use the blob URL as download URL
      size: fileSize,
      content_type: tokenPayload.contentType || blob.contentType,
      created_at: new Date().toISOString(),
      status: 'complete',
    });

    // Update user's storage usage
    await db.collection<UserDoc>('users').updateOne(
      { _id: tokenPayload.userId },
      { $inc: { used: fileSize } }
    );

    console.log(`File uploaded successfully: ${blob.pathname} (id: ${result.insertedId}, size: ${fileSize})`);

    return NextResponse.json({ success: true, fileId: result.insertedId });
  } catch (error: any) {
    console.error('Upload completion webhook failed:', error);
    return NextResponse.json({ error: error.message ?? 'Webhook processing failed' }, { status: 400 });
  }
}
