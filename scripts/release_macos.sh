#!/bin/bash
# ── IMLiti macOS release script ───────────────────────────────────────────────
# Usage:  ./scripts/release_macos.sh <version>
# Example: ./scripts/release_macos.sh 1.0.1
#
# Prerequisites:
#   - aws CLI configured (eu-west-3)
#   - Flutter installed
#   - Xcode installed
#
# What it does:
#   1. Bumps version in pubspec.yaml
#   2. Builds the macOS .app
#   3. Zips the .app bundle
#   4. Uploads to S3 at app/macos/imliti-<version>.zip
#   5. Updates app/latest.json  (only updates the macos field)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version>  (e.g. 1.0.1)"
  exit 1
fi

BUCKET="imliti-scrapes-$(aws sts get-caller-identity --query Account --output text)"
S3_KEY="app/macos/imliti-${VERSION}.zip"
S3_URL="https://${BUCKET}.s3.eu-west-3.amazonaws.com/${S3_KEY}"
FRONTEND_DIR="$(cd "$(dirname "$0")/../frontend" && pwd)"
BUILD_DIR="${FRONTEND_DIR}/build/macos/Build/Products/Release"
APP_NAME="imliti"   # matches the product name in Xcode
ZIP_PATH="/tmp/imliti-${VERSION}-macos.zip"

echo "── Bumping version to ${VERSION} ────────────────────────────────────────"
# Replace 'version: X.Y.Z+N' keeping same build number, or reset to +1
sed -i '' -E "s/^version: [0-9]+\.[0-9]+\.[0-9]+\+[0-9]+/version: ${VERSION}+1/" \
  "${FRONTEND_DIR}/pubspec.yaml"

echo "── Building macOS release ────────────────────────────────────────────────"
cd "$FRONTEND_DIR"
flutter build macos --release

echo "── Packaging .app bundle ─────────────────────────────────────────────────"
# Find the actual .app (could be "IMLiti.app" or similar)
APP_BUNDLE=$(find "$BUILD_DIR" -maxdepth 1 -name "*.app" | head -1)
if [[ -z "$APP_BUNDLE" ]]; then
  echo "ERROR: no .app found in $BUILD_DIR"
  exit 1
fi
APP_BUNDLE_NAME=$(basename "$APP_BUNDLE")
echo "Packaging: $APP_BUNDLE_NAME"

cd "$BUILD_DIR"
zip -r --symlinks "$ZIP_PATH" "$APP_BUNDLE_NAME"
echo "Zip size: $(du -sh "$ZIP_PATH" | cut -f1)"

echo "── Uploading to S3 ───────────────────────────────────────────────────────"
aws s3 cp "$ZIP_PATH" "s3://${BUCKET}/${S3_KEY}" \
  --region eu-west-3 \
  --content-type "application/zip"

echo "── Updating latest.json ──────────────────────────────────────────────────"
# Fetch existing manifest (or create fresh)
MANIFEST_KEY="app/latest.json"
EXISTING=$(aws s3 cp "s3://${BUCKET}/${MANIFEST_KEY}" - --region eu-west-3 2>/dev/null || echo '{}')

# Merge: update version + macos url, keep other fields
NOTES=$(echo "$EXISTING" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('notes',''))" 2>/dev/null || echo "")
WIN_URL=$(echo "$EXISTING" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('windows',''))" 2>/dev/null || echo "")

NEW_MANIFEST=$(python3 - <<PYEOF
import json
manifest = {
    "version": "${VERSION}",
    "notes": "${NOTES}",
    "macos": "${S3_URL}",
    "windows": "${WIN_URL}",
}
print(json.dumps(manifest, indent=2))
PYEOF
)

echo "$NEW_MANIFEST" | aws s3 cp - "s3://${BUCKET}/${MANIFEST_KEY}" \
  --region eu-west-3 \
  --content-type "application/json"

rm -f "$ZIP_PATH"

echo ""
echo "✓  Released macOS ${VERSION}"
echo "   Manifest: https://${BUCKET}.s3.eu-west-3.amazonaws.com/${MANIFEST_KEY}"
echo "   Download: ${S3_URL}"
