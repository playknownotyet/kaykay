#include "apple_muzik.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

static void initialize_apple_muzik(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(AppleMuzik);
}

static void uninitialize_apple_muzik(ModuleInitializationLevel p_level) {
}

extern "C" {
// Godot bu adı .gdextension dosyasındaki entry_symbol ile bulur
GDExtensionBool GDE_EXPORT apple_muzik_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_apple_muzik);
	init_obj.register_terminator(uninitialize_apple_muzik);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
