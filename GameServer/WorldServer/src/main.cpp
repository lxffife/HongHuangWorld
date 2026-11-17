#include "network/enet_server.hpp"

#include <chrono>
#include <csignal>
#include <cstdlib>
#include <iostream>
#include <string>

namespace {
volatile std::sig_atomic_t running = 1;
void handle_signal(int) { running = 0; }
std::string env_or(const char* key, const char* fallback) {
    const char* value = std::getenv(key);
    return value == nullptr ? fallback : value;
}
} // namespace

int main() {
    std::signal(SIGINT, handle_signal);
    std::signal(SIGTERM, handle_signal);

    honghuang::network::ServerConfig config;
    config.bind_host = env_or("WORLD_SERVER_BIND", "0.0.0.0");
    config.backend_url = env_or("BACKEND_URL", "");
    config.node_key = env_or("WORLD_SERVER_NODE_KEY", "");
    config.api_key = env_or("WORLD_SERVER_API_KEY", "");
    config.advertise_host = env_or("WORLD_SERVER_ADVERTISE_HOST", "");
    config.region = env_or("WORLD_SERVER_REGION", "local");
    config.world_id = env_or("WORLD_ID", "qingyun_human");
    config.instance_key = env_or("WORLD_SERVER_INSTANCE_KEY", "qingyun-local-1");
    config.outbox_database_path = env_or("WORLD_SERVER_OUTBOX_PATH", "./data/worldserver-outbox.sqlite3");
    config.capacity = std::stoi(env_or("WORLD_SERVER_CAPACITY", "100"));
    config.port = static_cast<std::uint16_t>(std::stoi(env_or("WORLD_SERVER_UDP_PORT", "7777")));

    honghuang::network::EnetServer server(std::move(config));
    if (!server.start()) {
        std::cerr << "WorldServer startup failed. Check environment configuration.\n";
        return 1;
    }

    std::cout << "WorldServer is running. Press Ctrl+C to stop.\n";
    while (running != 0) server.poll(50);
    server.stop();
    return 0;
}
