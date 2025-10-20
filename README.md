<div align="center">
  <img src="./Dropp.icon/Assets/Dropp.png" alt="Dropp Logo" width="120" height="120">
  <h1>Dropp</h1>
  <p><strong>Cross-Platform File Transfer Made Simple</strong></p>
  <p>Seamlessly share files between your devices—Mac, Android, and Web—with zero friction.</p>
</div>

---

## Overview

Dropp is a modern file transfer platform designed for users who work across multiple devices. Inspired by Yoink, Dropp brings a unified dropzone experience to your entire ecosystem, enabling instant file synchronization and transfer between macOS, Android, and web interfaces.

Whether you're moving files from your phone to your Mac or organizing content across devices, Dropp handles the heavy lifting with a simple drag-and-drop interface.

## Key Features

- **🔗 Cross-Platform Synchronization** – Files pinned to your shelf sync instantly across all connected devices
- **📱 Native Apps** – Purpose-built applications for macOS and Android with platform-optimized interfaces
- **🌐 Web Access** – Manage your files from any browser, anywhere
- **🔐 Secure Authentication** – Firebase Authentication with backend session finalization for desktop hand-off
- **☁️ Cloud-Backed Storage** – Files stored on Vercel's CDN-backed infrastructure for reliable access
- **⚡ Zero Configuration** – Sign in once, access everywhere
- **🎯 Intuitive Dropzone** – Drag files to your shelf for instant cross-device availability

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| **macOS** | ✅ Available | Native SwiftUI app with floating panel UI |
| **Android** | ✅ In Development | Native Android app with seamless auth flow |
| **Web** | ✅ Available | React-based progressive web app |
| **iOS** | 🚧 Planned | Coming soon |
| **Windows** | 🚧 Planned | Coming soon |

## Architecture

Dropp is built on a modern, scalable microservices architecture:

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  macOS App  │  Android App  │  Web App (React)            │
│  (SwiftUI)  │   (Native)    │                             │
│                                                             │
└────────────────┬──────────────────────┬────────────────────┘
                 │                      │
                 └──────────┬───────────┘
                            │
                    REST API (Flask)
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
    MongoDB          Vercel Blob          Firebase Auth
    (Metadata)       (File Storage)       (Authentication)
```

### Technology Stack

**Backend:**
- Python Flask REST API
- MongoDB Atlas (metadata & persistence)
- Vercel Blob (scalable file storage)
- Firebase Authentication (identity provider & token verification)

**Frontend:**
- React 18 with Vite
- macOS: SwiftUI native application
- Android: Native Java/Gradle application

**Infrastructure:**
- Vercel Serverless Functions
- MongoDB Atlas Cloud
- Vercel Blob CDN

## Getting Started

### Prerequisites

- Python 3.8+ (for backend development)
- Node.js 16+ (for web frontend)
- Xcode 14+ (for macOS app development)
- Android Studio 2021+ (for Android development)
- Firebase project (Web app + Admin SDK credentials) for authentication

### Backend Setup

```bash
cd backend

# Create virtual environment
python -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Configure environment
# Create a `.env` file (or export variables) with your Firebase Admin credentials,
# MongoDB connection string, and any other required secrets.

# Start development server
python run.py
```

The API will be available at `http://localhost:5000`

### Web Frontend Setup

```bash
cd website

# Install dependencies
npm install

# Configure environment by providing the following Vite variables (e.g. via `.env.local`)

# Start development server
npm run dev
```

The web app will be available at `http://localhost:5173`

Required Vite environment variables:
- `VITE_FIREBASE_API_KEY`, `VITE_FIREBASE_AUTH_DOMAIN`, `VITE_FIREBASE_PROJECT_ID`, `VITE_FIREBASE_APP_ID`
- Optional Firebase extras: `VITE_FIREBASE_STORAGE_BUCKET`, `VITE_FIREBASE_MESSAGING_SENDER_ID`, `VITE_FIREBASE_MEASUREMENT_ID`
- Backend session finalize endpoint: `VITE_BACKEND_URL` (base HTTPS URL) and optional `VITE_AUTH_FINALIZE_PATH` (defaults to `/auth/firebase/session`)
- Desktop redirect fallback: `VITE_APP_REDIRECT_URI` (default `dropp://auth/callback`)

## Desktop ↔ Web Authentication Flow

- **Environment configuration** – On Vercel (or your hosting provider) set all required `VITE_FIREBASE_*` values plus `VITE_BACKEND_URL` (HTTPS origin for your API) and `VITE_APP_REDIRECT_URI` (default desktop callback). Override the finalize path with `VITE_AUTH_FINALIZE_PATH` only if your API route differs from `/auth/firebase/session`.
- **Desktop/web hand-off** – The Dropp desktop client launches `https://dropp.yangm.tech/login?redirect_uri=<URL-encoded callback>`. The query param overrides the configured default so the web app knows where to return the user.
- **User auth in browser** – The `/login` page renders a single “Login with Google” button. Clicking it initializes the Firebase Web SDK (see `src/lib/firebase.js`), preferring `signInWithPopup` and falling back to `signInWithRedirect` when popups are blocked. Auth state is managed inside `AuthContext`.
- **Session finalization** – As soon as a Firebase user exists, the web app POSTs `${VITE_BACKEND_URL}${VITE_AUTH_FINALIZE_PATH}` with `Authorization: Bearer <Firebase ID token>` and an empty JSON body, using `credentials: 'include'` so secure cookies from your API persist. The backend must verify the token with the Firebase Admin SDK, create or refresh a Dropp session, and respond with JSON such as `{ session_token, user_id, email?, session_id? }`, optionally setting cookies.
- **Return to the caller** – The frontend merges the backend payload with any Firebase-derived fields and appends everything to the `redirect_uri` before calling `window.location.replace(...)`, handing control back to the desktop app (or other consumer).
- **Sign-out** – On the marketing page (`/`), the “Sign out” header button invokes `firebase.auth().signOut()`. After sign-out, the page returns to its anonymous state.
- **Hosting note** – The web client is a static Vite build served from `https://dropp.yangm.tech`; only the finalize endpoint needs to run on your API host. Ensure `VITE_BACKEND_URL` points to that HTTPS origin.

### macOS App Setup

```bash
cd macos/Dropp

# Open in Xcode
open Dropp.xcodeproj

# The dropp://auth/callback redirect is preconfigured for Firebase hand-off
# Build and run (Cmd+R)
```

### Android App Setup

```bash
cd android

# Open in Android Studio
# Configure API keys in AndroidManifest.xml
# Build and run on emulator or device
```

## API Endpoints

### Authentication
- `POST /auth/firebase/session` – Verify Firebase ID token, mint/refresh Dropp session, and return session metadata

### File Operations
- `GET /api/list/` – List all files for authenticated user
- `POST /api/upload/` – Upload file to cloud storage
- `GET /api/download/<file_id>` – Get direct download URL

All subsequent API requests must include the Dropp session token returned by the finalize endpoint (via `Authorization: Bearer` header) or rely on secure cookies issued by the backend.

## Deployment

### Backend Deployment (Vercel)

```bash
cd backend
vercel deploy
```

### Web Frontend Deployment (Vercel)

```bash
cd website
vercel deploy
```

Environment variables are automatically configured during deployment.

## Security

- **Firebase ID Verification** – Backend validates Google ID tokens with the Firebase Admin SDK before issuing Dropp sessions
- **Session Token Isolation** – Keychain (macOS), SharedPreferences (Android), and HTTPS-only cookies (web) keep session tokens protected
- **User Data Isolation** – Files scoped to authenticated user
- **CORS Protection** – Cross-origin requests strictly controlled
- **HTTPS Enforced** – All production traffic encrypted

## Development Workflow

```bash
# Frontend development (with API proxy)
npm run dev

# Backend development
python run.py

# Build for production
npm run build
python -m py_compile app/
```

## Contributing

We welcome contributions! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Project Structure

```
Dropp/
├── backend/           # Flask REST API
├── website/           # React web application
├── macos/            # SwiftUI macOS application
├── android/          # Native Android application
└── Dropp.icon/       # Brand assets
```

## Performance

- **File Upload:** Optimized for files up to 2GB
- **Sync Latency:** Sub-second metadata synchronization
- **Global Availability:** CDN-backed file delivery with <100ms access times

## Roadmap

- [ ] iOS application
- [ ] Windows desktop application
- [ ] Direct device-to-device transfer mode
- [ ] File versioning and recovery
- [ ] Advanced sharing & collaboration features
- [ ] Team workspaces

## Support

For issues, feature requests, or questions:
- Open an issue on GitHub
- Contact support through our website
- Check our documentation wiki

## License

This project is licensed under the MIT License – see the LICENSE file for details.

---

<div align="center">
  <p><strong>Dropp – Make file transfer effortless across all your devices</strong></p>
</div>
