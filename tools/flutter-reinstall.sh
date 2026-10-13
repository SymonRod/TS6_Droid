#!/bin/sh
# Installs the Flutter debug APK without leaving a ghost client on the server:
# asks the running app to disconnect first (a plain `install -r` kills it abruptly).
set -e
ADB="adb ${ANDROID_SERIAL:+-s $ANDROID_SERIAL}"
PKG=com.flammedemon.ts6_flutter
APK="$(dirname "$0")/../flutter/build/app/outputs/flutter-apk/app-debug.apk"
if [ -n "$($ADB shell pidof $PKG)" ]; then
  $ADB shell am start -n $PKG/.MainActivity --ez ts6_disconnect true >/dev/null
  sleep 2
fi
$ADB install -r "$APK"
