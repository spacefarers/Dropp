import { useEffect, useState } from 'react'
import Login from './components/Login'
import Home from './components/Home'
import { useAuth } from './context/AuthContext.jsx'

const resolvePageFromLocation = () => {
  if (typeof window === 'undefined') {
    return 'home'
  }

  return window.location.pathname.startsWith('/login') ? 'login' : 'home'
}

function App() {
  const [currentPage, setCurrentPage] = useState(resolvePageFromLocation)
  const { user, signOut } = useAuth()

  useEffect(() => {
    if (typeof window === 'undefined') return undefined

    const handleLocationChange = () => {
      setCurrentPage(resolvePageFromLocation())
    }

    handleLocationChange()
    window.addEventListener('popstate', handleLocationChange)

    return () => {
      window.removeEventListener('popstate', handleLocationChange)
    }
  }, [])

  if (currentPage === 'login') {
    return <Login />
  }

  const handleSignOut = async () => {
    try {
      await signOut()
    } catch (error) {
      console.error('Failed to sign out', error)
    }
  }

  const navAuth = user
    ? (
      <button className="header-link" type="button" onClick={handleSignOut}>
        Sign out
      </button>
    )
    : undefined

  const primaryCta = user ? null : undefined

  return (
    <Home
      navAuth={navAuth}
      primaryCta={primaryCta}
    />
  )
}

export default App
