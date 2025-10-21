import { NextRequest, NextResponse } from 'next/server';
import { getDb } from '@/lib/mongodb';
import { verifyDroppToken } from '@/lib/jwt';

export async function GET(req: NextRequest) {
  const authz = req.headers.get('authorization') || '';
  const token = authz.startsWith('Bearer ') ? authz.slice(7) : req.cookies.get('dropp_session')?.value;
  if (!token) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const claims = verifyDroppToken(token);
    const db = await getDb();
    const files = await db.collection('files')
      .find({ user_id: claims.sub })
      .sort({ created_at: -1 })
      .toArray();

    return NextResponse.json(files);
  } catch (e) {
    console.error(e);
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
}
