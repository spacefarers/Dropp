# Upload API - Quick Start Guide

## 3-Step Upload Process

### Step 1: Get Upload Token

**Endpoint:** `POST /api/upload/token`

**cURL:**
```bash
curl -X POST https://droppapi.yangm.tech/api/upload/token \
  -H "Authorization: Bearer $SESSION_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "filename": "myfile.pdf",
    "contentType": "application/pdf"
  }'
```

**Response:**
```json
{
  "token": "eyJhbGc...",
  "uploadUrl": "https://blob.vercelusercontent.com/upload"
}
```

---

### Step 2: Upload to Vercel

**Endpoint:** `POST https://blob.vercelusercontent.com/upload`

**cURL:**
```bash
curl -X POST https://blob.vercelusercontent.com/upload \
  -H "Authorization: Bearer $UPLOAD_TOKEN" \
  -H "Content-Type: application/pdf" \
  --data-binary @myfile.pdf
```

**Response:**
```json
{
  "url": "https://blob.vercelusercontent.com/.../myfile-abc123.pdf",
  "downloadUrl": "https://blob.vercelusercontent.com/download/...",
  "pathname": "myfile-abc123.pdf",
  "contentType": "application/pdf",
  "contentDisposition": "attachment"
}
```

---

### Step 3: Done!

**No need to do anything.** Vercel automatically calls `/api/upload/complete` webhook and the file is recorded in the database.

---

## Swift Example (macOS)

```swift
import Foundation

// 1. Request token
struct TokenRequest: Encodable {
    let filename: String
    let contentType: String?
}

struct TokenResponse: Decodable {
    let token: String
    let uploadUrl: String
}

let tokenRequest = TokenRequest(filename: "document.pdf", contentType: "application/pdf")
var tokenReq = URLRequest(url: URL(string: "https://droppapi.yangm.tech/api/upload/token")!)
tokenReq.httpMethod = "POST"
tokenReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
tokenReq.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
tokenReq.httpBody = try JSONEncoder().encode(tokenRequest)

let (tokenData, _) = try await URLSession.shared.data(for: tokenReq)
let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: tokenData)

// 2. Upload to Vercel
let fileData = try Data(contentsOf: fileURL)
var uploadReq = URLRequest(url: URL(string: tokenResponse.uploadUrl)!)
uploadReq.httpMethod = "POST"
uploadReq.setValue("Bearer \(tokenResponse.token)", forHTTPHeaderField: "Authorization")
uploadReq.setValue("application/pdf", forHTTPHeaderField: "Content-Type")
uploadReq.httpBody = fileData

let (uploadData, uploadResponse) = try await URLSession.shared.data(for: uploadReq)
print("Upload successful: \(uploadResponse)")

// 3. No action needed - webhook handles the rest
```

---

## Python Example

```python
import requests
import json

# Configuration
BASE_URL = "https://droppapi.yangm.tech"
SESSION_TOKEN = "your_session_token_here"
FILE_PATH = "document.pdf"

# Step 1: Get upload token
token_response = requests.post(
    f"{BASE_URL}/api/upload/token",
    headers={
        "Authorization": f"Bearer {SESSION_TOKEN}",
        "Content-Type": "application/json"
    },
    json={
        "filename": "document.pdf",
        "contentType": "application/pdf"
    }
)

token_data = token_response.json()
upload_token = token_data["token"]
upload_url = token_data["uploadUrl"]

# Step 2: Upload to Vercel
with open(FILE_PATH, "rb") as f:
    upload_response = requests.post(
        upload_url,
        headers={
            "Authorization": f"Bearer {upload_token}",
            "Content-Type": "application/pdf"
        },
        data=f
    )

print(f"Upload status: {upload_response.status_code}")
print(f"Response: {upload_response.json()}")

# Step 3: Done! Webhook will record the file
```

---

## JavaScript Example

```javascript
async function uploadFile(sessionToken, file) {
  // Step 1: Request upload token
  const tokenResponse = await fetch('https://droppapi.yangm.tech/api/upload/token', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${sessionToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      filename: file.name,
      contentType: file.type
    })
  });

  const { token, uploadUrl } = await tokenResponse.json();

  // Step 2: Upload directly to Vercel
  const uploadResponse = await fetch(uploadUrl, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': file.type
    },
    body: file
  });

  const result = await uploadResponse.json();

  // Step 3: Done! Webhook handles persistence
  return result;
}

// Usage
const file = document.querySelector('input[type=file]').files[0];
uploadFile(sessionToken, file).then(console.log);
```

---

## Required Headers

### /api/upload/token endpoint:
- `Authorization: Bearer <session_token>` ✅ Required
- `Content-Type: application/json` ✅ Required

### Vercel upload endpoint:
- `Authorization: Bearer <upload_token>` ✅ Required
- `Content-Type: <mime_type>` ✅ Required

---

## Response Codes

### /api/upload/token

| Code | Meaning |
|------|---------|
| 200 | Token generated successfully |
| 400 | Missing filename or invalid request |
| 401 | Invalid or missing session token |
| 500 | BLOB_READ_WRITE_TOKEN not configured |

### Vercel upload endpoint

| Code | Meaning |
|------|---------|
| 200 | Upload successful |
| 401 | Invalid upload token |
| 413 | File too large |
| 415 | MIME type not allowed |

---

## Allowed File Types

- `image/jpeg` - JPEG images
- `image/png` - PNG images
- `image/webp` - WebP images
- `application/pdf` - PDF documents
- `text/plain` - Plain text files

---

## Common Errors

### "Unauthorized"
**Cause:** Session token missing or invalid
**Fix:** Ensure you have valid JWT from `/api/auth/firebase/session`

### "File exceeds maximum size"
**Cause:** File larger than allowed
**Fix:** Check if you passed `maximumSizeInBytes` that's too small

### "Content type not allowed"
**Cause:** MIME type not in whitelist
**Fix:** Use one of the allowed types above

### "Token expired"
**Cause:** Took too long to upload
**Fix:** Request a new token

---

## Session Token

Get a session token by:
1. Logging in with Google via web
2. Or calling `/api/auth/firebase/session` with Firebase ID token:

```bash
curl -X POST https://droppapi.yangm.tech/api/auth/firebase/session \
  -H "Authorization: Bearer $FIREBASE_ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}'
```

---

## Webhook (automatic)

After upload completes, Vercel automatically calls:
```
POST /api/upload/complete
```

Your file is now recorded in MongoDB with:
- `user_id`: Your user ID
- `name`: Original filename
- `url`: CDN URL to access the file
- `content_type`: MIME type
- `created_at`: Upload timestamp
- `status`: "complete"

No action needed from your client.

---

## Testing with curl

```bash
#!/bin/bash

# Set these
SESSION_TOKEN="your_jwt_token"
FILE_PATH="./myfile.pdf"
FILE_NAME="myfile.pdf"
MIME_TYPE="application/pdf"

# Step 1: Get token
echo "=== Getting upload token ==="
TOKEN_RESPONSE=$(curl -s -X POST https://droppapi.yangm.tech/api/upload/token \
  -H "Authorization: Bearer $SESSION_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"filename\": \"$FILE_NAME\", \"contentType\": \"$MIME_TYPE\"}")

echo $TOKEN_RESPONSE | jq .

UPLOAD_TOKEN=$(echo $TOKEN_RESPONSE | jq -r '.token')
UPLOAD_URL=$(echo $TOKEN_RESPONSE | jq -r '.uploadUrl')

# Step 2: Upload to Vercel
echo ""
echo "=== Uploading file ==="
curl -X POST $UPLOAD_URL \
  -H "Authorization: Bearer $UPLOAD_TOKEN" \
  -H "Content-Type: $MIME_TYPE" \
  --data-binary @$FILE_PATH | jq .

echo ""
echo "=== Done! Check database for file record ==="
```

---

## Summary

**3 Steps:**
1. POST `/api/upload/token` → Get token
2. POST Vercel URL → Upload file
3. Done! (Webhook handles the rest)

**Works with:** macOS, iOS, Android, Web, CLI, anything with HTTP

**Security:** JWT auth on step 1, signed token on step 2, webhook on step 3
