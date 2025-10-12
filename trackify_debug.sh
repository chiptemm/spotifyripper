#!/bin/bash
# Debug version to see what Spotify API returns

TRACK_ID=$(echo "$1" | cut -d/ -f5)

if [[ -z "$SPOTIFY_CLIENT_ID" ]] || [[ -z "$SPOTIFY_CLIENT_SECRET" ]]; then
  echo "ERROR: Missing credentials"
  exit 1
fi

# Get token
TOKEN_FILE="/tmp/spotify_token_$(echo $SPOTIFY_CLIENT_ID | md5sum | cut -d' ' -f1)"
if [[ ! -f "$TOKEN_FILE" ]] || [[ $(find "$TOKEN_FILE" -mmin +55 2>/dev/null) ]]; then
  TOKEN=$(curl -s -X POST "https://accounts.spotify.com/api/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials&client_id=$SPOTIFY_CLIENT_ID&client_secret=$SPOTIFY_CLIENT_SECRET" \
    | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
  echo "$TOKEN" > "$TOKEN_FILE"
else
  TOKEN=$(cat "$TOKEN_FILE")
fi

echo "=== TRACK DATA ==="
TRACK_DATA=$(curl -s -X GET "https://api.spotify.com/v1/tracks/$TRACK_ID" \
  -H "Authorization: Bearer $TOKEN")
echo "$TRACK_DATA" | jq '.' 2>/dev/null || echo "$TRACK_DATA"

echo ""
echo "=== AUDIO FEATURES ==="
AUDIO_FEATURES=$(curl -s -X GET "https://api.spotify.com/v1/audio-features/$TRACK_ID" \
  -H "Authorization: Bearer $TOKEN")
echo "$AUDIO_FEATURES" | jq '.' 2>/dev/null || echo "$AUDIO_FEATURES"

echo ""
echo "=== ARTIST DATA ==="
ARTIST_ID=$(echo "$TRACK_DATA" | grep -o '"artists":\[{"[^}]*"id":"[^"]*' | grep -o 'id":"[^"]*' | head -1 | cut -d'"' -f3)
echo "Artist ID: $ARTIST_ID"
if [[ -n "$ARTIST_ID" ]]; then
  ARTIST_DATA=$(curl -s -X GET "https://api.spotify.com/v1/artists/$ARTIST_ID" \
    -H "Authorization: Bearer $TOKEN")
  echo "$ARTIST_DATA" | jq '.' 2>/dev/null || echo "$ARTIST_DATA"
fi
