#!/usr/bin/env bash
# Helper around the dev container.
#   docker/dev.sh build            build the image
#   docker/dev.sh shell            interactive shell in flutter/
#   docker/dev.sh apk [debug]      flutter pub get + release (or debug) APK
#   docker/dev.sh install          adb install the last APK
#   docker/dev.sh <cmd...>         run any command (flutter, cargo, adb, ...)
set -euo pipefail
cd "$(dirname "$0")"

export HOST_UID="$(id -u)" HOST_GID="$(id -g)"
export TSLIB_DIR="${TSLIB_DIR:-$(cd .. && cd ../ts6-lib 2>/dev/null && pwd || true)}"
[ -d "${TSLIB_DIR:-}" ] || { echo "ts6-lib not found; set TSLIB_DIR" >&2; exit 1; }

dc() { docker compose -f docker-compose.yml "$@"; }
run() { dc run --rm dev "$@"; }

case "${1:-shell}" in
  build)   dc build ;;
  shell)   run bash ;;
  apk)
    mode="${2:-release}"
    run bash -lc "flutter pub get && flutter build apk --${mode}" ;;
  install) run bash -lc 'adb install -r build/app/outputs/flutter-apk/app-*.apk' ;;
  *)       run "$@" ;;
esac
