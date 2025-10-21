import jwt from 'jsonwebtoken';

const JWT_SECRET: string = process.env.JWT_SECRET_KEY || process.env.SECRET_KEY || 'dev-secret';

export type DroppClaims = {
  sub: string; email?: string; name?: string;
  sid: string; // session id
};

export function signDroppToken(claims: DroppClaims, expiresIn: string = '7d') {
  return jwt.sign(claims, JWT_SECRET, { expiresIn } as jwt.SignOptions);
}

export function verifyDroppToken(token: string) {
  return jwt.verify(token, JWT_SECRET) as DroppClaims & jwt.JwtPayload;
}
