#include "persistence/durable_outbox.hpp"
#include "persistence/monster_contribution_writer.hpp"

#include <cassert>
#include <cstdio>
#include <string>
#include <chrono>
#include <thread>
#include <sqlite3.h>

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
        sqlite3* blocker = nullptr;
        assert(sqlite3_open(path.c_str(), &blocker) == SQLITE_OK);
        assert(sqlite3_exec(blocker, "BEGIN IMMEDIATE", nullptr, nullptr, nullptr) == SQLITE_OK);
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
        std::int64_t health = 100;
        assert(!writer.submit_before_damage(first, [&]() noexcept { health -= first.total_damage; }, error));
        assert(health == 100); // A full queue must reject before health changes.
        assert(!writer.wait_until_drained("life-a", 20ms)); // In-flight write is still pending.
        assert(sqlite3_exec(blocker, "COMMIT", nullptr, nullptr, nullptr) == SQLITE_OK);
        sqlite3_close(blocker);
        assert(writer.wait_until_drained("life-a", 3s));
        assert(writer.pending_count() == 0);
        auto rows = outbox.load_monster_contributions("life-a", error);
        assert(rows.size() == 1);
        assert(rows.front().total_damage == 30);
        assert(rows.front().hit_count == 2);
        auto third = first;
        third.write_id = "writer-hit-3";
        third.total_damage = 10;
        third.first_hit_at_ms = 130;
        third.last_hit_at_ms = 130;
        assert(writer.submit_before_damage(third, [&]() noexcept { health -= third.total_damage; }, error));
        assert(health == 90);
        assert(writer.wait_until_drained("life-a", 3s));
        rows = outbox.load_monster_contributions("life-a", error);
        assert(rows.size() == 1 && rows.front().total_damage == 40);
        assert(rows.front().hit_count == 3);
        assert(rows.front().first_hit_at_ms == 100);
        assert(rows.front().last_hit_at_ms == 130);
        assert(writer.last_error().empty());
        auto final_write = first;
        final_write.write_id = "writer-hit-final";
        final_write.total_damage = 5;
        assert(writer.submit(final_write, error));
        assert(writer.stop_after_drain(3s));
        assert(writer.pending_count() == 0);
        rows = outbox.load_monster_contributions("life-a", error);
        assert(rows.size() == 1 && rows.front().total_damage == 45);
        assert(rows.front().hit_count == 4);

    }
    remove_database(path);
    return 0;
}
