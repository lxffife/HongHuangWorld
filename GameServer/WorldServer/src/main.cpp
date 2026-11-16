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

    std::cout << "HongHuang WorldServer bootstrap (ENet transport is the next milestone)\n";
    std::cout << "Process is running. Press Ctrl+C to stop.\n";

    while (running != 0) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    std::cout << "WorldServer stopped.\n";
    return 0;
}
