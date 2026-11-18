#include "persistence/durable_outbox.hpp"

#include <chrono>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {
std::int64_t now_ms() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
}

void usage() {
    std::cerr
        << "Usage:\n"
        << "  world_outbox_admin [db_path] stats\n"
        << "  world_outbox_admin [db_path] dead-letters [limit] [event_type=nearby_chat]\n"
        << "  world_outbox_admin [db_path] retry <event_id>\n"
        << "If db_path is omitted, WORLD_SERVER_OUTBOX_PATH is used, then "
           "./data/worldserver-outbox.sqlite3.\n";
}
} // namespace

int main(int argc, char** argv) {
    std::string database_path;
    int command_index = 1;
    if (argc >= 3 && std::string(argv[1]) != "stats" &&
        std::string(argv[1]) != "dead-letters" && std::string(argv[1]) != "retry") {
        database_path = argv[1];
        command_index = 2;
    } else {
        const char* configured = std::getenv("WORLD_SERVER_OUTBOX_PATH");
        database_path = configured == nullptr ? "./data/worldserver-outbox.sqlite3" : configured;
    }
    if (argc <= command_index) {
        usage();
        return 2;
    }

    try {
        // Do not reset inflight rows: the WorldServer may be using this database now.
        honghuang::persistence::DurableOutbox outbox(database_path, 10000, false);
        const std::string command = argv[command_index];
        std::string error;

        if (command == "stats") {
            const auto value = outbox.stats(now_ms(), error);
            if (!error.empty()) throw std::runtime_error(error);
            std::cout
                << "pending=" << value.pending
                << " inflight=" << value.inflight
                << " delivered=" << value.delivered
                << " dead_letter=" << value.dead_letter
                << " oldest_pending_age_seconds=" << value.oldest_pending_age_ms / 1000
                << " oldest_dead_letter_age_seconds=" << value.oldest_dead_letter_age_ms / 1000
                << '\n';
            return 0;
        }

        if (command == "dead-letters") {
            std::size_t limit = 50;
            if (argc > command_index + 1) {
                const auto parsed = std::stoul(argv[command_index + 1]);
                if (parsed == 0 || parsed > 500) throw std::invalid_argument("limit must be 1..500");
                limit = static_cast<std::size_t>(parsed);
            }
            const std::string event_type = argc > command_index + 2 ? argv[command_index + 2] : "nearby_chat";
            const auto events = outbox.list_dead_letters(limit, event_type, error);
            if (!error.empty()) throw std::runtime_error(error);
            for (const auto& event : events) {
                std::cout << "id=" << event.event_id
                          << " type=" << event.event_type
                          << " attempts=" << event.attempts
                          << " created_at_ms=" << event.created_at_ms
                          << " error=" << std::quoted(event.last_error) << '\n';
            }
            std::cout << "listed=" << events.size() << '\n';
            return 0;
        }

        if (command == "retry") {
            if (argc <= command_index + 1) {
                usage();
                return 2;
            }
            const std::string event_id = argv[command_index + 1];
            if (!outbox.retry_dead_letter(event_id, now_ms(), error)) {
                throw std::runtime_error(error);
            }
            std::cout << "requeued=" << event_id << '\n';
            return 0;
        }

        usage();
        return 2;
    } catch (const std::exception& exception) {
        std::cerr << "outbox admin failed: " << exception.what() << '\n';
        return 1;
    }
}
