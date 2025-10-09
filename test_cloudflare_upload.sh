#!/bin/bash

# Test script to diagnose Cloudflare upload issues
# This creates a small test file and attempts upload to both direct and Cloudflare URLs

echo "🧪 GigHive Cloudflare Upload Test"
echo "=================================="
echo ""

# Configuration
DIRECT_URL="https://gighive/api/uploads.php?ui=json"
CLOUDFLARE_URL="https://dev.gighive.app/api/uploads.php?ui=json"
USERNAME="uploader"  # Replace with actual username
PASSWORD="secretuploader"  # Replace with actual password

# Create a test file (10MB)
TEST_FILE="/tmp/gighive_test_10mb.bin"
TEST_FILE="/Users/sodo/Downloads/chopper.mp4"
echo "📝 Creating 10MB test file..."
#dd if=/dev/zero of="$TEST_FILE" bs=1m count=10 2>/dev/null
echo "✅ Test file created: $TEST_FILE"
echo ""

# Test 1: Direct upload (local network)
echo "🧪 Test 1: Direct upload to $DIRECT_URL"
echo "----------------------------------------"
curl -v \
  --max-time 300 \
  -u "$USERNAME:$PASSWORD" \
  -F "event_date=2025-10-08" \
  -F "org_name=TestBand" \
  -F "event_type=band" \
  -F "label=curl test direct" \
  -F "file=@$TEST_FILE;type=application/octet-stream" \
  "$DIRECT_URL" \
  2>&1 | tee /tmp/curl_direct.log

echo ""
echo "✅ Direct upload test complete"
echo ""

# Test 2: Cloudflare upload
echo "🧪 Test 2: Cloudflare upload to $CLOUDFLARE_URL"
echo "------------------------------------------------"
curl -v \
  --max-time 300 \
  -u "$USERNAME:$PASSWORD" \
  -F "event_date=2025-10-08" \
  -F "org_name=TestBand" \
  -F "event_type=band" \
  -F "label=curl test cloudflare" \
  -F "file=@$TEST_FILE;type=application/octet-stream" \
  "$CLOUDFLARE_URL" \
  2>&1 | tee /tmp/curl_cloudflare.log

echo ""
echo "✅ Cloudflare upload test complete"
echo ""

# Test 3: Check Cloudflare response headers
echo "🧪 Test 3: Check Cloudflare headers"
echo "------------------------------------"
curl -I "$CLOUDFLARE_URL" 2>&1 | grep -i "cf-\|server\|content-length"
echo ""

# Cleanup
rm -f "$TEST_FILE"

echo ""
echo "📊 Summary"
echo "=========="
echo "Check the logs above for:"
echo "  - HTTP status codes (200/201 = success, 413 = too large, 524 = timeout)"
echo "  - Cloudflare headers (cf-ray, cf-cache-status)"
echo "  - Connection errors or timeouts"
echo ""
echo "Logs saved to:"
echo "  - /tmp/curl_direct.log"
echo "  - /tmp/curl_cloudflare.log"
