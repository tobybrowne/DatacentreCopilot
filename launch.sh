#!/bin/bash
GODOT=~/Downloads/Godot_mono.app/Contents/MacOS/Godot
ADB=~/Library/Android/sdk/platform-tools/adb

echo "Building APK..."
$GODOT --headless --path "$(dirname "$0")/app" --export-debug "MagicLeap2" /tmp/entangl-copilot.apk
if [ $? -ne 0 ]; then echo "Build failed"; exit 1; fi

echo "Installing APK..."
$ADB install -r /tmp/entangl-copilot.apk
if [ $? -ne 0 ]; then echo "Install failed"; exit 1; fi

$ADB shell am force-stop com.example.entanglcopilot
sleep 1
$ADB shell am start -a android.intent.action.MAIN \
  -n com.example.entanglcopilot/com.godot.game.GodotApp \
  -c org.khronos.openxr.intent.category.IMMERSIVE_HMD
$ADB logcat -s godot
