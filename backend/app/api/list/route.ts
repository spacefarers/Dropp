import { NextRequest, NextResponse } from 'next/server';
import { getDb } from '@/lib/mongodb';
import { verifyDroppToken } from '@/lib/jwt';
import { UserDoc } from '@/types/UserDoc';

export async function GET(req: NextRequest) {
  const authz = req.headers.get('authorization') || '';
  const token = authz.startsWith('Bearer ') ? authz.slice(7) : req.cookies.get('dropp_session')?.value;
  if (!token) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const claims = verifyDroppToken(token);
    const db = await getDb();

    // Get user's storage information
    const user = await db.collection<UserDoc>('users').findOne({ _id: claims.sub });

    // Get user's files
    const files = await db.collection('files')
      .find({ user_id: claims.sub })
      .sort({ created_at: -1 })
      .toArray();

    const storage = {
      used: user?.used ?? 0,
      cap: user?.cap ?? 100000000, // Default to 100MB if user doc not found
    };

    return NextResponse.json({
      files,
      storage,
    });
  } catch (e) {
    console.error(e);
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
}
