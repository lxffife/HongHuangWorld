#include "persistence/monster_runtime_checkpoint_writer.hpp"

#include <cassert>
#include <cstdio>
#include <string>
#include <thread>

namespace {
void remove_database(const std::string& path) {
    std::remove(path.c_str());
    std::remove((path + "-wal").c_str());
    std::remove((path + "-shm").c_str());
}
}

int main() {
    const std::string path = "monster_checkpoint_writer_test.sqlite";
    remove_database(path);
    {
        honghuang::persistence::DurableOutbox outbox(path, 32);
        std::string error;
        honghuang::persistence::MonsterLifeStateRecord life{
            "spawn-writer", "life-writer-1", "wolf", 80.0};
        honghuang::persistence::MonsterLifeStateRecord persisted;
        assert(outbox.ensure_monster_life_state(life, persisted, error));

        honghuang::persistence::MonsterRuntimeCheckpointWriter writer(
            outbox, 8, std::chrono::milliseconds{20});
        assert(writer.submit({"spawn-writer", "life-writer-1", "wolf",
                              1.0, 2.0, 0.1, 1, 0, 1000}, error));
        // The latest pending state replaces earlier snapshots for the same runtime.
        assert(writer.submit({"spawn-writer", "life-writer-1", "wolf",
                              4.0, 5.0, 0.2, 2, 0, 1001}, error));
        assert(writer.wait_until_drained(std::chrono::seconds(2)));
        auto rows = outbox.load_monster_runtime_checkpoints(error);
        assert(error.empty() && rows.size() == 1);
        assert(rows.front().x == 4.0 && rows.front().z == 5.0 && rows.front().mode == 2);

        // An older late-arriving snapshot cannot replace the newer pending state.
        assert(writer.submit({"spawn-writer", "life-writer-1", "wolf",
                              6.0, 7.0, 0.3, 1, 0, 1002}, error));
        assert(writer.submit({"spawn-writer", "life-writer-1", "wolf",
                              0.0, 0.0, 0.0, 0, 0, 999}, error));
        assert(writer.wait_until_drained(std::chrono::seconds(2)));
        rows = outbox.load_monster_runtime_checkpoints(error);
        assert(error.empty() && rows.size() == 1 && rows.front().x == 6.0);
        assert(writer.stop_after_drain(std::chrono::seconds(2)));
        assert(!writer.submit({"spawn-writer", "life-writer-1", "wolf",
                               8.0, 9.0, 0.0, 0, 0, 1003}, error));
    }
    remove_database(path);
    return 0;
}
