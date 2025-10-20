# Dropp Backend

Flask-based backend service that issues pre-signed upload/download URLs for Vercel Blob storage, stores file metadata in MongoDB, and supports Google OAuth based authentication for the desktop applications.

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
| `GOOGLE_CLIENT_ID` | Google OAuth client id. |
| `GOOGLE_CLIENT_SECRET` | Google OAuth client secret. |
| `GOOGLE_REDIRECT_URI` | HTTPS URL that Google redirects to after login (`/auth/google/callback`). |
| `APP_REDIRECT_URI` | Desktop deep-link (e.g. `dropp://auth/callback`) where we send users after Google login. |
| `PRESIGN_TTL_SECONDS` | TTL for download links (default 900). |
| `UPLOAD_POST_TTL_SECONDS` | TTL for upload URLs (default 3600). |

## API Overview

- `GET /healthz` – lightweight health check.
- `GET /login/` – renders a Google sign-in button that initiates OAuth.
- `GET /auth/google` – starts Google OAuth flow.
- `GET /auth/google/callback` – handles the Google redirect, stores the user identity in session, then returns to the desktop app via `APP_REDIRECT_URI`.
- `GET /list/` – returns metadata for the authenticated user's files. Expect the user id via the session (after Google login) or the `X-User-Id` header for desktop clients.
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
│   ├── auth.py            # Google OAuth helper
│   ├── repository.py      # MongoDB persistence helpers
│   ├── routes.py          # Flask blueprint with API routes
│   └── storage.py         # Vercel Blob storage helper functions
├── app/templates/
│   └── login.html         # Minimal login UI for Google sign-in
├── config.py              # Environment-driven configuration
├── requirements.txt
└── run.py
```

## Notes

- Mongo collections are created lazily when the first document is inserted. Indexes (e.g. for `user_id`) should be added via migrations or an init script in production.
- The desktop client can call `/upload/<file_id>/complete` to flip file status from `pending` to `complete` once the upload finishes.
- For a production deployment, place the app behind HTTPS, configure secure cookies, and store Google OAuth state in a server-side store such as Redis rather than Flask's signed cookie session.
