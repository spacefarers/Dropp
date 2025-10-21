import { NextRequest, NextResponse } from 'next/server';
import { del } from '@vercel/blob';
import { ObjectId } from 'mongodb';
import { getDb } from '@/lib/mongodb';
import { verifyDroppToken } from '@/lib/jwt';
import { FileDoc } from '@/types/FileDoc';
import { UserDoc } from '@/types/UserDoc';

export async function DELETE(
  req: NextRequest,
  { params }: { params: Promise<{ fileId: string }> }
): Promise<NextResponse> {
  try {
    // Authenticate user
    const authz = req.headers.get('authorization') || '';
    const token = authz.startsWith('Bearer ')
      ? authz.slice(7)
      : req.cookies.get('dropp_session')?.value;

    if (!token) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const claims = verifyDroppToken(token);
    const { fileId } = await params;

    // Validate fileId format
    if (!ObjectId.isValid(fileId)) {
      return NextResponse.json({ error: 'Invalid file ID' }, { status: 400 });
    }

    const db = await getDb();

    // Find the file and verify ownership
    const file = await db.collection<FileDoc>('files').findOne({
      _id: new ObjectId(fileId) as any,
    });

    if (!file) {
      return NextResponse.json({ error: 'File not found' }, { status: 404 });
    }

    // Verify the file belongs to the authenticated user
    if (file.user_id !== claims.sub) {
      return NextResponse.json({ error: 'Forbidden' }, { status: 403 });
    }

    // Delete from Vercel Blob storage
    try {
      await del(file.url);
    } catch (blobError: any) {
      console.error('Failed to delete from blob storage:', blobError);
      // Continue with database deletion even if blob deletion fails
      // This prevents orphaned database records
    }

    // Delete from MongoDB
    await db.collection('files').deleteOne({
      _id: new ObjectId(fileId) as any,
    });

    // Update user's storage usage (decrease by file size)
    await db.collection<UserDoc>('users').updateOne(
      { _id: claims.sub },
      { $inc: { used: -file.size } }
    );

    console.log(`File deleted successfully: ${fileId} (size: ${file.size})`);

    return NextResponse.json({
      success: true,
      message: 'File deleted successfully',
    });
  } catch (error: any) {
    console.error('File deletion failed:', error);

    if (error.message === 'Invalid token' || error.name === 'JWTVerifyError') {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    return NextResponse.json(
      { error: error.message ?? 'File deletion failed' },
      { status: 500 }
    );
  }
}
