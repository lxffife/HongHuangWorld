cmake_minimum_required(VERSION 3.24)
project(HongHuangNativeNet LANGUAGES C CXX)

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

FetchContent_Declare(
    enet
    GIT_REPOSITORY https://github.com/lsalzman/enet.git
    GIT_TAG v1.3.18
    GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(enet)

add_library(honghuang_native_net SHARED
    src/register_types.cpp
    src/enet_client.cpp
)
target_include_directories(honghuang_native_net PRIVATE include "${enet_SOURCE_DIR}/include")
target_link_libraries(honghuang_native_net PRIVATE godot-cpp enet)
if(WIN32)
    target_link_libraries(honghuang_native_net PRIVATE ws2_32 winmm)
endif()

if(MSVC)
    target_compile_options(honghuang_native_net PRIVATE /W4 /permissive-)
else()
    target_compile_options(honghuang_native_net PRIVATE -Wall -Wextra -Wpedantic)
endif()

set(_client_bin "${CMAKE_CURRENT_SOURCE_DIR}/../HongHuangClient/bin")
set_target_properties(honghuang_native_net PROPERTIES
    PREFIX ""
    OUTPUT_NAME "honghuang_native_net"
    LIBRARY_OUTPUT_DIRECTORY "${_client_bin}"
    RUNTIME_OUTPUT_DIRECTORY "${_client_bin}"
    LIBRARY_OUTPUT_DIRECTORY_DEBUG "${_client_bin}"
    LIBRARY_OUTPUT_DIRECTORY_RELEASE "${_client_bin}"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG "${_client_bin}"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${_client_bin}"
)
