#include "persistence/durable_outbox.hpp"

#include <sqlite3.h>

#include <algorithm>
#include <stdexcept>
#include <utility>

namespace honghuang::persistence {
namespace {
class Stmt {
public:
    Stmt(sqlite3* db, const char* sql) {
        if (sqlite3_prepare_v2(db, sql, -1, &stmt_, nullptr) != SQLITE_OK) {
            throw std::runtime_error(sqlite3_errmsg(db));
        }
    }
    ~Stmt() { sqlite3_finalize(stmt_); }
    sqlite3_stmt* get() const { return stmt_; }
private:
    sqlite3_stmt* stmt_{};
};

void bind_text(sqlite3_stmt* stmt, int index, const std::string& value) {
    if (sqlite3_bind_text(stmt, index, value.c_str(),
                          static_cast<int>(value.size()), SQLITE_TRANSIENT) != SQLITE_OK) {
        throw std::runtime_error("failed to bind outbox text");
    }
}

std::string column_text(sqlite3_stmt* stmt, int index) {
    const auto* value = sqlite3_column_text(stmt, index);
    return value == nullptr ? std::string{} :
        std::string(reinterpret_cast<const char*>(value));
}
} // namespace

DurableOutbox::DurableOutbox(const std::string& path, std::size_t capacity, bool recover_inflight)
    : capacity_(capacity) {
    if (path.empty() || capacity_ == 0) {
        throw std::invalid_argument("invalid outbox path or capacity");
    }
    if (sqlite3_open_v2(path.c_str(), &db_,
                        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                        nullptr) != SQLITE_OK) {
        const std::string message = db_ ? sqlite3_errmsg(db_) : "cannot open sqlite database";
        if (db_ != nullptr) sqlite3_close(db_);
        db_ = nullptr;
        throw std::runtime_error(message);
    }

    sqlite3_busy_timeout(db_, 5000);
    const char* schema =
        "PRAGMA journal_mode=WAL;"
        "PRAGMA synchronous=FULL;"
        "PRAGMA foreign_keys=ON;"
        "CREATE TABLE IF NOT EXISTS world_event_outbox("
        "event_id TEXT PRIMARY KEY NOT NULL,event_type TEXT NOT NULL,payload TEXT NOT NULL,"
        "status TEXT NOT NULL CHECK(status IN('pending','inflight','delivered','dead_letter')),"
        "attempts INTEGER NOT NULL DEFAULT 0,next_retry_at_ms INTEGER NOT NULL,"
        "created_at_ms INTEGER NOT NULL,updated_at_ms INTEGER NOT NULL,last_error TEXT NOT NULL DEFAULT '');"
        "CREATE INDEX IF NOT EXISTS idx_world_event_outbox_due "
        "ON world_event_outbox(status,next_retry_at_ms,created_at_ms);"
        "CREATE TABLE IF NOT EXISTS monster_damage_contributions("
        "monster_instance_id TEXT NOT NULL,monster_definition_id TEXT NOT NULL,"
        "session_id TEXT NOT NULL,character_id TEXT NOT NULL,total_damage INTEGER NOT NULL,"
        "hit_count INTEGER NOT NULL,first_hit_at_ms INTEGER NOT NULL,last_hit_at_ms INTEGER NOT NULL,"
        "bounty_objectives_json TEXT NOT NULL DEFAULT '[]',"
        "PRIMARY KEY(monster_instance_id,session_id,character_id));"
        "CREATE INDEX IF NOT EXISTS idx_monster_damage_contributions_instance "
        "ON monster_damage_contributions(monster_instance_id);"
        "CREATE TABLE IF NOT EXISTS monster_damage_contribution_writes("
        "write_id TEXT PRIMARY KEY NOT NULL,monster_instance_id TEXT NOT NULL,session_id TEXT NOT NULL,"
        "character_id TEXT NOT NULL,monster_definition_id TEXT NOT NULL,damage INTEGER NOT NULL,hit_count INTEGER NOT NULL,"
        "first_hit_at_ms INTEGER NOT NULL,last_hit_at_ms INTEGER NOT NULL,bounty_objectives_json TEXT NOT NULL);"
        "CREATE INDEX IF NOT EXISTS idx_monster_contribution_writes_instance "
        "ON monster_damage_contribution_writes(monster_instance_id);";
    char* message = nullptr;
    if (sqlite3_exec(db_, schema, nullptr, nullptr, &message) != SQLITE_OK) {
        const std::string error = message ? message : sqlite3_errmsg(db_);
        sqlite3_free(message);
        sqlite3_close(db_);
        db_ = nullptr;
        throw std::runtime_error(error);
    }
    if (recover_inflight) {
        if (sqlite3_exec(db_, "UPDATE world_event_outbox SET status='pending' WHERE status='inflight';", nullptr, nullptr, &message) != SQLITE_OK) {
            const std::string error = message ? message : sqlite3_errmsg(db_);
            sqlite3_free(message);
            sqlite3_close(db_);
            db_ = nullptr;
            throw std::runtime_error(error);
        }
    }
}

DurableOutbox::~DurableOutbox() {
    if (db_ != nullptr) sqlite3_close(db_);
}

bool DurableOutbox::execute(const char* sql, std::string& error) const {
    char* message = nullptr;
    const int result = sqlite3_exec(db_, sql, nullptr, nullptr, &message);
    if (result == SQLITE_OK) return true;
    error = message ? message : sqlite3_errmsg(db_);
    sqlite3_free(message);
    return false;
}

bool DurableOutbox::enqueue(const OutboxEvent& event, std::string& error) {
    if (event.event_id.empty() || event.event_type.empty() || event.payload.empty()) {
        error = "event id/type/payload required";
        return false;
    }

    std::lock_guard lock(mutex_);
    bool transaction_open = false;
    try {
        if (!execute("BEGIN IMMEDIATE", error)) return false;
        transaction_open = true;

        // A repeated event ID is idempotent only when it represents the exact same event.
        Stmt existing(db_, "SELECT event_type,payload,status FROM world_event_outbox WHERE event_id=?");
        bind_text(existing.get(), 1, event.event_id);
        const int existing_result = sqlite3_step(existing.get());
        if (existing_result == SQLITE_ROW) {
            const bool dead_letter = column_text(existing.get(), 2) == "dead_letter";
            const bool same = column_text(existing.get(), 0) == event.event_type &&
                              column_text(existing.get(), 1) == event.payload && !dead_letter;
            if (!execute("COMMIT", error)) {
                std::string ignored;
                execute("ROLLBACK", ignored);
                transaction_open = false;
                return false;
            }
            transaction_open = false;
            if (!same) error = dead_letter ? "event is in the dead-letter queue" : "event id already exists with a different type or payload";
            return same;
        }
        if (existing_result != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));

        Stmt count(db_, "SELECT COUNT(*) FROM world_event_outbox WHERE status IN('pending','inflight')");
        if (sqlite3_step(count.get()) != SQLITE_ROW) throw std::runtime_error(sqlite3_errmsg(db_));
        const auto active_count = static_cast<std::size_t>(sqlite3_column_int64(count.get(), 0));
        if (active_count >= capacity_) {
            error = "durable outbox capacity reached";
            std::string ignored;
            execute("ROLLBACK", ignored);
            transaction_open = false;
            return false;
        }
        if (event.event_type == "nearby_chat") {
            const auto chat_capacity = std::min<std::size_t>(std::max<std::size_t>(1, capacity_ / 2), 2000);
            Stmt chat_count(db_, "SELECT COUNT(*) FROM world_event_outbox WHERE event_type='nearby_chat' AND status IN('pending','inflight')");
            if (sqlite3_step(chat_count.get()) != SQLITE_ROW) throw std::runtime_error(sqlite3_errmsg(db_));
            const auto active_chat_count = static_cast<std::size_t>(sqlite3_column_int64(chat_count.get(), 0));
            if (active_chat_count >= chat_capacity) {
                error = "nearby chat outbox capacity reached";
                std::string ignored;
                execute("ROLLBACK", ignored);
                transaction_open = false;
                return false;
            }
        }

        Stmt insert(db_,
            "INSERT INTO world_event_outbox(event_id,event_type,payload,status,attempts,"
            "next_retry_at_ms,created_at_ms,updated_at_ms) VALUES(?,?,?,'pending',?,?,?,?)");
        bind_text(insert.get(), 1, event.event_id);
        bind_text(insert.get(), 2, event.event_type);
        bind_text(insert.get(), 3, event.payload);
        sqlite3_bind_int64(insert.get(), 4, event.attempts);
        sqlite3_bind_int64(insert.get(), 5, event.next_retry_at_ms);
        sqlite3_bind_int64(insert.get(), 6, event.created_at_ms);
        sqlite3_bind_int64(insert.get(), 7, event.created_at_ms);
        if (sqlite3_step(insert.get()) != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));

        if (!execute("COMMIT", error)) {
            std::string ignored;
            execute("ROLLBACK", ignored);
            transaction_open = false;
            return false;
        }
        transaction_open = false;
        return true;
    } catch (const std::exception& exception) {
        if (transaction_open) {
            std::string ignored;
            execute("ROLLBACK", ignored);
        }
        error = exception.what();
        return false;
    }
}


bool DurableOutbox::enqueue_batch(const std::vector<OutboxEvent>& events, std::string& error) {
    if (events.empty()) { error = "outbox batch must not be empty"; return false; }
    for (const auto& event : events) {
        if (event.event_id.empty() || event.event_type.empty() || event.event_type == "nearby_chat" || event.payload.empty()) {
            error = "monster finalization requires non-chat events with id/type/payload";
            return false;
        }
    }

    std::lock_guard lock(mutex_);
    bool transaction_open = false;
    try {
        if (!execute("BEGIN IMMEDIATE", error)) return false;
        transaction_open = true;

        std::vector<std::string> batch_ids;
        batch_ids.reserve(events.size());
        std::size_t new_count = 0;
        std::size_t new_chat_count = 0;
        for (const auto& event : events) {
            if (std::find(batch_ids.begin(), batch_ids.end(), event.event_id) != batch_ids.end()) {
                throw std::runtime_error("duplicate event id inside outbox batch");
            }
            batch_ids.push_back(event.event_id);

            Stmt existing(db_, "SELECT event_type,payload,status FROM world_event_outbox WHERE event_id=?");
            bind_text(existing.get(), 1, event.event_id);
            const int result = sqlite3_step(existing.get());
            if (result == SQLITE_ROW) {
                const auto status = column_text(existing.get(), 2);
                const bool same = column_text(existing.get(), 0) == event.event_type &&
                                  column_text(existing.get(), 1) == event.payload &&
                                  status != "dead_letter";
                if (!same) throw std::runtime_error("event id already exists with a different payload or is dead-lettered");
            } else if (result == SQLITE_DONE) {
                ++new_count;
                if (event.event_type == "nearby_chat") ++new_chat_count;
            } else {
                throw std::runtime_error(sqlite3_errmsg(db_));
            }
        }

        Stmt count(db_, "SELECT COUNT(*) FROM world_event_outbox WHERE status IN('pending','inflight')");
        if (sqlite3_step(count.get()) != SQLITE_ROW) throw std::runtime_error(sqlite3_errmsg(db_));
        const auto active_count = static_cast<std::size_t>(sqlite3_column_int64(count.get(), 0));
        if (new_count > capacity_ || active_count > capacity_ - new_count) {
            throw std::runtime_error("durable outbox capacity reached");
        }

        const auto chat_capacity = std::min<std::size_t>(std::max<std::size_t>(1, capacity_ / 2), 2000);
        if (new_chat_count > 0) {
            Stmt chat_count(db_, "SELECT COUNT(*) FROM world_event_outbox WHERE event_type='nearby_chat' AND status IN('pending','inflight')");
            if (sqlite3_step(chat_count.get()) != SQLITE_ROW) throw std::runtime_error(sqlite3_errmsg(db_));
            const auto active_chat_count = static_cast<std::size_t>(sqlite3_column_int64(chat_count.get(), 0));
            if (new_chat_count > chat_capacity || active_chat_count > chat_capacity - new_chat_count) {
                throw std::runtime_error("nearby chat outbox capacity reached");
            }
        }

        for (const auto& event : events) {
            Stmt existing(db_, "SELECT 1 FROM world_event_outbox WHERE event_id=?");
            bind_text(existing.get(), 1, event.event_id);
            if (sqlite3_step(existing.get()) == SQLITE_ROW) continue;
            Stmt insert(db_,
                "INSERT INTO world_event_outbox(event_id,event_type,payload,status,attempts,"
                "next_retry_at_ms,created_at_ms,updated_at_ms) VALUES(?,?,?,'pending',?,?,?,?)");
            bind_text(insert.get(), 1, event.event_id);
            bind_text(insert.get(), 2, event.event_type);
            bind_text(insert.get(), 3, event.payload);
            sqlite3_bind_int64(insert.get(), 4, event.attempts);
            sqlite3_bind_int64(insert.get(), 5, event.next_retry_at_ms);
            sqlite3_bind_int64(insert.get(), 6, event.created_at_ms);
            sqlite3_bind_int64(insert.get(), 7, event.created_at_ms);
            if (sqlite3_step(insert.get()) != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
        }

        if (!execute("COMMIT", error)) {
            std::string ignored;
            execute("ROLLBACK", ignored);
            transaction_open = false;
            return false;
        }
        transaction_open = false;
        return true;
    } catch (const std::exception& exception) {
        if (transaction_open) {
            std::string ignored;
            execute("ROLLBACK", ignored);
        }
        error = exception.what();
        return false;
    }
}


bool DurableOutbox::record_monster_contribution(
    const MonsterContributionRecord& item, std::string& error) {
    if (item.write_id.empty() || item.write_id.size() > 128 ||
        item.monster_instance_id.empty() || item.monster_instance_id.size() > 96 ||
        item.monster_definition_id.empty() || item.monster_definition_id.size() > 64 ||
        item.session_id.empty() || item.character_id.empty() ||
        item.total_damage <= 0 || item.hit_count <= 0 ||
        item.first_hit_at_ms <= 0 || item.last_hit_at_ms < item.first_hit_at_ms ||
        item.bounty_objectives_json.empty()) {
        error = "invalid monster contribution record";
        return false;
    }
    std::lock_guard lock(mutex_);
    bool transaction_open = false;
    try {
        if (!execute("BEGIN IMMEDIATE", error)) return false;
        transaction_open = true;
        Stmt finalized(db_, "SELECT 1 FROM monster_damage_contribution_finalized WHERE monster_instance_id=?");
        bind_text(finalized.get(), 1, item.monster_instance_id);
        const int finalized_result = sqlite3_step(finalized.get());
        if (finalized_result == SQLITE_ROW)
            throw std::runtime_error("monster contribution ledger is already finalized");
        if (finalized_result != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
        Stmt existing(db_,
            "SELECT monster_instance_id,session_id,character_id,monster_definition_id,damage,hit_count,"
            "first_hit_at_ms,last_hit_at_ms,bounty_objectives_json "
            "FROM monster_damage_contribution_writes WHERE write_id=?");
        bind_text(existing.get(), 1, item.write_id);
        const int existing_result = sqlite3_step(existing.get());
        if (existing_result == SQLITE_ROW) {
            const bool same = column_text(existing.get(), 0) == item.monster_instance_id &&
                column_text(existing.get(), 1) == item.session_id &&
                column_text(existing.get(), 2) == item.character_id &&
                column_text(existing.get(), 3) == item.monster_definition_id &&
                sqlite3_column_int64(existing.get(), 4) == item.total_damage &&
                sqlite3_column_int64(existing.get(), 5) == item.hit_count &&
                sqlite3_column_int64(existing.get(), 6) == item.first_hit_at_ms &&
                sqlite3_column_int64(existing.get(), 7) == item.last_hit_at_ms &&
                column_text(existing.get(), 8) == item.bounty_objectives_json;
            if (!same) throw std::runtime_error("monster contribution write id reused with different data");
            if (!execute("COMMIT", error)) throw std::runtime_error(error);
            transaction_open = false;
            return true;
        }
        if (existing_result != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
        Stmt write(db_,
            "INSERT INTO monster_damage_contribution_writes(write_id,monster_instance_id,session_id,"
            "character_id,monster_definition_id,damage,hit_count,first_hit_at_ms,last_hit_at_ms,bounty_objectives_json) "
            "VALUES(?,?,?,?,?,?,?,?,?,?)");
        bind_text(write.get(), 1, item.write_id);
        bind_text(write.get(), 2, item.monster_instance_id);
        bind_text(write.get(), 3, item.session_id);
        bind_text(write.get(), 4, item.character_id);
        bind_text(write.get(), 5, item.monster_definition_id);
        sqlite3_bind_int64(write.get(), 6, item.total_damage);
        sqlite3_bind_int64(write.get(), 7, item.hit_count);
        sqlite3_bind_int64(write.get(), 8, item.first_hit_at_ms);
        sqlite3_bind_int64(write.get(), 9, item.last_hit_at_ms);
        bind_text(write.get(), 10, item.bounty_objectives_json);
        if (sqlite3_step(write.get()) != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
        Stmt upsert(db_,
            "INSERT INTO monster_damage_contributions(monster_instance_id,monster_definition_id,"
            "session_id,character_id,total_damage,hit_count,first_hit_at_ms,last_hit_at_ms,bounty_objectives_json) "
            "VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(monster_instance_id,session_id,character_id) DO UPDATE SET "
            "total_damage=CASE WHEN total_damage>9223372036854775807-excluded.total_damage "
            "THEN 9223372036854775807 ELSE total_damage+excluded.total_damage END,"
            "hit_count=CASE WHEN hit_count>9223372036854775807-excluded.hit_count "
            "THEN 9223372036854775807 ELSE hit_count+excluded.hit_count END,"
            "first_hit_at_ms=MIN(first_hit_at_ms,excluded.first_hit_at_ms),"
            "last_hit_at_ms=MAX(last_hit_at_ms,excluded.last_hit_at_ms),"
            "bounty_objectives_json=excluded.bounty_objectives_json "
            "WHERE monster_damage_contributions.monster_definition_id=excluded.monster_definition_id");
        bind_text(upsert.get(), 1, item.monster_instance_id);
        bind_text(upsert.get(), 2, item.monster_definition_id);
        bind_text(upsert.get(), 3, item.session_id);
        bind_text(upsert.get(), 4, item.character_id);
        sqlite3_bind_int64(upsert.get(), 5, item.total_damage);
        sqlite3_bind_int64(upsert.get(), 6, item.hit_count);
        sqlite3_bind_int64(upsert.get(), 7, item.first_hit_at_ms);
        sqlite3_bind_int64(upsert.get(), 8, item.last_hit_at_ms);
        bind_text(upsert.get(), 9, item.bounty_objectives_json);
        if (sqlite3_step(upsert.get()) != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
        if (sqlite3_changes(db_) != 1)
            throw std::runtime_error("monster instance id is already associated with a different definition");
        if (!execute("COMMIT", error)) throw std::runtime_error(error);
        transaction_open = false;
        return true;
    } catch (const std::exception& exception) {
        if (transaction_open) {
            std::string ignored;
            execute("ROLLBACK", ignored);
        }
        error = exception.what();
        return false;
    }
}

std::vector<MonsterContributionRecord> DurableOutbox::load_monster_contributions(
    const std::string& monster_instance_id, std::string& error) const {
    std::vector<MonsterContributionRecord> result;
    if (monster_instance_id.empty() || monster_instance_id.size() > 96) {
        error = "invalid monster instance id";
        return result;
    }
    std::lock_guard lock(mutex_);
    try {
        Stmt query(db_,
            "SELECT monster_instance_id,monster_definition_id,session_id,character_id,total_damage,"
            "hit_count,first_hit_at_ms,last_hit_at_ms,bounty_objectives_json "
            "FROM monster_damage_contributions WHERE monster_instance_id=? "
            "ORDER BY total_damage DESC,character_id");
        bind_text(query.get(), 1, monster_instance_id);
        int step = SQLITE_ROW;
        while ((step = sqlite3_step(query.get())) == SQLITE_ROW) {
            result.push_back(MonsterContributionRecord{
                column_text(query.get(), 0), column_text(query.get(), 1),
                column_text(query.get(), 2), column_text(query.get(), 3),
                sqlite3_column_int64(query.get(), 4), sqlite3_column_int64(query.get(), 5),
                sqlite3_column_int64(query.get(), 6), sqlite3_column_int64(query.get(), 7),
                column_text(query.get(), 8)
            });
        }
        if (step != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
        return result;
    } catch (const std::exception& exception) {
        error = exception.what();
        return {};
    }
}

bool DurableOutbox::finalize_monster_contributions(
    const std::string& monster_instance_id, const std::vector<OutboxEvent>& events,
    std::string& error) {
    if (monster_instance_id.empty() || monster_instance_id.size() > 96 || events.empty()) {
        error = "monster instance id and finalization events are required";
        return false;
    }
    for (const auto& event : events) {
        if (event.event_id.empty() || event.event_type.empty() || event.payload.empty()) {
            error = "event id/type/payload required";
            return false;
        }
    }
    std::lock_guard lock(mutex_);
    bool transaction_open = false;
    try {
        if (!execute("BEGIN IMMEDIATE", error)) return false;
        transaction_open = true;
        std::vector<std::string> ids;
        std::size_t new_count = 0;
        for (const auto& event : events) {
            if (std::find(ids.begin(), ids.end(), event.event_id) != ids.end())
                throw std::runtime_error("duplicate event id inside monster finalization batch");
            ids.push_back(event.event_id);
            Stmt existing(db_, "SELECT event_type,payload,status FROM world_event_outbox WHERE event_id=?");
            bind_text(existing.get(), 1, event.event_id);
            const int result = sqlite3_step(existing.get());
            if (result == SQLITE_ROW) {
                if (column_text(existing.get(), 0) != event.event_type ||
                    column_text(existing.get(), 1) != event.payload ||
                    column_text(existing.get(), 2) == "dead_letter")
                    throw std::runtime_error("monster finalization event conflicts with existing outbox row");
            } else if (result == SQLITE_DONE) {
                ++new_count;
            } else {
                throw std::runtime_error(sqlite3_errmsg(db_));
            }
        }
        Stmt count(db_, "SELECT COUNT(*) FROM world_event_outbox WHERE status IN('pending','inflight')");
        if (sqlite3_step(count.get()) != SQLITE_ROW) throw std::runtime_error(sqlite3_errmsg(db_));
        const auto active_count = static_cast<std::size_t>(sqlite3_column_int64(count.get(), 0));
        if (new_count > capacity_ || active_count > capacity_ - new_count)
            throw std::runtime_error("durable outbox capacity reached");
        for (const auto& event : events) {
            Stmt existing(db_, "SELECT 1 FROM world_event_outbox WHERE event_id=?");
            bind_text(existing.get(), 1, event.event_id);
            if (sqlite3_step(existing.get()) == SQLITE_ROW) continue;
            Stmt insert(db_,
                "INSERT INTO world_event_outbox(event_id,event_type,payload,status,attempts,"
                "next_retry_at_ms,created_at_ms,updated_at_ms) VALUES(?,?,?,'pending',?,?,?,?)");
            bind_text(insert.get(), 1, event.event_id);
            bind_text(insert.get(), 2, event.event_type);
            bind_text(insert.get(), 3, event.payload);
            sqlite3_bind_int64(insert.get(), 4, event.attempts);
            sqlite3_bind_int64(insert.get(), 5, event.next_retry_at_ms);
            sqlite3_bind_int64(insert.get(), 6, event.created_at_ms);
            sqlite3_bind_int64(insert.get(), 7, event.created_at_ms);
            if (sqlite3_step(insert.get()) != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
        }
        std::vector<std::string> finalized_event_ids;
        finalized_event_ids.reserve(events.size());
        for (const auto& event : events) finalized_event_ids.push_back(event.event_id);
        std::sort(finalized_event_ids.begin(), finalized_event_ids.end());
        std::string event_ids;
        for (const auto& id : finalized_event_ids) {
            if (!event_ids.empty()) event_ids.push_back(',');
            event_ids += id;
        }
        Stmt existing_finalization(db_,
            "SELECT event_ids FROM monster_damage_contribution_finalized WHERE monster_instance_id=?");
        bind_text(existing_finalization.get(), 1, monster_instance_id);
        const int finalization_result = sqlite3_step(existing_finalization.get());
        if (finalization_result == SQLITE_ROW) {
            if (column_text(existing_finalization.get(), 0) != event_ids)
                throw std::runtime_error("monster instance was finalized with a different event batch");
        } else if (finalization_result == SQLITE_DONE) {
            Stmt mark_finalized(db_,
                "INSERT INTO monster_damage_contribution_finalized(monster_instance_id,event_ids,finalized_at_ms) "
                "VALUES(?,?,?)");
            bind_text(mark_finalized.get(), 1, monster_instance_id);
            bind_text(mark_finalized.get(), 2, event_ids);
            sqlite3_bind_int64(mark_finalized.get(), 3, events.front().created_at_ms);
            if (sqlite3_step(mark_finalized.get()) != SQLITE_DONE)
                throw std::runtime_error(sqlite3_errmsg(db_));
        } else {
            throw std::runtime_error(sqlite3_errmsg(db_));
        }
        Stmt remove_writes(db_, "DELETE FROM monster_damage_contribution_writes WHERE monster_instance_id=?");
        bind_text(remove_writes.get(), 1, monster_instance_id);
        if (sqlite3_step(remove_writes.get()) != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
        Stmt remove(db_, "DELETE FROM monster_damage_contributions WHERE monster_instance_id=?");
        bind_text(remove.get(), 1, monster_instance_id);
        if (sqlite3_step(remove.get()) != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
        if (!execute("COMMIT", error)) {
            std::string ignored;
            execute("ROLLBACK", ignored);
            transaction_open = false;
            return false;
        }
        transaction_open = false;
        return true;
    } catch (const std::exception& exception) {
        if (transaction_open) {
            std::string ignored;
            execute("ROLLBACK", ignored);
        }
        error = exception.what();
        return false;
    }
}

std::optional<OutboxEvent> DurableOutbox::find(const std::string& event_id, std::string& error) const {
    if (event_id.empty()) { error = "event id is required"; return std::nullopt; }
    std::lock_guard lock(mutex_);
    try {
        Stmt query(db_,
            "SELECT event_id,event_type,payload,attempts,next_retry_at_ms,created_at_ms,last_error "
            "FROM world_event_outbox WHERE event_id=?");
        bind_text(query.get(), 1, event_id);
        const int result = sqlite3_step(query.get());
        if (result == SQLITE_DONE) return std::nullopt;
        if (result != SQLITE_ROW) throw std::runtime_error(sqlite3_errmsg(db_));
        return OutboxEvent{
            column_text(query.get(), 0), column_text(query.get(), 1), column_text(query.get(), 2),
            static_cast<std::uint32_t>(sqlite3_column_int64(query.get(), 3)),
            sqlite3_column_int64(query.get(), 4), sqlite3_column_int64(query.get(), 5),
            column_text(query.get(), 6)
        };
    } catch (const std::exception& exception) {
        error = exception.what();
        return std::nullopt;
    }
}

std::optional<OutboxEvent> DurableOutbox::claim_due(std::int64_t now_ms, std::string& error) {
    return claim_due_filtered(now_ms, {}, false, error);
}

std::optional<OutboxEvent> DurableOutbox::claim_due_type(
    std::int64_t now_ms, const std::string& event_type, std::string& error) {
    if (event_type.empty()) { error = "event type is required"; return std::nullopt; }
    return claim_due_filtered(now_ms, event_type, false, error);
}

std::optional<OutboxEvent> DurableOutbox::claim_due_excluding(
    std::int64_t now_ms, const std::string& event_type, std::string& error) {
    if (event_type.empty()) { error = "event type is required"; return std::nullopt; }
    return claim_due_filtered(now_ms, event_type, true, error);
}

std::optional<OutboxEvent> DurableOutbox::claim_due_filtered(
    std::int64_t now_ms, const std::string& event_type, bool exclude, std::string& error) {
    std::lock_guard lock(mutex_);
    bool transaction_open = false;
    try {
        if (!execute("BEGIN IMMEDIATE", error)) return std::nullopt;
        transaction_open = true;

        const char* query_sql = event_type.empty()
            ? "SELECT event_id,event_type,payload,attempts,next_retry_at_ms,created_at_ms,last_error "
              "FROM world_event_outbox WHERE status='pending' AND next_retry_at_ms<=? "
              "ORDER BY created_at_ms,event_id LIMIT 1"
            : (exclude
                ? "SELECT event_id,event_type,payload,attempts,next_retry_at_ms,created_at_ms,last_error "
                  "FROM world_event_outbox WHERE status='pending' AND next_retry_at_ms<=? AND event_type<>? "
                  "ORDER BY created_at_ms,event_id LIMIT 1"
                : "SELECT event_id,event_type,payload,attempts,next_retry_at_ms,created_at_ms,last_error "
                  "FROM world_event_outbox WHERE status='pending' AND next_retry_at_ms<=? AND event_type=? "
                  "ORDER BY created_at_ms,event_id LIMIT 1");
        Stmt query(db_, query_sql);
        sqlite3_bind_int64(query.get(), 1, now_ms);
        if (!event_type.empty()) bind_text(query.get(), 2, event_type);
        const int result = sqlite3_step(query.get());
        if (result == SQLITE_DONE) {
            if (!execute("COMMIT", error)) {
                std::string ignored;
                execute("ROLLBACK", ignored);
                transaction_open = false;
                return std::nullopt;
            }
            transaction_open = false;
            return std::nullopt;
        }
        if (result != SQLITE_ROW) throw std::runtime_error(sqlite3_errmsg(db_));

        OutboxEvent event{
            column_text(query.get(), 0), column_text(query.get(), 1), column_text(query.get(), 2),
            static_cast<std::uint32_t>(sqlite3_column_int64(query.get(), 3)),
            sqlite3_column_int64(query.get(), 4), sqlite3_column_int64(query.get(), 5),
            column_text(query.get(), 6)
        };
        Stmt update(db_,
            "UPDATE world_event_outbox SET status='inflight',updated_at_ms=? "
            "WHERE event_id=? AND status='pending'");
        sqlite3_bind_int64(update.get(), 1, now_ms);
        bind_text(update.get(), 2, event.event_id);
        if (sqlite3_step(update.get()) != SQLITE_DONE || sqlite3_changes(db_) != 1) {
            throw std::runtime_error("outbox claim conflict");
        }
        if (!execute("COMMIT", error)) {
            std::string ignored;
            execute("ROLLBACK", ignored);
            transaction_open = false;
            return std::nullopt;
        }
        transaction_open = false;
        return event;
    } catch (const std::exception& exception) {
        if (transaction_open) {
            std::string ignored;
            execute("ROLLBACK", ignored);
        }
        error = exception.what();
        return std::nullopt;
    }
}

bool DurableOutbox::mark_delivered(const std::string& event_id, std::string& error) {
    std::lock_guard lock(mutex_);
    try {
        Stmt update(db_,
            "UPDATE world_event_outbox SET status='delivered',updated_at_ms=unixepoch()*1000,last_error='' "
            "WHERE event_id=? AND status='inflight'");
        bind_text(update.get(), 1, event_id);
        if (sqlite3_step(update.get()) != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
        if (sqlite3_changes(db_) != 1) error = "outbox event is not inflight";
        return sqlite3_changes(db_) == 1;
    } catch (const std::exception& exception) {
        error = exception.what();
        return false;
    }
}

bool DurableOutbox::schedule_retry(const std::string& event_id, std::uint32_t attempts,
                                   std::int64_t next_retry_at_ms, const std::string& detail,
                                   std::string& error) {
    std::lock_guard lock(mutex_);
    try {
        Stmt update(db_,
            "UPDATE world_event_outbox SET status='pending',attempts=?,next_retry_at_ms=?,"
            "updated_at_ms=unixepoch()*1000,last_error=? WHERE event_id=? AND status='inflight'");
        sqlite3_bind_int64(update.get(), 1, attempts);
        sqlite3_bind_int64(update.get(), 2, next_retry_at_ms);
        bind_text(update.get(), 3, detail);
        bind_text(update.get(), 4, event_id);
        if (sqlite3_step(update.get()) != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
        if (sqlite3_changes(db_) != 1) error = "outbox event is not inflight";
        return sqlite3_changes(db_) == 1;
    } catch (const std::exception& exception) {
        error = exception.what();
        return false;
    }
}

bool DurableOutbox::move_to_dead_letter(const std::string& event_id, std::uint32_t attempts,
                                        const std::string& detail, std::string& error) {
    std::lock_guard lock(mutex_);
    try {
        Stmt update(db_,
            "UPDATE world_event_outbox SET status='dead_letter',attempts=?,"
            "updated_at_ms=unixepoch()*1000,last_error=? WHERE event_id=? AND status='inflight'");
        sqlite3_bind_int64(update.get(), 1, attempts);
        bind_text(update.get(), 2, detail);
        bind_text(update.get(), 3, event_id);
        if (sqlite3_step(update.get()) != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
        if (sqlite3_changes(db_) != 1) error = "outbox event is not inflight";
        return sqlite3_changes(db_) == 1;
    } catch (const std::exception& exception) {
        error = exception.what();
        return false;
    }
}


OutboxStats DurableOutbox::stats(std::int64_t now_ms, std::string& error, const std::string& event_type) const {
    std::lock_guard lock(mutex_);
    OutboxStats result;
    try {
        Stmt counts(db_, "SELECT status,COUNT(*) FROM world_event_outbox WHERE (?='' OR event_type=?) GROUP BY status");
        bind_text(counts.get(), 1, event_type);
        bind_text(counts.get(), 2, event_type);
        int step = SQLITE_ROW;
        while ((step = sqlite3_step(counts.get())) == SQLITE_ROW) {
            const auto status = column_text(counts.get(), 0);
            const auto count = static_cast<std::size_t>(sqlite3_column_int64(counts.get(), 1));
            if (status == "pending") result.pending = count;
            else if (status == "inflight") result.inflight = count;
            else if (status == "delivered") result.delivered = count;
            else if (status == "dead_letter") result.dead_letter = count;
        }
        if (step != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));

        Stmt ages(db_,
            "SELECT "
            "COALESCE(MAX(CASE WHEN status='pending' THEN ?-created_at_ms END),0),"
            "COALESCE(MAX(CASE WHEN status='dead_letter' THEN ?-created_at_ms END),0) "
            "FROM world_event_outbox WHERE (?='' OR event_type=?)");
        sqlite3_bind_int64(ages.get(), 1, now_ms);
        sqlite3_bind_int64(ages.get(), 2, now_ms);
        bind_text(ages.get(), 3, event_type);
        bind_text(ages.get(), 4, event_type);
        if (sqlite3_step(ages.get()) != SQLITE_ROW) throw std::runtime_error(sqlite3_errmsg(db_));
        result.oldest_pending_age_ms = std::max<std::int64_t>(0, sqlite3_column_int64(ages.get(), 0));
        result.oldest_dead_letter_age_ms = std::max<std::int64_t>(0, sqlite3_column_int64(ages.get(), 1));
        return result;
    } catch (const std::exception& exception) {
        error = exception.what();
        return {};
    }
}

std::vector<OutboxEvent> DurableOutbox::list_dead_letters(
    std::size_t limit, const std::string& event_type, std::string& error) const {
    std::lock_guard lock(mutex_);
    std::vector<OutboxEvent> result;
    if (limit == 0 || limit > 500) {
        error = "dead-letter limit must be between 1 and 500";
        return result;
    }
    try {
        const char* sql = event_type.empty()
            ? "SELECT event_id,event_type,payload,attempts,next_retry_at_ms,created_at_ms,last_error "
              "FROM world_event_outbox WHERE status='dead_letter' ORDER BY updated_at_ms DESC,event_id LIMIT ?"
            : "SELECT event_id,event_type,payload,attempts,next_retry_at_ms,created_at_ms,last_error "
              "FROM world_event_outbox WHERE status='dead_letter' AND event_type=? "
              "ORDER BY updated_at_ms DESC,event_id LIMIT ?";
        Stmt query(db_, sql);
        if (event_type.empty()) {
            sqlite3_bind_int64(query.get(), 1, static_cast<sqlite3_int64>(limit));
        } else {
            bind_text(query.get(), 1, event_type);
            sqlite3_bind_int64(query.get(), 2, static_cast<sqlite3_int64>(limit));
        }
        int step = SQLITE_ROW;
        while ((step = sqlite3_step(query.get())) == SQLITE_ROW) {
            result.push_back(OutboxEvent{
                column_text(query.get(), 0), column_text(query.get(), 1), column_text(query.get(), 2),
                static_cast<std::uint32_t>(sqlite3_column_int64(query.get(), 3)),
                sqlite3_column_int64(query.get(), 4), sqlite3_column_int64(query.get(), 5),
                column_text(query.get(), 6)
            });
        }
        if (step != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
        return result;
    } catch (const std::exception& exception) {
        error = exception.what();
        return {};
    }
}

bool DurableOutbox::retry_dead_letter(
    const std::string& event_id, std::int64_t now_ms, std::string& error) {
    if (event_id.empty()) {
        error = "event id is required";
        return false;
    }
    std::lock_guard lock(mutex_);
    try {
        Stmt update(db_,
            "UPDATE world_event_outbox SET status='pending',next_retry_at_ms=?,"
            "updated_at_ms=?,last_error='manual retry requested' "
            "WHERE event_id=? AND event_type='nearby_chat' AND status='dead_letter'");
        sqlite3_bind_int64(update.get(), 1, now_ms);
        sqlite3_bind_int64(update.get(), 2, now_ms);
        bind_text(update.get(), 3, event_id);
        if (sqlite3_step(update.get()) != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
        if (sqlite3_changes(db_) != 1) {
            error = "event was not found in dead-letter queue";
            return false;
        }
        return true;
    } catch (const std::exception& exception) {
        error = exception.what();
        return false;
    }
}

std::size_t DurableOutbox::pending_count(std::string& error) const {
    std::lock_guard lock(mutex_);
    try {
        Stmt query(db_, "SELECT COUNT(*) FROM world_event_outbox WHERE status IN('pending','inflight')");
        if (sqlite3_step(query.get()) != SQLITE_ROW) throw std::runtime_error(sqlite3_errmsg(db_));
        return static_cast<std::size_t>(sqlite3_column_int64(query.get(), 0));
    } catch (const std::exception& exception) {
        error = exception.what();
        return 0;
    }
}
} // namespace honghuang::persistence
