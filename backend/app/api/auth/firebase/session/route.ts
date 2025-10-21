import { NextRequest, NextResponse } from 'next/server';
import { firebaseAuth } from '@/lib/firebaseAdmin';
import { signDroppToken } from '@/lib/jwt';
import { randomUUID } from 'crypto';
import { getDb } from '@/lib/mongodb';

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, { status: 204 });
}

export async function POST(req: NextRequest) {
  try {
    const authz = req.headers.get('authorization') || '';
    const idToken = authz.startsWith('Bearer ') ? authz.slice(7) : null;
    if (!idToken) return NextResponse.json({ error: 'Missing Firebase ID token' }, { status: 401 });

    const decoded = await firebaseAuth().verifyIdToken(idToken); // verifies client SDK tokens
    const db = await getDb();

    // Create or update user with storage cap
    const DEFAULT_STORAGE_CAP = 100000000; // 100MB in bytes
    const userCollection = db.collection<any>('users');

    await userCollection.updateOne(
      { _id: decoded.uid },
      {
        $setOnInsert: {
          _id: decoded.uid,
          cap: DEFAULT_STORAGE_CAP,
          used: 0,
          email: decoded.email,
          created_at: new Date().toISOString(),
        },
      },
      { upsert: true }
    );

    const sessionId = randomUUID();
    const jwt = signDroppToken({
      sub: decoded.uid,
      email: decoded.email,
      name: decoded.name,
      sid: sessionId,
    });

    const expiresInSeconds = 7 * 24 * 60 * 60;

    const res = NextResponse.json({
      session_token: jwt,
      user_id: decoded.uid,
      email: decoded.email,
      display_name: decoded.name,
      session_id: sessionId,
      expires_in: expiresInSeconds,
    });
    // Optionally set HttpOnly cookie for web use
    res.cookies.set('dropp_session', jwt, { httpOnly: true, secure: true, sameSite: 'lax', maxAge: expiresInSeconds });
    return res;
  } catch (e) {
    console.error(e);
    return NextResponse.json({ error: 'Invalid Firebase token' }, { status: 401 });
  }
}
