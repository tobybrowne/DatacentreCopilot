#include "ml_voice_intent_manager.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

MLVoiceIntentManager *MLVoiceIntentManager::singleton = nullptr;

MLVoiceIntentManager *MLVoiceIntentManager::get_singleton() {
	return singleton;
}

MLVoiceIntentManager::MLVoiceIntentManager() {
	if (singleton == nullptr) {
		singleton = this;
	}
}

MLVoiceIntentManager::~MLVoiceIntentManager() {
	stop();
	api.unload();
	if (singleton == this) {
		singleton = nullptr;
	}
}

void MLVoiceIntentManager::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_available"), &MLVoiceIntentManager::is_available);
	ClassDB::bind_method(D_METHOD("set_intents", "intents"), &MLVoiceIntentManager::set_intents);
	ClassDB::bind_method(D_METHOD("get_intents"), &MLVoiceIntentManager::get_intents);
	ClassDB::bind_method(D_METHOD("configure_and_start"), &MLVoiceIntentManager::configure_and_start);
	ClassDB::bind_method(D_METHOD("stop"), &MLVoiceIntentManager::stop);

	ADD_PROPERTY(PropertyInfo(Variant::PACKED_STRING_ARRAY, "intents"), "set_intents", "get_intents");

	ADD_SIGNAL(MethodInfo("voice_intent",
			PropertyInfo(Variant::STRING, "intent_name"),
			PropertyInfo(Variant::INT, "intent_id")));

	ADD_SIGNAL(MethodInfo("voice_state_changed",
			PropertyInfo(Variant::INT, "state")));

	ADD_SIGNAL(MethodInfo("voice_error",
			PropertyInfo(Variant::STRING, "error")));
}

// ---- Lifecycle ----

void MLVoiceIntentManager::_ready() {
	if (!api.load()) {
		UtilityFunctions::push_warning("MLVoiceIntentManager: libinput.magicleap.so not available (not on ML2?)");
		return;
	}
	UtilityFunctions::print("MLVoiceIntentManager: MLSDK voice API loaded");
}

void MLVoiceIntentManager::_exit_tree() {
	stop();
}

// ---- Public API ----

bool MLVoiceIntentManager::is_available() const {
	return api.is_loaded();
}

void MLVoiceIntentManager::set_intents(const PackedStringArray &p_intents) {
	intent_commands = p_intents;
}

PackedStringArray MLVoiceIntentManager::get_intents() const {
	return intent_commands;
}

bool MLVoiceIntentManager::configure_and_start() {
	if (!api.is_loaded()) {
		emit_signal("voice_error", String("MLSDK voice API not loaded"));
		return false;
	}

	// Create client if needed.
	if (voice_handle == ML_INVALID_HANDLE) {
		MLResult res = api.create(&voice_handle);
		if (res != MLResult_Ok) {
			UtilityFunctions::push_error("MLVoiceIntentManager: MLVoiceIntentCreate failed: ", res);
			emit_signal("voice_error", String("MLVoiceIntentCreate failed"));
			voice_handle = ML_INVALID_HANDLE;
			return false;
		}
	}

	// Check if voice is enabled in system settings.
	bool enabled = false;
	api.is_enabled(voice_handle, &enabled);
	if (!enabled) {
		UtilityFunctions::push_error("MLVoiceIntentManager: Voice input disabled in system settings");
		emit_signal("voice_error", String("Voice input disabled in system settings"));
		return false;
	}

	// Configure intents.
	String json = build_intent_json();
	CharString utf8 = json.utf8();

	MLVoiceIntentSettings settings = {};
	settings.version = 1;
	settings.app_intent = utf8.get_data();

	MLResult res = api.configure_settings(voice_handle, &settings);
	if (res != MLResult_Ok) {
		UtilityFunctions::push_error("MLVoiceIntentManager: ConfigureSettings failed: ", res);
		emit_signal("voice_error", String("ConfigureSettings failed"));
		return false;
	}

	// Set callbacks.
	callbacks.version = 2;
	callbacks.on_voice_event = &MLVoiceIntentManager::on_voice_event_static;

	res = api.set_callbacks(voice_handle, &callbacks, this);
	if (res != MLResult_Ok) {
		UtilityFunctions::push_error("MLVoiceIntentManager: SetCallbacks failed: ", res);
		emit_signal("voice_error", String("SetCallbacks failed"));
		return false;
	}

	// Start processing.
	res = api.start_processing(voice_handle);
	if (res != MLResult_Ok) {
		UtilityFunctions::push_error("MLVoiceIntentManager: StartProcessing failed: ", res);
		emit_signal("voice_error", String("StartProcessing failed"));
		return false;
	}

	processing = true;
	UtilityFunctions::print("MLVoiceIntentManager: Voice processing started with ", intent_commands.size(), " intents");
	return true;
}

void MLVoiceIntentManager::stop() {
	if (processing && api.is_loaded() && voice_handle != ML_INVALID_HANDLE) {
		api.stop_processing(voice_handle);
		processing = false;
		UtilityFunctions::print("MLVoiceIntentManager: Voice processing stopped");
	}

	if (voice_handle != ML_INVALID_HANDLE && api.is_loaded()) {
		api.destroy(voice_handle);
		voice_handle = ML_INVALID_HANDLE;
	}
}

// ---- JSON builder ----

String MLVoiceIntentManager::build_intent_json() const {
	String json = "{\"language\":\"en-us\",\"version\":1,\"app_slots\":[],\"app_variables\":[],\"app_intents\":[";
	for (int i = 0; i < intent_commands.size(); i++) {
		if (i > 0) {
			json += ",";
		}
		String cmd = intent_commands[i];
		// Escape quotes in command string.
		cmd = cmd.replace("\"", "\\\"");
		json += "{\"name\":\"APP_INTENT_" + String::num_int64(i) + "\",\"id\":" + String::num_int64(i) + ",\"value\":\"" + cmd + "\"}";
	}
	json += "]}";
	return json;
}

// ---- Callback ----

void MLVoiceIntentManager::on_voice_event_static(const MLVoiceIntentEvent *event, void *data) {
	MLVoiceIntentManager *self = static_cast<MLVoiceIntentManager *>(data);
	if (self) {
		self->on_voice_event(event);
	}
}

void MLVoiceIntentManager::on_voice_event(const MLVoiceIntentEvent *event) {
	if (!event) {
		return;
	}

	// Callback fires on MLSDK thread — must defer all signal emissions to the main thread.
	call_deferred("emit_signal", "voice_state_changed", (int)event->state);

	if (!event->is_success) {
		if (event->no_intent_reason == MLVoiceIntentNoIntentReason_NoMatch) {
			call_deferred("emit_signal", "voice_error", String("no_match"));
		} else if (event->no_intent_reason == MLVoiceIntentNoIntentReason_Silence) {
			call_deferred("emit_signal", "voice_error", String("silence"));
		}
		return;
	}

	// Successful intent recognition.
	if (event->state == MLVoiceState_IntentHotwordDetected ||
			event->text != nullptr) {
		String intent_name = event->text ? String::utf8(event->text) : String();
		uint32_t intent_id = event->intent_id;

		UtilityFunctions::print("MLVoiceIntentManager: Intent recognized: '", intent_name, "' (id=", intent_id, ")");
		call_deferred("emit_signal", "voice_intent", intent_name, (int64_t)intent_id);
	}
}
