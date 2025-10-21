import { getApps, initializeApp, cert, App } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

function decodeServiceAccount() {
  const b64 = process.env.FIREBASE_SERVICE_ACCOUNT_BASE64;
  if (!b64) throw new Error('FIREBASE_SERVICE_ACCOUNT_BASE64 not set');
  const json = Buffer.from(b64, 'base64').toString('utf8');
  const obj = JSON.parse(json);
  // Ensure private_key newlines are correct
  if (typeof obj.private_key === 'string') obj.private_key = obj.private_key.replace(/\\n/g, '\n');
  return obj;
}

let app: App;
export function getFirebaseAdmin() {
  if (!getApps().length) {
    app = initializeApp({ credential: cert(decodeServiceAccount()) });
  }
  return app!;
}
export const firebaseAuth = () => getAuth(getFirebaseAdmin());
