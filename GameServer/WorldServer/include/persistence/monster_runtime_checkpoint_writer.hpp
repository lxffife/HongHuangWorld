#pragma once

#include "persistence/durable_outbox.hpp"

#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>

namespace honghuang::persistence {

// Coalescing, bounded asynchronous checkpoint writer. One latest snapshot per
// spawn runtime is retained; SQLite is touched only by this worker thread.
class MonsterRuntimeCheckpointWriter {
public:
    explicit MonsterRuntimeCheckpointWriter(
        DurableOutbox& outbox, std::size_t capacity = 4096,
        std::chrono::milliseconds flush_interval = std::chrono::milliseconds{1000});
    ~MonsterRuntimeCheckpointWriter();

    MonsterRuntimeCheckpointWriter(const MonsterRuntimeCheckpointWriter&) = delete;
    MonsterRuntimeCheckpointWriter& operator=(const MonsterRuntimeCheckpointWriter&) = delete;

    bool submit(const MonsterRuntimeCheckpointRecord& checkpoint, std::string& error);
    bool wait_until_drained(std::chrono::milliseconds timeout);
    std::size_t pending_count() const;
    std::string last_error() const;
    bool stop_after_drain(std::chrono::milliseconds timeout);
    void stop();

private:
    void run();

    DurableOutbox& outbox_;
    const std::size_t capacity_;
    const std::chrono::milliseconds flush_interval_;
    mutable std::mutex mutex_;
    std::condition_variable cv_;
    std::condition_variable drained_cv_;
    std::unordered_map<std::string, MonsterRuntimeCheckpointRecord> pending_;
    std::thread worker_;
    bool accepting_{true};
    bool stop_requested_{false};
    bool in_flight_{false};
    std::chrono::steady_clock::time_point stop_deadline_{};
    std::string last_error_;
};

} // namespace honghuang::persistence
