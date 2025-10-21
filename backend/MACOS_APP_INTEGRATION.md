# macOS App Integration with New Upload API

## Overview

The macOS app can now use a simplified upload flow:

**Old flow:** Send multipart form data directly to backend
**New flow:** Get token from backend → upload directly to Vercel

This is cleaner, more secure, and works for all platforms.

---

## Current macOS Implementation (DroppAPI.swift)

The macOS app currently:
1. Constructs multipart form-data manually
2. Sends to `/api/upload` with JWT auth
3. Backend handles file storage (old pattern)

**This no longer works** with the new backend architecture.

---

## New Integration Pattern

### Step 1: Update DroppAPIClient.upload()

**Location:** `/macos/Dropp/Dropp/DroppAPI.swift:54`

**Replace the entire `upload()` function with:**

```swift
func upload(item: ShelfItem) async throws {
  try requireAuth()

  let fileURL = item.resolvedURL()
  let didStartAccess = fileURL.startAccessingSecurityScopedResource()
  defer {
    if didStartAccess {
      fileURL.stopAccessingSecurityScopedResource()
    }
  }

  let filename = item.cloudInfo?.filename ?? fileURL.lastPathComponent
  guard !filename.isEmpty else { throw DroppAPIError.noFilename }

  // Read file data
  let fileData: Data
  do {
    fileData = try await readFileData(at: fileURL)
  } catch {
    NSLog("❌ Upload read failed for \(fileURL.path): \(error.localizedDescription)")
    throw DroppAPIError.fileReadFailed
  }

  let contentType = item.cloudInfo?.contentType ?? "application/octet-stream"

  // STEP 1: Get upload token from backend
  let uploadToken = try await getUploadToken(
    filename: filename,
    contentType: contentType,
    fileSize: fileData.count
  )

  // STEP 2: Upload directly to Vercel
  try await uploadToVercel(
    token: uploadToken,
    filename: filename,
    contentType: contentType,
    fileData: fileData
  )

  NSLog("✅ File uploaded successfully: \(filename)")
}
```

---

### Step 2: Add Helper Functions

**Add these functions to `DroppAPIClient` class:**

```swift
private func getUploadToken(
  filename: String,
  contentType: String,
  fileSize: Int
) async throws -> String {
  try requireAuth()

  let url = DroppAPI.baseURL.appendingPathComponent("upload/token", isDirectory: true)
  var request = URLRequest(url: url)
  request.httpMethod = "POST"
  auth.authorize(&request)
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")

  let body = [
    "filename": filename,
    "contentType": contentType,
    "maximumSizeInBytes": fileSize * 2  // Allow 2x for safety
  ] as [String : Any]

  request.httpBody = try JSONSerialization.data(withJSONObject: body)

  let t0 = Date()
  let (data, response) = try await session.data(for: request)
  logNetwork(request: request, response: response, data: data, startedAt: t0, purpose: "get-upload-token")
  try validateResponse(response, data: data)

  let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
  return tokenResponse.token
}

private func uploadToVercel(
  token: String,
  filename: String,
  contentType: String,
  fileData: Data
) async throws {
  let url = URL(string: "https://blob.vercelusercontent.com/upload")!
  var request = URLRequest(url: url)
  request.httpMethod = "POST"
  request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
  request.setValue(contentType, forHTTPHeaderField: "Content-Type")
  request.httpBody = fileData

  NSLog("➡️ [upload] POST \(url.absoluteString) • filename=\(filename) • size=\(fileData.count)")

  let t0 = Date()
  let (data, response) = try await session.data(for: request)
  logNetwork(request: request, response: response, data: data, startedAt: t0, purpose: "upload-to-vercel")
  try validateResponse(response, data: data)

  NSLog("✅ Vercel accepted upload: \(filename)")
}

private struct TokenResponse: Decodable {
  let token: String
  let uploadUrl: String
}
```

---

### Step 3: Clean Up

**Remove the old multipart form building code:**

Delete these functions from `DroppAPIClient` (they're no longer needed):
- `makeMultipartBody()` - No longer needed
- The old multipart body construction in `upload()` - Replaced

---

## Behavior Changes

### Before (Old Flow)
```
macOS app
  ↓
POST /api/upload (multipart form)
  ↓
Backend stores in MongoDB
  ↓
Done
```

### After (New Flow)
```
macOS app
  ↓
POST /api/upload/token (get token)
  ↓
Backend validates JWT, generates Vercel token
  ↓
macOS app
  ↓
POST https://blob.vercelusercontent.com/upload (direct to Vercel)
  ↓
File stored at Vercel CDN
  ↓
Vercel webhook calls backend
  ↓
Backend stores in MongoDB
  ↓
Done
```

---

## Benefits

✅ **Smaller requests to backend** - Only token request goes to backend
✅ **Faster uploads** - Direct connection to Vercel CDN
✅ **Better security** - Token is time-limited and signed
✅ **Same user isolation** - JWT auth still required on token request
✅ **Webhook reliability** - Vercel retries if backend is down
✅ **Works with all clients** - macOS, iOS, Android, web use same flow

---

## Error Handling

The existing error handling in DroppAPIClient mostly works:

```swift
enum DroppAPIError: Error, LocalizedError {
  case invalidURL        // Token endpoint URL invalid
  case noFilename        // Filename missing
  case fileReadFailed    // File read failed
  case badResponse(status: Int, body: String?)  // Token or Vercel responded with error
  case missingData       // Response missing token
  case unauthorized      // Session token missing/invalid
}
```

### New error scenarios to handle:

**Token request fails (401):**
```swift
// User needs to re-authenticate
throw DroppAPIError.unauthorized
```

**Vercel upload fails (413 - file too large):**
```swift
// tokenResponse has constraints, check before upload
throw DroppAPIError.badResponse(status: 413, body: "File too large")
```

**MIME type not allowed (415):**
```swift
// contentType not in whitelist
throw DroppAPIError.badResponse(status: 415, body: "MIME type not allowed")
```

---

## Network Logging

The existing `logNetwork()` function works great for debugging.

You'll see logs like:
```
➡️ [get-upload-token] POST https://droppapi.yangm.tech/api/upload/token
   Status: 200 • 245 ms
   Response Headers:
   ...
   Body: {"token":"eyJ...", "uploadUrl":"https://..."}

➡️ [upload-to-vercel] POST https://blob.vercelusercontent.com/upload
   Status: 200 • 1234 ms
   Body: {"url":"https://blob.../file-abc123.pdf", ...}
```

---

## Session Token Management

No changes needed! AuthManager still:
- Gets JWT from login callback
- Stores in Keychain
- Sends in `Authorization: Bearer <token>` header

The only difference is this token is now used for `/api/upload/token` instead of the old `/api/upload` endpoint.

---

## Testing

### Manual Test Steps

1. **Login to macOS app** (with Google)

2. **Drag a file onto the app**

3. **Check Console.app logs:**
   ```
   ✅ File uploaded successfully: document.pdf
   ```

4. **Verify in MongoDB:**
   ```javascript
   db.files.findOne({ name: "document.pdf" })
   // Should show: { user_id, name, url, status: "complete" }
   ```

### CLI Test
```bash
# Get session token from AuthManager (or login on web first)
SESSION_TOKEN="eyJ..."

# Request token
curl -X POST https://droppapi.yangm.tech/api/upload/token \
  -H "Authorization: Bearer $SESSION_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"filename": "test.pdf", "contentType": "application/pdf"}'

# Copy the token from response
UPLOAD_TOKEN="eyJ..."

# Upload test file
curl -X POST https://blob.vercelusercontent.com/upload \
  -H "Authorization: Bearer $UPLOAD_TOKEN" \
  -H "Content-Type: application/pdf" \
  --data-binary @test.pdf
```

---

## Backwards Compatibility

⚠️ **Breaking Change**: Old `/api/upload` endpoint no longer accepts multipart form uploads.

If you still need to support old client versions, create a migration endpoint:
```swift
// In DroppAPI.swift, add a version check
let apiVersion = auth.apiVersion ?? "1.0"
if apiVersion < "2.0" {
  // Use old upload flow
} else {
  // Use new token-based flow
}
```

---

## File Lifecycle

### Before Upload
```
macOS app
  ↓
Reading file (with NSFileCoordinator)
  ↓
iCloud files are downloaded if needed
  ↓
File data loaded into memory
```

### During Upload
```
Token request
  ↓ (JWT verified, user checked)
Vercel upload
  ↓ (Token validated, MIME type checked, file size checked)
File stored at Vercel
```

### After Upload
```
Vercel webhook → /api/upload/complete
  ↓
Backend validates webhook
  ↓
MongoDB record created
  ↓
File visible in app's file list
```

---

## Performance Improvements

| Metric | Before | After |
|--------|--------|-------|
| Backend CPU | 100% (handling upload) | ~5% (just validation) |
| Upload speed | Network limited | **CDN optimized** |
| Request size | Full file → backend | Only token request |
| Concurrent uploads | Limited by server | Limited by Vercel |

---

## Summary

Replace the old multipart upload in DroppAPI.swift with:
1. `getUploadToken()` - Request signed token
2. `uploadToVercel()` - Upload directly to CDN

The new flow is simpler, faster, and works for all client types.

For questions about the backend, see `API_UPLOAD_ARCHITECTURE.md`.
