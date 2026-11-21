#include "persistence/monster_death_finalizer.hpp"

#include <algorithm>
#include <nlohmann/json.hpp>
#include <stdexcept>
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
            const auto pending_deaths = outbox_.load_pending_monster_deaths(error);
            if (!error.empty()) {
                task.last_error = std::move(error);
            } else {
                const auto intent = std::find_if(
                    pending_deaths.begin(), pending_deaths.end(),
                    [&](const PendingMonsterDeathRecord& record) {
                        return record.monster_instance_id == task.monster_instance_id;
                    });
                if (intent == pending_deaths.end()) {
                    task.last_error = "pending monster death intent is missing from SQLite";
                } else if (!intent->prepared_events_json.empty()) {
                    try {
                        const auto encoded = nlohmann::json::parse(intent->prepared_events_json);
                        if (!encoded.is_array()) throw std::runtime_error("prepared death batch is not an array");
                        for (const auto& value : encoded) {
                            if (!value.is_object()) throw std::runtime_error("prepared death event is not an object");
                            OutboxEvent event;
                            event.event_id = value.at("event_id").get<std::string>();
                            event.event_type = value.at("event_type").get<std::string>();
                            event.payload = value.at("payload").get<std::string>();
                            event.attempts = value.value("attempts", 0U);
                            event.next_retry_at_ms = value.value("next_retry_at_ms", std::int64_t{});
                            event.created_at_ms = value.value("created_at_ms", std::int64_t{});
                            event.last_error = value.value("last_error", std::string{});
                            task.batch.push_back(std::move(event));
                        }
                        task.batch_prepared = true;
                        task.last_error.clear();
                    } catch (const std::exception& exception) {
                        task.batch.clear();
                        task.last_error = std::string("persisted monster death batch is invalid: ") + exception.what();
                    }
                } else {
                    const auto contributions =
                        outbox_.load_monster_contributions(task.monster_instance_id, error);
                    if (!error.empty()) {
                        task.last_error = std::move(error);
                    } else {
                        std::vector<OutboxEvent> batch;
                        try {
                            if (task.builder(contributions, batch, error)) {
                                nlohmann::json encoded = nlohmann::json::array();
                                for (const auto& event : batch) {
                                    encoded.push_back({
                                        {"event_id", event.event_id},
                                        {"event_type", event.event_type},
                                        {"payload", event.payload},
                                        {"attempts", event.attempts},
                                        {"next_retry_at_ms", event.next_retry_at_ms},
                                        {"created_at_ms", event.created_at_ms},
                                        {"last_error", event.last_error}
                                    });
                                }
                                if (outbox_.save_pending_monster_death_batch(
                                        task.monster_instance_id, encoded.dump(), error)) {
                                    task.batch = std::move(batch);
                                    task.batch_prepared = true;
                                    task.last_error.clear();
                                } else {
                                    task.last_error = std::move(error);
                                }
                            } else {
                                task.last_error = error.empty()
                                    ? "monster death event builder rejected the ledger snapshot"
                                    : std::move(error);
                            }
                        } catch (const std::exception& exception) {
                            task.last_error = std::string("monster death event builder threw: ") + exception.what();
                        } catch (...) {
                            task.last_error = "monster death event builder threw an unknown exception";
                        }
                    }
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
