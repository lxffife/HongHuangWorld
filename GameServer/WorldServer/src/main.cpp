#include "network/enet_server.hpp"

#include <chrono>
#include <csignal>
#include <iostream>
#include <thread>

namespace {
volatile std::sig_atomic_t running = 1;

void handle_signal(int) {
    running = 0;
}
} // namespace

int main() {
    std::signal(SIGINT, handle_signal);
    std::signal(SIGTERM, handle_signal);

    honghuang::network::EnetServer server("0.0.0.0", 7777, 512);
    if (!server.start()) {
        std::cerr << "WorldServer startup failed.\n";
        return 1;
    }

    std::cout << "HongHuang WorldServer transport is running. UDP port: 7777\n";
    std::cout << "Gameplay ticket redemption is not enabled yet. Press Ctrl+C to stop.\n";
    while (running != 0) {
        server.poll(50);
    }

    server.stop();
    std::cout << "WorldServer stopped.\n";
    return 0;
}
