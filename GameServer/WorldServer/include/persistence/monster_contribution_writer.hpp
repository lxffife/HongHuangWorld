#pragma once

#include "persistence/durable_outbox.hpp"

#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <deque>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>

namespace honghuang::persistence {

// Bounded asynchronous bridge between the combat thread and SQLite. A successful
// submit means accepted into this process-local queue, not yet durable; callers
// must apply backpressure before applying damage when submit returns false.
class MonsterContributionWriter {
public:
    explicit MonsterContributionWriter(DurableOutbox& outbox, std::size_t capacity = 32768);
    ~MonsterContributionWriter();

    MonsterContributionWriter(const MonsterContributionWriter&) = delete;
    MonsterContributionWriter& operator=(const MonsterContributionWriter&) = delete;

    bool submit(const MonsterContributionRecord& contribution, std::string& error);
    bool wait_until_drained(const std::string& monster_instance_id,
                            std::chrono::milliseconds timeout);
    std::size_t pending_count() const;
    std::string last_error() const;
    void stop();

private:
    void run();

    DurableOutbox& outbox_;
    const std::size_t capacity_;
    mutable std::mutex mutex_;
    std::condition_variable cv_;
    std::condition_variable drained_cv_;
    std::deque<MonsterContributionRecord> pending_;
    std::unordered_map<std::string, std::size_t> pending_by_monster_;
    std::thread worker_;
    bool stop_requested_{false};
    std::string last_error_;
};

} // namespace honghuang::persistence
