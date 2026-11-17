#include "persistence/durable_outbox.hpp"
#include <sqlite3.h>
#include <stdexcept>

namespace honghuang::persistence {
namespace {
class Stmt {
public:
    Stmt(sqlite3* db, const char* sql) {
        if (sqlite3_prepare_v2(db, sql, -1, &stmt_, nullptr) != SQLITE_OK) throw std::runtime_error(sqlite3_errmsg(db));
    }
    ~Stmt() { sqlite3_finalize(stmt_); }
    sqlite3_stmt* get() const { return stmt_; }
private:
    sqlite3_stmt* stmt_{};
};
void bind(sqlite3_stmt* s, int i, const std::string& v) {
    sqlite3_bind_text(s, i, v.c_str(), static_cast<int>(v.size()), SQLITE_TRANSIENT);
}
}
DurableOutbox::DurableOutbox(const std::string& path, std::size_t capacity) : capacity_(capacity) {
    if (path.empty() || capacity_ == 0) throw std::invalid_argument("invalid outbox path or capacity");
    if (sqlite3_open_v2(path.c_str(), &db_, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nullptr) != SQLITE_OK) {
        const std::string e = db_ ? sqlite3_errmsg(db_) : "cannot open sqlite database";
        if (db_) sqlite3_close(db_);
        db_ = nullptr;
        throw std::runtime_error(e);
    }
    sqlite3_busy_timeout(db_, 5000);
    std::string error;
    const char* schema =
        "PRAGMA journal_mode=WAL;"
        "PRAGMA synchronous=FULL;"
        "PRAGMA foreign_keys=ON;"
        "CREATE TABLE IF NOT EXISTS world_event_outbox("
        "event_id TEXT PRIMARY KEY NOT NULL,event_type TEXT NOT NULL,payload TEXT NOT NULL,"
        "status TEXT NOT NULL CHECK(status IN('pending','inflight','delivered','dead_letter')),"
        "attempts INTEGER NOT NULL DEFAULT 0,next_retry_at_ms INTEGER NOT NULL,"
        "created_at_ms INTEGER NOT NULL,updated_at_ms INTEGER NOT NULL,last_error TEXT NOT NULL DEFAULT '');"
        "CREATE INDEX IF NOT EXISTS idx_world_event_outbox_due ON world_event_outbox(status,next_retry_at_ms,created_at_ms);"
        "UPDATE world_event_outbox SET status='pending' WHERE status='inflight';";
    char* message = nullptr;
    if (sqlite3_exec(db_, schema, nullptr, nullptr, &message) != SQLITE_OK) {
        error = message ? message : sqlite3_errmsg(db_);
        sqlite3_free(message);
        sqlite3_close(db_);
        db_ = nullptr;
        throw std::runtime_error(error);
    }
}
DurableOutbox::~DurableOutbox() { if (db_) sqlite3_close(db_); }
bool DurableOutbox::execute(const char* sql, std::string& error) const {
    char* message = nullptr;
    const int rc = sqlite3_exec(db_, sql, nullptr, nullptr, &message);
    if (rc == SQLITE_OK) return true;
    error = message ? message : sqlite3_errmsg(db_);
    sqlite3_free(message);
    return false;
}
bool DurableOutbox::enqueue(const OutboxEvent& e, std::string& error) {
    if (e.event_id.empty() || e.event_type.empty() || e.payload.empty()) { error = "event id/type/payload required"; return false; }
    std::lock_guard lock(mutex_);
    try {
        Stmt count(db_, "SELECT COUNT(*) FROM world_event_outbox WHERE status IN('pending','inflight')");
        if (sqlite3_step(count.get()) != SQLITE_ROW) throw std::runtime_error(sqlite3_errmsg(db_));
        const auto n = static_cast<std::size_t>(sqlite3_column_int64(count.get(), 0));
        Stmt insert(db_, "INSERT INTO world_event_outbox(event_id,event_type,payload,status,attempts,next_retry_at_ms,created_at_ms,updated_at_ms) VALUES(?,?,?,'pending',?,?,?,?) ON CONFLICT(event_id) DO NOTHING");
        bind(insert.get(),1,e.event_id); bind(insert.get(),2,e.event_type); bind(insert.get(),3,e.payload);
        sqlite3_bind_int64(insert.get(),4,e.attempts); sqlite3_bind_int64(insert.get(),5,e.next_retry_at_ms);
        sqlite3_bind_int64(insert.get(),6,e.created_at_ms); sqlite3_bind_int64(insert.get(),7,e.created_at_ms);
        if (sqlite3_step(insert.get()) != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
        if (sqlite3_changes(db_) == 0) return true;
        if (n >= capacity_) {
            Stmt remove(db_, "DELETE FROM world_event_outbox WHERE event_id=?");
            bind(remove.get(),1,e.event_id); sqlite3_step(remove.get());
            error = "durable outbox capacity reached";
            return false;
        }
        return true;
    } catch (const std::exception& ex) { error = ex.what(); return false; }
}
std::optional<OutboxEvent> DurableOutbox::claim_due(std::int64_t now, std::string& error) {
    std::lock_guard lock(mutex_);
    try {
        if (!execute("BEGIN IMMEDIATE",error)) return std::nullopt;
        Stmt q(db_,"SELECT event_id,event_type,payload,attempts,next_retry_at_ms,created_at_ms,last_error FROM world_event_outbox WHERE status='pending' AND next_retry_at_ms<=? ORDER BY created_at_ms,event_id LIMIT 1");
        sqlite3_bind_int64(q.get(),1,now);
        const int rc=sqlite3_step(q.get());
        if (rc==SQLITE_DONE) { execute("COMMIT",error); return std::nullopt; }
        if (rc!=SQLITE_ROW) throw std::runtime_error(sqlite3_errmsg(db_));
        auto str=[&](int i){const auto* p=sqlite3_column_text(q.get(),i);return p?std::string(reinterpret_cast<const char*>(p)):std::string{};};
        OutboxEvent e{str(0),str(1),str(2),static_cast<std::uint32_t>(sqlite3_column_int64(q.get(),3)),sqlite3_column_int64(q.get(),4),sqlite3_column_int64(q.get(),5),str(6)};
        Stmt u(db_,"UPDATE world_event_outbox SET status='inflight',updated_at_ms=? WHERE event_id=? AND status='pending'");
        sqlite3_bind_int64(u.get(),1,now); bind(u.get(),2,e.event_id);
        if(sqlite3_step(u.get())!=SQLITE_DONE || sqlite3_changes(db_)!=1) throw std::runtime_error("outbox claim conflict");
        if(!execute("COMMIT",error)) return std::nullopt;
        return e;
    } catch(const std::exception& ex) { execute("ROLLBACK",error); error=ex.what(); return std::nullopt; }
}
bool DurableOutbox::mark_delivered(const std::string& id,std::string& error) {
    std::lock_guard lock(mutex_);
    try { Stmt q(db_,"UPDATE world_event_outbox SET status='delivered',updated_at_ms=unixepoch()*1000,last_error='' WHERE event_id=?");
        bind(q.get(),1,id); if(sqlite3_step(q.get())!=SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
        return sqlite3_changes(db_)==1;
    } catch(const std::exception& ex){error=ex.what();return false;}
}
bool DurableOutbox::schedule_retry(const std::string& id,std::uint32_t attempts,std::int64_t due,const std::string& detail,std::string& error) {
    std::lock_guard lock(mutex_);
    try { Stmt q(db_,"UPDATE world_event_outbox SET status='pending',attempts=?,next_retry_at_ms=?,updated_at_ms=unixepoch()*1000,last_error=? WHERE event_id=?");
        sqlite3_bind_int64(q.get(),1,attempts); sqlite3_bind_int64(q.get(),2,due); bind(q.get(),3,detail); bind(q.get(),4,id);
        if(sqlite3_step(q.get())!=SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
        return sqlite3_changes(db_)==1;
    } catch(const std::exception& ex){error=ex.what();return false;}
}
bool DurableOutbox::move_to_dead_letter(const std::string& id,std::uint32_t attempts,const std::string& detail,std::string& error) {
    std::lock_guard lock(mutex_);
    try { Stmt q(db_,"UPDATE world_event_outbox SET status='dead_letter',attempts=?,updated_at_ms=unixepoch()*1000,last_error=? WHERE event_id=?");
        sqlite3_bind_int64(q.get(),1,attempts); bind(q.get(),2,detail); bind(q.get(),3,id);
        if(sqlite3_step(q.get())!=SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
        return sqlite3_changes(db_)==1;
    } catch(const std::exception& ex){error=ex.what();return false;}
}
std::size_t DurableOutbox::pending_count(std::string& error) const {
    std::lock_guard lock(mutex_);
    try { Stmt q(db_,"SELECT COUNT(*) FROM world_event_outbox WHERE status IN('pending','inflight')");
        if(sqlite3_step(q.get())!=SQLITE_ROW) throw std::runtime_error(sqlite3_errmsg(db_));
        return static_cast<std::size_t>(sqlite3_column_int64(q.get(),0));
    } catch(const std::exception& ex){error=ex.what();return 0;}
}
}
