#include "persistence/durable_outbox.hpp"
#include "persistence/monster_contribution_writer.hpp"

#include <cassert>
#include <cstdio>
#include <string>
#include <chrono>
#include <thread>

namespace {
void remove_database(const std::string& path) {
    std::remove(path.c_str());
    std::remove((path + "-wal").c_str());
    std::remove((path + "-shm").c_str());
}
}

int main() {
    using namespace std::chrono_literals;
    const std::string path = "world_monster_contribution_writer_test.sqlite";
    remove_database(path);
    {
        honghuang::persistence::DurableOutbox outbox(path, 8);
        honghuang::persistence::MonsterContributionWriter writer(outbox, 2);
        std::string error;
        honghuang::persistence::MonsterContributionRecord first{
            "writer-hit-1", "life-a", "wolf", "session-a", "character-a", 10, 1, 100, 100, "[]"
        };
        auto second = first;
        second.write_id = "writer-hit-2";
        second.total_damage = 20;
        second.last_hit_at_ms = 120;
        assert(writer.submit(first, error));
        assert(writer.submit(second, error));
        assert(!writer.submit(first, error)); // Bounded queue applies explicit backpressure.
        assert(writer.wait_until_drained("life-a", 3s));
        assert(writer.pending_count() == 0);
        auto rows = outbox.load_monster_contributions("life-a", error);
        assert(rows.size() == 1);
        assert(rows.front().total_damage == 30);
        assert(rows.front().hit_count == 2);
        assert(rows.front().first_hit_at_ms == 100);
        assert(rows.front().last_hit_at_ms == 120);
        assert(writer.last_error().empty());
        writer.stop();
    }
    remove_database(path);
    return 0;
}
