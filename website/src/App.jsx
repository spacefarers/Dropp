import { useEffect, useState } from 'react'
import {
  SignedIn,
  SignedOut,
  SignInButton,
  SignUpButton,
  UserButton,
} from '@clerk/clerk-react'
import Login from './components/Login'
import Home from './components/Home'

const resolvePageFromLocation = () => {
  if (typeof window === 'undefined') {
    return 'home'
  }

  return window.location.pathname.startsWith('/login') ? 'login' : 'home'
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

  if (currentPage === 'login') {
    return (
      <>
        <SignedOut>
          <Login />
        </SignedOut>
        <SignedIn>
          <Login />
        </SignedIn>
      </>
    )
  }

  return (
    <>
      <SignedOut>
        <Home
          navAuth={
            <>
              <SignInButton signInUrl="/login">
                <button className="header-link" type="button">Sign in</button>
              </SignInButton>
              <SignUpButton signUpUrl="/login">
                <button className="header-link" type="button">Create account</button>
              </SignUpButton>
            </>
          }
          primaryCta={
            <SignInButton signInUrl="/login">
              <button className="btn btn-primary" type="button">Open Dropp</button>
            </SignInButton>
          }
        />
      </SignedOut>
      <SignedIn>
        <Home
          navAuth={(
            <div className="header-user">
              <UserButton afterSignOutUrl="/" />
            </div>
          )}
          primaryCta={null}
        />
      </SignedIn>
    </>
  )
}

export default App
