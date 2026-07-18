#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 || ! -d "$1" ]]; then
  echo "Usage: $0 /path/to/archive/dSYMs" >&2
  exit 64
fi

if [[ "${SKIP_SENTRY_DSYM_UPLOAD:-0}" == "1" ]]; then
  echo "Warning: Sentry dSYM upload was explicitly skipped." >&2
  exit 0
fi

if command -v sentry-cli >/dev/null 2>&1; then
  SENTRY_CLI=(sentry-cli)
elif command -v npx >/dev/null 2>&1; then
  SENTRY_CLI=(npx --yes @sentry/cli@3.6.0)
else
  echo "sentry-cli or npx is required so Pastr release events are symbolicated." >&2
  exit 1
fi

if [[ -z "${SENTRY_AUTH_TOKEN:-}" && ! -f "$HOME/.sentryclirc" ]]; then
  echo "Set SENTRY_AUTH_TOKEN or authenticate sentry-cli before releasing." >&2
  exit 1
fi

"${SENTRY_CLI[@]}" debug-files upload \
  --org modestnerds-co \
  --project pastr \
  --include-sources \
  "$1"
