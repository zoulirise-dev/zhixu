#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$ROOT/apps/macos/scripts/test-dialog-close.sh" "$@"
