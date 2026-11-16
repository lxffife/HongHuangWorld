cmake_minimum_required(VERSION 3.24)
project(HongHuangNativeNet LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

include(FetchContent)
FetchContent_Declare(
    godot_cpp
    GIT_REPOSITORY https://github.com/godotengine/godot-cpp.git
    GIT_TAG godot-4.3-stable
    GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(godot_cpp)

find_package(PkgConfig REQUIRED)
pkg_check_modules(ENET REQUIRED IMPORTED_TARGET libenet)

add_library(honghuang_native_net SHARED
    src/register_types.cpp
    src/enet_client.cpp
)
target_include_directories(honghuang_native_net PRIVATE include)
target_link_libraries(honghuang_native_net PRIVATE godot-cpp PkgConfig::ENET)

if(MSVC)
    target_compile_options(honghuang_native_net PRIVATE /W4 /permissive-)
else()
    target_compile_options(honghuang_native_net PRIVATE -Wall -Wextra -Wpedantic)
endif()

set_target_properties(honghuang_native_net PROPERTIES
    PREFIX ""
    OUTPUT_NAME "honghuang_native_net"
)
