import { initializeApp, getApps, getApp } from 'firebase/app'
import { getAuth, GoogleAuthProvider } from 'firebase/auth'

const requiredEnvVars = {
  VITE_FIREBASE_API_KEY: 'apiKey',
  VITE_FIREBASE_AUTH_DOMAIN: 'authDomain',
  VITE_FIREBASE_PROJECT_ID: 'projectId',
  VITE_FIREBASE_APP_ID: 'appId',
}

const optionalEnvVars = {
  VITE_FIREBASE_MESSAGING_SENDER_ID: 'messagingSenderId',
  VITE_FIREBASE_STORAGE_BUCKET: 'storageBucket',
  VITE_FIREBASE_MEASUREMENT_ID: 'measurementId',
}

const firebaseConfigEntries = Object.entries(requiredEnvVars).map(([envKey, configKey]) => {
  const value = import.meta.env[envKey]
  if (!value) {
    throw new Error(`Missing Firebase configuration value for ${envKey}`)
  }
  return [configKey, value]
})

const optionalConfigEntries = Object.entries(optionalEnvVars)
  .map(([envKey, configKey]) => {
    const value = import.meta.env[envKey]
    if (!value) return null
    return [configKey, value]
  })
  .filter(Boolean)

const firebaseConfig = Object.fromEntries([...firebaseConfigEntries, ...optionalConfigEntries])

const firebaseApp = getApps().length ? getApp() : initializeApp(firebaseConfig)

const auth = getAuth(firebaseApp)
const googleProvider = new GoogleAuthProvider()
googleProvider.setCustomParameters({ prompt: 'select_account' })

export { firebaseApp, auth, googleProvider }
