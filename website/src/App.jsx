import { ClerkProvider } from '@clerk/clerk-react'
import { useEffect, useState } from 'react'
import Login from './components/Login'
import Home from './components/Home'

const publishableKey = import.meta.env.VITE_CLERK_PUBLISHABLE_KEY

if (!publishableKey) {
  throw new Error('Missing VITE_CLERK_PUBLISHABLE_KEY environment variable')
}

function App() {
  const [currentPage, setCurrentPage] = useState('home')

  useEffect(() => {
    // Simple routing based on URL hash or query params
    const path = window.location.pathname
    if (path.includes('/login')) {
      setCurrentPage('login')
    } else {
      setCurrentPage('home')
    }
  }, [])

  return (
    <ClerkProvider publishableKey={publishableKey}>
      {currentPage === 'login' ? <Login /> : <Home />}
    </ClerkProvider>
  )
}

export default App
