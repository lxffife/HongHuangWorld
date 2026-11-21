#include "persistence/monster_death_finalizer.hpp"

#include <algorithm>
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
        honghuang::persistence::PendingMonsterDeathRecord intent;
        intent.monster_instance_id = "life-death-1";
        intent.runtime_id = "spawn-death-1";
        intent.payload = R"({"version":1,"killer_objectives":[],"drops":[]})";
        intent.created_at_ms = 1;
        assert(outbox.save_pending_monster_death(intent, error));

        honghuang::persistence::MonsterDeathFinalizer finalizer(outbox, writer);
        bool builder_called = false;
        assert(finalizer.submit("life-death-1",
            [&builder_called](const auto& records, auto& events, std::string&) {
                builder_called = true;
                assert(records.size() == 1);
                assert(records.front().total_damage == 25);
                const std::string payload = R"({"event_id":"death-event-1"})";
                events.push_back({"death-event-1", "test_death_event", payload, 0, 0, 1, {}});
                events.push_back({"death-event-2", "test_death_event",
                    R"({"event_id":"death-event-2"})", 0, 0, 1, {}});
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
        const auto first_event = outbox.find("death-event-1", error);
        assert(error.empty() && first_event.has_value());
        const auto second_event = outbox.find("death-event-2", error);
        assert(error.empty() && second_event.has_value());
        const auto pending_deaths = outbox.load_pending_monster_deaths(error);
        assert(error.empty() && pending_deaths.size() == 1);
        assert(pending_deaths.front().committed_at_ms > 0);
        assert(!pending_deaths.front().prepared_events_json.empty());
        assert(outbox.acknowledge_monster_death_respawn("life-death-1", error));
        assert(outbox.load_pending_monster_deaths(error).empty());
        honghuang::persistence::MonsterContributionRecord recovered_contribution = contribution;
        recovered_contribution.write_id = "write-death-2";
        recovered_contribution.monster_instance_id = "life-death-2";
        assert(writer.submit(recovered_contribution, error));
        honghuang::persistence::PendingMonsterDeathRecord recovered_intent;
        recovered_intent.monster_instance_id = "life-death-2";
        recovered_intent.runtime_id = "spawn-death-2";
        recovered_intent.payload = R"({"version":1,"killer_objectives":[],"drops":[]})";
        recovered_intent.created_at_ms = 2;
        assert(outbox.save_pending_monster_death(recovered_intent, error));
        const std::string persisted_batch =
            R"([{"event_id":"recovered-event-1","event_type":"test_death_event","payload":"{\"event_id\":\"recovered-event-1\"}","attempts":0,"next_retry_at_ms":0,"created_at_ms":2,"last_error":""}])";
        assert(outbox.save_pending_monster_death_batch("life-death-2", persisted_batch, error));
        bool recovered_builder_called = false;
        assert(finalizer.submit("life-death-2",
            [&recovered_builder_called](const auto&, auto&, std::string&) {
                recovered_builder_called = true;
                return false;
            }, error));
        bool recovered_completed = false;
        const auto recovered_deadline = std::chrono::steady_clock::now() + 3s;
        while (std::chrono::steady_clock::now() < recovered_deadline && !recovered_completed) {
            for (const auto& result : finalizer.take_results()) {
                assert(result.success);
                assert(result.monster_instance_id == "life-death-2");
                recovered_completed = true;
            }
            if (!recovered_completed) std::this_thread::sleep_for(10ms);
        }
        assert(recovered_completed);
        assert(!recovered_builder_called);
        const auto recovered_event = outbox.find("recovered-event-1", error);
        assert(error.empty() && recovered_event.has_value());
        const auto committed_records = outbox.load_pending_monster_deaths(error);
        const auto committed_intent = std::find_if(
            committed_records.begin(), committed_records.end(),
            [](const auto& item) { return item.monster_instance_id == "life-death-2"; });
        assert(error.empty() && committed_intent != committed_records.end());
        assert(committed_intent->committed_at_ms > 0);
        assert(outbox.acknowledge_monster_death_respawn("life-death-2", error));
        assert(finalizer.stop_after_drain(1s));
        assert(writer.stop_after_drain(1s));
    }
    std::filesystem::remove(path);
    return 0;
}
