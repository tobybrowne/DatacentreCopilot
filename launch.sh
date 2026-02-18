#!/bin/bash
ADB=~/Library/Android/sdk/platform-tools/adb
$ADB shell am force-stop com.example.entanglcopilot
sleep 1
$ADB shell am start -a android.intent.action.MAIN \
  -n com.example.entanglcopilot/com.godot.game.GodotApp \
  -c org.khronos.openxr.intent.category.IMMERSIVE_HMD
