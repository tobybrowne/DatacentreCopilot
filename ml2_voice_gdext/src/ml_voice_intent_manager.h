#pragma once

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include "ml_voice_loader.h"

namespace godot {

class MLVoiceIntentManager : public Node {
	GDCLASS(MLVoiceIntentManager, Node)

private:
	static MLVoiceIntentManager *singleton;

	MLVoiceAPI api;
	MLHandle voice_handle = ML_INVALID_HANDLE;
	MLVoiceIntentCallbacks callbacks = {};
	bool processing = false;

	// Intent configuration
	PackedStringArray intent_commands;

	// Build the JSON config string expected by MLVoiceIntentConfigureSettings.
	String build_intent_json() const;

	// Static callback forwarded from the MLSDK.
	static void on_voice_event_static(const MLVoiceIntentEvent *event, void *data);
	void on_voice_event(const MLVoiceIntentEvent *event);

protected:
	static void _bind_methods();

public:
	static MLVoiceIntentManager *get_singleton();

	MLVoiceIntentManager();
	~MLVoiceIntentManager();

	void _ready() override;
	void _exit_tree() override;

	// GDScript API
	bool is_available() const;
	void set_intents(const PackedStringArray &p_intents);
	PackedStringArray get_intents() const;
	bool configure_and_start();
	void stop();
};

} // namespace godot
