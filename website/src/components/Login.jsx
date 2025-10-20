import { useEffect, useRef, useState } from 'react'
import { useClerk } from '@clerk/clerk-react'
import './Login.css'

export default function Login() {
  const { clerk } = useClerk()
  const signInRef = useRef(null)
  const [status, setStatus] = useState(null)
  const [statusError, setStatusError] = useState(false)
  const [finalizing, setFinalizing] = useState(false)
  const [finalized, setFinalized] = useState(false)

  useEffect(() => {
    if (!clerk || !signInRef.current) return

    const finalizeSession = async () => {
      if (finalizing || finalized) return

      const session = clerk.session
      if (!session) return

      setFinalizing(true)
      setStatus('Completing sign-in…')
      setStatusError(false)

      try {
        const token = await session.getToken()
        const response = await fetch('/api/auth/clerk/session', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`,
          },
          credentials: 'include',
        })

        if (!response.ok) {
          throw new Error(`Finalize session failed with status ${response.status}`)
        }

        const payload = await response.json()
        setFinalized(true)
        setStatus('Redirecting…')

        const redirectUrl = new URL('dropp://auth/callback')
        redirectUrl.searchParams.set('user_id', payload.user_id)
        if (payload.email) {
          redirectUrl.searchParams.set('email', payload.email)
        }

        window.location.replace(redirectUrl.toString())
      } catch (error) {
        console.error('Failed to finalize Clerk session', error)
        setFinalizing(false)
        setStatus("We couldn't finish signing you in. Please try again.")
        setStatusError(true)
      }
    }

    const handleSignIn = async () => {
      // Mount the sign-in component
      if (clerk.user && clerk.session) {
        await finalizeSession()
      } else {
        clerk.mountSignIn(signInRef.current, {
          redirectUrl: window.location.href,
          afterSignInUrl: window.location.href,
        })
      }
    }

    // Set up listener for auth changes
    const unsubscribe = clerk.addListener(async ({ user, session }) => {
      if (user && session) {
        await finalizeSession()
      }
    })

    handleSignIn()

    return () => {
      unsubscribe()
    }
  }, [clerk, finalizing, finalized])

  return (
    <div className="login-container">
      <main className="login-card">
        <h1>Welcome to Dropp</h1>
        <p className="login-lead">Authenticate with Clerk to continue to the Dropp desktop app.</p>
        <div id="sign-in-mount" ref={signInRef} className="sign-in-mount"></div>
        {status && (
          <p className={`login-status ${statusError ? 'error' : ''}`} role="status">
            {status}
          </p>
        )}
      </main>
    </div>
  )
}
