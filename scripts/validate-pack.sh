#!/usr/bin/env bash
set -euo pipefail

# validate-pack.sh — Validate a community sound pack ZIP
# Usage: validate-pack.sh <zip-path> <pack-id>
# Exit 0 on pass, 1 on failure with error details.

if [ $# -ne 2 ]; then
  echo "Usage: $0 <zip-path> <pack-id>"
  exit 1
fi

ZIP_PATH="$1"
PACK_ID="$2"
ERRORS=0

error() {
  echo "ERROR: $1"
  ERRORS=$((ERRORS + 1))
}

if [ ! -f "$ZIP_PATH" ]; then
  error "ZIP file not found: $ZIP_PATH"
  exit 1
fi

ALLOWED_EXTS="wav mp3 aiff m4a ogg aac"
VALID_EVENTS="session-start prompt-submit notification stop session-end subagent-stop tool-failure"
MAX_FILE_SIZE=$((10 * 1024 * 1024))  # 10 MB
MAX_DEPTH=3

echo "=== Phase 1: Pre-extract validation (zipinfo) ==="

# Get file listing
ENTRIES=$(zipinfo -1 "$ZIP_PATH" 2>/dev/null) || { error "Failed to read ZIP"; exit 1; }

while IFS= read -r entry; do
  [ -z "$entry" ] && continue

  # Path traversal
  if echo "$entry" | grep -q '\.\./' ; then
    error "Path traversal: $entry"
  fi

  # Absolute paths
  if [[ "$entry" == /* ]]; then
    error "Absolute path: $entry"
  fi

  # Nesting depth
  depth=$(echo "$entry" | tr -cd '/' | wc -c | tr -d ' ')
  # Trailing slash on dirs doesn't count as extra depth for files
  if [ "$depth" -gt "$MAX_DEPTH" ]; then
    error "Too deeply nested ($depth levels): $entry"
  fi

  # Structure check: must be <pack-id>/<event>/<file> or <pack-id>/<event>/
  # Strip trailing slash for dirs
  clean="${entry%/}"
  IFS='/' read -ra parts <<< "$clean"

  # Top-level must be the pack ID
  if [ "${parts[0]}" != "$PACK_ID" ]; then
    error "Unexpected top-level directory '${parts[0]}', expected '$PACK_ID': $entry"
  fi

  # If it's a file (no trailing slash and has 3 parts)
  if [[ "$entry" != */ ]] && [ ${#parts[@]} -ge 3 ]; then
    event_dir="${parts[1]}"
    filename="${parts[2]}"

    # Validate event name
    valid_event=false
    for ev in $VALID_EVENTS; do
      if [ "$event_dir" = "$ev" ]; then
        valid_event=true
        break
      fi
    done
    if [ "$valid_event" = false ]; then
      error "Invalid event directory '$event_dir': $entry"
    fi

    # Validate extension
    ext="${filename##*.}"
    ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    valid_ext=false
    for ae in $ALLOWED_EXTS; do
      if [ "$ext_lower" = "$ae" ]; then
        valid_ext=true
        break
      fi
    done
    if [ "$valid_ext" = false ]; then
      error "Disallowed extension '.$ext_lower': $entry"
    fi
  fi

done <<< "$ENTRIES"

# Check for symlinks
SYMLINKS=$(zipinfo "$ZIP_PATH" 2>/dev/null | grep '^l' || true)
if [ -n "$SYMLINKS" ]; then
  error "Symlinks detected in ZIP:"
  echo "$SYMLINKS"
fi

if [ "$ERRORS" -gt 0 ]; then
  echo "=== Phase 1 FAILED with $ERRORS error(s) ==="
  exit 1
fi
echo "Phase 1 passed."

echo ""
echo "=== Phase 2: Post-extract validation (file content) ==="

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

unzip -o -q "$ZIP_PATH" -d "$TEMP_DIR" || { error "Failed to extract ZIP"; exit 1; }

PACK_DIR="$TEMP_DIR/$PACK_ID"
if [ ! -d "$PACK_DIR" ]; then
  error "Expected pack directory '$PACK_ID' not found after extraction"
  exit 1
fi

# Walk all files
find "$PACK_DIR" -type f | while IFS= read -r filepath; do
  relpath="${filepath#$PACK_DIR/}"
  filename=$(basename "$filepath")

  # File size check
  file_size=$(stat -f%z "$filepath" 2>/dev/null || stat --printf="%s" "$filepath" 2>/dev/null || echo 0)
  if [ "$file_size" -gt "$MAX_FILE_SIZE" ]; then
    error "File too large (${file_size} bytes, max ${MAX_FILE_SIZE}): $relpath"
  fi

  # Magic byte validation via xxd
  header=$(xxd -p -l 12 "$filepath" 2>/dev/null || true)
  if [ -z "$header" ]; then
    error "Cannot read file header: $relpath"
    continue
  fi

  valid_magic=false

  # WAV: 52494646....57415645
  if [[ ${#header} -ge 24 && "${header:0:8}" == "52494646" && "${header:16:8}" == "57415645" ]]; then
    valid_magic=true
  fi
  # AIFF: 464f524d....41494646
  if [[ ${#header} -ge 24 && "${header:0:8}" == "464f524d" && "${header:16:8}" == "41494646" ]]; then
    valid_magic=true
  fi
  # OGG: 4f676753
  if [[ "${header:0:8}" == "4f676753" ]]; then
    valid_magic=true
  fi
  # MP3 ID3: 494433
  if [[ "${header:0:6}" == "494433" ]]; then
    valid_magic=true
  fi
  # MP3 frame sync: fffb, fff3, fff2
  if [[ "${header:0:4}" == "fffb" || "${header:0:4}" == "fff3" || "${header:0:4}" == "fff2" ]]; then
    valid_magic=true
  fi
  # AAC ADTS: fff1, fff9
  if [[ "${header:0:4}" == "fff1" || "${header:0:4}" == "fff9" ]]; then
    valid_magic=true
  fi
  # M4A: ftyp at offset 4 (bytes 4-7 = chars 8-15)
  if [[ ${#header} -ge 16 && "${header:8:8}" == "66747970" ]]; then
    valid_magic=true
  fi

  if [ "$valid_magic" = false ]; then
    error "Invalid audio magic bytes (${header:0:16}...): $relpath"
  fi

done

if [ "$ERRORS" -gt 0 ]; then
  echo "=== Phase 2 FAILED with $ERRORS error(s) ==="
  exit 1
fi

echo "Phase 2 passed."
echo ""
echo "=== All validations passed for $PACK_ID ==="
exit 0
