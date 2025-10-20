# Dropp Backend

Flask-based backend service that issues pre-signed upload/download URLs for Amazon S3, stores file metadata in MongoDB, and supports Google OAuth based authentication for the desktop applications.

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
| `AWS_S3_BUCKET` | Target S3 bucket that stores user uploads. |
| `AWS_REGION` | AWS region for the bucket. |
| `GOOGLE_CLIENT_ID` | Google OAuth client id. |
| `GOOGLE_CLIENT_SECRET` | Google OAuth client secret. |
| `GOOGLE_REDIRECT_URI` | HTTPS URL that Google redirects to after login (`/auth/google/callback`). |
| `APP_REDIRECT_URI` | Desktop deep-link (e.g. `dropp://auth/callback`) where we send users after Google login. |
| `PRESIGN_TTL_SECONDS` | TTL for download links (default 900). |
| `UPLOAD_POST_TTL_SECONDS` | TTL for upload URLs (default 3600). |

AWS credentials are read from the standard environment variables or shared configuration files supported by `boto3`.

## API Overview

- `GET /healthz` – lightweight health check.
- `GET /login/` – renders a Google sign-in button that initiates OAuth.
- `GET /auth/google` – starts Google OAuth flow.
- `GET /auth/google/callback` – handles the Google redirect, stores the user identity in session, then returns to the desktop app via `APP_REDIRECT_URI`.
- `GET /list/` – returns metadata for the authenticated user's files. Expect the user id via the session (after Google login) or the `X-User-Id` header for desktop clients.
- `POST /upload/` – accepts `{ filename, size?, content_type? }`, generates a unique S3 object key, stores metadata in MongoDB, and responds with a pre-signed POST so the desktop client can upload directly to S3 without handling AWS credentials.
- `POST /upload/<file_id>/complete` – optional hook the client can call after a successful upload to set the final size and mark the record as complete.
- `GET /download/<file_id>` – produces a pre-signed GET link for downloading the file from S3.

## Upload Strategy

The `/upload/` endpoint creates a short-lived pre-signed POST policy by combining the AWS bucket name, a randomised key (UUID + timestamp), and optional content-type/length constraints. This allows the desktop client to upload files straight to S3 over HTTPS without proxying the file through the Flask service. Because the presigned policy is limited in scope and lifetime, AWS credentials remain protected while still enabling a secure single-file upload path. Streaming through the backend is not necessary unless you need inline virus scanning, transformation, or want to support environments that cannot reach S3 directly.

## Folder Structure

```
backend/
├── app/
│   ├── __init__.py        # Application factory and dependency initialisation
│   ├── auth.py            # Google OAuth helper
│   ├── repository.py      # MongoDB persistence helpers
│   ├── routes.py          # Flask blueprint with API routes
│   └── storage.py         # S3 helper functions
├── app/templates/
│   └── login.html         # Minimal login UI for Google sign-in
├── config.py              # Environment-driven configuration
├── requirements.txt
└── run.py
```

## Notes

- Mongo collections are created lazily when the first document is inserted. Indexes (e.g. for `user_id`) should be added via migrations or an init script in production.
- A verification webhook from S3 or the desktop client can call `/upload/<file_id>/complete` to flip file status from `pending` to `complete` once the upload finishes.
- For a production deployment, place the app behind HTTPS, configure secure cookies, and store Google OAuth state in a server-side store such as Redis rather than Flask's signed cookie session.
