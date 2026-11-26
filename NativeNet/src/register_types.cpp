#include "enet_client.hpp"

#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_honghuang_native_net(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
        ClassDB::register_class<honghuang::EnetClient>();
    }
}

void uninitialize_honghuang_native_net(ModuleInitializationLevel) {
}

extern "C" {
GDExtensionBool GDE_EXPORT honghuang_native_net_library_init(
    GDExtensionInterfaceGetProcAddress get_proc_address,
    GDExtensionClassLibraryPtr library,
    GDExtensionInitialization* initialization) {
    GDExtensionBinding::InitObject init_obj(get_proc_address, library, initialization);
    init_obj.register_initializer(initialize_honghuang_native_net);
    init_obj.register_terminator(uninitialize_honghuang_native_net);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_obj.init();
}
}
