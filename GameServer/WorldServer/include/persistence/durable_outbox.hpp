#pragma once
#include <cstdint>
#include <mutex>
#include <optional>
#include <string>
#include <vector>
#include <cstddef>
struct sqlite3;
namespace honghuang::persistence {
struct OutboxStats { std::size_t pending{}; std::size_t inflight{}; std::size_t delivered{}; std::size_t dead_letter{}; std::int64_t oldest_pending_age_ms{}; std::int64_t oldest_dead_letter_age_ms{}; };
struct MonsterContributionRecord {
 std::string write_id;
 std::string monster_instance_id;
 std::string monster_definition_id;
 std::string session_id;
 std::string character_id;
 std::int64_t total_damage{};
 std::int64_t hit_count{};
 std::int64_t first_hit_at_ms{};
 std::int64_t last_hit_at_ms{};
 // Complete, deduplicated objective-subscription JSON supplied by the caller.
 std::string bounty_objectives_json{"[]"};
};
struct PendingMonsterDeathRecord {
 std::string monster_instance_id;
 std::string runtime_id;
 std::string payload;
 std::string prepared_events_json;
 std::int64_t created_at_ms{};
 std::int64_t committed_at_ms{};
};
struct OutboxEvent { std::string event_id; std::string event_type; std::string payload; std::uint32_t attempts{}; std::int64_t next_retry_at_ms{}; std::int64_t created_at_ms{}; std::string last_error; };
class DurableOutbox {
public:
 explicit DurableOutbox(const std::string& database_path, std::size_t capacity = 10000, bool recover_inflight = true);
 ~DurableOutbox();
 DurableOutbox(const DurableOutbox&) = delete; DurableOutbox& operator=(const DurableOutbox&) = delete;
 bool enqueue(const OutboxEvent& event, std::string& error);
 bool enqueue_batch(const std::vector<OutboxEvent>& events, std::string& error);
 bool record_monster_contribution(const MonsterContributionRecord& contribution, std::string& error);
 // Persist immutable death context before any finalization task is admitted.
 bool save_pending_monster_death(const PendingMonsterDeathRecord& death, std::string& error);
 bool save_pending_monster_death_batch(const std::string& monster_instance_id,
                                       const std::string& events_json, std::string& error);
 std::vector<PendingMonsterDeathRecord> load_pending_monster_deaths(std::string& error) const;
 bool acknowledge_monster_death_respawn(const std::string& monster_instance_id, std::string& error);
 std::vector<MonsterContributionRecord> load_monster_contributions(const std::string& monster_instance_id, std::string& error) const;
 // Atomically enqueue the death snapshot, clear live ledger rows, and mark the death committed.
 bool finalize_monster_contributions(const std::string& monster_instance_id,
                                     const std::vector<OutboxEvent>& events, std::string& error);
 std::optional<OutboxEvent> find(const std::string& event_id, std::string& error) const;
 std::optional<OutboxEvent> claim_due(std::int64_t now_ms, std::string& error);
 std::optional<OutboxEvent> claim_due_type(std::int64_t now_ms, const std::string& event_type, std::string& error);
 std::optional<OutboxEvent> claim_due_excluding(std::int64_t now_ms, const std::string& event_type, std::string& error);
 bool mark_delivered(const std::string& event_id, std::string& error);
 bool schedule_retry(const std::string& event_id, std::uint32_t attempts, std::int64_t next_retry_at_ms, const std::string& error_text, std::string& error);
 bool move_to_dead_letter(const std::string& event_id, std::uint32_t attempts, const std::string& error_text, std::string& error);
 std::size_t pending_count(std::string& error) const;
 OutboxStats stats(std::int64_t now_ms, std::string& error, const std::string& event_type = {}) const;
 std::vector<OutboxEvent> list_dead_letters(std::size_t limit, const std::string& event_type, std::string& error) const;
 bool retry_dead_letter(const std::string& event_id, std::int64_t now_ms, std::string& error);
private:
 sqlite3* db_{}; std::size_t capacity_{}; mutable std::mutex mutex_;
 std::optional<OutboxEvent> claim_due_filtered(std::int64_t now_ms, const std::string& event_type, bool exclude, std::string& error);
 bool execute(const char* sql, std::string& error) const;
};
}
