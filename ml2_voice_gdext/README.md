# ML2 Voice Extension for Godot

An extension for Godot that allows for use of the ML2's in-built voice intent system.

## MLSDK

The Magic Leap Software Development Kit (MLSDK) is mainly written in C/C++ it includes compiled libraries (.so) and header files (.h) to interact with it.

By importing the header files, you can call the functions in the SDK, the compiled portion of the SDK is loaded at runtime.

## godot-cpp

This is the official C++ binding layer for Godot. It allows you to write Godot game logic in native C++ instead of GDScript or C#.

## Building this Extension

This library must be built against the `godot-cpp` bindings, so it uses `Scons` the build system used for Godot (more recently they've added support for other build systems like CMake, but this is the most "native" option).
It requires the `godot-cpp` bindings so it can wrap its logic inside a node called `MLVoiceIntentManager` that is instantiated by the `VoiceManager` class.
The extension gets built as a `.so` file which is then copied to `app/addons/ml2_voice/bin/`.
