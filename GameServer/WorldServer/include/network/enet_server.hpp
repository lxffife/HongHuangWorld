#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

namespace honghuang::network {

struct ServerConfig {
    std::string bind_host{"0.0.0.0"};
    std::uint16_t port{7777};
    std::size_t max_clients{512};
    std::string backend_url;
    std::string node_key;
    std::string api_key;
    std::string advertise_host;
    std::string region{"local"};
    std::string world_id{"qingyun_human"};
    std::string instance_key{"qingyun-local-1"};
    int capacity{100};
};

class EnetServer {
public:
    explicit EnetServer(ServerConfig config);
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
