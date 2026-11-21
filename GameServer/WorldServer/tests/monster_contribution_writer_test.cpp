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

    honghuang::persistence::MonsterContributionRecord first{
        "writer-hit-1", "life-a", "wolf", "session-a", "character-a", 10, 1, 100, 100, "[]"
    };
    auto second = first;
    second.write_id = "writer-hit-2";
    second.total_damage = 20;
    second.last_hit_at_ms = 120;

    // Durable admission survives closing and reopening the database before a worker sees it.
    {
        honghuang::persistence::DurableOutbox outbox(path, 8);
        std::string error;
        assert(outbox.admit_monster_contribution(first, error));
        assert(outbox.admit_monster_contribution(second, error));
        assert(outbox.admit_monster_contribution(first, error)); // Same write ID is idempotent.
        auto conflict = first;
        conflict.total_damage = 11;
        assert(!outbox.admit_monster_contribution(conflict, error));
        const auto pending = outbox.load_pending_monster_contribution_writes(8, error);
        assert(error.empty() && pending.size() == 2);
    }

    {
        honghuang::persistence::DurableOutbox outbox(path, 8);
        sqlite3* blocker = nullptr;
        assert(sqlite3_open(path.c_str(), &blocker) == SQLITE_OK);
        assert(sqlite3_exec(blocker, "BEGIN IMMEDIATE", nullptr, nullptr, nullptr) == SQLITE_OK);
        std::string error;
        auto busy_hit = first;
        busy_hit.write_id = "writer-hit-busy";
        assert(!outbox.admit_monster_contribution(busy_hit, error));

        // The writer reconstructs its queue from the durable inbox on startup.
        honghuang::persistence::MonsterContributionWriter writer(outbox, 2);
        assert(writer.pending_count() == 2);
        assert(writer.pending_count_for_monster("life-a") == 2);
        std::int64_t health = 100;
        auto third = first;
        third.write_id = "writer-hit-3";
        third.total_damage = 10;
        third.first_hit_at_ms = 130;
        third.last_hit_at_ms = 130;
        assert(!writer.submit_before_damage(
            third, [&]() noexcept { health -= third.total_damage; }, error));
        assert(health == 100); // Queue backpressure still rejects before health changes.
        assert(!writer.wait_until_drained("life-a", 20ms));

        assert(sqlite3_exec(blocker, "COMMIT", nullptr, nullptr, nullptr) == SQLITE_OK);
        sqlite3_close(blocker);
        assert(writer.wait_until_drained("life-a", 3s));
        assert(writer.pending_count() == 0);
        auto rows = outbox.load_monster_contributions("life-a", error);
        assert(error.empty() && rows.size() == 1);
        assert(rows.front().total_damage == 30);
        assert(rows.front().hit_count == 2);
        assert(outbox.load_pending_monster_contribution_writes(8, error).empty());

        assert(writer.submit_before_damage(
            third, [&]() noexcept { health -= third.total_damage; }, error));
        assert(health == 90);
        assert(writer.wait_until_drained("life-a", 3s));
        rows = outbox.load_monster_contributions("life-a", error);
        assert(error.empty() && rows.size() == 1 && rows.front().total_damage == 40);
        assert(rows.front().hit_count == 3);
        assert(rows.front().first_hit_at_ms == 100);
        assert(rows.front().last_hit_at_ms == 130);
        assert(writer.last_error().empty());

        // A completed write ID cannot be reused to apply a second health mutation.
        assert(!writer.submit(first, error));
        assert(writer.pending_count_for_monster("life-a") == 0);
        rows = outbox.load_monster_contributions("life-a", error);
        assert(error.empty() && rows.size() == 1 && rows.front().total_damage == 40);
        assert(rows.front().hit_count == 3);

        auto final_write = first;
        final_write.write_id = "writer-hit-final";
        final_write.total_damage = 5;
        assert(writer.submit(final_write, error));
        assert(writer.stop_after_drain(3s));
        assert(writer.pending_count() == 0);
        rows = outbox.load_monster_contributions("life-a", error);
        assert(error.empty() && rows.size() == 1 && rows.front().total_damage == 45);
        assert(rows.front().hit_count == 4);
    }

    // Simulate a crash after durable admission and before aggregation/acknowledgement.
    {
        honghuang::persistence::DurableOutbox outbox(path, 8);
        std::string error;
        auto crash_pending = first;
        crash_pending.write_id = "writer-hit-after-crash";
        crash_pending.monster_instance_id = "life-recovered";
        crash_pending.total_damage = 77;
        crash_pending.first_hit_at_ms = 900;
        crash_pending.last_hit_at_ms = 900;
        assert(outbox.admit_monster_contribution(crash_pending, error));
    }
    {
        honghuang::persistence::DurableOutbox reopened(path, 8);
        honghuang::persistence::MonsterContributionWriter recovered_writer(reopened, 8);
        assert(recovered_writer.pending_count_for_monster("life-recovered") == 1);
        assert(recovered_writer.wait_until_drained("life-recovered", 3s));
        std::string error;
        const auto rows = reopened.load_monster_contributions("life-recovered", error);
        assert(error.empty() && rows.size() == 1 && rows.front().total_damage == 77);
        assert(reopened.load_pending_monster_contribution_writes(8, error).empty());
        assert(recovered_writer.stop_after_drain(3s));
    }

    remove_database(path);
    return 0;
}
