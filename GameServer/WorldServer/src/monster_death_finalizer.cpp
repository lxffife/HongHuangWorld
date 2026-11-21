#include "persistence/monster_death_finalizer.hpp"

#include <algorithm>
#include <utility>

namespace honghuang::persistence {

MonsterDeathFinalizer::MonsterDeathFinalizer(
    DurableOutbox& outbox, MonsterContributionWriter& writer)
    : outbox_(outbox), writer_(writer), worker_(&MonsterDeathFinalizer::run, this) {}

MonsterDeathFinalizer::~MonsterDeathFinalizer() { stop(); }

bool MonsterDeathFinalizer::submit(
    const std::string& monster_instance_id, EventBuilder builder, std::string& error) {
    if (monster_instance_id.empty() || !builder) {
        error = "monster death finalization requires an instance ID and event builder";
        return false;
    }
    {
        std::lock_guard lock(mutex_);
        if (!accepting_ || stop_requested_) {
            error = "monster death finalizer is stopping";
            return false;
        }
        if (!active_instances_.insert(monster_instance_id).second) {
            error = "monster death finalization is already pending for this life";
            return false;
        }
        pending_.push_back(Task{monster_instance_id, std::move(builder), false, {}, {}});
    }
    cv_.notify_one();
    return true;
}

std::vector<MonsterDeathFinalizer::Result> MonsterDeathFinalizer::take_results() {
    std::vector<Result> results;
    std::lock_guard lock(mutex_);
    results.reserve(completed_.size());
    while (!completed_.empty()) {
        results.push_back(std::move(completed_.front()));
        completed_.pop_front();
    }
    return results;
}

std::size_t MonsterDeathFinalizer::pending_count() const {
    std::lock_guard lock(mutex_);
    return active_instances_.size();
}

bool MonsterDeathFinalizer::stop_after_drain(std::chrono::milliseconds timeout) {
    bool drained = false;
    {
        std::unique_lock lock(mutex_);
        accepting_ = false;
        drained = drained_cv_.wait_for(lock, timeout, [&] {
            return active_instances_.empty() || stop_requested_;
        }) && active_instances_.empty();
        stop_requested_ = true;
    }
    cv_.notify_all();
    if (worker_.joinable()) worker_.join();
    return drained;
}

void MonsterDeathFinalizer::stop() {
    {
        std::lock_guard lock(mutex_);
        if (stop_requested_) return;
        accepting_ = false;
        stop_requested_ = true;
    }
    cv_.notify_all();
    if (worker_.joinable()) worker_.join();
}

void MonsterDeathFinalizer::run() {
    std::chrono::milliseconds retry_delay{50};
    Task task;
    bool has_task = false;
    while (true) {
        if (!has_task) {
            std::unique_lock lock(mutex_);
            cv_.wait(lock, [&] { return stop_requested_ || !pending_.empty(); });
            if (stop_requested_) return;
            task = std::move(pending_.front());
            pending_.pop_front();
            has_task = true;
        }

        if (writer_.pending_count_for_monster(task.monster_instance_id) != 0) {
            std::unique_lock lock(mutex_);
            cv_.wait_for(lock, retry_delay, [&] { return stop_requested_; });
            if (stop_requested_) return;
            retry_delay = std::min(retry_delay * 2, std::chrono::milliseconds{500});
            continue;
        }

        if (!task.batch_prepared) {
            std::string error;
            const auto contributions =
                outbox_.load_monster_contributions(task.monster_instance_id, error);
            if (!error.empty()) {
                task.last_error = std::move(error);
            } else {
                std::vector<OutboxEvent> batch;
                if (task.builder(contributions, batch, error)) {
                    task.batch = std::move(batch);
                    task.batch_prepared = true;
                    task.last_error.clear();
                } else {
                    task.last_error = error.empty()
                        ? "monster death event builder rejected the ledger snapshot"
                        : std::move(error);
                }
            }
        }

        if (task.batch_prepared) {
            std::string error;
            if (outbox_.finalize_monster_contributions(
                    task.monster_instance_id, task.batch, error)) {
                {
                    std::lock_guard lock(mutex_);
                    completed_.push_back(Result{task.monster_instance_id, true, {}});
                    active_instances_.erase(task.monster_instance_id);
                }
                drained_cv_.notify_all();
                cv_.notify_all();
                has_task = false;
                retry_delay = std::chrono::milliseconds{50};
                continue;
            }
            task.last_error = std::move(error);
        }

        {
            std::unique_lock lock(mutex_);
            cv_.wait_for(lock, retry_delay, [&] { return stop_requested_; });
            if (stop_requested_) return;
        }
        retry_delay = std::min(retry_delay * 2, std::chrono::milliseconds{2000});
    }
}

} // namespace honghuang::persistence
