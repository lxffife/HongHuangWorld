#pragma once

#include <cstddef>

#include <cstdint>
#include <string>

namespace honghuang::network {

class EnetServer {
public:
    EnetServer(std::string bind_host, std::uint16_t port, std::size_t max_clients);
    ~EnetServer();
    EnetServer(const EnetServer&) = delete;
    EnetServer& operator=(const EnetServer&) = delete;

    bool start();
    void poll(std::uint32_t timeout_ms);
    void stop();

private:
    struct Impl;
    Impl* impl_{};
};

} // namespace honghuang::network
