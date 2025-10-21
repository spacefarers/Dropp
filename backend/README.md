# Dropp Backend

Flask-based backend service that issues pre-signed upload/download URLs for Vercel Blob storage, stores file metadata in MongoDB, and authenticates users via Firebase-backed sign-in that exchanges for Dropp-managed session tokens.

## Getting Started

1. Create and activate a virtual environment.
2. `pip install -r requirements.txt`
3. Populate a `.env` file with the environment variables listed below.
4. `FLASK_APP=run.py flask run`

### Required Environment Variables

| Name | Description |
| --- | --- |
| `SECRET_KEY` | Session signing key for Flask. |
| `MONGODB_URI` | Connection string for MongoDB (e.g. `mongodb+srv://...`). |
| `MONGO_DB` | Database name for Dropp metadata. |
| `BLOB_READ_WRITE_TOKEN` | Vercel Blob storage token (automatically injected by Vercel when Blob is enabled). |
| `FIREBASE_SERVICE_ACCOUNT_BASE64` | Base64-encoded Firebase service account JSON. See setup instructions below. |
| `APP_REDIRECT_URI` | Desktop deep-link (e.g. `dropp://auth/callback`) where we send users after Firebase login. |
| `PRESIGN_TTL_SECONDS` | TTL for download links (default 900). |
| `UPLOAD_POST_TTL_SECONDS` | TTL for upload URLs (default 3600). |
| `CORS_ALLOWED_ORIGINS` | Optional comma-separated list of allowed origins for cross-site requests (e.g. `https://dropp.yangm.tech,https://app.dropp.yangm.tech`). Defaults to localhost + production web domain. |
| `JWT_SECRET_KEY` | Optional override for signing Dropp session tokens (defaults to `SECRET_KEY`). |
| `JWT_TTL_SECONDS` | Lifespan in seconds for Dropp session tokens (default 604800). |

## API Overview

- `GET /` – lightweight health check.
- `POST /auth/firebase/session` – verifies a Firebase ID token and issues a Dropp session token (JWT) plus user metadata so clients can persist it locally.
- `GET /list/` – returns metadata for the authenticated user's files. Always include a Dropp session token via `Authorization: Bearer <token>`.
- `POST /upload/` – accepts multipart file uploads, streams the file to Vercel Blob storage, stores metadata in MongoDB, and returns the file record. Also supports legacy JSON payload with `{ filename, size?, content_type? }` for backward compatibility.
- `POST /upload/<file_id>/complete` – optional endpoint for clients to update the blob URL and mark an upload as complete (mainly for backward compatibility with legacy flow).
- `GET /download/<file_id>` – returns the direct Vercel Blob URL for downloading the file.

## Upload Strategy

The `/upload/` endpoint accepts multipart file uploads and streams them directly to Vercel Blob storage using the Python vercel_blob package. Files are uploaded with a randomised key (UUID + timestamp) to ensure uniqueness. The backend handles the upload process, which provides opportunities for inline processing like virus scanning, file validation, or transformation if needed. Vercel Blob URLs are directly accessible for downloads without additional presigning.

## Folder Structure

```
backend/
├── app/
│   ├── __init__.py        # Application factory and dependency initialisation
│   ├── firebase_auth.py   # Firebase token verification helper
│   ├── jwt_auth.py        # Dropp session token issuance/verification helper
│   ├── repository.py      # MongoDB persistence helpers
│   ├── routes.py          # Flask blueprint with API routes
│   └── storage.py         # Vercel Blob storage helper functions
├── config.py              # Environment-driven configuration
├── requirements.txt
└── run.py
```

## Firebase Setup for Vercel

### Step 1: Download Service Account Key

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Go to **Project Settings** (gear icon) → **Service accounts** tab
4. Click **"Generate new private key"** and download the JSON file

### Step 2: Convert to Base64

**Using the provided script (recommended):**

```bash
# From the backend directory
./scripts/encode_firebase_credentials.sh path/to/your-firebase-service-account.json
```

**Or manually:**

```bash
# macOS/Linux
base64 -i path/to/your-firebase-service-account.json | tr -d '\n'

# Windows (PowerShell)
[Convert]::ToBase64String([System.IO.File]::ReadAllBytes("path\to\your-firebase-service-account.json"))
```

This will output a long base64 string.

### Step 3: Add to Vercel

1. Go to your Vercel project settings
2. Navigate to **Environment Variables**
3. Add a new variable:
   - **Name**: `FIREBASE_SERVICE_ACCOUNT_BASE64`
   - **Value**: Paste the base64 string from Step 2
4. Select the appropriate environments (Production, Preview, Development)
5. Save and redeploy


## Notes

- Mongo collections are created lazily when the first document is inserted. Indexes (e.g. for `user_id`) should be added via migrations or an init script in production.
- The desktop client can call `/upload/<file_id>/complete` to flip file status from `pending` to `complete` once the upload finishes.
- For a production deployment, place the app behind HTTPS, configure secure cookies, and ensure Firebase credentials are properly secured.
- **Never commit your Firebase service account JSON file to git!** Add it to `.gitignore`.
