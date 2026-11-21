#include "persistence/monster_contribution_writer.hpp"

#include <algorithm>
#include <stdexcept>
#include <utility>
#include <limits>

namespace honghuang::persistence {

MonsterContributionWriter::MonsterContributionWriter(DurableOutbox& outbox, std::size_t capacity)
    : outbox_(outbox), capacity_(capacity) {
    if (capacity_ == 0) throw std::invalid_argument("monster contribution queue capacity must be positive");
    std::string error;
    const auto recovered = outbox_.load_pending_monster_contribution_writes(
        std::numeric_limits<std::size_t>::max(), error);
    if (!error.empty()) throw std::runtime_error("failed to recover durable monster contributions: " + error);
    for (const auto& item : recovered) {
        pending_.push_back(item);
        ++pending_by_monster_[item.monster_instance_id];
    }
    worker_ = std::thread(&MonsterContributionWriter::run, this);
}

MonsterContributionWriter::~MonsterContributionWriter() {
    stop();
}

bool MonsterContributionWriter::submit(const MonsterContributionRecord& contribution, std::string& error) {
    if (contribution.write_id.empty() || contribution.monster_instance_id.empty()) {
        error = "monster contribution write and instance IDs are required";
        return false;
    }
    {
        std::lock_guard lock(mutex_);
        if (!accepting_ || stop_requested_) {
            error = "monster contribution writer is stopping or draining";
            return false;
        }
        const auto duplicate = std::find_if(pending_.begin(), pending_.end(),
            [&contribution](const MonsterContributionRecord& queued) {
                return queued.write_id == contribution.write_id;
            });
        if (duplicate != pending_.end()) {
            error = "monster contribution write ID is already pending; duplicate hit rejected";
            return false;
        }
        if (pending_.size() >= capacity_) {
            error = "monster contribution queue is full";
            return false;
        }
        if (!outbox_.admit_monster_contribution(contribution, error)) return false;
        pending_.push_back(contribution);
        ++pending_by_monster_[contribution.monster_instance_id];
    }
    cv_.notify_one();
    return true;
}

bool MonsterContributionWriter::submit_damage(
    const MonsterContributionRecord& contribution, const std::string& runtime_id,
    double expected_health, double resulting_health, std::string& error) {
    if (contribution.write_id.empty() || contribution.monster_instance_id.empty()) {
        error = "monster contribution write and instance IDs are required";
        return false;
    }
    {
        std::lock_guard lock(mutex_);
        if (!accepting_ || stop_requested_) {
            error = "monster contribution writer is stopping or draining";
            return false;
        }
        const auto duplicate = std::find_if(pending_.begin(), pending_.end(),
            [&contribution](const MonsterContributionRecord& queued) {
                return queued.write_id == contribution.write_id;
            });
        if (duplicate != pending_.end()) {
            error = "monster contribution write ID is already pending; duplicate hit rejected";
            return false;
        }
        if (pending_.size() >= capacity_) {
            error = "monster contribution queue is full";
            return false;
        }
        if (!outbox_.admit_monster_damage(
                contribution, runtime_id, expected_health, resulting_health, error)) return false;
        pending_.push_back(contribution);
        ++pending_by_monster_[contribution.monster_instance_id];
    }
    cv_.notify_one();
    return true;
}

bool MonsterContributionWriter::wait_until_drained(
    const std::string& monster_instance_id, std::chrono::milliseconds timeout) {
    if (monster_instance_id.empty()) return false;
    std::unique_lock lock(mutex_);
    return drained_cv_.wait_for(lock, timeout, [&] {
        return pending_by_monster_.find(monster_instance_id) == pending_by_monster_.end() ||
               stop_requested_;
    }) && pending_by_monster_.find(monster_instance_id) == pending_by_monster_.end();
}

std::size_t MonsterContributionWriter::pending_count() const {
    std::lock_guard lock(mutex_);
    return pending_.size();
}

std::size_t MonsterContributionWriter::pending_count_for_monster(
    const std::string& monster_instance_id) const {
    if (monster_instance_id.empty()) return 0;
    std::lock_guard lock(mutex_);
    const auto found = pending_by_monster_.find(monster_instance_id);
    return found == pending_by_monster_.end() ? 0 : found->second;
}

std::string MonsterContributionWriter::last_error() const {
    std::lock_guard lock(mutex_);
    return last_error_;
}

bool MonsterContributionWriter::stop_after_drain(std::chrono::milliseconds timeout) {
    bool drained = false;
    {
        std::unique_lock lock(mutex_);
        accepting_ = false;
        drained = drained_cv_.wait_for(lock, timeout, [&] {
            return pending_.empty() || stop_requested_;
        }) && pending_.empty();
        stop_requested_ = true;
    }
    cv_.notify_all();
    drained_cv_.notify_all();
    if (worker_.joinable()) worker_.join();
    return drained;
}

void MonsterContributionWriter::stop() {
    {
        std::lock_guard lock(mutex_);
        if (stop_requested_) return;
        accepting_ = false;
        stop_requested_ = true;
    }
    cv_.notify_all();
    drained_cv_.notify_all();
    if (worker_.joinable()) worker_.join();
}

void MonsterContributionWriter::run() {
    std::chrono::milliseconds retry_delay{100};
    while (true) {
        MonsterContributionRecord item;
        {
            std::unique_lock lock(mutex_);
            cv_.wait(lock, [&] { return stop_requested_ || !pending_.empty(); });
            if (stop_requested_) return;
            item = pending_.front();
        }

        std::string error;
        if (!outbox_.record_monster_contribution(item, error) ||
            !outbox_.acknowledge_monster_contribution_write(item.write_id, error)) {
            std::unique_lock lock(mutex_);
            last_error_ = error;
            cv_.wait_for(lock, retry_delay, [&] { return stop_requested_; });
            if (stop_requested_) return;
            retry_delay = std::min(retry_delay * 2, std::chrono::milliseconds{2000});
            continue; // Durable inbox row remains available for retry/restart.
        }

        {
            std::lock_guard lock(mutex_);
            if (!pending_.empty() && pending_.front().write_id == item.write_id) {
                pending_.pop_front();
                auto found = pending_by_monster_.find(item.monster_instance_id);
                if (found != pending_by_monster_.end()) {
                    if (found->second <= 1) pending_by_monster_.erase(found);
                    else --found->second;
                }
            }
            last_error_.clear();
        }
        retry_delay = std::chrono::milliseconds{100};
        drained_cv_.notify_all();
        cv_.notify_all();
    }
}

} // namespace honghuang::persistence
