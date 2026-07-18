#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
ARCHIVE_PATH="${TMPDIR%/}/Pastr.xcarchive"

rm -rf "$ARCHIVE_PATH"
trap 'rm -rf "$ARCHIVE_PATH"' EXIT

echo "Building Pastr"
xcodebuild \
  -project "$PROJECT_DIR/Pastr.xcodeproj" \
  -scheme Pastr \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  archive

APP_PATH="$ARCHIVE_PATH/Products/Applications/Pastr.app"
DSYM_PATH="$ARCHIVE_PATH/dSYMs/Pastr.app.dSYM"
if [[ ! -d "$APP_PATH" || ! -d "$DSYM_PATH" ]]; then
  echo "Release archive is missing Pastr.app or its dSYM." >&2
  exit 1
fi

"$SCRIPT_DIR/upload-sentry-dsyms.sh" "$ARCHIVE_PATH/dSYMs"

echo "Build and symbol upload complete; installing Application"
rm -rf /Applications/Pastr.app
ditto "$APP_PATH" /Applications/Pastr.app
echo "Done 👍"
