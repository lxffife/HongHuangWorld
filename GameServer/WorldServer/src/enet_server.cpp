#include "network/enet_server.hpp"
#include "protocol/frame.hpp"

#include <enet/enet.h>

#include <iostream>
#include <memory>
#include <string>
#include <vector>

namespace honghuang::network {
struct EnetServer::Impl {
    std::string bind_host;
    std::uint16_t port;
    std::size_t max_clients;
    ENetHost* host{};

    Impl(std::string host_name, std::uint16_t listen_port, std::size_t clients)
        : bind_host(std::move(host_name)), port(listen_port), max_clients(clients) {}
};

EnetServer::EnetServer(std::string bind_host, std::uint16_t port, std::size_t max_clients)
    : impl_(new Impl(std::move(bind_host), port, max_clients)) {}

EnetServer::~EnetServer() {
    stop();
    delete impl_;
}

bool EnetServer::start() {
    if (enet_initialize() != 0) {
        std::cerr << "ENet initialization failed\n";
        return false;
    }
    ENetAddress address{};
    address.host = ENET_HOST_ANY;
    if (impl_->bind_host != "0.0.0.0" && enet_address_set_host(&address, impl_->bind_host.c_str()) != 0) {
        std::cerr << "Invalid bind host: " << impl_->bind_host << '\n';
        enet_deinitialize();
        return false;
    }
    address.port = impl_->port;
    impl_->host = enet_host_create(&address, impl_->max_clients, 2, 0, 0);
    if (impl_->host == nullptr) {
        std::cerr << "Could not create ENet host on UDP port " << impl_->port << '\n';
        enet_deinitialize();
        return false;
    }
    std::cout << "ENet listening on " << impl_->bind_host << ':' << impl_->port << '\n';
    return true;
}

void EnetServer::poll(std::uint32_t timeout_ms) {
    if (impl_->host == nullptr) return;
    ENetEvent event{};
    while (enet_host_service(impl_->host, &event, timeout_ms) > 0) {
        switch (event.type) {
        case ENET_EVENT_TYPE_CONNECT:
            std::cout << "Client connected (transport only)\n";
            break;
        case ENET_EVENT_TYPE_RECEIVE: {
            const auto bytes = std::span<const std::uint8_t>(
                event.packet->data, static_cast<std::size_t>(event.packet->dataLength));
            honghuang::protocol::Frame frame{};
            std::string error;
            if (!honghuang::protocol::decode_frame(bytes, frame, error)) {
                std::cerr << "Rejected malformed protocol frame: " << error << '\n';
                enet_peer_disconnect(event.peer, 1);
            } else if (frame.type == honghuang::protocol::MessageType::Heartbeat) {
                const auto response = honghuang::protocol::encode_frame(
                    honghuang::protocol::MessageType::HeartbeatAck, {});
                auto* packet = enet_packet_create(response.data(), response.size(), ENET_PACKET_FLAG_RELIABLE);
                if (packet != nullptr && enet_peer_send(event.peer, 0, packet) != 0) enet_packet_destroy(packet);
            } else {
                // Ticket redemption and authoritative player creation are intentionally not
                // enabled until the backend HTTPS client is configured.
                std::cerr << "Protocol frame received; gameplay handshake is not enabled yet\n";
                enet_peer_disconnect(event.peer, 2);
            }
            enet_packet_destroy(event.packet);
            break;
        }
        case ENET_EVENT_TYPE_DISCONNECT:
            std::cout << "Client disconnected\n";
            break;
        case ENET_EVENT_TYPE_NONE:
            break;
        }
    }
}

void EnetServer::stop() {
    if (impl_ != nullptr && impl_->host != nullptr) {
        enet_host_destroy(impl_->host);
        impl_->host = nullptr;
        enet_deinitialize();
        std::cout << "ENet stopped\n";
    }
}
} // namespace honghuang::network
