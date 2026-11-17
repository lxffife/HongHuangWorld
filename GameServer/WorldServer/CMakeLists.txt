cmake_minimum_required(VERSION 3.24)
project(HongHuangWorldServer VERSION 0.3.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Threads REQUIRED)
find_package(SQLite3 REQUIRED)

if(WIN32)
    find_package(unofficial-enet CONFIG REQUIRED)
    find_package(CURL REQUIRED)
    find_package(nlohmann_json CONFIG REQUIRED)
    set(HH_ENET_TARGET unofficial::enet::enet)
    set(HH_CURL_TARGET CURL::libcurl)
else()
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(ENET REQUIRED IMPORTED_TARGET libenet)
    pkg_check_modules(CURL REQUIRED IMPORTED_TARGET libcurl)
    find_package(nlohmann_json 3.10 REQUIRED)
    set(HH_ENET_TARGET PkgConfig::ENET)
    set(HH_CURL_TARGET PkgConfig::CURL)
endif()

add_executable(world_server
    src/main.cpp
    src/enet_server.cpp
    src/frame.cpp
    src/durable_outbox.cpp
)

target_include_directories(world_server PRIVATE include)
target_link_libraries(world_server PRIVATE
    ${HH_ENET_TARGET}
    ${HH_CURL_TARGET}
    nlohmann_json::nlohmann_json
    Threads::Threads
    SQLite::SQLite3
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

    add_executable(combat_test tests/combat_test.cpp)
    target_include_directories(combat_test PRIVATE include)
    add_test(NAME combat_test COMMAND combat_test)

    add_executable(monster_test tests/monster_test.cpp)
    target_include_directories(monster_test PRIVATE include)
    add_test(NAME monster_test COMMAND monster_test)

    add_executable(durable_outbox_test tests/durable_outbox_test.cpp src/durable_outbox.cpp)
    target_include_directories(durable_outbox_test PRIVATE include)
    target_link_libraries(durable_outbox_test PRIVATE SQLite::SQLite3 Threads::Threads)
    add_test(NAME durable_outbox_test COMMAND durable_outbox_test)
endif()

if(MSVC)
    target_compile_options(world_server PRIVATE /W4 /permissive-)
else()
    target_compile_options(world_server PRIVATE -Wall -Wextra -Wpedantic -Wconversion)
endif()
