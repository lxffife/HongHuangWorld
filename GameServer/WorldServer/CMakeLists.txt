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
    src/monster_runtime_checkpoint_writer.cpp
    src/monster_contribution_writer.cpp
    src/monster_death_finalizer.cpp
)

target_include_directories(world_server PRIVATE include)

add_executable(world_outbox_admin src/outbox_admin.cpp src/durable_outbox.cpp)
target_include_directories(world_outbox_admin PRIVATE include)
target_link_libraries(world_outbox_admin PRIVATE SQLite::SQLite3 Threads::Threads)
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

    add_executable(weapon_combat_test tests/weapon_combat_test.cpp)
    target_include_directories(weapon_combat_test PRIVATE include)
    add_test(NAME weapon_combat_test COMMAND weapon_combat_test)

    add_executable(projectile_test tests/projectile_test.cpp)
    target_include_directories(projectile_test PRIVATE include)
    add_test(NAME projectile_test COMMAND projectile_test)

    add_executable(spell_combat_test tests/spell_combat_test.cpp)
    target_include_directories(spell_combat_test PRIVATE include)
    add_test(NAME spell_combat_test COMMAND spell_combat_test)

    add_executable(spell_mastery_test tests/spell_mastery_test.cpp)
    target_include_directories(spell_mastery_test PRIVATE include)
    add_test(NAME spell_mastery_test COMMAND spell_mastery_test)

    add_executable(player_resources_test tests/player_resources_test.cpp)
    target_include_directories(player_resources_test PRIVATE include)
    add_test(NAME player_resources_test COMMAND player_resources_test)

    add_executable(status_effect_test tests/status_effect_test.cpp)
    target_include_directories(status_effect_test PRIVATE include)
    add_test(NAME status_effect_test COMMAND status_effect_test)

    add_executable(consumable_test tests/consumable_test.cpp)
    target_include_directories(consumable_test PRIVATE include)
    add_test(NAME consumable_test COMMAND consumable_test)

    add_executable(monster_test tests/monster_test.cpp)
    target_include_directories(monster_test PRIVATE include)
    add_test(NAME monster_test COMMAND monster_test)

    add_executable(revive_test tests/revive_test.cpp)
    target_include_directories(revive_test PRIVATE include)
    add_test(NAME revive_test COMMAND revive_test)

    add_executable(support_combat_test tests/support_combat_test.cpp)
    target_include_directories(support_combat_test PRIVATE include)
    add_test(NAME support_combat_test COMMAND support_combat_test)

    add_executable(chat_delivery_policy_test tests/chat_delivery_policy_test.cpp)
    target_include_directories(chat_delivery_policy_test PRIVATE include)
    add_test(NAME chat_delivery_policy_test COMMAND chat_delivery_policy_test)

    # The HTTP fault-injection fixture uses only Python's standard library.
    # Keep it optional so native WorldServer builds do not require Python.
    find_package(Python3 COMPONENTS Interpreter QUIET)
    if(Python3_Interpreter_FOUND)
        add_test(
            NAME chat_fake_server_test
            COMMAND ${Python3_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/../../Deployment/scripts/test-chat-fake-server.py
        )
    endif()

    add_executable(durable_outbox_test tests/durable_outbox_test.cpp src/durable_outbox.cpp)
    target_include_directories(durable_outbox_test PRIVATE include)
    target_link_libraries(durable_outbox_test PRIVATE SQLite::SQLite3 Threads::Threads)
    add_test(NAME durable_outbox_test COMMAND durable_outbox_test)

    add_executable(monster_runtime_checkpoint_writer_test
        tests/monster_runtime_checkpoint_writer_test.cpp
        src/monster_runtime_checkpoint_writer.cpp
        src/durable_outbox.cpp
    )
    target_include_directories(monster_runtime_checkpoint_writer_test PRIVATE include)
    target_link_libraries(monster_runtime_checkpoint_writer_test PRIVATE SQLite::SQLite3 Threads::Threads)
    add_test(NAME monster_runtime_checkpoint_writer_test COMMAND monster_runtime_checkpoint_writer_test)

    add_executable(monster_contribution_writer_test
        tests/monster_contribution_writer_test.cpp
        src/monster_contribution_writer.cpp
        src/durable_outbox.cpp
    )
    target_include_directories(monster_contribution_writer_test PRIVATE include)
    target_link_libraries(monster_contribution_writer_test PRIVATE SQLite::SQLite3 Threads::Threads)
    add_test(NAME monster_contribution_writer_test COMMAND monster_contribution_writer_test)

    add_executable(monster_death_finalizer_test
        tests/monster_death_finalizer_test.cpp
        src/monster_death_finalizer.cpp
        src/monster_contribution_writer.cpp
        src/durable_outbox.cpp
    )
    target_include_directories(monster_death_finalizer_test PRIVATE include)
    target_link_libraries(monster_death_finalizer_test PRIVATE SQLite::SQLite3 Threads::Threads)
    add_test(NAME monster_death_finalizer_test COMMAND monster_death_finalizer_test)
endif()

if(MSVC)
    target_compile_options(world_server PRIVATE /W4 /permissive-)
else()
    target_compile_options(world_server PRIVATE -Wall -Wextra -Wpedantic -Wconversion)
endif()
