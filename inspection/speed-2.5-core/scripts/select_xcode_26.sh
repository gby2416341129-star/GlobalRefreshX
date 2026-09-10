#!/usr/bin/env bash
set -euo pipefail

minimum_major=26

sdk_major_for() {
  local developer_dir="$1"
  local version
  if ! version="$(DEVELOPER_DIR="$developer_dir" xcrun --sdk iphoneos --show-sdk-version 2>/dev/null)"; then
    return 1
  fi
  python3 - "$version" <<'PY'
import sys
try:
    print(int(sys.argv[1].split('.', 1)[0]))
except Exception:
    raise SystemExit(1)
PY
}

current_dir="$(xcode-select -p 2>/dev/null || true)"
if [[ -n "$current_dir" ]]; then
  current_major="$(sdk_major_for "$current_dir" || true)"
  if [[ -n "$current_major" && "$current_major" -ge "$minimum_major" ]]; then
    selected="$current_dir"
  fi
fi

if [[ -z "${selected:-}" ]]; then
  best_dir=""
  best_version=""
  shopt -s nullglob
  for app in /Applications/Xcode*.app; do
    developer_dir="$app/Contents/Developer"
    [[ -d "$developer_dir" ]] || continue
    version="$(DEVELOPER_DIR="$developer_dir" xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || true)"
    [[ -n "$version" ]] || continue
    major="${version%%.*}"
    [[ "$major" =~ ^[0-9]+$ ]] || continue
    (( major >= minimum_major )) || continue
    if [[ -z "$best_version" ]] || [[ "$(printf '%s\n%s\n' "$best_version" "$version" | sort -V | tail -n1)" == "$version" ]]; then
      best_version="$version"
      best_dir="$developer_dir"
    fi
  done
  shopt -u nullglob
  [[ -n "$best_dir" ]] || { echo "No installed Xcode with iPhoneOS SDK ${minimum_major}+ found." >&2; exit 2; }
  selected="$best_dir"
fi

sdk_version="$(DEVELOPER_DIR="$selected" xcrun --sdk iphoneos --show-sdk-version)"

echo "Selected DEVELOPER_DIR=$selected"
echo "Selected iPhoneOS SDK=$sdk_version"
DEVELOPER_DIR="$selected" xcodebuild -version

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "DEVELOPER_DIR=$selected" >> "$GITHUB_ENV"
fi
