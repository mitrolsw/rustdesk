#!/bin/bash

#!/usr/bin/env bash
set -euo pipefail

# test if the environment is set (useful when debugging this script...)
ENV_FILE="$(dirname "$0")/.env"
if [ -f "$ENV_FILE" ]; then
  echo "Loading environment from $ENV_FILE"
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    # Parse KEY=VALUE and strip surrounding quotes from value
    if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      val="${BASH_REMATCH[2]}"
      # Remove surrounding double or single quotes if present
      val="${val%\"}"
      val="${val#\"}"
      val="${val%\'}"
      val="${val#\'}"
      export "$key"="$val"
    fi
  done < "$ENV_FILE"
else
  echo "ERROR: file $ENV_FILE not found"
  exit 1
fi

# replace_safe <file> <old> <new> [desc]
# - if <old> is absent but <new> is already present, treat as already patched (no error)
# - if neither <old> nor <new> is present, fail (source changed upstream)
# - otherwise replace all occurrences of <old> with <new> and verify
replace_safe() {
  local file="$1" old="$2" new="$3" desc="${4:-$2}"
  local old_count new_count

  if [ ! -f "$file" ]; then
    echo "ERROR: file not found: $file"
    exit 1
  fi

  old_count=$(grep -cF -- "$old" "$file" || true)

  if [ "$old_count" -eq 0 ]; then
    # <old> not found: maybe already patched?
    new_count=$(grep -cF -- "$new" "$file" || true)
    if [ "$new_count" -gt 0 ]; then
      echo "[$desc] already patched in $file, skipping"
      return 0
    fi
    echo "ERROR: '$desc' not found in $file and replacement not present either (upstream changed the source?)"
    exit 1
  fi

  # print an unterminated message (will have the result appended)
  echo -n "[$desc] $old_count occurrence(s) in $file, replacing..."
  sed -i "s|$old|$new|g" "$file"

  if grep -qF -- "$old" "$file"; then
    echo " ERROR"
    echo "ERROR: '$desc' still present in $file after sed (escaping issue?)"
    exit 1
  fi

  echo " OK"
}

# setting app icons (starts from custom/icon.svg)
echo "Replacing icons..."
cp -f  custom/icon.svg        flutter/assets/icon.svg
cp -f  custom/icon.svg        res/scalable.svg
cp -f  custom/icon.svg        res/logo.svg
cp -f  custom/32x32.png       res/32x32.png
cp -f  custom/64x64.png       res/64x64.png
cp -f  custom/128x128.png     res/128x128.png
cp -f  custom/128x128@2x.png  res/128x128@2x.png
cp -f  custom/icon.ico        flutter/windows/runner/resources/app_icon.ico
cp -f  custom/icon.ico        res/icon.ico
cp -f  custom/icon.ico        res/tray-icon.ico

# replacing source code values
echo "Setting custom values..."
replace_safe "libs/hbb_common/src/config.rs" "rs-ny.rustdesk.com" "$RENDEZVOUS_SERVER" "Set Rendezvous server"
replace_safe "src/common.rs" "https://admin.rustdesk.com" "$API_SERVER" "Set API server"
replace_safe "libs/hbb_common/src/config.rs" "OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=" "$RS_PUB_KEY" "Set public key"
replace_safe "libs/hbb_common/src/config.rs" "APP_NAME: RwLock<String> = RwLock::new(\"RustDesk\".to_owned())" "APP_NAME: RwLock<String> = RwLock::new(\"$APP_NAME\".to_owned())" "Set application name"

# completed
echo "Customizations applied successfully"
