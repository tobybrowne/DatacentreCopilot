#pragma once

// Dynamic loader for ML2 Voice Intent C API (libinput.magicleap.so).
// Uses dlopen/dlsym so we don't need to link at build time and degrade
// gracefully when running off-device (editor, non-ML2 Android, etc.).

#include <cstdint>
#include <cstdbool>
#include <dlfcn.h>

// ---- Minimal type re-declarations from ml_api.h / ml_voice.h ----
// We duplicate just enough so the GDExtension compiles without the MLSDK.

using MLHandle = uint64_t;
using MLResult = int32_t;

constexpr MLHandle ML_INVALID_HANDLE = 0xFFFFFFFFFFFFFFFF;
constexpr MLResult MLResult_Ok = 0;

enum MLVoiceState {
	MLVoiceState_IntentHotwordDetected = 0,
	MLVoiceState_IntentSessionEnded = 1,
	MLVoiceState_IntentSessionEndedAborted = 2,
	MLVoiceState_IntentSessionEndedNoIntent = 3,
	MLVoiceState_IntentSessionEndedTimeout = 4,
	MLVoiceState_IntentSessionEndedError = 5,
	MLVoiceState_IntentReady = 6,
	MLVoiceState_IntentNotAvailable = 7,
	MLVoiceState_IntentInvalidAppIntent = 8,
};

enum MLVoiceIntentNoIntentReason {
	MLVoiceIntentNoIntentReason_NoReason = 0,
	MLVoiceIntentNoIntentReason_Silence = 1,
	MLVoiceIntentNoIntentReason_NoMatch = 2,
};

struct MLInputVoiceAppIntentSlot {
	const char *slot_name;
	const char *slot_value;
};

struct MLVoiceIntentEvent {
	bool is_success;
	MLVoiceState state;
	MLVoiceIntentNoIntentReason no_intent_reason;
	const char *text;
	uint32_t intent_id;
	MLInputVoiceAppIntentSlot *app_intent_slots;
	uint32_t app_intent_slot_count;
};

struct MLVoiceIntentCallbacks {
	uint32_t version;
	void (*on_voice_event)(const MLVoiceIntentEvent *event, void *data);
};

struct MLVoiceIntentSettings {
	uint32_t version;
	const char *app_intent;
};

// ---- Function pointer types ----

using pfn_MLVoiceIntentCreate = MLResult (*)(MLHandle *);
using pfn_MLVoiceIntentDestroy = MLResult (*)(MLHandle);
using pfn_MLVoiceIntentConfigureSettings = MLResult (*)(MLHandle, const MLVoiceIntentSettings *);
using pfn_MLVoiceIntentSetCallbacks = MLResult (*)(MLHandle, const MLVoiceIntentCallbacks *, void *);
using pfn_MLVoiceIntentStartProcessing = MLResult (*)(MLHandle);
using pfn_MLVoiceIntentStopProcessing = MLResult (*)(MLHandle);
using pfn_MLVoiceIntentIsEnabled = MLResult (*)(MLHandle, bool *);

// ---- Loader ----

struct MLVoiceAPI {
	void *lib_handle = nullptr;

	pfn_MLVoiceIntentCreate create = nullptr;
	pfn_MLVoiceIntentDestroy destroy = nullptr;
	pfn_MLVoiceIntentConfigureSettings configure_settings = nullptr;
	pfn_MLVoiceIntentSetCallbacks set_callbacks = nullptr;
	pfn_MLVoiceIntentStartProcessing start_processing = nullptr;
	pfn_MLVoiceIntentStopProcessing stop_processing = nullptr;
	pfn_MLVoiceIntentIsEnabled is_enabled = nullptr;

	bool load() {
		lib_handle = dlopen("libinput.magicleap.so", RTLD_LAZY);
		if (!lib_handle) {
			return false;
		}

		create = (pfn_MLVoiceIntentCreate)dlsym(lib_handle, "MLVoiceIntentCreate");
		destroy = (pfn_MLVoiceIntentDestroy)dlsym(lib_handle, "MLVoiceIntentDestroy");
		configure_settings = (pfn_MLVoiceIntentConfigureSettings)dlsym(lib_handle, "MLVoiceIntentConfigureSettings");
		set_callbacks = (pfn_MLVoiceIntentSetCallbacks)dlsym(lib_handle, "MLVoiceIntentSetCallbacks");
		start_processing = (pfn_MLVoiceIntentStartProcessing)dlsym(lib_handle, "MLVoiceIntentStartProcessing");
		stop_processing = (pfn_MLVoiceIntentStopProcessing)dlsym(lib_handle, "MLVoiceIntentStopProcessing");
		is_enabled = (pfn_MLVoiceIntentIsEnabled)dlsym(lib_handle, "MLVoiceIntentIsEnabled");

		return create && destroy && configure_settings && set_callbacks &&
			   start_processing && stop_processing && is_enabled;
	}

	void unload() {
		if (lib_handle) {
			dlclose(lib_handle);
			lib_handle = nullptr;
		}
	}

	bool is_loaded() const { return lib_handle != nullptr; }
};
