#include "network/enet_server.hpp"
#include "protocol/frame.hpp"
#include "simulation/movement.hpp"

#include <enet/enet.h>
#include <curl/curl.h>
#include <nlohmann/json.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <iostream>
#include <memory>
#include <span>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace honghuang::network {
namespace {
using Json = nlohmann::json;
using Clock = std::chrono::steady_clock;
constexpr auto kSnapshotInterval = std::chrono::milliseconds(50);
constexpr auto kInputTimeout = std::chrono::milliseconds(500);
// The client sends at 20 Hz. Accept modest jitter, but cap command processing at 100 Hz.
constexpr auto kMinimumInputInterval = std::chrono::milliseconds(10);

struct PlayerState {
    std::string character_id;
    std::string name;
    float x{};
    float y{};
    float z{};
    float yaw{};
    float move_x{};
    float move_z{};
    float vertical_velocity{};
    bool jump_requested{};
    std::uint64_t last_input_sequence{};
    Clock::time_point last_input_at{Clock::now()};
    Clock::time_point last_input_received_at{};
};

std::size_t collect_response(char* data, std::size_t size, std::size_t count, void* user) {
    const auto bytes = size * count;
    static_cast<std::string*>(user)->append(data, bytes);
    return bytes;
}

bool redeem_ticket(const ServerConfig& config, const std::string& ticket, Json& snapshot, std::string& error) {
    CURL* curl = curl_easy_init();
    if (curl == nullptr) { error = "could not initialize HTTPS client"; return false; }

    const std::string url = config.backend_url + "/api/v1/servers/tickets/redeem";
    const std::string body = Json{{"node_key", config.node_key}, {"ticket", ticket}}.dump();
    std::string response;
    struct curl_slist* headers = nullptr;
    headers = curl_slist_append(headers, "Content-Type: application/json");
    const std::string auth_header = "X-World-Server-Key: " + config.api_key;
    headers = curl_slist_append(headers, auth_header.c_str());

    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_POST, 1L);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body.c_str());
    curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, static_cast<long>(body.size()));
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, collect_response);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, 3000L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, 5000L);
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);

    const auto result = curl_easy_perform(curl);
    long status = 0;
    if (result == CURLE_OK) curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    if (result != CURLE_OK) {
        error = std::string("backend request failed: ") + curl_easy_strerror(result);
        return false;
    }
    if (status != 200) {
        error = "ticket redemption rejected by backend (HTTP " + std::to_string(status) + ")";
        return false;
    }
    try {
        snapshot = Json::parse(response);
        if (!snapshot.contains("character_id") || !snapshot.contains("world_id") ||
            !snapshot.contains("instance_id") || !snapshot.contains("name")) {
            error = "backend snapshot is missing required fields";
            return false;
        }
    } catch (const std::exception& ex) {
        error = std::string("invalid backend JSON response: ") + ex.what();
        return false;
    }
    return true;
}

void send_json(ENetPeer* peer, honghuang::protocol::MessageType type, const Json& value) {
    const auto payload_text = value.dump();
    const auto* begin = reinterpret_cast<const std::uint8_t*>(payload_text.data());
    const auto frame = honghuang::protocol::encode_frame(
        type, std::span<const std::uint8_t>(begin, payload_text.size()));
    if (frame.empty()) return;
    auto* packet = enet_packet_create(frame.data(), frame.size(), ENET_PACKET_FLAG_RELIABLE);
    if (packet != nullptr && enet_peer_send(peer, 0, packet) != 0) enet_packet_destroy(packet);
}
} // namespace

struct EnetServer::Impl {
    ServerConfig config;
    ENetHost* host{};
    std::unordered_map<ENetPeer*, PlayerState> players;
    Clock::time_point last_snapshot{Clock::now()};

    explicit Impl(ServerConfig value) : config(std::move(value)) {}

    void broadcast_snapshot() {
        if (players.empty()) return;
        Json entities = Json::array();
        for (const auto& [peer, player] : players) {
            (void)peer;
            entities.push_back({
                {"character_id", player.character_id},
                {"name", player.name},
                {"x", player.x}, {"y", player.y}, {"z", player.z},
                {"yaw", player.yaw},
                {"last_input_sequence", player.last_input_sequence}
            });
        }
        const auto payload_text = Json{{"entities", std::move(entities)}}.dump();
        const auto* begin = reinterpret_cast<const std::uint8_t*>(payload_text.data());
        const auto frame = honghuang::protocol::encode_frame(
            honghuang::protocol::MessageType::EntitySnapshot,
            std::span<const std::uint8_t>(begin, payload_text.size()));
        if (frame.empty()) return;
        for (const auto& [peer, player] : players) {
            (void)player;
            auto* packet = enet_packet_create(frame.data(), frame.size(), 0);
            if (packet != nullptr && enet_peer_send(peer, 1, packet) != 0) enet_packet_destroy(packet);
        }
    }

    void tick_world() {
        const auto now = Clock::now();
        const auto elapsed = now - last_snapshot;
        if (elapsed < kSnapshotInterval) return;
        const float delta = std::clamp(std::chrono::duration<float>(elapsed).count(), 0.0F, 0.1F);
        for (auto& [peer, player] : players) {
            (void)peer;
            if (now - player.last_input_at > kInputTimeout) {
                player.move_x = 0.0F;
                player.move_z = 0.0F;
            }
            honghuang::simulation::integrate_horizontal(
                player.x, player.z, player.move_x, player.move_z, delta);
            honghuang::simulation::integrate_vertical(
                player.y, player.vertical_velocity, player.jump_requested, delta);
        }
        last_snapshot = now;
        broadcast_snapshot();
    }
};

EnetServer::EnetServer(ServerConfig config) : impl_(new Impl(std::move(config))) {}
EnetServer::~EnetServer() { stop(); delete impl_; }

bool EnetServer::start() {
    if (impl_->config.backend_url.empty() || impl_->config.node_key.empty() || impl_->config.api_key.empty()) {
        std::cerr << "BACKEND_URL, WORLD_SERVER_NODE_KEY and WORLD_SERVER_API_KEY are required\n";
        return false;
    }
    if (enet_initialize() != 0) {
        std::cerr << "ENet initialization failed\n";
        return false;
    }
    if (curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK) {
        std::cerr << "libcurl initialization failed\n";
        enet_deinitialize();
        return false;
    }
    ENetAddress address{};
    address.host = ENET_HOST_ANY;
    if (impl_->config.bind_host != "0.0.0.0" &&
        enet_address_set_host(&address, impl_->config.bind_host.c_str()) != 0) {
        std::cerr << "Invalid bind host: " << impl_->config.bind_host << '\n';
        curl_global_cleanup();
        enet_deinitialize();
        return false;
    }
    address.port = impl_->config.port;
    impl_->host = enet_host_create(&address, impl_->config.max_clients, 2, 0, 0);
    if (impl_->host == nullptr) {
        std::cerr << "Could not create ENet host on UDP port " << impl_->config.port << '\n';
        curl_global_cleanup();
        enet_deinitialize();
        return false;
    }
    std::cout << "WorldServer ENet listening on UDP " << impl_->config.port << '\n';
    return true;
}

void EnetServer::poll(std::uint32_t timeout_ms) {
    if (impl_->host == nullptr) return;
    ENetEvent event{};
    while (enet_host_service(impl_->host, &event, timeout_ms) > 0) {
        switch (event.type) {
        case ENET_EVENT_TYPE_CONNECT:
            std::cout << "ENet client connected; awaiting ClientHello\n";
            break;
        case ENET_EVENT_TYPE_RECEIVE: {
            const auto bytes = std::span<const std::uint8_t>(
                event.packet->data, static_cast<std::size_t>(event.packet->dataLength));
            honghuang::protocol::Frame frame{};
            std::string error;
            if (!honghuang::protocol::decode_frame(bytes, frame, error)) {
                send_json(event.peer, honghuang::protocol::MessageType::ServerReject, Json{{"reason", error}});
                enet_peer_disconnect_later(event.peer, 1);
            } else if (frame.type == honghuang::protocol::MessageType::ClientHello &&
                       !impl_->players.contains(event.peer)) {
                honghuang::protocol::ClientHello hello{};
                if (!honghuang::protocol::decode_client_hello(frame.payload, hello, error)) {
                    send_json(event.peer, honghuang::protocol::MessageType::ServerReject, Json{{"reason", error}});
                    enet_peer_disconnect_later(event.peer, 2);
                } else {
                    Json snapshot;
                    if (!redeem_ticket(impl_->config, hello.ticket, snapshot, error)) {
                        std::cerr << "World entry rejected: " << error << '\n';
                        send_json(event.peer, honghuang::protocol::MessageType::ServerReject,
                                  Json{{"reason", "world entry ticket rejected"}});
                        enet_peer_disconnect_later(event.peer, 3);
                    } else {
                        PlayerState player;
                        player.character_id = snapshot.value("character_id", std::string{});
                        player.name = snapshot.value("name", std::string{});
                        player.x = snapshot.value("position_x", 0.0F);
                        player.y = snapshot.value("position_y", 0.0F);
                        player.z = snapshot.value("position_z", 0.0F);
                        player.last_input_at = Clock::now();
                        impl_->players.emplace(event.peer, std::move(player));
                        send_json(event.peer, honghuang::protocol::MessageType::ServerWelcome, snapshot);
                        std::cout << "Authenticated character entered world: "
                                  << snapshot.value("character_id", std::string{}) << '\n';
                    }
                }
            } else if (frame.type == honghuang::protocol::MessageType::Heartbeat &&
                       impl_->players.contains(event.peer)) {
                const auto response = honghuang::protocol::encode_frame(
                    honghuang::protocol::MessageType::HeartbeatAck, {});
                auto* packet = enet_packet_create(response.data(), response.size(), ENET_PACKET_FLAG_RELIABLE);
                if (packet != nullptr && enet_peer_send(event.peer, 0, packet) != 0) enet_packet_destroy(packet);
            } else if (frame.type == honghuang::protocol::MessageType::InputCommand &&
                       impl_->players.contains(event.peer)) {
                try {
                    const std::string payload(frame.payload.begin(), frame.payload.end());
                    const auto command = Json::parse(payload);
                    const auto sequence = command.at("sequence").get<std::uint64_t>();
                    float move_x = command.at("move_x").get<float>();
                    float move_z = command.at("move_z").get<float>();
                    if (!honghuang::simulation::normalize_direction(move_x, move_z)) {
                        throw std::runtime_error("movement input must be finite");
                    }
                    auto& player = impl_->players.at(event.peer);
                    const auto now = Clock::now();
                    if (sequence > player.last_input_sequence &&
                        now - player.last_input_received_at >= kMinimumInputInterval) {
                        player.move_x = move_x;
                        player.move_z = move_z;
                        player.jump_requested = command.value("jump", false);
                        if (move_x != 0.0F || move_z != 0.0F) {
                            player.yaw = std::atan2(-move_x, -move_z);
                        }
                        player.last_input_sequence = sequence;
                        player.last_input_at = now;
                        player.last_input_received_at = now;
                    }
                } catch (const std::exception&) {
                    send_json(event.peer, honghuang::protocol::MessageType::ServerReject,
                              Json{{"reason", "invalid movement input"}});
                    enet_peer_disconnect_later(event.peer, 5);
                }
            } else {
                send_json(event.peer, honghuang::protocol::MessageType::ServerReject,
                          Json{{"reason", "message not allowed before authentication"}});
                enet_peer_disconnect_later(event.peer, 4);
            }
            enet_packet_destroy(event.packet);
            break;
        }
        case ENET_EVENT_TYPE_DISCONNECT:
            impl_->players.erase(event.peer);
            std::cout << "ENet client disconnected\n";
            break;
        case ENET_EVENT_TYPE_NONE:
            break;
        }
    }
    impl_->tick_world();
}

void EnetServer::stop() {
    if (impl_ != nullptr && impl_->host != nullptr) {
        enet_host_destroy(impl_->host);
        impl_->host = nullptr;
        curl_global_cleanup();
        enet_deinitialize();
        impl_->players.clear();
        std::cout << "WorldServer stopped\n";
    }
}
} // namespace honghuang::network
