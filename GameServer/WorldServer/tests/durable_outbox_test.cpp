#include "persistence/durable_outbox.hpp"

#include <algorithm>

#include <cassert>
#include <cstdio>
#include <string>
#include <atomic>
#include <thread>
#include <vector>

namespace {
void remove_database(const std::string& path) {
    std::remove(path.c_str());
    std::remove((path + "-wal").c_str());
    std::remove((path + "-shm").c_str());
}
}

int main() {
    const std::string path = "world_outbox_test.sqlite";
    remove_database(path);

    {
        honghuang::persistence::DurableOutbox box(path, 2);
        std::string error;
        const honghuang::persistence::OutboxEvent reward{
            "e1", "character_reward", "{\"xp\":20}", 0, 100, 100, {}
        };
        assert(box.enqueue(reward, error));
        assert(box.enqueue(reward, error)); // Exact duplicate is idempotent.
        assert(!box.enqueue({"e1", "character_reward", "{\"xp\":99}", 0, 100, 100, {}}, error));
        assert(box.pending_count(error) == 1);

        auto first = box.claim_due(100, error);
        assert(first && first->event_id == "e1");
        assert(!box.claim_due(100, error));
    }

    {
        // Constructor recovers an inflight event after a simulated process crash.
        honghuang::persistence::DurableOutbox box(path, 2);
        std::string error;
        auto recovered = box.claim_due(100, error);
        assert(recovered && recovered->attempts == 0);

        assert(box.schedule_retry("e1", 1, 250, "temporary failure", error));
        assert(!box.claim_due(200, error));
        auto retry = box.claim_due(250, error);
        assert(retry && retry->attempts == 1);
        assert(box.enqueue({"pickup-1", "ground_drop_pickup", "{\"drop_id\":\"d1\",\"request_session_id\":\"s1\"}", 0, 0, 275, {}}, error));
        auto pickup = box.claim_due(275, error);
        assert(pickup && pickup->event_type == "ground_drop_pickup");
        assert(box.schedule_retry("pickup-1", 1, 300, "session temporarily unavailable", error));
        auto pickup_retry = box.claim_due(300, error);
        assert(pickup_retry && pickup_retry->event_id == "pickup-1");
        assert(box.mark_delivered("pickup-1", error));

        assert(box.mark_delivered("e1", error));
        assert(!box.mark_delivered("e1", error));
        assert(box.pending_count(error) == 0);

        assert(box.enqueue({"e2", "ground_drop_create", "{\"item\":\"wolf_fang\"}", 0, 0, 300, {}}, error));
        assert(box.enqueue({"e3", "ground_drop_create", "{\"item\":\"wolf_pelt\"}", 0, 0, 301, {}}, error));
        assert(!box.enqueue({"e4", "ground_drop_create", "{\"item\":\"other\"}", 0, 0, 302, {}}, error));
        auto e2 = box.claim_due(300, error);
        assert(e2 && e2->event_id == "e2");
        assert(box.move_to_dead_letter("e2", 1, "permanent HTTP 400", error));
        assert(!box.schedule_retry("e2", 2, 400, "must not revive dead letter", error));
    }

    {
        // Nearby chat uses the same durable outbox and survives process restart.
        honghuang::persistence::DurableOutbox box(path, 4);
        std::string error;
        const honghuang::persistence::OutboxEvent chat{
            "nearby-chat:client-1", "nearby_chat",
            R"({"session_id":"s1","client_message_id":"client-1","content":"changed"})",
            0, 500, 500, {}
        };
        assert(box.enqueue(chat, error));
        assert(box.enqueue(chat, error));
        auto found_chat = box.find("nearby-chat:client-1", error);
        assert(found_chat && found_chat->payload == chat.payload);
        assert(!box.enqueue({
            "nearby-chat:client-1", "nearby_chat",
            R"({"session_id":"s1","client_message_id":"client-1"})",
            0, 500, 500, {}
        }, error));
        auto pending_chat = box.claim_due_type(500, "nearby_chat", error);
        assert(pending_chat && pending_chat->event_type == "nearby_chat");
    }
    {
        honghuang::persistence::DurableOutbox recovered_box(path, 4);
        std::string error;
        auto gameplay_event = recovered_box.claim_due_excluding(500, "nearby_chat", error);
        assert(gameplay_event && gameplay_event->event_type != "nearby_chat"); // Gameplay workers never claim chat traffic.
        auto recovered_chat = recovered_box.claim_due_type(500, "nearby_chat", error);
        assert(recovered_chat && recovered_chat->event_id == "nearby-chat:client-1");
        assert(recovered_chat->payload.find("client-1") != std::string::npos);
        assert(recovered_box.mark_delivered(recovered_chat->event_id, error));
    }

    remove_database(path);

    // Two independent connections must still respect one shared capacity limit.
    const std::string concurrent_path = "world_outbox_concurrent_test.sqlite";
    remove_database(concurrent_path);
    {
        honghuang::persistence::DurableOutbox first_box(concurrent_path, 2);
        honghuang::persistence::DurableOutbox second_box(concurrent_path, 2);
        std::atomic<int> accepted{0};
        std::vector<std::thread> writers;
        for (int i = 0; i < 8; ++i) {
            writers.emplace_back([&, i] {
                std::string error;
                auto& box = (i % 2 == 0) ? first_box : second_box;
                const bool stored = box.enqueue({
                    "parallel-" + std::to_string(i), "character_reward",
                    "{\"xp\":1}", 0, 0, 400 + i, {}
                }, error);
                if (stored) ++accepted;
            });
        }
        for (auto& writer : writers) writer.join();
        std::string error;
        assert(accepted == 2);
        assert(first_box.pending_count(error) == 2);
    }
    remove_database(concurrent_path);

    const std::string quota_path = "world_outbox_quota_test.sqlite";
    remove_database(quota_path);
    {
        honghuang::persistence::DurableOutbox box(quota_path, 4);
        std::string error;
        assert(box.enqueue({"chat-1", "nearby_chat", "payload", 0, 0, 1, {}}, error));
        assert(box.enqueue({"chat-2", "nearby_chat", "payload", 0, 0, 2, {}}, error));
        assert(!box.enqueue({"chat-3", "nearby_chat", "payload", 0, 0, 3, {}}, error));
        assert(box.enqueue({"game-1", "character_reward", "payload", 0, 0, 4, {}}, error));
        assert(box.enqueue({"game-2", "ground_drop_create", "payload", 0, 0, 5, {}}, error));
        assert(!box.enqueue({"game-3", "character_reward", "payload", 0, 0, 6, {}}, error));
    }
    remove_database(quota_path);


    const std::string batch_path = "world_outbox_batch_test.sqlite";
    remove_database(batch_path);
    {
        honghuang::persistence::DurableOutbox box(batch_path, 2);
        std::string error;
        const std::vector<honghuang::persistence::OutboxEvent> kill_and_contribution{
            {"kill-1", "bounty_objective_event", R"({"event_id":"kill-1"})", 0, 100, 100, {}},
            {"contrib-1", "bounty_monster_contributions", R"({"event_id":"contrib-1"})", 0, 100, 100, {}}
        };
        assert(box.enqueue_batch(kill_and_contribution, error));
        assert(box.pending_count(error) == 2);
        assert(box.enqueue_batch(kill_and_contribution, error)); // Entire batch retry is idempotent.
        assert(box.pending_count(error) == 2);

        auto conflicting = kill_and_contribution;
        conflicting[1].payload = R"({"event_id":"contrib-1","damage":99})";
        assert(!box.enqueue_batch(conflicting, error)); // Conflict rejects the batch.
        assert(box.pending_count(error) == 2);

        const std::vector<honghuang::persistence::OutboxEvent> late_conflict{
            {"new-before-conflict", "bounty_objective_event", R"({"event_id":"new-before-conflict"})", 0, 100, 100, {}},
            {"kill-1", "bounty_objective_event", R"({"event_id":"kill-1","different":true})", 0, 100, 100, {}}
        };
        assert(!box.enqueue_batch(late_conflict, error));
        assert(box.pending_count(error) == 2);
        assert(!box.find("new-before-conflict", error)); // No earlier row leaked from the rejected batch.

        assert(box.mark_delivered("kill-1", error));
        assert(box.mark_delivered("contrib-1", error));
    }
    remove_database(batch_path);

    const std::string batch_capacity_path = "world_outbox_batch_capacity_test.sqlite";
    remove_database(batch_capacity_path);
    {
        honghuang::persistence::DurableOutbox box(batch_capacity_path, 1);
        std::string error;
        const std::vector<honghuang::persistence::OutboxEvent> too_large{
            {"kill-cap", "bounty_objective_event", R"({"event_id":"kill-cap"})", 0, 100, 100, {}},
            {"contrib-cap", "bounty_monster_contributions", R"({"event_id":"contrib-cap"})", 0, 100, 100, {}}
        };
        assert(!box.enqueue_batch(too_large, error));
        assert(box.pending_count(error) == 0); // Capacity failure leaves no partial batch.
    }
    remove_database(batch_capacity_path);

    const std::string admin_path = "world_outbox_admin_test.sqlite";
    remove_database(admin_path);
    {
        honghuang::persistence::DurableOutbox worker_box(admin_path, 8);
        std::string error;
        assert(worker_box.enqueue({"chat-dead", "nearby_chat", "chat payload", 0, 0, 10, {}}, error));
        auto dead = worker_box.claim_due_type(10, "nearby_chat", error);
        assert(dead && dead->event_id == "chat-dead");
        assert(worker_box.move_to_dead_letter("chat-dead", 1, "HTTP 401", error));

        assert(worker_box.enqueue({"chat-live", "nearby_chat", "live payload", 0, 0, 20, {}}, error));
        auto inflight = worker_box.claim_due_type(20, "nearby_chat", error);
        assert(inflight && inflight->event_id == "chat-live");
        assert(worker_box.enqueue({"game-dead", "character_reward", "reward payload", 0, 0, 30, {}}, error));
        auto game_event = worker_box.claim_due_excluding(30, "nearby_chat", error);
        assert(game_event && game_event->event_id == "game-dead");
        assert(worker_box.move_to_dead_letter("game-dead", 1, "game API rejected event", error));

        {
            // An operator inspection must not reset a live worker's inflight row.
            honghuang::persistence::DurableOutbox inspector(admin_path, 8, false);
            auto snapshot = inspector.stats(1000, error, "nearby_chat");
            assert(snapshot.dead_letter == 1 && snapshot.inflight == 1);
            auto dead_letters = inspector.list_dead_letters(10, "nearby_chat", error);
            assert(dead_letters.size() == 1 && dead_letters.front().event_id == "chat-dead");
            assert(inspector.retry_dead_letter("chat-dead", 1000, error));
            snapshot = inspector.stats(1000, error, "nearby_chat");
            assert(snapshot.pending == 1 && snapshot.inflight == 1 && snapshot.dead_letter == 0);
            assert(!inspector.retry_dead_letter("chat-live", 1000, error));
            assert(!inspector.retry_dead_letter("game-dead", 1000, error));
        }

        auto retried = worker_box.claim_due_type(1000, "nearby_chat", error);
        assert(retried && retried->event_id == "chat-dead");
        assert(worker_box.mark_delivered("chat-dead", error));
        assert(worker_box.mark_delivered("chat-live", error));
    }
    remove_database(admin_path);

    const std::string ledger_path = "world_outbox_monster_ledger_test.sqlite";
    remove_database(ledger_path);
    {
        honghuang::persistence::DurableOutbox box(ledger_path, 8);
        std::string error;
        honghuang::persistence::MonsterContributionRecord hit{
            "hit-write-1", "monster-runtime-1", "wolf", "session-a", "character-a", 25, 1, 100, 100, R"([{"task_id":"task-a"}])"
        };
        assert(box.record_monster_contribution(hit, error));
        assert(box.record_monster_contribution(hit, error)); // Retrying the same write ID never double-counts.
        hit.write_id = "hit-write-2";
        hit.total_damage = 35;
        hit.hit_count = 1;
        hit.first_hit_at_ms = 90;
        hit.last_hit_at_ms = 120;
        hit.bounty_objectives_json = R"([{"task_id":"task-a"},{"task_id":"task-b"}])";
        assert(box.record_monster_contribution(hit, error));
        auto conflicting_write = hit;
        conflicting_write.total_damage = 36;
        assert(!box.record_monster_contribution(conflicting_write, error));
        error = "stale error from an earlier database operation";
        auto loaded = box.load_monster_contributions("monster-runtime-1", error);
        assert(error.empty()); // Successful reads clear a reused error buffer.
        assert(loaded.size() == 1);
        error = "stale error before empty ledger read";
        const auto absent = box.load_monster_contributions("monster-with-no-ledger", error);
        assert(absent.empty() && error.empty()); // Empty is distinct from a failed read.
        assert(loaded.front().total_damage == 60 && loaded.front().hit_count == 2);
        assert(loaded.front().first_hit_at_ms == 90 && loaded.front().last_hit_at_ms == 120);
        assert(loaded.front().bounty_objectives_json.find("task-b") != std::string::npos);
        {
            honghuang::persistence::DurableOutbox reopened(ledger_path, 8, false);
            auto recovered = reopened.load_monster_contributions("monster-runtime-1", error);
            assert(recovered.size() == 1 && recovered.front().total_damage == 60);
        }
        const std::vector<honghuang::persistence::OutboxEvent> final_events{
            {"monster-kill-final", "bounty_objective_event", R"({"event_id":"monster-kill-final"})", 0, 200, 200, {}},
            {"monster-contrib-final", "bounty_monster_contributions", R"({"event_id":"monster-contrib-final"})", 0, 200, 200, {}}
        };
        error = "stale error before finalization retry";
        assert(box.finalize_monster_contributions("monster-runtime-1", final_events, error));
        assert(error.empty()); // Successful finalization clears a reused error buffer.
        assert(box.load_monster_contributions("monster-runtime-1", error).empty());
        assert(box.pending_count(error) == 2);
        error = "stale error before idempotent finalization";
        assert(box.finalize_monster_contributions("monster-runtime-1", final_events, error));
        assert(error.empty());
        assert(box.pending_count(error) == 2);
        auto late_hit = hit;
        late_hit.write_id = "late-hit-after-death";
        assert(!box.record_monster_contribution(late_hit, error));
        auto conflicting_final_events = final_events;
        conflicting_final_events[0].event_id = "different-kill-event";
        assert(!box.finalize_monster_contributions("monster-runtime-1", conflicting_final_events, error));
        assert(box.pending_count(error) == 2);
    }
    remove_database(ledger_path);


    const std::string ledger_capacity_path = "world_outbox_monster_ledger_capacity_test.sqlite";
    remove_database(ledger_capacity_path);
    {
        honghuang::persistence::DurableOutbox box(ledger_capacity_path, 1);
        std::string error;
        honghuang::persistence::MonsterContributionRecord hit{
            "hit-write-cap", "monster-runtime-cap", "wolf", "session-cap", "character-cap", 10, 1, 300, 300, "[]"
        };
        assert(box.record_monster_contribution(hit, error));
        const std::vector<honghuang::persistence::OutboxEvent> too_large{
            {"monster-kill-cap", "bounty_objective_event", R"({"event_id":"monster-kill-cap"})", 0, 400, 400, {}},
            {"monster-contrib-cap", "bounty_monster_contributions", R"({"event_id":"monster-contrib-cap"})", 0, 400, 400, {}}
        };
        assert(!box.finalize_monster_contributions("monster-runtime-cap", too_large, error));
        auto retained = box.load_monster_contributions("monster-runtime-cap", error);
        assert(retained.size() == 1 && retained.front().total_damage == 10);
        assert(box.pending_count(error) == 0);
    }
    remove_database(ledger_capacity_path);

    // A monster with no matching bounty subscriptions still needs its ledger
    // tombstoned and cleared; an empty event batch is a valid finalization.
    const std::string no_objective_path = "world_outbox_monster_no_objective_test.sqlite";
    remove_database(no_objective_path);
    {
        honghuang::persistence::DurableOutbox box(no_objective_path, 4);
        std::string error;
        honghuang::persistence::MonsterContributionRecord hit{
            "hit-no-objective", "monster-no-objective", "wolf", "session-x", "character-x", 12, 1, 500, 500, "[]"
        };
        assert(box.record_monster_contribution(hit, error));
        const std::vector<honghuang::persistence::OutboxEvent> no_events;
        assert(box.finalize_monster_contributions("monster-no-objective", no_events, error));
        assert(box.load_monster_contributions("monster-no-objective", error).empty());
        assert(box.pending_count(error) == 0);
        auto late_hit = hit;
        late_hit.write_id = "late-no-objective";
        assert(!box.record_monster_contribution(late_hit, error));
        assert(box.finalize_monster_contributions("monster-no-objective", no_events, error));
    }
    // The empty-batch tombstone must survive restart and continue rejecting late writes.
    {
        honghuang::persistence::DurableOutbox reopened(no_objective_path, 4, false);
        std::string error;
        const std::vector<honghuang::persistence::OutboxEvent> no_events;
        assert(reopened.finalize_monster_contributions("monster-no-objective", no_events, error));
        honghuang::persistence::MonsterContributionRecord late_hit{
            "late-no-objective-after-restart", "monster-no-objective", "wolf",
            "session-x", "character-x", 1, 1, 600, 600, "[]"
        };
        assert(!reopened.record_monster_contribution(late_hit, error));
        assert(reopened.load_monster_contributions("monster-no-objective", error).empty());
    }
    remove_database(no_objective_path);

    {
        // Death intent and the prepared event batch survive reopening the SQLite file.
        honghuang::persistence::DurableOutbox box(path, 100);
        std::string error;
        honghuang::persistence::PendingMonsterDeathRecord intent;
        intent.monster_instance_id = "life-pending-restart";
        intent.runtime_id = "spawn-pending-restart";
        intent.payload = R"({"version":1,"killer_objectives":[],"drops":[]})";
        intent.created_at_ms = 500;
        assert(box.save_pending_monster_death(intent, error));
        assert(box.save_pending_monster_death(intent, error));
        auto conflicting = intent;
        conflicting.payload = R"({"version":2})";
        assert(!box.save_pending_monster_death(conflicting, error));
        const std::string batch =
            R"([{"event_id":"stable-event","event_type":"test","payload":"{}","attempts":0,"next_retry_at_ms":0,"created_at_ms":500,"last_error":""}])";
        assert(box.save_pending_monster_death_batch(intent.monster_instance_id, batch, error));
        assert(box.save_pending_monster_death_batch(intent.monster_instance_id, batch, error));
    }
    {
        honghuang::persistence::DurableOutbox reopened(path, 100);
        std::string error;
        const auto records = reopened.load_pending_monster_deaths(error);
        assert(error.empty() && records.size() == 1);
        assert(records.front().monster_instance_id == "life-pending-restart");
        assert(records.front().prepared_events_json.find("stable-event") != std::string::npos);
        assert(records.front().committed_at_ms == 0);
        const std::vector<honghuang::persistence::OutboxEvent> events{
            {"stable-event", "test", "{}", 0, 0, 500, {}}
        };
        assert(reopened.finalize_monster_contributions("life-pending-restart", events, error));
        const auto committed = reopened.load_pending_monster_deaths(error);
        assert(error.empty() && committed.size() == 1);
        assert(committed.front().committed_at_ms > 0);
        assert(reopened.acknowledge_monster_death_respawn("life-pending-restart", error));
        assert(reopened.load_pending_monster_deaths(error).empty());
    }

    {
        // The lethal hit and its pending death intent commit as one SQLite transaction.
        honghuang::persistence::DurableOutbox box(path, 100);
        std::string error;
        honghuang::persistence::MonsterContributionRecord lethal;
        lethal.write_id = "write-lethal-atomic";
        lethal.monster_instance_id = "life-lethal-atomic";
        lethal.monster_definition_id = "test_monster";
        lethal.session_id = "session-lethal";
        lethal.character_id = "character-lethal";
        lethal.total_damage = 99;
        lethal.hit_count = 1;
        lethal.first_hit_at_ms = 700;
        lethal.last_hit_at_ms = 700;
        lethal.bounty_objectives_json = "[]";
        honghuang::persistence::PendingMonsterDeathRecord intent;
        intent.monster_instance_id = lethal.monster_instance_id;
        intent.runtime_id = "spawn-lethal-atomic";
        intent.payload = R"({"version":1,"killer_objectives":[],"drops":[]})";
        intent.created_at_ms = 700;
        assert(box.record_monster_contribution_and_pending_death(lethal, intent, error));
        const auto snapshot = box.load_monster_contributions(lethal.monster_instance_id, error);
        assert(error.empty() && snapshot.size() == 1);
        const auto deaths = box.load_pending_monster_deaths(error);
        assert(error.empty() && deaths.size() == 1);
        assert(deaths.front().monster_instance_id == lethal.monster_instance_id);
        auto late_hit = lethal;
        late_hit.write_id = "write-after-lethal";
        assert(!box.admit_monster_contribution(late_hit, error));

        honghuang::persistence::MonsterContributionRecord rejected = lethal;
        rejected.write_id = "write-lethal-conflict";
        rejected.monster_instance_id = "life-lethal-conflict";
        honghuang::persistence::PendingMonsterDeathRecord conflicting_intent;
        conflicting_intent.monster_instance_id = rejected.monster_instance_id;
        conflicting_intent.runtime_id = "spawn-lethal-conflict";
        conflicting_intent.payload = R"({"version":1})";
        conflicting_intent.created_at_ms = 701;
        assert(box.save_pending_monster_death(conflicting_intent, error));
        conflicting_intent.payload = R"({"version":2})";
        assert(!box.record_monster_contribution_and_pending_death(
            rejected, conflicting_intent, error));
        const auto rolled_back = box.load_monster_contributions(rejected.monster_instance_id, error);
        assert(error.empty() && rolled_back.empty());
    }

    const std::string life_state_path = "world_outbox_monster_life_state_test.sqlite";
    remove_database(life_state_path);
    {
        honghuang::persistence::DurableOutbox box(life_state_path, 16);
        std::string error;
        honghuang::persistence::MonsterLifeStateRecord initial{
            "spawn-state-1", "life-state-1", "wolf", 100.0};
        honghuang::persistence::MonsterLifeStateRecord persisted;
        assert(box.ensure_monster_life_state(initial, persisted, error));
        assert(persisted.monster_instance_id == "life-state-1" && persisted.health == 100.0);

        honghuang::persistence::MonsterContributionRecord hit;
        hit.write_id = "life-state-hit-1";
        hit.monster_instance_id = "life-state-1";
        hit.monster_definition_id = "wolf";
        hit.session_id = "session-state";
        hit.character_id = "character-state";
        hit.total_damage = 25;
        hit.hit_count = 1;
        hit.first_hit_at_ms = 800;
        hit.last_hit_at_ms = 800;
        hit.bounty_objectives_json = "[]";
        assert(box.admit_monster_damage(hit, "spawn-state-1", 100.0, 75.0, error));
        // Simulate a crash immediately after SQLite commit but before the caller's
        // in-memory health callback: a fresh process must load the committed 75 HP.
        {
            honghuang::persistence::DurableOutbox recovered(life_state_path, 16, false);
            honghuang::persistence::MonsterLifeStateRecord startup{
                "spawn-state-1", "random-process-instance", "wolf", 100.0};
            honghuang::persistence::MonsterLifeStateRecord restored;
            assert(recovered.ensure_monster_life_state(startup, restored, error));
            assert(restored.monster_instance_id == "life-state-1" && restored.health == 75.0);
        }
        auto states = box.load_monster_life_states(error);
        assert(error.empty() && states.size() == 1 && states.front().health == 75.0);
        assert(!box.admit_monster_damage(
            hit, "spawn-state-1", 100.0, 75.0, error)); // stale expected health cannot overwrite.
        assert(box.record_monster_contribution(hit, error));
        assert(box.acknowledge_monster_contribution_write(hit.write_id, error));

        honghuang::persistence::MonsterContributionRecord lethal = hit;
        lethal.write_id = "life-state-lethal";
        lethal.total_damage = 75;
        lethal.first_hit_at_ms = 900;
        lethal.last_hit_at_ms = 900;
        honghuang::persistence::PendingMonsterDeathRecord death;
        death.monster_instance_id = "life-state-1";
        death.runtime_id = "spawn-state-1";
        death.payload = R"({"version":1})";
        death.created_at_ms = 900;
        death.expected_health = 75.0;
        death.resulting_health = 0.0;
        assert(box.record_monster_contribution_and_pending_death(lethal, death, error));
        assert(!box.respawn_monster_life("life-state-1",
            honghuang::persistence::MonsterLifeStateRecord{
                "spawn-state-1", "premature-life", "wolf", 100.0}, error));
        states = box.load_monster_life_states(error);
        assert(error.empty() && states.size() == 1 && states.front().health == 0.0);

        const std::vector<honghuang::persistence::OutboxEvent> events{
            {"life-state-final", "bounty_objective_event", R"({"event_id":"life-state-final"})", 0, 0, 950, {}}
        };
        assert(box.finalize_monster_contributions("life-state-1", events, error));
        assert(box.respawn_monster_life("life-state-1",
            honghuang::persistence::MonsterLifeStateRecord{
                "spawn-state-1", "life-state-2", "wolf", 100.0}, error));
        states = box.load_monster_life_states(error);
        assert(error.empty() && states.size() == 1);
        assert(states.front().monster_instance_id == "life-state-2" && states.front().health == 100.0);
        assert(box.load_pending_monster_deaths(error).empty());
    }
    {
        honghuang::persistence::DurableOutbox reopened(life_state_path, 16);
        std::string error;
        honghuang::persistence::MonsterLifeStateRecord initial{
            "spawn-state-1", "random-startup-id", "wolf", 100.0};
        honghuang::persistence::MonsterLifeStateRecord persisted;
        assert(reopened.ensure_monster_life_state(initial, persisted, error));
        assert(persisted.monster_instance_id == "life-state-2" && persisted.health == 100.0);

        honghuang::persistence::MonsterLifeStateRecord legacy_initial{
            "spawn-legacy-death", "life-legacy-death", "wraith", 55.0};
        assert(reopened.ensure_monster_life_state(legacy_initial, persisted, error));
        assert(reopened.apply_monster_health_transition(
            "spawn-legacy-death", "life-legacy-death", 55.0, 45.0, error));
        honghuang::persistence::PendingMonsterDeathRecord legacy_death;
        legacy_death.monster_instance_id = "life-legacy-death";
        legacy_death.runtime_id = "spawn-legacy-death";
        legacy_death.payload = R"({"version":1,"reward_eligible":false})";
        legacy_death.created_at_ms = 1000;
        legacy_death.expected_health = 45.0;
        legacy_death.resulting_health = 0.0;
        assert(reopened.save_pending_monster_death(legacy_death, error));
        const auto legacy_states = reopened.load_monster_life_states(error);
        const auto legacy_state = std::find_if(legacy_states.begin(), legacy_states.end(),
            [](const auto& value) { return value.runtime_id == "spawn-legacy-death"; });
        assert(error.empty() && legacy_state != legacy_states.end() && legacy_state->health == 0.0);
        const std::vector<honghuang::persistence::OutboxEvent> no_reward_events{};
        assert(reopened.finalize_monster_contributions("life-legacy-death", no_reward_events, error));
        assert(reopened.respawn_monster_life("life-legacy-death",
            honghuang::persistence::MonsterLifeStateRecord{
                "spawn-legacy-death", "life-legacy-respawned", "wraith", 55.0}, error));
    }
    remove_database(life_state_path);

    return 0;
}
