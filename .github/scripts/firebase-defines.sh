#!/usr/bin/env bash
# Writes the Firebase dart-define file from the FIREBASE_DEFINES_JSON secret
# (see docs/FIREBASE_SETUP.md) and prints the flutter flag that uses it.
# Prints nothing when the secret is not set: the app is then built without
# remote monitoring ("Remote monitoring is not configured in this build").
set -euo pipefail
if [ -n "${FIREBASE_DEFINES_JSON:-}" ]; then
  printf '%s' "$FIREBASE_DEFINES_JSON" > firebase.json
  echo "Firebase config: from FIREBASE_DEFINES_JSON" >&2
  echo "--dart-define-from-file=firebase.json"
else
  echo "Firebase config: none (FIREBASE_DEFINES_JSON not set); remote monitoring off" >&2
fi
