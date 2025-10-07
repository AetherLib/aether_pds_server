#!/bin/bash
# End-to-end test for PDS

set -e

BASE_URL="http://localhost:4000"

echo "========================================"
echo "PDS End-to-End Test"
echo "========================================"
echo ""

# 1. Create Account
echo "1. Creating account..."
CREATE_RESPONSE=$(curl -s -X POST "$BASE_URL/xrpc/com.atproto.server.createAccount" \
  -H "Content-Type: application/json" \
  -d '{
    "handle": "test.user",
    "email": "test@example.com",
    "password": "testpassword123"
  }')

echo "Response: $CREATE_RESPONSE"
echo ""

# Extract tokens and DID
ACCESS_TOKEN=$(echo $CREATE_RESPONSE | jq -r '.accessJwt')
DID=$(echo $CREATE_RESPONSE | jq -r '.did')

if [ "$ACCESS_TOKEN" == "null" ] || [ "$DID" == "null" ]; then
  echo "❌ Failed to create account"
  exit 1
fi

echo "✓ Account created"
echo "  DID: $DID"
echo "  Token: ${ACCESS_TOKEN:0:20}..."
echo ""

# 2. Check repository exists
echo "2. Checking repository..."
REPO_RESPONSE=$(curl -s -X GET "$BASE_URL/xrpc/com.atproto.repo.describeRepo?repo=$DID")
echo "Response: $REPO_RESPONSE"

if echo "$REPO_RESPONSE" | jq -e '.did' > /dev/null; then
  echo "✓ Repository exists"
else
  echo "❌ Repository not found"
  exit 1
fi
echo ""

# 3. Create a record
echo "3. Creating record..."
RECORD_RESPONSE=$(curl -s -X POST "$BASE_URL/xrpc/com.atproto.repo.createRecord" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d "{
    \"repo\": \"$DID\",
    \"collection\": \"app.bsky.feed.post\",
    \"record\": {
      \"text\": \"Hello from PDS!\",
      \"createdAt\": \"$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")\"
    }
  }")

echo "Response: $RECORD_RESPONSE"
echo ""

RECORD_URI=$(echo $RECORD_RESPONSE | jq -r '.uri')
RECORD_CID=$(echo $RECORD_RESPONSE | jq -r '.cid')

if [ "$RECORD_URI" == "null" ]; then
  echo "❌ Failed to create record"
  exit 1
fi

echo "✓ Record created"
echo "  URI: $RECORD_URI"
echo "  CID: $RECORD_CID"
echo ""

# 4. Query the record
echo "4. Querying record..."
RKEY=$(echo $RECORD_URI | awk -F'/' '{print $NF}')
GET_RESPONSE=$(curl -s -X GET "$BASE_URL/xrpc/com.atproto.repo.getRecord?repo=$DID&collection=app.bsky.feed.post&rkey=$RKEY")
echo "Response: $GET_RESPONSE"

if echo "$GET_RESPONSE" | jq -e '.value.text' > /dev/null; then
  echo "✓ Record retrieved"
else
  echo "❌ Failed to retrieve record"
  exit 1
fi
echo ""

# 5. List records
echo "5. Listing records..."
LIST_RESPONSE=$(curl -s -X GET "$BASE_URL/xrpc/com.atproto.repo.listRecords?repo=$DID&collection=app.bsky.feed.post")
echo "Response: $LIST_RESPONSE"

RECORD_COUNT=$(echo $LIST_RESPONSE | jq '.records | length')
echo "✓ Found $RECORD_COUNT record(s)"
echo ""

# 6. Sync repository (CAR export)
echo "6. Syncing repository (CAR export)..."
curl -s -X GET "$BASE_URL/xrpc/com.atproto.sync.getRepo?did=$DID" \
  -o /tmp/repo.car

if [ -f /tmp/repo.car ]; then
  SIZE=$(wc -c < /tmp/repo.car)
  echo "✓ Repository exported to CAR"
  echo "  Size: $SIZE bytes"
  echo "  File: /tmp/repo.car"
else
  echo "❌ Failed to export repository"
  exit 1
fi
echo ""

# 7. Get latest commit
echo "7. Getting latest commit..."
COMMIT_RESPONSE=$(curl -s -X GET "$BASE_URL/xrpc/com.atproto.sync.getLatestCommit?did=$DID")
echo "Response: $COMMIT_RESPONSE"

if echo "$COMMIT_RESPONSE" | jq -e '.cid' > /dev/null; then
  echo "✓ Got latest commit"
else
  echo "❌ Failed to get commit"
  exit 1
fi
echo ""

echo "========================================"
echo "✅ All tests passed!"
echo "========================================"
