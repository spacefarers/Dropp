# Dropp Upload Architecture

## Overview

The backend implements a **universal token-based upload system** that works with any client (macOS, iOS, Android, web, etc.). The design separates token generation from actual file storage, enabling:

- **Security**: Tokens are scoped, time-limited, and server-generated
- **Scalability**: Files bypass backend and upload directly to Vercel Blob
- **Universality**: Any client using the same HTTP API can upload
- **Webhook Integration**: Vercel notifies backend when upload completes

---

## Architecture

### Three-Step Flow

```
1. Client requests token
   ↓
   POST /api/upload/token
   (backend authenticates & generates token)
   ↓

2. Client uploads directly to Vercel
   ↓
   POST https://blob.vercelusercontent.com/upload
   (with signed token)
   ↓

3. Vercel notifies backend
   ↓
   POST /api/upload/complete
   (webhook: backend records file metadata)
```

---

## Endpoints

### POST /api/upload/token
**Request token to upload a file**

**Request:**
```bash
curl -X POST https://droppapi.yangm.tech/api/upload/token \
  -H "Authorization: Bearer <session_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "filename": "document.pdf",
    "contentType": "application/pdf",
    "maximumSizeInBytes": 10485760
  }'
```

**Request Body:**
- `filename` (required): Name of file to upload
- `contentType` (optional): MIME type of file
- `maximumSizeInBytes` (optional): Maximum allowed file size

**Response:**
```json
{
  "token": "eyJhbGc...",
  "uploadUrl": "https://blob.vercelusercontent.com/upload"
}
```

**Returns:**
- `token`: Signed token to use for upload (time-limited, ~15 min)
- `uploadUrl`: Direct upload endpoint to use

**Constraints applied by token:**
- ✓ Authenticated user only
- ✓ MIME type whitelist: JPEG, PNG, WebP, PDF, plain text
- ✓ Random filename suffix (prevents collisions)
- ✓ User context embedded (userId, email, original filename)

**Errors:**
- `401 Unauthorized`: Missing or invalid session token
- `400 Bad Request`: Missing filename, invalid token config

---

### POST /api/upload/complete
**Webhook for upload completion (called by Vercel)**

**Called by:** Vercel Blob service (automatically)

**Request:** (Vercel sends)
```json
{
  "blob": {
    "url": "https://blob.vercelusercontent.com/..../document-abc123.pdf",
    "downloadUrl": "https://blob.vercelusercontent.com/download/...",
    "pathname": "document-abc123.pdf",
    "contentType": "application/pdf",
    "contentDisposition": "attachment"
  },
  "tokenPayload": "{\"userId\":\"user123\",\"origName\":\"document.pdf\",\"userEmail\":\"user@example.com\",\"contentType\":\"application/pdf\"}"
}
```

**Response:**
```json
{
  "success": true,
  "fileId": "507f1f77bcf86cd799439011"
}
```

**Stored in MongoDB:**
```json
{
  "_id": "507f1f77bcf86cd799439011",
  "user_id": "user123",
  "name": "document.pdf",
  "url": "https://blob.vercelusercontent.com/..../document-abc123.pdf",
  "download_url": "https://blob.vercelusercontent.com/download/...",
  "content_type": "application/pdf",
  "created_at": "2025-10-21T12:34:56.789Z",
  "status": "complete"
}
```

**Errors:**
- `400 Bad Request`: Missing blob.url, missing userId in tokenPayload

---

## Client Implementation Examples

### macOS App
```swift
// 1. Request token
let response = try await URLSession.shared.data(
  from: URL(string: "https://droppapi.yangm.tech/api/upload/token")!,
  body: ["filename": "file.pdf", "contentType": "application/pdf"]
)
let tokenData = try JSONDecoder().decode(TokenResponse.self, from: response)

// 2. Upload directly to Vercel
var request = URLRequest(url: URL(string: tokenData.uploadUrl)!)
request.setValue("Bearer \(tokenData.token)", forHTTPHeaderField: "Authorization")
request.httpBody = fileData
let uploadResponse = try await URLSession.shared.data(for: request)
```

### Web Client
```javascript
// 1. Request token
const tokenRes = await fetch('/api/upload/token', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ filename: file.name })
});
const { token, uploadUrl } = await tokenRes.json();

// 2. Upload directly to Vercel
const formData = new FormData();
formData.append('file', file);
formData.append('token', token);

const uploadRes = await fetch(uploadUrl, {
  method: 'POST',
  headers: { 'Authorization': `Bearer ${token}` },
  body: file
});
```

### cURL
```bash
# 1. Get token
TOKEN_RESPONSE=$(curl -X POST https://droppapi.yangm.tech/api/upload/token \
  -H "Authorization: Bearer $SESSION_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"filename": "myfile.pdf"}')

TOKEN=$(echo $TOKEN_RESPONSE | jq -r '.token')
UPLOAD_URL=$(echo $TOKEN_RESPONSE | jq -r '.uploadUrl')

# 2. Upload to Vercel
curl -X POST $UPLOAD_URL \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/pdf" \
  --data-binary @myfile.pdf
```

---

## Workflow Diagram

```
┌─ CLIENT (any type) ─────────────────────────────┐
│                                                 │
│  User wants to upload file                      │
│  ↓                                              │
│  POST /api/upload/token                         │
│  Authorization: Bearer <session_token>          │
│  { filename: "file.pdf" }                       │
│                                                 │
└──────────────┬──────────────────────────────────┘
               │
               v
┌─ BACKEND ──────────────────────────────────────┐
│                                                │
│  authOrThrow(req)                              │
│  ↓ verify JWT signature                        │
│  ✓ authenticated as user123                    │
│                                                │
│  generateClientTokenFromReadWriteToken()       │
│  ↓ create signed Vercel token                  │
│  ↓ embed: userId, filename, MIME types        │
│  ↓ set webhook callback URL                    │
│  ✓ token expires in ~15 minutes                │
│                                                │
│  return { token, uploadUrl }                   │
│                                                │
└──────────────┬──────────────────────────────────┘
               │
               v
┌─ CLIENT ─────────────────────────────────────┐
│                                              │
│  Receive token & uploadUrl                   │
│  ↓                                           │
│  POST https://blob.vercelusercontent.com/... │
│  Authorization: Bearer <token>               │
│  Content: <binary file>                      │
│                                              │
│  Vercel validates token & stores file        │
│  ↓                                           │
│  File stored at https://blob..../file-XYZ   │
│                                              │
└──────────────┬────────────────────────────────┘
               │
               v
┌─ VERCEL ─────────────────────────────────────┐
│                                              │
│  File upload complete                        │
│  ↓                                           │
│  POST /api/upload/complete                   │
│  { blob: {...}, tokenPayload: {...} }        │
│                                              │
└──────────────┬────────────────────────────────┘
               │
               v
┌─ BACKEND ──────────────────────────────────────┐
│                                                │
│  Webhook received                              │
│  ↓                                             │
│  Parse tokenPayload (user context)             │
│  ↓                                             │
│  Insert file record to MongoDB                 │
│  ↓                                             │
│  File now visible in user's library            │
│  ✓ status: 'complete'                          │
│                                                │
└────────────────────────────────────────────────┘
```

---

## Security Features

### Token Security
- **Signed by Vercel**: Client cannot forge tokens
- **Time-limited**: Default ~15 minute expiration
- **Scoped**: Can only upload with specific constraints
- **Single-use**: Token tied to specific upload

### Content Validation
- **MIME type whitelist**: Only allowed types accepted
  - `image/jpeg`, `image/png`, `image/webp`
  - `application/pdf`
  - `text/plain`
- **File size limits**: Optional `maximumSizeInBytes` enforced
- **Random suffixes**: Prevents filename enumeration

### User Isolation
- **JWT authentication**: Verify user on token request
- **Metadata embedding**: User context in token payload
- **Webhook verification**: Vercel calls backend with signed request
- **Database isolation**: Files tagged with user_id in MongoDB

### Network Security
- **HTTPS-only**: All endpoints encrypted
- **Authorization headers**: Bearer token in headers
- **CORS support**: Apps can call from any origin

---

## Configuration

### Environment Variables
```bash
# Required for upload tokens
BLOB_READ_WRITE_TOKEN=vercel_blob_rw_...

# Base URL for webhook callbacks
NEXT_PUBLIC_BASE_URL=https://droppapi.yangm.tech

# JWT signing (for session tokens)
JWT_SECRET_KEY=...
```

### Allowed MIME Types
Edit in `/api/upload/token/route.ts`:
```typescript
allowedContentTypes: [
  'image/jpeg',
  'image/png',
  'image/webp',
  'application/pdf',
  'text/plain'
]
```

---

## Error Scenarios

### Scenario: Token Expired
**Client receives:**
```json
{ "error": "Token expired" }
```
**Action:** Request new token via `/api/upload/token`

### Scenario: File Too Large
**Client receives:**
```json
{ "error": "File exceeds maximum size" }
```
**Action:** Check `maximumSizeInBytes` constraint, retry with smaller file

### Scenario: MIME Type Not Allowed
**Client receives:**
```json
{ "error": "Content type not allowed" }
```
**Action:** Upload allowed type or request whitelist expansion

### Scenario: Unauthorized
**Client receives:**
```json
{ "error": "Unauthorized" }
```
**Action:** Ensure valid session token in Authorization header

---

## Testing

### 1. Get Session Token
```bash
# Login via web or get from AuthManager
SESSION_TOKEN="<your_jwt_token>"
```

### 2. Request Upload Token
```bash
curl -X POST https://droppapi.yangm.tech/api/upload/token \
  -H "Authorization: Bearer $SESSION_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"filename": "test.txt", "contentType": "text/plain"}'
```

### 3. Upload File
```bash
UPLOAD_TOKEN="<token_from_step_2>"
curl -X POST https://blob.vercelusercontent.com/upload \
  -H "Authorization: Bearer $UPLOAD_TOKEN" \
  -H "Content-Type: text/plain" \
  --data-binary @test.txt
```

### 4. Verify in Database
```javascript
db.files.findOne({ name: "test.txt" });
// Should show: { user_id, name, url, content_type, created_at, status: "complete" }
```

---

## Frontend Removal

The website is now **backend-only** and serves as an API gateway for native apps.

- ❌ Removed: `UploadWidget` component
- ❌ Removed: Browser-based upload UI
- ❌ Removed: Vercel Blob client SDK from frontend
- ✅ Kept: Landing page, login flow (for authentication)
- ✅ Kept: `/api/list` for file listing (apps use this)
- ✅ Kept: `/api/auth/firebase/session` for login

The website is now a **pure API backend** with optional landing page marketing.

---

## Related Endpoints

### GET /api/list
List files for authenticated user
```bash
curl -H "Authorization: Bearer $SESSION_TOKEN" \
  https://droppapi.yangm.tech/api/list
```

Response:
```json
{
  "files": [
    {
      "filename": "document.pdf",
      "size": 1024000,
      "contentType": "application/pdf",
      "id": "507f...",
      "downloadURL": "https://..."
    }
  ],
  "storage": { "used": 5242880, "cap": 10737418240 }
}
```

### POST /api/auth/firebase/session
Exchange Firebase ID token for session JWT
```bash
curl -X POST https://droppapi.yangm.tech/api/auth/firebase/session \
  -H "Authorization: Bearer $FIREBASE_ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}'
```

Response:
```json
{
  "session_token": "eyJ...",
  "user_id": "uid123",
  "email": "user@example.com",
  "display_name": "John Doe",
  "session_id": "sid456",
  "expires_in": 604800
}
```

---

## Summary

This architecture provides:
- **Unified API** for all client types
- **Zero trust security** with JWT + Vercel tokens
- **Scalable uploads** bypassing backend servers
- **Webhook-driven persistence** for reliability
- **User isolation** with per-user file tracking

All clients (macOS, iOS, Android, web) follow the same three-step flow to upload files securely and directly to Vercel's CDN.
