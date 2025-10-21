'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { signInWithGooglePopup } from '@/lib/firebaseClient';

const DEFAULT_APP_REDIRECT_URI = process.env.NEXT_PUBLIC_APP_REDIRECT_URI || 'dropp://auth/callback';
const RETURNING_STATUS = 'Returning to Dropp…';

export default function Login() {
  const [status, setStatus] = useState<string | null>(null);
  const [statusError, setStatusError] = useState(false);
  const [finalizing, setFinalizing] = useState(false);
  const [finalized, setFinalized] = useState(false);
  const [showSuccessBanner, setShowSuccessBanner] = useState(false);
  const hasAttemptedFinalization = useRef(false);

  const finalizeSession = useCallback(async (idToken: string) => {
    if (finalized) return;
    setFinalizing(true);
    setStatus('Completing sign-in…');
    setStatusError(false);

    try {
      const res = await fetch('/api/auth/firebase/session', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${idToken}` },
        credentials: 'include',
        body: JSON.stringify({}),
      });
      if (!res.ok) throw new Error(`Finalize failed: ${res.status}`);
      const payload = await res.json().catch(() => ({}));

      const jwtToken = payload.session_token ?? payload.sessionToken ?? payload.token;
      setFinalized(true);
      setStatus(RETURNING_STATUS);
      setShowSuccessBanner(true);

      // Deep-link back to desktop client, mirroring existing logic.
      const redirectStr = DEFAULT_APP_REDIRECT_URI;
      const redirectUrl = new URL(redirectStr);
      const fallbackParams = {
        session_token: jwtToken,
        user_id: payload.user_id,
        email: payload.email,
        session_id: payload.session_id,
        display_name: payload.display_name,
        expires_in: payload.expires_in,
      };
      const redirectParams = { ...fallbackParams, ...payload };
      Object.entries(redirectParams).forEach(([k, v]) => {
        if (v === undefined || v === null) return;
        redirectUrl.searchParams.set(k, typeof v === 'object' ? JSON.stringify(v) : String(v));
      });
      window.location.replace(redirectUrl.toString());
    } catch (e) {
      console.error(e);
      setFinalizing(false);
      setStatus("We couldn't finish signing you in. Please try again.");
      setStatusError(true);
      setShowSuccessBanner(false);
    }
  }, [finalized]);

  const handleGoogleLogin = async () => {
    setStatus('Opening Google sign-in…');
    setStatusError(false);
    setShowSuccessBanner(false);
    hasAttemptedFinalization.current = false;

    try {
      const { idToken } = await signInWithGooglePopup();
      setStatus('Waiting for Google sign-in to complete…');
      await finalizeSession(idToken);
    } catch (err) {
      console.error('Google sign-in failed', err);
      setStatus('Google sign-in was cancelled or failed. Please try again.');
      setStatusError(true);
      setShowSuccessBanner(false);
    }
  };

  const isReturning = status === RETURNING_STATUS;

  return (
    <div className="login-container">
      <main className="login-card">
        <h1>Welcome to Dropp</h1>
        <p className="login-lead">Authenticate with Firebase to continue to the Dropp desktop app.</p>

        {!isReturning && (
          <div className="login-actions">
            <button className="btn btn-primary" type="button" onClick={handleGoogleLogin} disabled={finalizing}>
              Login with Google
            </button>
          </div>
        )}
        {status && <p className={`login-status ${statusError ? 'error' : ''}`} role="status">{status}</p>}
        {showSuccessBanner && !statusError && (
          <div className="login-success-banner" role="status">Feel free to close this page.</div>
        )}
      </main>
    </div>
  );
}
