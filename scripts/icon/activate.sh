#!/usr/bin/env bash
# Install one icon variant.
#
#   ./activate.sh a-two-shapes     active
#   ./activate.sh b-halved         whole ellipse + the same ellipse halved
#   ./activate.sh c-split-disc     one disc, golden-ratio cut
#
# Writes two things from the same source: the Icon Composer bundle, and the
# landing page favicon. There is deliberately no asset catalog -- Xcode derives
# every legacy size from AppIcon.icon, and measured, its 16px is better than a
# hand-made PNG was (counter at luma 205 against 145; 240 is background).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
ICON="$REPO/FramePeek/FramePeek/AppIcon.icon"

V="${1:-}"
[[ -z "$V" ]] && { echo "usage: $0 <variant>"; ls -1 "$HERE/variants"; exit 2; }
SRC="$HERE/variants/$V"
[[ -d "$SRC" ]] || { echo "no such variant: $V"; ls -1 "$HERE/variants"; exit 1; }

rm -rf "$ICON/Assets"; mkdir -p "$ICON/Assets"
cp "$SRC/icon.json" "$ICON/icon.json"
cp "$SRC"/Assets/*.svg "$ICON/Assets/"
echo "activated: $V"
echo "  $ICON"

# The site favicon and nav wordmark are the same mark. Generating them from the
# same layers is what stops docs/ drifting away from the app, which it already
# did once: the live site served a placeholder from an earlier design.
if [[ -f "$REPO/docs/index.html" ]]; then
  # Swift renderer: the square web icon is trivial, but keeping one rasteriser
  # avoids a second dependency, and it already handles the SVG correctly.
  [[ -x "$HERE/render" ]] || swiftc -O "$HERE/render.swift" -o "$HERE/render"
  python3 "$HERE/webicon.py" "$SRC" "$HERE/_web.svg"
  # Square, not the macOS body shape: the page rounds it in CSS, and at 24px the
  # Apple margin would only waste pixels.
  "$HERE/render" png "$HERE/_web.svg" "$REPO/docs/img/icon.png" 256 square >/dev/null
  rm -f "$HERE/_web.svg"
  echo "  $REPO/docs/img/icon.png"
fi
