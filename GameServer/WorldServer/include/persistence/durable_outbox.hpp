#pragma once
#include <cstdint>
#include <mutex>
#include <optional>
#include <string>
#include <cstddef>
struct sqlite3;
namespace honghuang::persistence {
struct OutboxEvent { std::string event_id; std::string event_type; std::string payload; std::uint32_t attempts{}; std::int64_t next_retry_at_ms{}; std::int64_t created_at_ms{}; std::string last_error; };
class DurableOutbox {
public:
 explicit DurableOutbox(const std::string& database_path, std::size_t capacity = 10000);
 ~DurableOutbox();
 DurableOutbox(const DurableOutbox&) = delete; DurableOutbox& operator=(const DurableOutbox&) = delete;
 bool enqueue(const OutboxEvent& event, std::string& error);
 std::optional<OutboxEvent> claim_due(std::int64_t now_ms, std::string& error);
 bool mark_delivered(const std::string& event_id, std::string& error);
 bool schedule_retry(const std::string& event_id, std::uint32_t attempts, std::int64_t next_retry_at_ms, const std::string& error_text, std::string& error);
 bool move_to_dead_letter(const std::string& event_id, std::uint32_t attempts, const std::string& error_text, std::string& error);
 std::size_t pending_count(std::string& error) const;
private:
 sqlite3* db_{}; std::size_t capacity_{}; mutable std::mutex mutex_;
 bool execute(const char* sql, std::string& error) const;
};
}
