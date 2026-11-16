#include <csignal>
#include <iostream>

namespace {
volatile std::sig_atomic_t running = 1;

void handle_signal(int) {
    running = 0;
}
} // namespace

int main() {
    std::signal(SIGINT, handle_signal);
    std::signal(SIGTERM, handle_signal);

    std::cout << "HongHuang WorldServer bootstrap (network layer not wired yet)\n";
    std::cout << "Press Ctrl+C to stop.\n";

    while (running != 0) {
        // P0 follow-up: add ENet event loop, sessions and authoritative world tick.
        // Keep this bootstrap dependency-free until the ENet version is pinned.
        std::signal(SIGINT, handle_signal);
        break;
    }

    std::cout << "WorldServer stopped.\n";
    return 0;
}
