#!/bin/bash
# Spotify API version with proper JSON parsing
# Requires: SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET environment variables
# Get these from https://developer.spotify.com/dashboard

TRACK_ID=$(echo "$1" | cut -d/ -f5)

# Check if credentials are set
if [[ -z "$SPOTIFY_CLIENT_ID" ]] || [[ -z "$SPOTIFY_CLIENT_SECRET" ]]; then
  # Fall back to returning empty values
  echo "TRACK_NUMBER="
  echo "YEAR="
  echo "GENRE="
  echo "BPM="
  exit 0
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo "TRACK_NUMBER="
  echo "YEAR="
  echo "GENRE="
  echo "BPM="
  exit 0
fi

# Get or refresh access token (cache for 55 minutes)
TOKEN_FILE="/tmp/spotify_token_$(echo $SPOTIFY_CLIENT_ID | md5sum | cut -d' ' -f1)"
if [[ ! -f "$TOKEN_FILE" ]] || [[ $(find "$TOKEN_FILE" -mmin +55 2>/dev/null) ]]; then
  TOKEN=$(curl -s -X POST "https://accounts.spotify.com/api/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials&client_id=$SPOTIFY_CLIENT_ID&client_secret=$SPOTIFY_CLIENT_SECRET" \
    | jq -r '.access_token // empty')
  
  if [[ -z "$TOKEN" ]]; then
    # Authentication failed
    echo "TRACK_NUMBER="
    echo "YEAR="
    echo "GENRE="
    echo "BPM="
    exit 0
  fi
  
  echo "$TOKEN" > "$TOKEN_FILE"
else
  TOKEN=$(cat "$TOKEN_FILE")
fi

# Get track info
TRACK_DATA=$(curl -s -X GET "https://api.spotify.com/v1/tracks/$TRACK_ID" \
  -H "Authorization: Bearer $TOKEN")

# Extract track number
TRACK_NUMBER=$(echo "$TRACK_DATA" | jq -r '.track_number // empty')

# Extract year from release date
YEAR=$(echo "$TRACK_DATA" | jq -r '.album.release_date // empty' | cut -d- -f1)

# Get artist ID and fetch genres
ARTIST_ID=$(echo "$TRACK_DATA" | jq -r '.artists[0].id // empty')
GENRE=""
if [[ -n "$ARTIST_ID" ]]; then
  ARTIST_DATA=$(curl -s -X GET "https://api.spotify.com/v1/artists/$ARTIST_ID" \
    -H "Authorization: Bearer $TOKEN")
  GENRE=$(echo "$ARTIST_DATA" | jq -r '.genres[0] // empty')
fi

# BPM requires user OAuth (not available with client credentials)
# Audio features endpoint returns 403 with client credentials flow
# Would need to implement full OAuth flow with user authorization
BPM=""

# Output results
echo "TRACK_NUMBER=$TRACK_NUMBER"
echo "YEAR=$YEAR"
echo "GENRE=$GENRE"
echo "BPM=$BPM"
