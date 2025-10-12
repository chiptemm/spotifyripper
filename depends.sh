#!/bin/bash
# Dependency checker for Spotify ripper script

missing_deps=()
missing_packages=()

# Check for required commands
check_command() {
  local cmd=$1
  local package=$2
  
  if ! command -v "$cmd" &> /dev/null; then
    missing_deps+=("$cmd")
    if [[ -n "$package" ]] && [[ ! " ${missing_packages[@]} " =~ " ${package} " ]]; then
      missing_packages+=("$package")
    fi
    return 1
  fi
  return 0
}

echo "Checking dependencies..."

# Audio recording and encoding
check_command "parec" "pulseaudio-utils"
check_command "pactl" "pulseaudio-utils"
check_command "oggenc" "vorbis-tools"
check_command "vorbiscomment" "vorbis-tools"

# MP3 encoding (optional - only needed if using --mp3 flag)
if [[ "$1" == "--mp3" ]]; then
  check_command "ffmpeg" "ffmpeg"
fi

# Utilities
check_command "wget" "wget"
check_command "curl" "curl"
check_command "dbus-monitor" "dbus"
check_command "jq" "jq"

# Check if any dependencies are missing
if [ ${#missing_deps[@]} -eq 0 ]; then
  echo "✓ All dependencies are installed!"
  
  # Check for optional Spotify API credentials
  if [[ -z "$SPOTIFY_CLIENT_ID" ]] || [[ -z "$SPOTIFY_CLIENT_SECRET" ]]; then
    echo ""
    echo "⚠ NOTICE: Spotify API credentials not configured"
    echo "Basic metadata (artist, album, title) will work, but enhanced metadata"
    echo "(track numbers, year, genre) will not be available."
    echo ""
    echo "To enable enhanced metadata (optional):"
    echo "1. Get free API credentials at: https://developer.spotify.com/dashboard"
    echo "   - Create an app (any name)"
    echo "   - Use 'http://localhost' as redirect URI"
    echo "   - Copy your Client ID and Client Secret"
    echo ""
    echo "2. Add to ~/.bashrc:"
    echo "   export SPOTIFY_CLIENT_ID=\"your_client_id_here\""
    echo "   export SPOTIFY_CLIENT_SECRET=\"your_client_secret_here\""
    echo ""
    echo "3. Reload: source ~/.bashrc"
    echo ""
  else
    echo "✓ Spotify API credentials configured!"
  fi
  
  exit 0
else
  echo ""
  echo "ERROR: Missing required dependencies!"
  echo ""
  echo "Missing commands:"
  for cmd in "${missing_deps[@]}"; do
    echo "  - $cmd"
  done
  echo ""
  echo "To install missing packages, run:"
  echo ""
  echo "  sudo apt install ${missing_packages[*]}"
  echo ""
  exit 1
fi
