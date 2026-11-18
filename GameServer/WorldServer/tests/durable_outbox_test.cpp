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
            R"({"session_id":"s1","client_message_id":"client-1"})",
            0, 500, 500, {}
        };
        assert(box.enqueue(chat, error));
        assert(box.enqueue(chat, error));
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
        assert(!gameplay_event); // Gameplay workers never claim chat traffic.
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
    return 0;
}
