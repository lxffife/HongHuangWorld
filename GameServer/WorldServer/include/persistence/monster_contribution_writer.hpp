#pragma once

#include "persistence/durable_outbox.hpp"

#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <deque>
#include <mutex>
#include <string>
#include <type_traits>
#include <utility>
#include <thread>
#include <unordered_map>

namespace honghuang::persistence {

// Bounded asynchronous bridge between combat and SQLite. Damage submissions
// atomically commit the monster's new health and an immutable contribution inbox
// row before changing runtime memory. The inbox is replayed on restart.
class MonsterContributionWriter {
public:
    explicit MonsterContributionWriter(DurableOutbox& outbox, std::size_t capacity = 32768);
    ~MonsterContributionWriter();

    MonsterContributionWriter(const MonsterContributionWriter&) = delete;
    MonsterContributionWriter& operator=(const MonsterContributionWriter&) = delete;

    bool submit(const MonsterContributionRecord& contribution, std::string& error);
    bool submit_damage(const MonsterContributionRecord& contribution,
                       const std::string& runtime_id, double expected_health,
                       double resulting_health, std::string& error);

    // Commit health and the contribution inbox atomically before mutating memory.
    template <typename ApplyDamage>
    bool submit_damage_before_mutation(const MonsterContributionRecord& contribution,
                                       const std::string& runtime_id, double expected_health,
                                       double resulting_health, ApplyDamage&& apply_damage,
                                       std::string& error) {
        static_assert(noexcept(std::declval<ApplyDamage&>()()),
                      "damage mutation callback must be noexcept");
        if (!submit_damage(contribution, runtime_id, expected_health, resulting_health, error))
            return false;
        std::forward<ApplyDamage>(apply_damage)();
        return true;
    }

    // Legacy admission helper; new combat paths should use submit_damage_before_mutation.
    template <typename ApplyDamage>
    bool submit_before_damage(const MonsterContributionRecord& contribution,
                              ApplyDamage&& apply_damage, std::string& error) {
        static_assert(noexcept(std::declval<ApplyDamage&>()()),
                      "damage mutation callback must be noexcept");
        if (!submit(contribution, error)) return false;
        std::forward<ApplyDamage>(apply_damage)();
        return true;
    }

    bool wait_until_drained(const std::string& monster_instance_id,
                            std::chrono::milliseconds timeout);
    std::size_t pending_count() const;
    // Non-blocking per-life count for world-loop state machines. Includes the
    // record currently being committed by the worker, not just queued records.
    std::size_t pending_count_for_monster(const std::string& monster_instance_id) const;
    std::string last_error() const;
    // Stop accepting writes, wait up to timeout for inbox aggregation/acknowledgement, then join.
    // Returns false when the queue could not be fully committed before the deadline.
    bool stop_after_drain(std::chrono::milliseconds timeout);
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
    bool accepting_{true};
    bool stop_requested_{false};
    std::string last_error_;
};

} // namespace honghuang::persistence
