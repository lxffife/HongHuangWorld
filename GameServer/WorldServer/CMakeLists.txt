cmake_minimum_required(VERSION 3.24)
project(HongHuangWorldServer VERSION 0.3.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(PkgConfig REQUIRED)
pkg_check_modules(ENET REQUIRED IMPORTED_TARGET libenet)
pkg_check_modules(CURL REQUIRED IMPORTED_TARGET libcurl)
find_package(nlohmann_json 3.10 REQUIRED)

add_executable(world_server
    src/main.cpp
    src/enet_server.cpp
    src/frame.cpp
)

target_include_directories(world_server PRIVATE include)
target_link_libraries(world_server PRIVATE
    PkgConfig::ENET
    PkgConfig::CURL
    nlohmann_json::nlohmann_json
)

include(CTest)
if(BUILD_TESTING)
    add_executable(protocol_frame_test
        tests/protocol_frame_test.cpp
        src/frame.cpp
    )
    target_include_directories(protocol_frame_test PRIVATE include)
    add_test(NAME protocol_frame_test COMMAND protocol_frame_test)

    add_executable(movement_test tests/movement_test.cpp)
    target_include_directories(movement_test PRIVATE include)
    add_test(NAME movement_test COMMAND movement_test)
endif()

if(MSVC)
    target_compile_options(world_server PRIVATE /W4 /permissive-)
else()
    target_compile_options(world_server PRIVATE -Wall -Wextra -Wpedantic -Wconversion)
endif()
