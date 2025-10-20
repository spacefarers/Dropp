import { useEffect, useRef, useState } from 'react'
import { useClerk } from '@clerk/clerk-react'
import './Login.css'

const DEFAULT_BACKEND_BASE = '/api'
const DEFAULT_APP_REDIRECT_URI = 'dropp://auth/callback'
const envBackendUrl = import.meta.env.VITE_BACKEND_URL
const normalizedBackendUrl = (envBackendUrl || '').trim().replace(/\/$/, '')
const backendBaseUrl = normalizedBackendUrl || DEFAULT_BACKEND_BASE
const jwtTemplate = import.meta.env.VITE_CLERK_JWT_TEMPLATE
const envAppRedirectUri = (import.meta.env.VITE_APP_REDIRECT_URI || '').trim()

const buildBackendUrl = (path) => {
  if (!path.startsWith('/')) {
    throw new Error(`Backend API paths must start with '/': received "${path}"`)
  }
  return `${backendBaseUrl}${path}`
}

const resolveRedirectUri = () => {
  if (typeof window === 'undefined') {
    return envAppRedirectUri || DEFAULT_APP_REDIRECT_URI
  }

  try {
    const currentUrl = new URL(window.location.href)
    const redirectFromQuery = currentUrl.searchParams.get('redirect_uri')
    if (redirectFromQuery) {
      return redirectFromQuery
    }
  } catch (error) {
    console.warn('Unable to parse redirect URI from location', error)
  }

  return envAppRedirectUri || DEFAULT_APP_REDIRECT_URI
}

export default function Login() {
  const { clerk } = useClerk()
  const signInRef = useRef(null)
  const [status, setStatus] = useState(null)
  const [statusError, setStatusError] = useState(false)
  const [finalizing, setFinalizing] = useState(false)
  const [finalized, setFinalized] = useState(false)
  const [redirectUri] = useState(resolveRedirectUri)

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
        const token = jwtTemplate
          ? await session.getToken({ template: jwtTemplate })
          : await session.getToken()
        const response = await fetch(buildBackendUrl('/auth/clerk/session'), {
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
        setStatus('Returning to Dropp…')

        const target = redirectUri || DEFAULT_APP_REDIRECT_URI
        let redirectUrl

        try {
          redirectUrl = new URL(target)
        } catch (parseError) {
          console.error('Invalid redirect URI', target, parseError)
          throw new Error('The redirect URI provided is invalid.')
        }

        const sessionToken = payload.session_token || token
        if (sessionToken) {
          redirectUrl.searchParams.set('session_token', sessionToken)
        }
        redirectUrl.searchParams.set('user_id', payload.user_id)
        if (payload.email) {
          redirectUrl.searchParams.set('email', payload.email)
        }
        if (payload.session_id) {
          redirectUrl.searchParams.set('session_id', payload.session_id)
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
  }, [clerk, finalizing, finalized, redirectUri])

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
