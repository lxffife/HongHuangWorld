#include "network/enet_server.hpp"
#include "protocol/frame.hpp"
#include "simulation/movement.hpp"
#include "simulation/monster.hpp"
#include "simulation/combat.hpp"

#include <enet/enet.h>
#include <curl/curl.h>
#include <nlohmann/json.hpp>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cmath>
#include <iostream>
#include <memory>
#include <limits>
#include <mutex>
#include <span>
#include <stdexcept>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
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
constexpr float kInterestRadius = 80.0F;
constexpr auto kHeartbeatInterval = std::chrono::seconds(10);
constexpr auto kAttackCooldown = std::chrono::milliseconds(650);
constexpr auto kMonsterRespawnDelay = std::chrono::seconds(12);
constexpr float kAttackRange = 3.5F;
constexpr auto kHeartbeatRetryInterval = std::chrono::seconds(5);

struct PlayerState {
    std::string session_id;
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
    Clock::time_point last_attack_at{};
};

struct MonsterRuntime {
    honghuang::simulation::MonsterDefinition definition;
    honghuang::simulation::MonsterState state;
    std::string runtime_id;
    Clock::time_point respawn_at{};
};

std::size_t collect_response(char* data, std::size_t size, std::size_t count, void* user) {
    const auto bytes = size * count;
    static_cast<std::string*>(user)->append(data, bytes);
    return bytes;
}

bool send_heartbeat(const ServerConfig& config, std::size_t current_players,
                    const std::string& status, std::string& error) {
    CURL* curl = curl_easy_init();
    if (curl == nullptr) { error = "could not initialize heartbeat HTTP client"; return false; }

    const std::string url = config.backend_url + "/api/v1/servers/heartbeat";
    const std::string body = Json{
        {"node_key", config.node_key},
        {"host", config.advertise_host},
        {"udp_port", config.port},
        {"region", config.region},
        {"capacity", config.capacity},
        {"current_players", current_players},
        {"world_id", config.world_id},
        {"instance_key", config.instance_key},
        {"status", status}
    }.dump();
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
    long http_status = 0;
    if (result == CURLE_OK) curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_status);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    if (result != CURLE_OK) {
        error = std::string("backend heartbeat request failed: ") + curl_easy_strerror(result);
        return false;
    }
    if (http_status != 200) {
        error = "backend heartbeat rejected (HTTP " + std::to_string(http_status) + ")";
        return false;
    }
    return true;
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
        if (!snapshot.contains("session_id") || !snapshot.contains("character_id") ||
            !snapshot.contains("world_id") || !snapshot.contains("instance_id") ||
            !snapshot.contains("name")) {
            error = "backend snapshot is missing required fields";
            return false;
        }
    } catch (const std::exception& ex) {
        error = std::string("invalid backend JSON response: ") + ex.what();
        return false;
    }
    return true;
}

bool save_and_close_session(const ServerConfig& config, const PlayerState& player, std::string& error) {
    if (player.session_id.empty() || player.character_id.empty()) {
        error = "player session identity is missing";
        return false;
    }
    CURL* curl = curl_easy_init();
    if (curl == nullptr) { error = "could not initialize session snapshot HTTP client"; return false; }

    const std::string url = config.backend_url + "/api/v1/servers/sessions/close";
    const std::string body = Json{
        {"node_key", config.node_key},
        {"session_id", player.session_id},
        {"character_id", player.character_id},
        {"position_x", player.x},
        {"position_y", player.y},
        {"position_z", player.z},
        {"rotation_y", player.yaw}
    }.dump();
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
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, 1000L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, 3000L);
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);

    const auto result = curl_easy_perform(curl);
    long http_status = 0;
    if (result == CURLE_OK) curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_status);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    if (result != CURLE_OK) {
        error = std::string("world session snapshot request failed: ") + curl_easy_strerror(result);
        return false;
    }
    if (http_status != 200) {
        error = "world session snapshot rejected by backend (HTTP " + std::to_string(http_status) + ")";
        return false;
    }
    return true;
}

bool save_periodic_position(const ServerConfig& config, const PlayerState& player,
                            bool& session_inactive, std::string& error) {
    session_inactive = false;
    if (player.session_id.empty() || player.character_id.empty()) {
        error = "player session identity is missing";
        return false;
    }
    CURL* curl = curl_easy_init();
    if (curl == nullptr) { error = "could not initialize periodic snapshot HTTP client"; return false; }

    const std::string url = config.backend_url + "/api/v1/servers/sessions/snapshot";
    const std::string body = Json{
        {"node_key", config.node_key},
        {"session_id", player.session_id},
        {"character_id", player.character_id},
        {"position_x", player.x},
        {"position_y", player.y},
        {"position_z", player.z},
        {"rotation_y", player.yaw}
    }.dump();
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
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, 1000L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, 2500L);
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);

    const auto result = curl_easy_perform(curl);
    long http_status = 0;
    if (result == CURLE_OK) curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_status);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    if (result != CURLE_OK) {
        error = std::string("periodic world snapshot request failed: ") + curl_easy_strerror(result);
        return false;
    }
    if (http_status == 409) {
        session_inactive = true;
        return false;
    }
    if (http_status != 200) {
        error = "periodic world snapshot rejected by backend (HTTP " + std::to_string(http_status) + ")";
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
    std::vector<MonsterRuntime> monsters;
    Clock::time_point last_snapshot{Clock::now()};
    std::atomic_size_t online_players{0};
    std::mutex heartbeat_mutex;
    std::condition_variable heartbeat_cv;
    bool heartbeat_stop_requested{false};
    std::thread heartbeat_thread;
    std::mutex persistence_mutex;
    std::condition_variable persistence_cv;
    std::unordered_map<std::string, PlayerState> pending_snapshots;
    std::unordered_set<std::string> revoked_sessions;
    bool persistence_stop_requested{false};
    std::thread persistence_thread;
    Clock::time_point last_persistence{Clock::now()};

    explicit Impl(ServerConfig value) : config(std::move(value)) {
        const auto add_monster = [this](std::string runtime_id, std::string definition_id,
                                        std::string name, int level, float health,
                                        float attack, float defense, float speed,
                                        float aggro, float leash, float x, float z) {
            honghuang::simulation::MonsterDefinition definition{
                std::move(definition_id), std::move(name), level, health, attack, defense,
                speed, aggro, leash, x, z
            };
            if (!honghuang::simulation::valid_monster_definition(definition)) return;
            honghuang::simulation::MonsterState state{x, z, health};
            monsters.push_back({std::move(definition), std::move(state), std::move(runtime_id), Clock::time_point{}});
        };
        add_monster("wolf-001", "wilderness_wolf", "荒原狼", 3, 80.0F, 12.0F, 4.0F,
                    2.8F, 10.0F, 24.0F, -12.0F, -8.0F);
        add_monster("wolf-002", "wilderness_wolf", "荒原狼", 3, 80.0F, 12.0F, 4.0F,
                    2.8F, 10.0F, 24.0F, 13.0F, -7.0F);
        add_monster("wolf-003", "wilderness_wolf", "荒原狼", 3, 80.0F, 12.0F, 4.0F,
                    2.8F, 10.0F, 24.0F, 0.0F, 17.0F);
    }

    void start_persistence_worker() {
        persistence_stop_requested = false;
        persistence_thread = std::thread([this] {
            while (true) {
                std::unordered_map<std::string, PlayerState> batch;
                {
                    std::unique_lock lock(persistence_mutex);
                    persistence_cv.wait(lock, [this] {
                        return persistence_stop_requested || !pending_snapshots.empty();
                    });
                    if (persistence_stop_requested) return;
                    batch.swap(pending_snapshots);
                }

                for (const auto& [session_id, player] : batch) {
                    {
                        std::lock_guard lock(persistence_mutex);
                        if (persistence_stop_requested) break;
                    }
                    bool inactive = false;
                    std::string error;
                    if (save_periodic_position(config, player, inactive, error)) continue;
                    if (inactive) {
                        std::lock_guard lock(persistence_mutex);
                        revoked_sessions.insert(session_id);
                        continue;
                    }
                    std::cerr << "Periodic player snapshot failed: " << error << '\n';
                    std::lock_guard lock(persistence_mutex);
                    if (!persistence_stop_requested && !pending_snapshots.contains(session_id)) {
                        pending_snapshots.emplace(session_id, player);
                    }
                }

                std::unique_lock lock(persistence_mutex);
                if (!persistence_stop_requested && !pending_snapshots.empty()) {
                    persistence_cv.wait_for(lock, std::chrono::seconds(1), [this] {
                        return persistence_stop_requested;
                    });
                }
                if (persistence_stop_requested) return;
            }
        });
    }

    void enqueue_periodic_snapshots() {
        const auto now = Clock::now();
        if (now - last_persistence < std::chrono::seconds(1)) return;
        last_persistence = now;
        {
            std::lock_guard lock(persistence_mutex);
            for (const auto& [peer, player] : players) {
                (void)peer;
                pending_snapshots[player.session_id] = player;
            }
        }
        persistence_cv.notify_one();
    }

    void disconnect_revoked_sessions() {
        std::unordered_set<std::string> revoked;
        {
            std::lock_guard lock(persistence_mutex);
            revoked.swap(revoked_sessions);
        }
        if (revoked.empty()) return;
        for (auto it = players.begin(); it != players.end();) {
            if (revoked.contains(it->second.session_id)) {
                std::cout << "Closing stale world session for character: "
                          << it->second.character_id << '\n';
                enet_peer_disconnect_later(it->first, 7);
                it = players.erase(it);
            } else {
                ++it;
            }
        }
    }

    void broadcast_player_event(honghuang::protocol::MessageType type,
                                const PlayerState& player,
                                ENetPeer* excluded_peer = nullptr) {
        const Json event{
            {"character_id", player.character_id},
            {"name", player.name},
            {"x", player.x}, {"y", player.y}, {"z", player.z},
            {"yaw", player.yaw}
        };
        for (const auto& [peer, recipient] : players) {
            (void)recipient;
            if (peer == excluded_peer) continue;
            send_json(peer, type, event);
        }
    }

    void stop_persistence_worker() {
        {
            std::lock_guard lock(persistence_mutex);
            persistence_stop_requested = true;
            pending_snapshots.clear();
        }
        persistence_cv.notify_all();
        if (persistence_thread.joinable()) persistence_thread.join();
    }

    void start_heartbeat_worker(bool initial_heartbeat_succeeded) {
        heartbeat_thread = std::thread([this, initial_heartbeat_succeeded] {
            auto interval = initial_heartbeat_succeeded ? kHeartbeatInterval : kHeartbeatRetryInterval;
            while (true) {
                std::unique_lock lock(heartbeat_mutex);
                if (heartbeat_cv.wait_for(lock, interval, [this] { return heartbeat_stop_requested; })) {
                    return;
                }
                lock.unlock();

                std::string error;
                if (send_heartbeat(config, online_players.load(std::memory_order_relaxed), "ready", error)) {
                    std::cout << "WorldServer heartbeat accepted; players="
                              << online_players.load(std::memory_order_relaxed) << '\n';
                    interval = kHeartbeatInterval;
                } else {
                    std::cerr << "WorldServer heartbeat failed: " << error << '\n';
                    interval = kHeartbeatRetryInterval;
                }
            }
        });
    }

    void handle_attack(ENetPeer* peer, const Json& command) {
        auto player_it = players.find(peer);
        if (player_it == players.end()) return;
        auto& player = player_it->second;
        const auto now = Clock::now();
        if (player.last_attack_at.time_since_epoch().count() != 0 &&
            now - player.last_attack_at < kAttackCooldown) {
            send_json(peer, honghuang::protocol::MessageType::ServerReject,
                      Json{{"reason", "attack cooldown"}});
            return;
        }
        const auto target_id = command.value("target_entity_id", std::string{});
        if (target_id.empty() || target_id.size() > 96) {
            send_json(peer, honghuang::protocol::MessageType::ServerReject,
                      Json{{"reason", "invalid attack target"}});
            return;
        }
        auto target = std::find_if(monsters.begin(), monsters.end(), [&](const MonsterRuntime& monster) {
            return monster.runtime_id == target_id;
        });
        if (target == monsters.end() || target->state.mode == honghuang::simulation::MonsterMode::Dead) {
            send_json(peer, honghuang::protocol::MessageType::ServerReject,
                      Json{{"reason", "target unavailable"}});
            return;
        }
        const double dx = static_cast<double>(target->state.x) - player.x;
        const double dz = static_cast<double>(target->state.z) - player.z;
        if (dx * dx + dz * dz > static_cast<double>(kAttackRange) * kAttackRange) {
            send_json(peer, honghuang::protocol::MessageType::ServerReject,
                      Json{{"reason", "target out of range"}});
            return;
        }
        const honghuang::simulation::CombatantStats attacker{20, 0, 100, 100};
        const honghuang::simulation::CombatantStats defender{
            static_cast<std::int64_t>(target->definition.attack),
            static_cast<std::int64_t>(target->definition.defense),
            static_cast<std::int64_t>(target->state.health),
            static_cast<std::int64_t>(target->definition.max_health)
        };
        honghuang::simulation::DamageResult damage{};
        if (!honghuang::simulation::calculate_damage(
                attacker, defender, honghuang::simulation::AttackProfile{}, damage)) {
            send_json(peer, honghuang::protocol::MessageType::ServerReject,
                      Json{{"reason", "combat calculation rejected"}});
            return;
        }
        player.last_attack_at = now;
        target->state.health = static_cast<float>(damage.remaining_health);
        if (damage.defeated) {
            target->state.mode = honghuang::simulation::MonsterMode::Dead;
            target->state.target_id.clear();
            target->respawn_at = now + kMonsterRespawnDelay;
        }
        const Json event{
            {"attacker_character_id", player.character_id},
            {"target_entity_id", target->runtime_id},
            {"target_name", target->definition.name},
            {"damage", damage.damage},
            {"remaining_health", damage.remaining_health},
            {"max_health", target->definition.max_health},
            {"defeated", damage.defeated}
        };
        send_json(peer, honghuang::protocol::MessageType::CombatEvent, event);
    }

    void broadcast_snapshot() {
        if (players.empty()) return;

        // Build a per-player interest snapshot. Each player always receives their own
        // authoritative entity plus nearby players; distant entities are omitted and
        // naturally disappear from the client's next snapshot.
        for (const auto& [recipient_peer, recipient] : players) {
            Json entities = Json::array();
            for (const auto& [entity_peer, entity] : players) {
                (void)entity_peer;
                if (entity.character_id != recipient.character_id &&
                    !honghuang::simulation::within_interest_radius(
                        entity.x, entity.z, recipient.x, recipient.z, kInterestRadius)) {
                    continue;
                }
                entities.push_back({
                    {"entity_type", "player"},
                    {"character_id", entity.character_id},
                    {"name", entity.name},
                    {"x", entity.x}, {"y", entity.y}, {"z", entity.z},
                    {"yaw", entity.yaw},
                    {"last_input_sequence", entity.last_input_sequence}
                });
            }
            for (const auto& monster : monsters) {
                if (monster.state.mode == honghuang::simulation::MonsterMode::Dead ||
                    !honghuang::simulation::within_interest_radius(
                        monster.state.x, monster.state.z, recipient.x, recipient.z, kInterestRadius)) {
                    continue;
                }
                entities.push_back({
                    {"entity_type", "monster"},
                    {"entity_id", monster.runtime_id},
                    {"monster_id", monster.definition.id},
                    {"name", monster.definition.name},
                    {"level", monster.definition.level},
                    {"health", monster.state.health},
                    {"max_health", monster.definition.max_health},
                    {"mode", static_cast<int>(monster.state.mode)},
                    {"x", monster.state.x}, {"y", 0.0F}, {"z", monster.state.z}
                });
            }
            const auto payload_text = Json{{"entities", std::move(entities)}}.dump();
            const auto* begin = reinterpret_cast<const std::uint8_t*>(payload_text.data());
            const auto frame = honghuang::protocol::encode_frame(
                honghuang::protocol::MessageType::EntitySnapshot,
                std::span<const std::uint8_t>(begin, payload_text.size()));
            if (frame.empty()) continue;
            auto* packet = enet_packet_create(frame.data(), frame.size(), 0);
            if (packet != nullptr && enet_peer_send(recipient_peer, 1, packet) != 0) {
                enet_packet_destroy(packet);
            }
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
        for (auto& monster : monsters) {
            if (monster.state.mode == honghuang::simulation::MonsterMode::Dead) {
                if (monster.respawn_at.time_since_epoch().count() != 0 && now >= monster.respawn_at) {
                    monster.state = {monster.definition.spawn_x, monster.definition.spawn_z,
                                     monster.definition.max_health};
                    monster.respawn_at = Clock::time_point{};
                }
                continue;
            }
            honghuang::simulation::MonsterTarget target_storage;
            const honghuang::simulation::MonsterTarget* nearest_target = nullptr;
            double nearest_distance_squared = std::numeric_limits<double>::max();
            for (const auto& [peer, player] : players) {
                (void)peer;
                const double dx = static_cast<double>(player.x) - monster.state.x;
                const double dz = static_cast<double>(player.z) - monster.state.z;
                const double distance_squared = dx * dx + dz * dz;
                if (distance_squared < nearest_distance_squared) {
                    nearest_distance_squared = distance_squared;
                    target_storage = {player.character_id, player.x, player.z, true};
                    nearest_target = &target_storage;
                }
            }
            if (!honghuang::simulation::tick_monster(
                    monster.definition, monster.state, nearest_target, delta)) {
                std::cerr << "Skipping invalid monster simulation state: "
                          << monster.runtime_id << '\n';
            }
        }
        last_snapshot = now;
        broadcast_snapshot();
    }
};

EnetServer::EnetServer(ServerConfig config) : impl_(new Impl(std::move(config))) {}
EnetServer::~EnetServer() { stop(); delete impl_; }

bool EnetServer::start() {
    if (impl_->config.backend_url.empty() || impl_->config.node_key.empty() || impl_->config.api_key.empty() ||
        impl_->config.advertise_host.empty() || impl_->config.world_id.empty() ||
        impl_->config.instance_key.empty() || impl_->config.capacity < 1) {
        std::cerr << "BACKEND_URL, WORLD_SERVER_NODE_KEY, WORLD_SERVER_API_KEY, "
                     "WORLD_SERVER_ADVERTISE_HOST, WORLD_ID, WORLD_SERVER_INSTANCE_KEY and "
                     "WORLD_SERVER_CAPACITY are required\n";
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
    impl_->config.max_clients = static_cast<std::size_t>(impl_->config.capacity);
    impl_->host = enet_host_create(&address, impl_->config.max_clients, 2, 0, 0);
    if (impl_->host == nullptr) {
        std::cerr << "Could not create ENet host on UDP port " << impl_->config.port << '\n';
        curl_global_cleanup();
        enet_deinitialize();
        return false;
    }
    std::string heartbeat_error;
    const bool heartbeat_ok = send_heartbeat(impl_->config, 0, "ready", heartbeat_error);
    if (heartbeat_ok) {
        std::cout << "WorldServer initial heartbeat accepted\n";
    } else {
        std::cerr << "WorldServer initial heartbeat failed; background retries enabled: "
                  << heartbeat_error << '\n';
    }
    impl_->heartbeat_stop_requested = false;
    impl_->start_heartbeat_worker(heartbeat_ok);
    impl_->start_persistence_worker();
    impl_->last_persistence = Clock::now();
    std::cout << "WorldServer ENet listening on UDP " << impl_->config.port << '\n';
    return true;
}

void EnetServer::poll(std::uint32_t timeout_ms) {
    if (impl_->host == nullptr) return;
    ENetEvent event{};
    bool first_event = true;
    while (enet_host_service(impl_->host, &event, first_event ? timeout_ms : 0) > 0) {
        first_event = false;
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
                        player.session_id = snapshot.value("session_id", std::string{});
                        player.character_id = snapshot.value("character_id", std::string{});
                        player.name = snapshot.value("name", std::string{});
                        player.x = snapshot.value("position_x", 0.0F);
                        player.y = snapshot.value("position_y", 0.0F);
                        player.z = snapshot.value("position_z", 0.0F);
                        player.yaw = snapshot.value("rotation_y", 0.0F);
                        player.last_input_at = Clock::now();
                        // A successful ticket redemption replaces the character's previous
                        // backend session. Close any older peer on this node before adding
                        // the new authenticated connection, so one character cannot control
                        // two simultaneous ENet peers.
                        for (auto existing = impl_->players.begin(); existing != impl_->players.end();) {
                            if (existing->second.character_id == player.character_id) {
                                std::cout << "Replacing previous connection for character: "
                                          << player.character_id << '\n';
                                impl_->broadcast_player_event(
                                    honghuang::protocol::MessageType::PlayerLeft, existing->second, existing->first);
                                enet_peer_disconnect_later(existing->first, 6);
                                existing = impl_->players.erase(existing);
                            } else {
                                ++existing;
                            }
                        }
                        impl_->players.emplace(event.peer, std::move(player));
                        impl_->broadcast_player_event(
                            honghuang::protocol::MessageType::PlayerJoined, impl_->players.at(event.peer));
                        Json client_welcome = snapshot;
                        client_welcome.erase("session_id");
                        send_json(event.peer, honghuang::protocol::MessageType::ServerWelcome, client_welcome);
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
            } else if (frame.type == honghuang::protocol::MessageType::AttackCommand &&
                       impl_->players.contains(event.peer)) {
                try {
                    const std::string payload(frame.payload.begin(), frame.payload.end());
                    const auto command = Json::parse(payload);
                    impl_->handle_attack(event.peer, command);
                } catch (const std::exception&) {
                    send_json(event.peer, honghuang::protocol::MessageType::ServerReject,
                              Json{{"reason", "invalid attack command"}});
                }
            } else if (frame.type == honghuang::protocol::MessageType::InputCommand &&
                       impl_->players.contains(event.peer)) {
                auto& player = impl_->players.at(event.peer);
                const auto received_at = Clock::now();
                // Drop excess packets before JSON parsing so the limiter also protects CPU time.
                if (received_at - player.last_input_received_at >= kMinimumInputInterval) {
                    player.last_input_received_at = received_at;
                    try {
                        const std::string payload(frame.payload.begin(), frame.payload.end());
                        const auto command = Json::parse(payload);
                        const auto sequence = command.at("sequence").get<std::uint64_t>();
                        float move_x = command.at("move_x").get<float>();
                        float move_z = command.at("move_z").get<float>();
                        if (!honghuang::simulation::normalize_direction(move_x, move_z)) {
                            throw std::runtime_error("movement input must be finite");
                        }
                        if (sequence > player.last_input_sequence) {
                            player.move_x = move_x;
                            player.move_z = move_z;
                            player.jump_requested = command.value("jump", false);
                            if (move_x != 0.0F || move_z != 0.0F) {
                                player.yaw = std::atan2(-move_x, -move_z);
                            }
                            player.last_input_sequence = sequence;
                            player.last_input_at = received_at;
                        }
                    } catch (const std::exception&) {
                        send_json(event.peer, honghuang::protocol::MessageType::ServerReject,
                                  Json{{"reason", "invalid movement input"}});
                        enet_peer_disconnect_later(event.peer, 5);
                    }
                }
            } else {
                send_json(event.peer, honghuang::protocol::MessageType::ServerReject,
                          Json{{"reason", "message not allowed before authentication"}});
                enet_peer_disconnect_later(event.peer, 4);
            }
            enet_packet_destroy(event.packet);
            break;
        }
        case ENET_EVENT_TYPE_DISCONNECT: {
            const auto player = impl_->players.find(event.peer);
            if (player != impl_->players.end()) {
                impl_->broadcast_player_event(
                    honghuang::protocol::MessageType::PlayerLeft, player->second, event.peer);
                std::string snapshot_error;
                if (!save_and_close_session(impl_->config, player->second, snapshot_error)) {
                    std::cerr << "Could not persist disconnected player session: "
                              << snapshot_error << '\n';
                }
                impl_->players.erase(player);
            }
            std::cout << "ENet client disconnected\n";
            break;
        }
        case ENET_EVENT_TYPE_NONE:
            break;
        }
    }
    impl_->disconnect_revoked_sessions();
    impl_->online_players.store(impl_->players.size(), std::memory_order_relaxed);
    impl_->tick_world();
    impl_->enqueue_periodic_snapshots();
}

void EnetServer::stop() {
    if (impl_ != nullptr && impl_->host != nullptr) {
        {
            std::lock_guard lock(impl_->heartbeat_mutex);
            impl_->heartbeat_stop_requested = true;
        }
        impl_->heartbeat_cv.notify_all();
        if (impl_->heartbeat_thread.joinable()) impl_->heartbeat_thread.join();

        impl_->stop_persistence_worker();

        std::string heartbeat_error;
        if (!send_heartbeat(impl_->config, impl_->online_players.load(std::memory_order_relaxed),
                             "draining", heartbeat_error)) {
            std::cerr << "WorldServer draining heartbeat failed: " << heartbeat_error << '\n';
        }

        for (const auto& [peer, player] : impl_->players) {
            (void)peer;
            std::string snapshot_error;
            if (!save_and_close_session(impl_->config, player, snapshot_error)) {
                std::cerr << "Could not persist player during WorldServer shutdown: "
                          << snapshot_error << '\n';
            }
        }
        enet_host_destroy(impl_->host);
        impl_->host = nullptr;
        curl_global_cleanup();
        enet_deinitialize();
        impl_->players.clear();
        std::cout << "WorldServer stopped\n";
    }
}
} // namespace honghuang::network
