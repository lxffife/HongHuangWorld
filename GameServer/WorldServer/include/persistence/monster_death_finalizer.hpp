#pragma once

#include "persistence/durable_outbox.hpp"
#include "persistence/monster_contribution_writer.hpp"

#include <chrono>
#include <condition_variable>
#include <deque>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_set>
#include <vector>

namespace honghuang::persistence {

// Performs the SQLite drain -> ledger snapshot -> atomic outbox finalization
// sequence away from the authoritative simulation thread. The event builder is
// invoked once per life; its exact batch is retained across finalize retries.
class MonsterDeathFinalizer {
public:
    using EventBuilder = std::function<bool(
        const std::vector<MonsterContributionRecord>&,
        std::vector<OutboxEvent>&, std::string&)>;

    struct Result {
        std::string monster_instance_id;
        bool success{};
        std::string error;
    };

    MonsterDeathFinalizer(DurableOutbox& outbox, MonsterContributionWriter& writer);
    ~MonsterDeathFinalizer();

    MonsterDeathFinalizer(const MonsterDeathFinalizer&) = delete;
    MonsterDeathFinalizer& operator=(const MonsterDeathFinalizer&) = delete;

    bool submit(const std::string& monster_instance_id, EventBuilder builder,
                std::string& error);
    std::vector<Result> take_results();
    std::size_t pending_count() const;
    bool stop_after_drain(std::chrono::milliseconds timeout);
    void stop();

private:
    struct Task {
        std::string monster_instance_id;
        EventBuilder builder;
        bool batch_prepared{};
        std::vector<OutboxEvent> batch;
        std::string last_error;
    };

    void run();

    DurableOutbox& outbox_;
    MonsterContributionWriter& writer_;
    mutable std::mutex mutex_;
    std::condition_variable cv_;
    std::condition_variable drained_cv_;
    std::deque<Task> pending_;
    std::deque<Result> completed_;
    std::unordered_set<std::string> active_instances_;
    std::thread worker_;
    bool accepting_{true};
    bool stop_requested_{false};
};

} // namespace honghuang::persistence
