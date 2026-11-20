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

# apply_patch_idempotent <desc> <patch_file>
apply_patch_idempotent() {
  local desc="$1" patch_file="$2"

  if [ ! -f "$patch_file" ]; then
    echo "ERROR: patch file not found: $patch_file"
    exit 1
  fi

  if git apply --ignore-whitespace --check "$patch_file" 2>/dev/null; then
    echo "[$desc] applying $patch_file..."
    git apply "$patch_file"
    echo "[$desc] applied OK"
    return 0
  fi

  if git apply --ignore-whitespace --reverse --check "$patch_file" 2>/dev/null; then
    echo "[$desc] already applied, skipping"
    return 0
  fi

  echo "ERROR: [$desc] failed to apply $patch_file (conflict or upstream drift)"
  git apply --ignore-whitespace --check "$patch_file"
  exit 1
}

# replace_safe <file> <old> <new> [desc]
# - if <old> is absent but <new> is already present, treat as already patched (no error)
# - if neither <old> nor <new> is present, fail (source changed upstream)
# - otherwise replace all occurrences of <old> with <new> and verify
replace_safe() {
  local desc="${1:-$2}" file="$2" old="$3" new="$4"
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

# replace_regex_safe <desc> <file> <old_regex> <new_replacement>
# - if <old_regex> matches nothing but <new_replacement> is already present, treat as already patched
# - if neither matches, fail (upstream source changed or regex is wrong)
# - otherwise replace all regex matches and verify no match remains
replace_regex_safe() {
  local desc="${1:-$3}" file="$2" old_re="$3" new_str="$4"
  local old_count new_count

  if [ ! -f "$file" ]; then
    echo "ERROR: file not found: $file"
    exit 1
  fi

  old_count=$(grep -cE -- "$old_re" "$file" || true)

  if [ "$old_count" -eq 0 ]; then
    # Regex did not match: check if replacement is already applied
    new_count=$(grep -cF -- "$new_str" "$file" || true)
    if [ "$new_count" -gt 0 ]; then
      echo "[$desc] already patched in $file, skipping"
      return 0
    fi
    echo "ERROR: '$desc' not found in $file and replacement not present either (upstream changed the source?)"
    exit 1
  fi

  # Print an unterminated message (will have the result appended)
  echo -n "[$desc] $old_count matching line(s) in $file, replacing..."
  sed -i -E "s|$old_re|$new_str|g" "$file"

  if grep -qE -- "$old_re" "$file"; then
    echo " ERROR"
    echo "ERROR: '$desc' still matches in $file after sed (check regex or delimiter '|')"
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
replace_safe \
  "Rendezvous server" \
  "libs/hbb_common/src/config.rs" \
  "rs-ny.rustdesk.com" \
  "$RENDEZVOUS_SERVER"
replace_safe \
  "API server" \
  "src/common.rs" \
  "https://admin.rustdesk.com" \
  "$API_SERVER"
replace_safe \
  "Public key" \
  "libs/hbb_common/src/config.rs" \
  "OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=" \
  "$RS_PUB_KEY"
replace_safe \
  "Application name" \
  "libs/hbb_common/src/config.rs" \
  "APP_NAME: RwLock<String> = RwLock::new(\"RustDesk\".to_owned())" \
  "APP_NAME: RwLock<String> = RwLock::new(\"$APP_NAME\".to_owned())"

if [[ "$CUSTOM_APP_URL" != "" ]]; then
  replace_safe \
    "App URL (1/2)" \
    "src/ui/index.tis" \
    "https://rustdesk.com" \
    "$CUSTOM_APP_URL"
  replace_safe \
    "App URL (2/2)" \
    "src/ui/index.tis" \
    "$CUSTOM_APP_URL/blog" \
    "https://rustdesk.com/blog"
fi;
if [[ "$CUSTOM_ALLOW_NUMERIC_ONE_TIME_PASSWORD" == "1" ]]; then
  apply_patch_idempotent \
    "Allow numeric numeric one-time password (set to enabled)" \
    "./custom/diffs/allow-numeric-one-time-password.diff"
fi;
if [[ "$CUSTOM_TEMPORARY_PASSWORD_LENGTH" != "" ]]; then
  replace_safe \
    "Password length (set to $CUSTOM_TEMPORARY_PASSWORD_LENGTH)" \
    "flutter/lib/models/server_model.dart" \
    "String _temporaryPasswordLength = \"\";" \
    "String _temporaryPasswordLength = \"$CUSTOM_TEMPORARY_PASSWORD_LENGTH\";"
fi;
if [[ "$CUSTOM_SET_ADAPTIVE_VIEW_STYLE" == "1" ]]; then
  apply_patch_idempotent \
    "Adaptive view style" \
    ./custom/diffs/set-adaptive-view-style.diff
fi;

# apply patches
apply_patch_idempotent \
  "Disable custom.txt file signature validation" \
  ./custom/diffs/disable-signature-check.diff

# completed
echo "Customizations applied successfully"
