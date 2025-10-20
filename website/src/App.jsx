import { ClerkProvider } from '@clerk/clerk-react'
import { useEffect, useState } from 'react'
import Login from './components/Login'
import Home from './components/Home'

const publishableKey = import.meta.env.VITE_CLERK_PUBLISHABLE_KEY
const isClerkConfigured = Boolean(publishableKey)

const resolvePageFromLocation = () => {
  if (typeof window === 'undefined') {
    return 'home'
  }

  return window.location.pathname.startsWith('/login') ? 'login' : 'home'
}

function ClerkConfigurationNotice() {
  return (
    <div className="login-container">
      <main className="login-card">
        <h1>Welcome to Dropp</h1>
        <p className="login-lead">
          Authentication is not configured yet. Provide VITE_CLERK_PUBLISHABLE_KEY to enable sign-in.
        </p>
      </main>
    </div>
  )
}

function App() {
  const [currentPage, setCurrentPage] = useState(resolvePageFromLocation)

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

  const content = currentPage === 'login'
    ? (isClerkConfigured ? <Login /> : <ClerkConfigurationNotice />)
    : <Home />

  if (!isClerkConfigured) {
    return content
  }

  return (
    <ClerkProvider publishableKey={publishableKey}>
      {content}
    </ClerkProvider>
  )
}

export default App
