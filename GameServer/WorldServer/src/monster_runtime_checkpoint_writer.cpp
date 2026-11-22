#include "persistence/monster_runtime_checkpoint_writer.hpp"

#include <algorithm>
#include <stdexcept>
#include <utility>
#include <vector>

namespace honghuang::persistence {

MonsterRuntimeCheckpointWriter::MonsterRuntimeCheckpointWriter(
    DurableOutbox& outbox, std::size_t capacity, std::chrono::milliseconds flush_interval)
    : outbox_(outbox), capacity_(capacity), flush_interval_(flush_interval) {
    if (capacity_ == 0 || flush_interval_ <= std::chrono::milliseconds::zero())
        throw std::invalid_argument("invalid monster checkpoint writer capacity or interval");
    worker_ = std::thread(&MonsterRuntimeCheckpointWriter::run, this);
}

MonsterRuntimeCheckpointWriter::~MonsterRuntimeCheckpointWriter() {
    stop();
}

bool MonsterRuntimeCheckpointWriter::submit(
    const MonsterRuntimeCheckpointRecord& checkpoint, std::string& error) {
    error.clear();
    if (checkpoint.runtime_id.empty() || checkpoint.monster_instance_id.empty() ||
        checkpoint.monster_definition_id.empty() || checkpoint.checkpoint_at_ms <= 0) {
        error = "invalid monster checkpoint submission";
        return false;
    }
    {
        std::lock_guard lock(mutex_);
        if (!accepting_ || stop_requested_) {
            error = "monster checkpoint writer is stopping";
            return false;
        }
        const auto found = pending_.find(checkpoint.runtime_id);
        if (found == pending_.end()) {
            if (pending_.size() >= capacity_) {
                error = "monster checkpoint queue is full";
                return false;
            }
            pending_.emplace(checkpoint.runtime_id, checkpoint);
        } else if (checkpoint.checkpoint_at_ms >= found->second.checkpoint_at_ms) {
            found->second = checkpoint;
        }
    }
    cv_.notify_one();
    return true;
}

bool MonsterRuntimeCheckpointWriter::wait_until_drained(std::chrono::milliseconds timeout) {
    std::unique_lock lock(mutex_);
    return drained_cv_.wait_for(lock, timeout, [&] { return pending_.empty() && !in_flight_; });
}

std::size_t MonsterRuntimeCheckpointWriter::pending_count() const {
    std::lock_guard lock(mutex_);
    return pending_.size() + (in_flight_ ? 1U : 0U);
}

std::string MonsterRuntimeCheckpointWriter::last_error() const {
    std::lock_guard lock(mutex_);
    return last_error_;
}

bool MonsterRuntimeCheckpointWriter::stop_after_drain(std::chrono::milliseconds timeout) {
    {
        std::lock_guard lock(mutex_);
        accepting_ = false;
        stop_requested_ = true;
        stop_deadline_ = std::chrono::steady_clock::now() + std::max(timeout, std::chrono::milliseconds::zero());
    }
    cv_.notify_all();
    bool drained = false;
    {
        std::unique_lock lock(mutex_);
        drained = drained_cv_.wait_for(lock, timeout, [&] { return pending_.empty() && !in_flight_; });
    }
    if (worker_.joinable()) worker_.join();
    return drained;
}

void MonsterRuntimeCheckpointWriter::stop() {
    if (!worker_.joinable()) return;
    (void)stop_after_drain(std::chrono::seconds(5));
}

void MonsterRuntimeCheckpointWriter::run() {
    constexpr std::size_t kBatchLimit = 256;
    std::chrono::milliseconds retry_delay{100};
    while (true) {
        std::vector<MonsterRuntimeCheckpointRecord> batch;
        {
            std::unique_lock lock(mutex_);
            cv_.wait_for(lock, flush_interval_, [&] {
                return stop_requested_ || pending_.size() >= kBatchLimit;
            });
            if (stop_requested_ && pending_.empty()) {
                drained_cv_.notify_all();
                return;
            }
            if (stop_requested_ && std::chrono::steady_clock::now() >= stop_deadline_) {
                drained_cv_.notify_all();
                return;
            }
            if (pending_.empty()) continue;
            batch.reserve(std::min(pending_.size(), kBatchLimit));
            for (auto it = pending_.begin(); it != pending_.end() && batch.size() < kBatchLimit;) {
                batch.push_back(std::move(it->second));
                it = pending_.erase(it);
            }
            in_flight_ = true;
        }

        std::string error;
        const bool saved = outbox_.save_monster_runtime_checkpoints(batch, error);
        {
            std::lock_guard lock(mutex_);
            in_flight_ = false;
            if (saved) {
                last_error_.clear();
                retry_delay = std::chrono::milliseconds{100};
            } else {
                last_error_ = error;
                for (const auto& checkpoint : batch) {
                    const auto found = pending_.find(checkpoint.runtime_id);
                    if (found == pending_.end()) {
                        pending_.emplace(checkpoint.runtime_id, checkpoint);
                    } else if (checkpoint.checkpoint_at_ms > found->second.checkpoint_at_ms) {
                        found->second = checkpoint;
                    }
                }
            }
        }
        drained_cv_.notify_all();
        cv_.notify_all();
        if (!saved) {
            std::unique_lock lock(mutex_);
            if (stop_requested_ && std::chrono::steady_clock::now() >= stop_deadline_) {
                drained_cv_.notify_all();
                return;
            }
            cv_.wait_for(lock, retry_delay);
            retry_delay = std::min(retry_delay * 2, std::chrono::milliseconds{2000});
        }
    }
}

} // namespace honghuang::persistence
