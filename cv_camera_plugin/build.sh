#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

export ANDROID_HOME=~/Library/Android/sdk

echo "=== Building CV Camera Plugin ==="
./gradlew :plugin:assembleDebug :plugin:assembleRelease

echo "=== Copying AARs into Godot project ==="
cp plugin/build/outputs/aar/cv_camera-debug.aar \
  "$REPO_ROOT/../app/addons/cv_camera/bin/debug/cv_camera-debug.aar"
cp plugin/build/outputs/aar/cv_camera-release.aar \
  "$REPO_ROOT/../app/addons/cv_camera/bin/release/cv_camera-release.aar"

echo "=== Copying AARs into Android custom build libs ==="
cp plugin/build/outputs/aar/cv_camera-debug.aar \
  "$REPO_ROOT/../app/android/build/libs/debug/cv_camera-debug.aar"
cp plugin/build/outputs/aar/cv_camera-release.aar \
  "$REPO_ROOT/../app/android/build/libs/release/cv_camera-release.aar"

echo "=== Done ==="
