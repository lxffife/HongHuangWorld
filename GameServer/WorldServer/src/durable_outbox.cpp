#include "persistence/durable_outbox.hpp"

#include <sqlite3.h>

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

DurableOutbox::DurableOutbox(const std::string& path, std::size_t capacity)
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
        "UPDATE world_event_outbox SET status='pending' WHERE status='inflight';";
    char* message = nullptr;
    if (sqlite3_exec(db_, schema, nullptr, nullptr, &message) != SQLITE_OK) {
        const std::string error = message ? message : sqlite3_errmsg(db_);
        sqlite3_free(message);
        sqlite3_close(db_);
        db_ = nullptr;
        throw std::runtime_error(error);
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
        Stmt existing(db_, "SELECT event_type,payload FROM world_event_outbox WHERE event_id=?");
        bind_text(existing.get(), 1, event.event_id);
        const int existing_result = sqlite3_step(existing.get());
        if (existing_result == SQLITE_ROW) {
            const bool same = column_text(existing.get(), 0) == event.event_type &&
                              column_text(existing.get(), 1) == event.payload;
            if (!execute("COMMIT", error)) {
                std::string ignored;
                execute("ROLLBACK", ignored);
                transaction_open = false;
                return false;
            }
            transaction_open = false;
            if (!same) error = "event id already exists with a different type or payload";
            return same;
        }
        if (existing_result != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));

        Stmt count(db_, "SELECT COUNT(*) FROM world_event_outbox WHERE status IN('pending','inflight')");
        if (sqlite3_step(count.get()) != SQLITE_ROW) throw std::runtime_error(sqlite3_errmsg(db_));
        const auto active_count = static_cast<std::size_t>(sqlite3_column_int64(count.get(), 0));
        if (active_count >= capacity_) {
            error = "durable outbox capacity reached";
            execute("ROLLBACK", error);
            transaction_open = false;
            return false;
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

std::optional<OutboxEvent> DurableOutbox::claim_due(std::int64_t now_ms, std::string& error) {
    std::lock_guard lock(mutex_);
    bool transaction_open = false;
    try {
        if (!execute("BEGIN IMMEDIATE", error)) return std::nullopt;
        transaction_open = true;

        Stmt query(db_,
            "SELECT event_id,event_type,payload,attempts,next_retry_at_ms,created_at_ms,last_error "
            "FROM world_event_outbox WHERE status='pending' AND next_retry_at_ms<=? "
            "ORDER BY created_at_ms,event_id LIMIT 1");
        sqlite3_bind_int64(query.get(), 1, now_ms);
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
