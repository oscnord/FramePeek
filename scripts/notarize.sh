#!/usr/bin/env bash
set -euo pipefail

# Submit an artifact (.dmg, .zip, or .app inside a zip) to Apple's notary service,
# wait for the result, optionally staple, and verify with spctl.
#
# Required env vars:
#   ASC_API_KEY_PATH    Path to the App Store Connect .p8 key file
#   ASC_API_KEY_ID      Key ID
#   ASC_API_KEY_ISSUER  Issuer ID
#
# Usage: scripts/notarize.sh <path-to-artifact> [--staple]

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <artifact> [--staple]" >&2
  exit 64
fi

ARTIFACT="$1"
STAPLE="${2:-}"

: "${ASC_API_KEY_PATH:?ASC_API_KEY_PATH not set}"
: "${ASC_API_KEY_ID:?ASC_API_KEY_ID not set}"
: "${ASC_API_KEY_ISSUER:?ASC_API_KEY_ISSUER not set}"

echo "==> Submitting $ARTIFACT to notarytool"
xcrun notarytool submit "$ARTIFACT" \
  --key "$ASC_API_KEY_PATH" \
  --key-id "$ASC_API_KEY_ID" \
  --issuer "$ASC_API_KEY_ISSUER" \
  --wait

if [[ "$STAPLE" == "--staple" ]]; then
  echo "==> Stapling $ARTIFACT"
  xcrun stapler staple "$ARTIFACT"
  xcrun stapler validate "$ARTIFACT"

  case "$ARTIFACT" in
    *.dmg) spctl -a -vvv -t install "$ARTIFACT" ;;
    *.app) spctl -a -vvv -t exec "$ARTIFACT" ;;
  esac
fi

echo "==> Done"
