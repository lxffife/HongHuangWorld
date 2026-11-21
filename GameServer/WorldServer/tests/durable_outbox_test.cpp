#include "persistence/durable_outbox.hpp"

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
    return 0;
}
