#!/bin/bash
# Script to encode Firebase service account JSON to base64 for Vercel deployment

if [ $# -eq 0 ]; then
    echo "Usage: $0 <path-to-firebase-service-account.json>"
    echo ""
    echo "This script converts your Firebase service account JSON file to base64"
    echo "for use with Vercel's environment variables."
    echo ""
    echo "Example:"
    echo "  $0 firebase-service-account.json"
    exit 1
fi

JSON_FILE="$1"

if [ ! -f "$JSON_FILE" ]; then
    echo "Error: File '$JSON_FILE' not found!"
    exit 1
fi

echo "Encoding $JSON_FILE to base64..."
echo ""
echo "Add this value to your Vercel environment variables as:"
echo "FIREBASE_SERVICE_ACCOUNT_BASE64"
echo ""
echo "============================================================"

# Encode to base64 and remove newlines
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    base64 -i "$JSON_FILE" | tr -d '\n'
else
    # Linux
    base64 -w 0 "$JSON_FILE"
fi

echo ""
echo "============================================================"
echo ""
echo "Next steps:"
echo "1. Copy the base64 string above"
echo "2. Go to your Vercel project: https://vercel.com/dashboard"
echo "3. Navigate to Settings → Environment Variables"
echo "4. Add FIREBASE_SERVICE_ACCOUNT_BASE64 with the copied value"
echo "5. Redeploy your application"
