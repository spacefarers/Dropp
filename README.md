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
- **🔐 Secure Authentication** – Enterprise-grade security with Clerk OAuth integration
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
    MongoDB          Vercel Blob          Clerk Auth
    (Metadata)       (File Storage)       (Authentication)
```

### Technology Stack

**Backend:**
- Python Flask REST API
- MongoDB Atlas (metadata & persistence)
- Vercel Blob (scalable file storage)
- Clerk (unified authentication)

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
- Clerk account for authentication (free tier available)

### Backend Setup

```bash
cd backend

# Create virtual environment
python -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Configure environment
cp .env.example .env
# Edit .env with your Clerk and MongoDB credentials

# Start development server
python run.py
```

The API will be available at `http://localhost:5000`

### Web Frontend Setup

```bash
cd website

# Install dependencies
npm install

# Create environment configuration
cp .env.example .env.local
# Edit .env.local with your Clerk publishable key

# Start development server
npm run dev
```

The web app will be available at `http://localhost:5173`

### macOS App Setup

```bash
cd macos/Dropp

# Open in Xcode
open Dropp.xcodeproj

# Configure build settings with your Clerk credentials
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
- `POST /api/auth/clerk/session` – Finalize Clerk session and verify JWT

### File Operations
- `GET /api/list/` – List all files for authenticated user
- `POST /api/upload/` – Upload file to cloud storage
- `GET /api/download/<file_id>` – Get direct download URL

All endpoints require Bearer token authentication via JWT.

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

- **JWT Token Verification** – All API requests validated server-side
- **User Data Isolation** – Files scoped to authenticated user
- **Secure Token Storage** – Keychain (macOS), SharedPreferences (Android)
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
