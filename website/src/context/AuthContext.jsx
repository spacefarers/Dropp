import { createContext, useContext, useEffect, useMemo, useState } from 'react'
import {
  onAuthStateChanged,
  signInWithPopup,
  signInWithRedirect,
  getRedirectResult,
  signOut as firebaseSignOut,
} from 'firebase/auth'
import { auth, googleProvider } from '../lib/firebase'

const AuthContext = createContext({
  user: null,
  loading: true,
  signInWithGoogle: async () => {},
  signOut: async () => {},
})

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let isMounted = true

    const resolveRedirect = async () => {
      try {
        await getRedirectResult(auth)
      } catch (error) {
        console.warn('Google sign-in redirect result could not be resolved.', error)
      }
    }

    resolveRedirect()

    const unsubscribe = onAuthStateChanged(auth, (firebaseUser) => {
      if (!isMounted) return
      setUser(firebaseUser)
      setLoading(false)
    })

    return () => {
      isMounted = false
      unsubscribe()
    }
  }, [])

  const signInWithGoogle = async () => {
    try {
      await signInWithPopup(auth, googleProvider)
    } catch (error) {
      if (error?.code === 'auth/operation-not-supported-in-this-environment' || error?.code === 'auth/popup-blocked') {
        await signInWithRedirect(auth, googleProvider)
        return
      }
      throw error
    }
  }

  const signOut = () => firebaseSignOut(auth)

  const value = useMemo(() => ({
    user,
    loading,
    signInWithGoogle,
    signOut,
  }), [user, loading])

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  )
}

export const useAuth = () => useContext(AuthContext)
