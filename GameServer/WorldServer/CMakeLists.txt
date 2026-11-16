cmake_minimum_required(VERSION 3.24)
project(HongHuangWorldServer VERSION 0.2.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(PkgConfig REQUIRED)
pkg_check_modules(ENET REQUIRED IMPORTED_TARGET libenet)

add_executable(world_server
    src/main.cpp
    src/enet_server.cpp
    src/frame.cpp
)

target_include_directories(world_server PRIVATE include)
target_link_libraries(world_server PRIVATE PkgConfig::ENET)

if(MSVC)
    target_compile_options(world_server PRIVATE /W4 /permissive-)
else()
    target_compile_options(world_server PRIVATE -Wall -Wextra -Wpedantic -Wconversion)
endif()
