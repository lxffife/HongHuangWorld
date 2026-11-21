#include "persistence/monster_death_finalizer.hpp"

#include <cassert>
#include <chrono>
#include <filesystem>
#include <string>
#include <thread>

using namespace std::chrono_literals;

int main() {
    const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
    const auto path = std::filesystem::temp_directory_path() /
        ("hh_monster_death_finalizer_" + std::to_string(stamp) + ".sqlite");
    {
        honghuang::persistence::DurableOutbox outbox(path.string(), 100);
        honghuang::persistence::MonsterContributionWriter writer(outbox, 16);
        honghuang::persistence::MonsterContributionRecord contribution;
        contribution.write_id = "write-death-1";
        contribution.monster_instance_id = "life-death-1";
        contribution.monster_definition_id = "test_monster";
        contribution.session_id = "session-1";
        contribution.character_id = "character-1";
        contribution.total_damage = 25;
        contribution.hit_count = 1;
        contribution.bounty_objectives_json = "[]";
        std::string error;
        assert(writer.submit(contribution, error));

        honghuang::persistence::MonsterDeathFinalizer finalizer(outbox, writer);
        bool builder_called = false;
        assert(finalizer.submit("life-death-1",
            [&builder_called](const auto& records, auto& events, std::string&) {
                builder_called = true;
                assert(records.size() == 1);
                assert(records.front().total_damage == 25);
                const std::string payload = R"({"event_id":"death-event-1"})";
                events.push_back({"death-event-1", "test_death_event", payload, 0, 0, 1, {}});
                return true;
            }, error));

        bool completed = false;
        const auto deadline = std::chrono::steady_clock::now() + 3s;
        while (std::chrono::steady_clock::now() < deadline && !completed) {
            for (const auto& result : finalizer.take_results()) {
                assert(result.success);
                assert(result.monster_instance_id == "life-death-1");
                completed = true;
            }
            if (!completed) std::this_thread::sleep_for(10ms);
        }
        assert(completed);
        assert(builder_called);
        assert(finalizer.pending_count() == 0);
        const auto remaining = outbox.load_monster_contributions("life-death-1", error);
        assert(error.empty());
        assert(remaining.empty());
        assert(finalizer.stop_after_drain(1s));
        assert(writer.stop_after_drain(1s));
    }
    std::filesystem::remove(path);
    return 0;
}
