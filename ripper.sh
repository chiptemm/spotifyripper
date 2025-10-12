#!/bin/bash
script_dir=$(dirname $(readlink -f $0))

# Parse command line arguments
OUTPUT_FORMAT="ogg"
MUSICDIR=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --mp3)
      OUTPUT_FORMAT="mp3"
      shift
      ;;
    --ogg)
      OUTPUT_FORMAT="ogg"
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS] [MUSIC_DIRECTORY]"
      echo ""
      echo "Options:"
      echo "  --mp3     Save recordings as MP3 (320kbps)"
      echo "  --ogg     Save recordings as OGG (default, 192kbps)"
      echo "  -h, --help    Show this help message"
      echo ""
      echo "Example:"
      echo "  $0 --mp3 ~/Music/spotify-rips/"
      exit 0
      ;;
    *)
      MUSICDIR="$1"
      shift
      ;;
  esac
done

# Check dependencies first
if [[ "$OUTPUT_FORMAT" == "mp3" ]]; then
  if ! "$script_dir/depends.sh" --mp3; then
    exit 1
  fi
else
  if ! "$script_dir/depends.sh"; then
    exit 1
  fi
fi

if [[ -z $MUSICDIR ]]; then
  musicdir="."
else
  musicdir=$MUSICDIR
fi

# Set file extension and temp file based on format
if [[ "$OUTPUT_FORMAT" == "mp3" ]]; then
  FILE_EXT="mp3"
  TEMP_FILE="tmp.mp3"
  echo "Recording format: MP3 (320kbps)"
else
  FILE_EXT="ogg"
  TEMP_FILE="tmp.ogg"
  echo "Recording format: OGG Vorbis (192kbps)"
fi

# Get the sink input ID of Spotify (PipeWire compatible)
spotify=$(pactl list sink-inputs | while read line; do
  [[ -n $(echo $line | grep "Sink Input #") ]] && index=$(echo $line | grep -o '[0-9]*')
  [[ -n $(echo $line | grep -i spotify) ]] && echo $index && exit
done)

if [[ -z $spotify ]]; then
  echo "Spotify is not running"
  exit
fi

# Determine if spotify.monitor is already set up
if [[ -z $(pactl list short sinks | grep spotify) ]]; then
  pactl load-module module-null-sink sink_name=spotify sink_properties=device.description="Spotify"
fi

# Move Spotify sound output back to default at exit
pasink=$(pactl get-default-sink)
trap "pactl move-sink-input $spotify $pasink" EXIT

# Move Spotify to its own sink so recorded output will not get corrupted
pactl move-sink-input $spotify spotify

$script_dir/notify.sh | while read line
do
  if [[ $line == "__SWITCH__" ]]; then
    killall oggenc 2>/dev/null
    killall ffmpeg 2>/dev/null
    killall parec 2>/dev/null
    
    # Give encoders time to finish writing and close files
    sleep 0.5
    
    if [[ -n $title ]]; then
      # Sanitize filenames
      saveto="$musicdir/${artist//\/ /}/${album//\/ /}"
      final_file="$saveto/${title//\/ /}.$FILE_EXT"
      
      if [[ ! -a $saveto ]]; then
        mkdir -p "$saveto"
      fi
      
      # Add metadata based on format
      if [[ "$OUTPUT_FORMAT" == "mp3" ]]; then
        # Use ffmpeg to add ID3 tags to MP3 and save directly to final location
        if [[ -f "$TEMP_FILE" ]]; then
          # Build metadata arguments
          metadata_args=(-metadata artist="$artist" -metadata album="$album" -metadata title="$title")
          [[ -n "$tracknumber" ]] && metadata_args+=(-metadata track="$tracknumber")
          [[ -n "$year" ]] && metadata_args+=(-metadata date="$year")
          [[ -n "$genre" ]] && metadata_args+=(-metadata genre="$genre")
          [[ -n "$bpm" ]] && metadata_args+=(-metadata TBPM="$bpm")
          
          ffmpeg -i "$TEMP_FILE" -y -c copy "${metadata_args[@]}" "$final_file" 2>/dev/null && rm "$TEMP_FILE"
          echo "Saved song $title by $artist to $final_file"
          [[ -n "$tracknumber" ]] && echo "  Track: $tracknumber"
          [[ -n "$year" ]] && echo "  Year: $year"
          [[ -n "$genre" ]] && echo "  Genre: $genre"
        else
          echo "Warning: Temporary file $TEMP_FILE not found"
        fi
      else
        # Use vorbiscomment for OGG
        if [[ -f "$TEMP_FILE" ]]; then
          vorbiscomment -a "$TEMP_FILE" -t "ARTIST=$artist" -t "ALBUM=$album" -t "TITLE=$title"
          [[ -n "$tracknumber" ]] && vorbiscomment -a "$TEMP_FILE" -t "TRACKNUMBER=$tracknumber"
          [[ -n "$year" ]] && vorbiscomment -a "$TEMP_FILE" -t "DATE=$year"
          [[ -n "$genre" ]] && vorbiscomment -a "$TEMP_FILE" -t "GENRE=$genre"
          [[ -n "$bpm" ]] && vorbiscomment -a "$TEMP_FILE" -t "BPM=$bpm"
          mv "$TEMP_FILE" "$final_file"
          echo "Saved song $title by $artist to $final_file"
        else
          echo "Warning: Temporary file $TEMP_FILE not found"
        fi
      fi
      if [[ -s cover.jpg ]] && [[ ! -a "$saveto/cover.jpg" ]]; then
        mv cover.jpg "$saveto/cover.jpg"
      fi
      artist=""
      album=""
      title=""
      tracknumber=""
      year=""
      genre=""
      bpm=""
      rm -f cover.jpg
    fi
    echo "RECORDING"
    
    # Start recording based on format
    if [[ "$OUTPUT_FORMAT" == "mp3" ]]; then
      parec -d spotify.monitor 2>/dev/null | ffmpeg -y -ac 2 -f s16le -ar 44100 -i pipe: -b:a 320k "$TEMP_FILE" 2>/dev/null &
    else
      parec -d spotify.monitor 2>/dev/null | oggenc -b 192 -o "$TEMP_FILE" --raw - 2>/dev/null &
    fi
    disown
    
    if [[ "$OUTPUT_FORMAT" == "mp3" ]]; then
      trap "pactl move-sink-input $spotify $pasink && killall ffmpeg && killall parec" EXIT
    else
      trap "pactl move-sink-input $spotify $pasink && killall oggenc && killall parec" EXIT
    fi
  else
    variant=$(echo "$line"|cut -d= -f1)
    string=$(echo "$line"|cut -d= -f2-)
    if [[ $variant == "artist" ]]; then
      artist="$string"
      echo "Artist = $string"
    elif [[ $variant == "title" ]]; then
      title="$string"
      echo "Title = $string"
    elif [[ $variant == "album" ]]; then
      album="$string"
      echo "Album = $string"
    elif [[ $variant == "contentCreated" ]]; then
      # Extract year from date (format: YYYY-MM-DD or just YYYY)
      year=$(echo "$string" | cut -d- -f1)
      echo "Year = $year"
    elif [[ $variant == "genre" ]]; then
      genre="$string"
      echo "Genre = $genre"
    elif [[ $variant == "bpm" ]]; then
      bpm="$string"
      echo "BPM = $bpm"
    elif [[ $variant == "url" ]]; then
      # Get the track number and metadata using trackify.sh
      echo "URL = $string"
      trackify_output=$("$script_dir/trackify.sh" "$string")
      
      # Parse the output from trackify.sh
      tracknumber=$(echo "$trackify_output" | grep "^TRACK_NUMBER=" | cut -d= -f2)
      year=$(echo "$trackify_output" | grep "^YEAR=" | cut -d= -f2)
      genre=$(echo "$trackify_output" | grep "^GENRE=" | cut -d= -f2)
      bpm=$(echo "$trackify_output" | grep "^BPM=" | cut -d= -f2)
      
      [[ -n "$tracknumber" ]] && echo "Track number = $tracknumber"
      [[ -n "$year" ]] && echo "Year = $year"
      [[ -n "$genre" ]] && echo "Genre = $genre"
      [[ -n "$bpm" ]] && echo "BPM = $bpm"
    elif [[ $variant == "artUrl" ]]; then
      # Download album art directly from Spotify's CDN
      echo "Downloading cover art from $string"
      wget -q -O cover.jpg "$string" 2>/dev/null || true
    fi
  fi
done
