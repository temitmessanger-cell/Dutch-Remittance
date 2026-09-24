#!/usr/bin/env bash
# Dutch Remit — Build & Deploy Script
# ------------------------------------
# Builds Flutter web and copies output to Backend/public/
# so the Express server can serve it as a PWA.
#
# Usage:
#   chmod +x build_web.sh
#   ./build_web.sh
#
# For Railway CI/CD, add this as the build command:
#   bash build_web.sh
#
# Requirements:
#   • Flutter SDK in PATH (flutter --version to verify)
#   • Run from the project root (New folder/)

set -euo pipefail

echo "═══════════════════════════════════════"
echo "  Dutch Remit — Flutter Web PWA Build"
echo "═══════════════════════════════════════"

# ── 1. Dependencies ──────────────────────────────────────────────────────────
echo "▶  flutter pub get"
flutter pub get

# ── 2. Build Flutter web (release, CanvasKit renderer for best quality) ──────
echo "▶  flutter build web --release"
flutter build web \
  --release \
  --web-renderer canvaskit \
  --pwa-strategy offline-first \
  --dart-define=FLUTTER_WEB_USE_SKIA=true

# ── 3. Copy output to Backend/public ─────────────────────────────────────────
OUTPUT_DIR="build/web"
TARGET_DIR="Backend/public"

echo "▶  Copying $OUTPUT_DIR → $TARGET_DIR"
rm -rf "$TARGET_DIR"
cp -r "$OUTPUT_DIR" "$TARGET_DIR"

# ── 4. Copy custom sw.js (overrides Flutter's generated one) ─────────────────
echo "▶  Copying custom sw.js"
cp web/sw.js "$TARGET_DIR/sw.js"

# ── 5. Verify key files exist ────────────────────────────────────────────────
echo "▶  Verifying output"
REQUIRED=(
  "$TARGET_DIR/index.html"
  "$TARGET_DIR/manifest.json"
  "$TARGET_DIR/sw.js"
  "$TARGET_DIR/main.dart.js"
  "$TARGET_DIR/flutter_bootstrap.js"
)

MISSING=0
for f in "${REQUIRED[@]}"; do
  if [ -f "$f" ]; then
    echo "   ✅ $f"
  else
    echo "   ❌ MISSING: $f"
    MISSING=$((MISSING + 1))
  fi
done

if [ $MISSING -gt 0 ]; then
  echo ""
  echo "⚠️  $MISSING required files are missing. Check the build output above."
  exit 1
fi

# ── 6. Print summary ─────────────────────────────────────────────────────────
TOTAL_SIZE=$(du -sh "$TARGET_DIR" | cut -f1)
echo ""
echo "═══════════════════════════════════════"
echo "  Build complete ✓"
echo "  Output: $TARGET_DIR  ($TOTAL_SIZE)"
echo ""
echo "  Next steps:"
echo "    • cd Backend && npm start"
echo "    • Visit http://localhost:4000"
echo "    • Chrome → Install Dutch Remit → offline test"
echo "═══════════════════════════════════════"
