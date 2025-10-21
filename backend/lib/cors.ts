import { NextRequest, NextResponse } from 'next/server';

export function applyCors(req: NextRequest, res: NextResponse) {
  const allowed = (process.env.CORS_ALLOWED_ORIGINS || '').split(',').map(s => s.trim()).filter(Boolean);
  const origin = req.headers.get('origin') || '';
  if (origin && (allowed.length === 0 || allowed.includes(origin))) {
    res.headers.set('Access-Control-Allow-Origin', origin);
    res.headers.set('Vary', 'Origin');
  }
  res.headers.set('Access-Control-Allow-Credentials', 'true');
  res.headers.set('Access-Control-Allow-Headers', 'authorization,content-type');
  res.headers.set('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  return res;
}
