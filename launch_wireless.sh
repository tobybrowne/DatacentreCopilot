#!/bin/bash
GODOT=~/Downloads/Godot_mono.app/Contents/MacOS/Godot
ADB=~/Library/Android/sdk/platform-tools/adb
DEVICE_IP="${1:-}"

if [ -z "$DEVICE_IP" ]; then
  echo "Usage: ./launch_wireless.sh <device-ip>"
  echo "  e.g. ./launch_wireless.sh 192.168.1.42"
  echo ""
  echo "To get the device IP (requires USB):"
  echo "  adb shell ip route"
  exit 1
fi

echo "Connecting to $DEVICE_IP:5555..."
$ADB connect "$DEVICE_IP:5555"
if [ $? -ne 0 ]; then echo "Connection failed"; exit 1; fi

echo "Building APK..."
$GODOT --headless --path "$(dirname "$0")/app" --export-debug "MagicLeap2" /tmp/entangl-copilot.apk
if [ $? -ne 0 ]; then echo "Build failed"; exit 1; fi

echo "Installing APK..."
$ADB -s "$DEVICE_IP:5555" install -r /tmp/entangl-copilot.apk
if [ $? -ne 0 ]; then echo "Install failed"; exit 1; fi

$ADB -s "$DEVICE_IP:5555" shell am force-stop com.example.entanglcopilot
sleep 1
$ADB -s "$DEVICE_IP:5555" shell am start -a android.intent.action.MAIN \
  -n com.example.entanglcopilot/com.godot.game.GodotApp \
  -c org.khronos.openxr.intent.category.IMMERSIVE_HMD
$ADB -s "$DEVICE_IP:5555" logcat -s godot
