import { NextResponse } from 'next/server';

/**
 * /api/upload is now backend-only without a default handler.
 * Use specific endpoints:
 * - POST /api/upload/token - Request an upload token
 * - POST /api/upload/complete - Webhook for upload completion (called by Vercel)
 */

export async function OPTIONS() {
  return new NextResponse(null, { status: 204 });
}

export async function POST() {
  return NextResponse.json(
    { error: 'Use /api/upload/token to request an upload token' },
    { status: 400 }
  );
}
