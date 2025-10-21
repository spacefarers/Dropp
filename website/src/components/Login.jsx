import {useCallback, useEffect, useRef, useState} from 'react'
import {useAuth} from '../context/AuthContext.jsx'
import './Login.css'

const DEFAULT_APP_REDIRECT_URI = 'dropp://auth/callback'
const backendBaseUrl = 'https://droppapi.yangm.tech'
const envAppRedirectUri = (import.meta.env.VITE_APP_REDIRECT_URI || '').trim()
const finalizePath = import.meta.env.VITE_AUTH_FINALIZE_PATH || '/auth/firebase/session'
const RETURNING_STATUS = 'Returning to Dropp…'

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
    const {user, loading, signInWithGoogle} = useAuth()
    const [status, setStatus] = useState(null)
    const [statusError, setStatusError] = useState(false)
    const [finalizing, setFinalizing] = useState(false)
    const [finalized, setFinalized] = useState(false)
    const [redirectUri] = useState(resolveRedirectUri)
    const [showSuccessBanner, setShowSuccessBanner] = useState(false)
    const hasAttemptedFinalization = useRef(false)

    useEffect(() => {
        if (!user) {
            hasAttemptedFinalization.current = false
            setFinalized(false)
            setFinalizing(false)
            setShowSuccessBanner(false)
        }
    }, [user])

    const finalizeSession = useCallback(async (force = false) => {
        if (!user || finalized) return
        if (!force && hasAttemptedFinalization.current) return

        hasAttemptedFinalization.current = true
        setFinalizing(true)
        setStatus('Completing sign-in…')
        setStatusError(false)

        try {
            const token = await user.getIdToken()
            console.log(buildBackendUrl(finalizePath))
            const response = await fetch(buildBackendUrl(finalizePath), {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${token}`,
                },
                credentials: 'include',
                body: JSON.stringify({}),
            })

            if (!response.ok) {
                throw new Error(`Finalize session failed with status ${response.status}`)
            }

            let payload = {}
            try {
                payload = await response.json()
            } catch (parseError) {
                console.warn('Finalize session response did not include JSON payload.', parseError)
            }
            if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
                payload = {}
            }

            setFinalized(true)
            setStatus(RETURNING_STATUS)
            setShowSuccessBanner(true)

            const target = redirectUri || DEFAULT_APP_REDIRECT_URI
            let redirectUrl

            try {
                redirectUrl = new URL(target)
            } catch (parseError) {
                console.error('Invalid redirect URI', target, parseError)
                throw new Error('The redirect URI provided is invalid.')
            }

            const fallbackParams = {
                session_token: payload.session_token ?? payload.sessionToken ?? token,
                user_id: payload.user_id ?? payload.userId ?? user.uid,
                email: payload.email ?? user.email ?? undefined,
                session_id: payload.session_id ?? payload.sessionId ?? undefined,
                display_name: payload.display_name ?? payload.displayName ?? user.displayName ?? payload.email ?? payload.user_id ?? undefined,
            }

            const redirectParams = {...payload}
            Object.entries(fallbackParams).forEach(([key, value]) => {
                if (value !== undefined && value !== null) {
                    redirectParams[key] = value
                }
            })

            Object.entries(redirectParams).forEach(([key, value]) => {
                if (value === undefined || value === null) {
                    return
                }
                if (typeof value === 'object') {
                    redirectUrl.searchParams.set(key, JSON.stringify(value))
                    return
                }
                redirectUrl.searchParams.set(key, String(value))
            })

            window.location.replace(redirectUrl.toString())
        } catch (error) {
            console.error('Failed to finalize Firebase session', error)
            setFinalizing(false)
            setStatus("We couldn't finish signing you in. Please try again.")
            setStatusError(true)
            setShowSuccessBanner(false)
        }
    }, [user, finalized, redirectUri])

    useEffect(() => {
        if (!user || loading) return
        finalizeSession()
    }, [user, loading, finalizeSession])

    const handleGoogleLogin = async () => {
        setStatus(null)
        setStatusError(false)
        setShowSuccessBanner(false)

        try {
            setStatus('Opening Google sign-in…')
            hasAttemptedFinalization.current = false
            await signInWithGoogle()
            setStatus('Waiting for Google sign-in to complete…')
            await finalizeSession(true)
        } catch (error) {
            console.error('Google sign-in failed', error)
            setStatus('Google sign-in was cancelled or failed. Please try again.')
            setStatusError(true)
            setShowSuccessBanner(false)
        }
    }

    const isReturningToDropp = status === RETURNING_STATUS

    return (
        <div className="login-container">
            <main className="login-card">
                <h1>Welcome to Dropp</h1>
                <p className="login-lead">Authenticate with Firebase to continue to the Dropp desktop app.</p>
                {!isReturningToDropp && (
                    <div className="login-actions">
                        <button className="btn btn-primary" type="button" onClick={handleGoogleLogin}
                                disabled={loading || finalizing}>
                            Login with Google
                        </button>
                    </div>
                )}
                {status && (
                    <p className={`login-status ${statusError ? 'error' : ''}`} role="status">
                        {status}
                    </p>
                )}
                {showSuccessBanner && !statusError && (
                    <div className="login-success-banner" role="status">
                        Feel free to close this page.
                    </div>
                )}
            </main>
        </div>
    )
}
