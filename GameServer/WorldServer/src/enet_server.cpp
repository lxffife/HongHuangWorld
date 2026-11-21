#include "network/enet_server.hpp"
#include "protocol/frame.hpp"
#include "simulation/movement.hpp"
#include "simulation/monster.hpp"
#include "simulation/combat.hpp"
#include "simulation/weapon_combat.hpp"
#include "simulation/projectile.hpp"
#include "simulation/spell_combat.hpp"
#include "simulation/player_resources.hpp"
#include "simulation/consumable.hpp"
#include "simulation/status_effect.hpp"
#include "persistence/durable_outbox.hpp"
#include "persistence/monster_contribution_writer.hpp"
#include "network/chat_delivery_policy.hpp"

#include <enet/enet.h>
#include <curl/curl.h>
#include <nlohmann/json.hpp>

#include <algorithm>
#include <array>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <atomic>
#include <chrono>
#include <cctype>
#include <condition_variable>
#include <cmath>
#include <iostream>
#include <iomanip>
#include <memory>
#include <limits>
#include <mutex>
#include <optional>
#include <random>
#include <sstream>
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
constexpr auto kManaRegenerationInterval = std::chrono::milliseconds(3000);
constexpr auto kCombatManaRegenerationInterval = std::chrono::milliseconds(6000);
constexpr auto kCombatInactivityWindow = std::chrono::seconds(8);
// The client sends at 20 Hz. Accept modest jitter, but cap command processing at 100 Hz.
constexpr auto kMinimumInputInterval = std::chrono::milliseconds(10);
constexpr float kInterestRadius = 80.0F;
constexpr auto kHeartbeatInterval = std::chrono::seconds(10);

constexpr auto kHeartbeatRetryInterval = std::chrono::seconds(5);

struct PendingSpellCast {
    std::string spell_id;
    std::string target_entity_id;
    Clock::time_point completes_at{};
};

struct BountyObjectiveSubscription {
    std::string task_id;
    std::string objective_key;
    std::string event_type;
};

struct PlayerState {
    std::vector<BountyObjectiveSubscription> bounty_objectives;
    std::string session_id;
    std::string character_id;
    std::string name;
    Json birth_inheritance{Json::object()};
    Json equipment{Json::array()};
    std::int64_t attack{20};
    std::int64_t defense{};
    std::int64_t health{100};
    std::int64_t max_health{100};
    std::int64_t mana{};
    std::int64_t max_mana{};
    std::int32_t constitution{};
    std::int32_t agility{};
    std::int32_t spirit{};
    std::int32_t vitality{};
    float movement_speed{5.0F};
    honghuang::simulation::TimedSlowEffect slow_effect;
    honghuang::simulation::TimedFreezeEffect freeze_effect;
    honghuang::simulation::PeriodicDamageEffect poison_effect;
    std::string poison_source_entity_id;
    float x{};
    float y{};
    float z{};
    float yaw{};
    float move_x{};
    float move_z{};
    float vertical_velocity{};
    bool jump_requested{};
    std::uint64_t last_input_sequence{};
    std::uint64_t accepted_inputs_since_diagnostic{};
    Clock::time_point last_input_at{Clock::now()};
    Clock::time_point last_input_received_at{};
    Clock::time_point last_movement_diagnostic_at{Clock::now()};
    Clock::time_point last_attack_at{};
    Clock::time_point last_mana_regen_at{Clock::now()};
    Clock::time_point last_combat_at{};
    bool mana_regen_was_in_combat{false};
    std::unordered_map<std::string, Clock::time_point> last_spell_at_by_id;
    std::optional<PendingSpellCast> pending_spell;
    Clock::time_point last_pickup_at{};
    Clock::time_point last_chat_at{};
    Clock::time_point last_combat_refresh_at{};
};

enum class MonsterAttackPhase { Ready, Windup, Recovery };

struct MonsterDamageContribution {
    std::string session_id;
    std::string character_id;
    std::int64_t total_damage{};
    std::int64_t hit_count{};
    Clock::time_point first_hit_at{};
    Clock::time_point last_hit_at{};
    // Preserve the objective subscriptions that were active when this
    // authenticated character contributed damage, even if the last hitter
    // belongs to a different bounty (or no bounty at all).
    std::vector<BountyObjectiveSubscription> bounty_objectives;
};

struct MonsterRuntime {
    honghuang::simulation::MonsterDefinition definition;
    honghuang::simulation::MonsterState state;
    std::string runtime_id;
    Clock::time_point respawn_at{};
    Clock::time_point last_attack_at{};
    Clock::time_point attack_phase_started_at{};
    MonsterAttackPhase attack_phase{MonsterAttackPhase::Ready};
    std::string attack_target_character_id;
    bool rare_spawn{false};
    int spawn_chance_percent{100};
    int retry_spawn_seconds{60};
    int first_spawn_delay_seconds{0};
    honghuang::simulation::TimedSlowEffect slow_effect;
    honghuang::simulation::TimedFreezeEffect freeze_effect;
    honghuang::simulation::PeriodicDamageEffect burn_effect;
    std::string burn_owner_character_id;
    // Preserve authenticated attribution at effect application for delayed ticks after disconnect.
    std::string burn_owner_session_id;
    std::vector<BountyObjectiveSubscription> burn_owner_bounty_objectives;
    std::unordered_map<std::string, MonsterDamageContribution> damage_contributions;
    // runtime_id identifies the stable spawn point; this ID identifies one life of that spawn.
    std::string contribution_instance_id;
};


struct LootEntry {
    std::string monster_id;
    std::string item_id;
    std::string item_name;
    int quality{};
    int drop_chance_bp{};
    int min_quantity{};
    int max_quantity{};
    int max_stack{};
    std::string icon_key;
};

struct GroundDropRuntime {
    std::string id;
    std::string session_id;
    std::string owner_character_id;
    std::string item_id;
    int quantity{};
    float x{};
    float z{};
    Clock::time_point expires_at{};
    bool pickup_pending{};
};

struct DropJob {
    bool pickup{};
    GroundDropRuntime drop;
    std::string event_id;
    std::string request_session_id;
    unsigned int attempts{};
};

struct DropJobResult {
    bool pickup{};
    GroundDropRuntime drop;
    std::string event_id;
    bool success{};
    std::string error;
};

struct ChatJob {
    std::string session_id;
    std::string character_id;
    std::string client_message_id;
    std::string content;
    std::vector<std::string> recipient_character_ids;
};

struct ChatJobResult {
    std::string session_id;
    std::string client_message_id;
    bool accepted{};
    std::string message_id;
    std::string reason;
};

struct CombatRefreshJob { std::string session_id, character_id; };
struct CombatRefreshResult {
    std::string session_id, character_id;
    bool success{};
    Json stats{Json::object()};
    std::string error;
};

struct BountyRefreshJob {
    std::string session_id;
    std::string character_id;
};
struct BountyRefreshResult {
    std::string session_id;
    std::string character_id;
    bool success{};
    std::vector<BountyObjectiveSubscription> objectives;
    std::string error;
};

struct ConsumableJob { std::string session_id, character_id, request_id, item_id; int quantity{}; std::int64_t health{}, max_health{}, mana{}, max_mana{}; };
struct ConsumableJobResult {
    std::string session_id, character_id, request_id, item_id;
    bool success{};
    Json result{Json::object()};
    std::string error;
};

struct CharacterRewardEvent {
    std::string event_id;
    std::string session_id;
    std::string character_id;
    std::int64_t experience{};
    std::int64_t cultivation{};
    unsigned int attempts{};
};

struct SoulRewardEvent {
    std::string event_id;
    std::string session_id;
    std::string character_id;
    std::int64_t experience{};
    std::string source;
};

struct SoulAbsorptionEvent {
    std::string event_id;
    std::string session_id;
    std::string character_id;
    std::string source_entity_id;
    std::string source_entity_kind;
};

struct ProjectileRuntime {
    std::string id;
    std::string owner_character_id;
    std::string target_entity_id;
    float x{};
    float y{};
    float z{};
    float velocity_x{};
    float velocity_z{};
    std::int64_t attack{};
    std::int32_t power_basis_points{10000};
    std::int32_t defense_penetration_basis_points{};
    Clock::time_point expires_at{};
    std::string projectile_type{"arrow"};
    std::int32_t slow_duration_ms{};
    float slow_multiplier{1.0F};
    std::int32_t freeze_duration_ms{};
    std::int32_t burn_duration_ms{};
    std::int32_t burn_interval_ms{};
    std::int32_t burn_damage_basis_points{};
};

std::string make_event_uuid() {
    static thread_local std::mt19937_64 generator(std::random_device{}());
    std::array<std::uint8_t, 16> bytes{};
    for (std::size_t i = 0; i < bytes.size(); i += 8) {
        const auto value = generator();
        for (std::size_t j = 0; j < 8; ++j) {
            bytes[i + j] = static_cast<std::uint8_t>((value >> (j * 8)) & 0xffU);
        }
    }
    bytes[6] = static_cast<std::uint8_t>((bytes[6] & 0x0fU) | 0x40U);
    bytes[8] = static_cast<std::uint8_t>((bytes[8] & 0x3fU) | 0x80U);
    std::ostringstream output;
    output << std::hex << std::setfill('0');
    for (std::size_t i = 0; i < bytes.size(); ++i) {
        output << std::setw(2) << static_cast<unsigned int>(bytes[i]);
        if (i == 3 || i == 5 || i == 7 || i == 9) output << '-';
    }
    return output.str();
}

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

std::int64_t mana_for_session_close(const PlayerState& player) {
    auto mana = player.mana;
    if (player.pending_spell.has_value()) {
        const auto* spell = honghuang::simulation::find_spell_definition(player.pending_spell->spell_id);
        if (spell != nullptr) mana = std::min(player.max_mana, mana + spell->mana_cost);
    }
    return mana;
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
        {"rotation_y", player.yaw},
        {"health", player.health},
        {"mana", mana_for_session_close(player)}
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
        {"rotation_y", player.yaw},
        {"health", player.health},
        {"mana", player.mana}
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


bool deliver_character_reward(const ServerConfig& config, const CharacterRewardEvent& reward,
                              long& http_status, std::string& error) {
    CURL* curl = curl_easy_init();
    if (curl == nullptr) { error = "could not initialize character reward HTTP client"; return false; }
    const std::string url = config.backend_url + "/api/v1/servers/characters/rewards";
    const std::string body = Json{
        {"event_id", reward.event_id},
        {"session_id", reward.session_id},
        {"character_id", reward.character_id},
        {"experience", reward.experience},
        {"cultivation", reward.cultivation}
    }.dump();
    std::string response;
    struct curl_slist* headers = nullptr;
    headers = curl_slist_append(headers, "Content-Type: application/json");
    const std::string auth_header = "X-World-Server-Key: " + config.api_key;
    const std::string node_header = "X-World-Server-Node: " + config.node_key;
    headers = curl_slist_append(headers, auth_header.c_str());
    headers = curl_slist_append(headers, node_header.c_str());
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_POST, 1L);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body.c_str());
    curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, static_cast<long>(body.size()));
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, collect_response);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, 1500L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, 4000L);
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
    const auto result = curl_easy_perform(curl);
    http_status = 0;
    if (result == CURLE_OK) curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_status);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    if (result != CURLE_OK) {
        error = std::string("character reward request failed: ") + curl_easy_strerror(result);
        return false;
    }
    if (http_status != 200) {
        error = "character reward rejected by backend (HTTP " + std::to_string(http_status) + ")";
        return false;
    }
    return true;
}


bool backend_inventory_request(const ServerConfig& config, const std::string& path,
                               const Json* body, long& http_status, Json& response,
                               std::string& error);

bool fetch_bounty_objectives(const ServerConfig& config, const std::string& session_id,
                             const std::string& character_id,
                             std::vector<BountyObjectiveSubscription>& objectives,
                             long& http_status, std::string& error) {
    CURL* curl = curl_easy_init();
    if (curl == nullptr) { error = "could not initialize bounty objective HTTP client"; return false; }
    const std::string url = config.backend_url +
        "/api/v1/servers/bounties/objectives?session_id=" + session_id +
        "&character_id=" + character_id;
    std::string response_text;
    struct curl_slist* headers = nullptr;
    headers = curl_slist_append(headers, "Accept: application/json");
    const std::string auth_header = "X-World-Server-Key: " + config.api_key;
    const std::string node_header = "X-World-Server-Node: " + config.node_key;
    headers = curl_slist_append(headers, auth_header.c_str());
    headers = curl_slist_append(headers, node_header.c_str());
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_HTTPGET, 1L);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, collect_response);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response_text);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, 1500L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, 4000L);
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
    const auto result = curl_easy_perform(curl);
    http_status = 0;
    if (result == CURLE_OK) curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_status);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    if (result != CURLE_OK) {
        error = std::string("bounty objective request failed: ") + curl_easy_strerror(result);
        return false;
    }
    if (http_status != 200) {
        error = "bounty objective lookup rejected by backend (HTTP " + std::to_string(http_status) + ")";
        return false;
    }
    try {
        const auto response = Json::parse(response_text);
        const auto items = response.at("objectives");
        if (!items.is_array()) throw std::runtime_error("objectives must be an array");
        std::vector<BountyObjectiveSubscription> parsed;
        parsed.reserve(items.size());
        for (const auto& item : items) {
            BountyObjectiveSubscription objective{
                item.at("task_id").get<std::string>(),
                item.at("objective_key").get<std::string>(),
                item.at("event_type").get<std::string>()
            };
            if (objective.task_id.empty() || objective.objective_key.empty() ||
                objective.event_type != "monster_killed") continue;
            parsed.push_back(std::move(objective));
        }
        objectives = std::move(parsed);
        return true;
    } catch (const std::exception& exception) {
        error = std::string("invalid bounty objective response: ") + exception.what();
        return false;
    }
}

bool deliver_soul_absorption(const ServerConfig& config, const SoulAbsorptionEvent& event,
                             long& status, std::string& error) {
    const Json body{
        {"event_id", event.event_id}, {"session_id", event.session_id},
        {"character_id", event.character_id}, {"source_entity_id", event.source_entity_id},
        {"source_entity_kind", event.source_entity_kind}
    };
    Json response;
    return backend_inventory_request(config, "/api/v1/servers/souls/absorptions",
                                     &body, status, response, error);
}

bool deliver_soul_reward(const ServerConfig& config, const SoulRewardEvent& reward,
                          long& http_status, std::string& error) {
    CURL* curl = curl_easy_init();
    if (curl == nullptr) { error = "could not initialize soul reward HTTP client"; return false; }
    const std::string url = config.backend_url + "/api/v1/servers/souls/rewards";
    const std::string body = Json{
        {"event_id", reward.event_id},
        {"session_id", reward.session_id},
        {"character_id", reward.character_id},
        {"experience", reward.experience},
        {"source", reward.source}
    }.dump();
    std::string response;
    struct curl_slist* headers = nullptr;
    headers = curl_slist_append(headers, "Content-Type: application/json");
    const std::string auth_header = "X-World-Server-Key: " + config.api_key;
    const std::string node_header = "X-World-Server-Node: " + config.node_key;
    headers = curl_slist_append(headers, auth_header.c_str());
    headers = curl_slist_append(headers, node_header.c_str());
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_POST, 1L);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body.c_str());
    curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, static_cast<long>(body.size()));
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, collect_response);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, 1500L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, 4000L);
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
    const auto result = curl_easy_perform(curl);
    http_status = 0;
    if (result == CURLE_OK) curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_status);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    if (result != CURLE_OK) {
        error = std::string("soul reward request failed: ") + curl_easy_strerror(result);
        return false;
    }
    if (http_status != 200) {
        error = "soul reward rejected by backend (HTTP " + std::to_string(http_status) + ")";
        return false;
    }
    return true;
}

bool backend_inventory_request(const ServerConfig& config, const std::string& path,
                               const Json* body, long& http_status, Json& response,
                               std::string& error) {
    CURL* curl = curl_easy_init();
    if (curl == nullptr) { error = "could not initialize inventory HTTP client"; return false; }
    const std::string url = config.backend_url + path;
    const std::string payload = body == nullptr ? std::string{} : body->dump();
    std::string response_text;
    struct curl_slist* headers = nullptr;
    headers = curl_slist_append(headers, "Accept: application/json");
    headers = curl_slist_append(headers, "Content-Type: application/json");
    const std::string auth_header = "X-World-Server-Key: " + config.api_key;
    const std::string node_header = "X-World-Server-Node: " + config.node_key;
    headers = curl_slist_append(headers, auth_header.c_str());
    headers = curl_slist_append(headers, node_header.c_str());
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    if (body != nullptr) {
        curl_easy_setopt(curl, CURLOPT_POST, 1L);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, payload.c_str());
        curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, static_cast<long>(payload.size()));
    } else {
        curl_easy_setopt(curl, CURLOPT_HTTPGET, 1L);
    }
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, collect_response);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response_text);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, 1500L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, 4000L);
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
    const auto result = curl_easy_perform(curl);
    http_status = 0;
    if (result == CURLE_OK) curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_status);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    if (result != CURLE_OK) {
        error = std::string("inventory request failed: ") + curl_easy_strerror(result);
        return false;
    }
    if (http_status < 200 || http_status >= 300) {
        error = "inventory backend returned HTTP " + std::to_string(http_status);
        return false;
    }
    try {
        response = response_text.empty() ? Json::object() : Json::parse(response_text);
    } catch (const std::exception&) {
        error = "inventory backend returned invalid JSON";
        return false;
    }
    return true;
}

bool load_loot_table(const ServerConfig& config, std::vector<LootEntry>& entries, std::string& error) {
    long status = 0;
    Json response;
    if (!backend_inventory_request(config, "/api/v1/servers/loot-table", nullptr, status, response, error)) {
        return false;
    }
    if (!response.is_object() || !response.contains("entries") || !response["entries"].is_array()) {
        error = "loot table response is missing entries";
        return false;
    }
    std::vector<LootEntry> loaded;
    for (const auto& value : response["entries"]) {
        if (!value.is_object()) continue;
        LootEntry entry;
        try {
            entry.monster_id = value.at("monster_id").get<std::string>();
            entry.item_id = value.at("item_id").get<std::string>();
            entry.item_name = value.value("item_name", std::string{});
            entry.quality = value.value("quality", 1);
            entry.drop_chance_bp = value.at("drop_chance_bp").get<int>();
            entry.min_quantity = value.at("min_quantity").get<int>();
            entry.max_quantity = value.at("max_quantity").get<int>();
            entry.max_stack = value.at("max_stack").get<int>();
            entry.icon_key = value.value("icon_key", std::string{});
        } catch (const std::exception&) {
            error = "loot table contains an invalid entry";
            return false;
        }
        if (entry.monster_id.empty() || entry.item_id.empty() ||
            entry.drop_chance_bp < 0 || entry.drop_chance_bp > 10000 ||
            entry.min_quantity < 1 || entry.max_quantity < entry.min_quantity ||
            entry.max_quantity > entry.max_stack || entry.max_stack < 1) {
            error = "loot table entry failed validation";
            return false;
        }
        loaded.push_back(std::move(entry));
    }
    entries = std::move(loaded);
    return true;
}

bool load_monster_spawn_config(const ServerConfig& config,std::vector<MonsterRuntime>& monsters,std::string& error) {
    long status=0;
    Json response;
    if(!backend_inventory_request(config,"/api/v1/servers/monster-spawn-config",nullptr,status,response,error))return false;
    if(!response.is_object()||!response.contains("entries")||!response["entries"].is_array()){
        error="monster spawn config response is missing entries";return false;
    }
    std::vector<MonsterRuntime> loaded;
    for(const auto& value:response["entries"]){
        if(!value.is_object()){error="monster spawn config contains a non-object entry";return false;}
        try{
            honghuang::simulation::MonsterDefinition definition;
            definition.id=value.at("monster_id").get<std::string>();
            definition.name=value.at("name").get<std::string>();
            definition.level=value.at("level").get<int>();
            definition.max_health=value.at("max_health").get<float>();
            definition.attack=value.at("attack").get<float>();
            definition.defense=value.at("defense").get<float>();
            definition.move_speed=value.at("move_speed").get<float>();
            definition.aggro_radius=value.at("aggro_radius").get<float>();
            definition.leash_radius=value.at("leash_radius").get<float>();
            definition.attack_range=value.value("attack_range", 1.8F);
            definition.attack_range=honghuang::simulation::monster_attack_profile(definition).range;
            const float x=value.at("spawn_x").get<float>();
            const float z=value.at("spawn_z").get<float>();
            const auto runtime_id=value.at("runtime_id").get<std::string>();
            const bool rare=value.at("rare_spawn").get<bool>();
            const int chance=value.at("spawn_chance_percent").get<int>();
            const int retry=value.at("retry_spawn_seconds").get<int>();
            const int first_delay=value.at("first_spawn_delay_seconds").get<int>();
            if(runtime_id.empty()||!honghuang::simulation::valid_monster_definition(definition)||
               !std::isfinite(x)||!std::isfinite(z)||chance<1||chance>100||retry<1||
               retry>604800||first_delay<0||first_delay>604800){
                error="monster spawn config entry failed validation";return false;
            }
            definition.spawn_x=x;definition.spawn_z=z;
            MonsterRuntime runtime;
            runtime.definition=std::move(definition);
            runtime.runtime_id=runtime_id;
            runtime.contribution_instance_id=make_event_uuid();
            runtime.rare_spawn=rare;
            runtime.spawn_chance_percent=chance;
            runtime.retry_spawn_seconds=retry;
            runtime.first_spawn_delay_seconds=first_delay;
            runtime.state={x,z,runtime.definition.max_health};
            if(rare||first_delay>0){
                runtime.state.mode=honghuang::simulation::MonsterMode::Dead;
                runtime.respawn_at=Clock::now()+std::chrono::seconds(std::max(first_delay,1));
            }
            loaded.push_back(std::move(runtime));
        }catch(const std::exception&){
            error="monster spawn config contains an invalid entry";return false;
        }
    }
    monsters=std::move(loaded);
    return true;
}

bool load_persisted_ground_drops(const ServerConfig& config, std::vector<GroundDropRuntime>& drops,
                                 std::string& error) {
    long status = 0;
    Json response;
    if (!backend_inventory_request(config, "/api/v1/servers/drops", nullptr, status, response, error)) return false;
    if (!response.is_object() || !response.contains("drops") || !response["drops"].is_array()) {
        error = "ground drop response is missing drops";
        return false;
    }
    std::vector<GroundDropRuntime> loaded;
    for (const auto& value : response["drops"]) {
        if (!value.is_object()) continue;
        try {
            GroundDropRuntime drop;
            drop.id = value.at("id").get<std::string>();
            drop.session_id = value.at("session_id").get<std::string>();
            drop.owner_character_id = value.at("owner_character_id").get<std::string>();
            drop.item_id = value.at("item_id").get<std::string>();
            drop.quantity = value.at("quantity").get<int>();
            drop.x = value.at("position_x").get<float>();
            drop.z = value.at("position_z").get<float>();
            const int remaining = value.at("remaining_seconds").get<int>();
            if (drop.id.empty() || drop.owner_character_id.empty() || drop.item_id.empty() ||
                drop.quantity < 1 || remaining < 1 || !std::isfinite(drop.x) || !std::isfinite(drop.z)) {
                continue;
            }
            drop.expires_at = Clock::now() + std::chrono::seconds(remaining);
            drop.pickup_pending = false;
            loaded.push_back(std::move(drop));
        } catch (const std::exception&) {
            error = "ground drop response contains an invalid entry";
            return false;
        }
    }
    drops = std::move(loaded);
    return true;
}

bool deliver_ground_drop(const ServerConfig& config, const GroundDropRuntime& drop,
                         long& status, std::string& error) {
    const Json body{
        {"drop_id", drop.id}, {"session_id", drop.session_id},
        {"character_id", drop.owner_character_id}, {"item_id", drop.item_id},
        {"quantity", drop.quantity}, {"position_x", drop.x}, {"position_z", drop.z}
    };
    Json response;
    return backend_inventory_request(config, "/api/v1/servers/drops", &body, status, response, error);
}

bool deliver_ground_pickup(const ServerConfig& config, const DropJob& job,
                           long& status, std::string& error) {
    const Json body{
        {"event_id", job.event_id}, {"drop_id", job.drop.id},
        {"session_id", job.request_session_id}, {"character_id", job.drop.owner_character_id}
    };
    Json response;
    return backend_inventory_request(config, "/api/v1/servers/drops/pickup", &body, status, response, error);
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
bool deliver_chat_message(const ServerConfig& config, const ChatJob& job,
                          long& http_status, std::string& message_id, std::string& error) {
    if (config.chat_backend_url.empty()) {
        error = "CHAT_SERVER_URL is not configured";
        return false;
    }
    CURL* curl = curl_easy_init();
    if (curl == nullptr) {
        error = "could not initialize ChatServer HTTP client";
        return false;
    }
    const std::string base_url = config.chat_backend_url.back() == '/'
        ? config.chat_backend_url.substr(0, config.chat_backend_url.size() - 1)
        : config.chat_backend_url;
    const std::string url = base_url + "/api/v1/servers/chat/messages";
    const std::string body = Json{
        {"session_id", job.session_id},
        {"character_id", job.character_id},
        {"client_message_id", job.client_message_id},
        {"channel", "nearby"},
        {"content", job.content},
        {"recipient_character_ids", job.recipient_character_ids}
    }.dump();
    std::string response_text;
    struct curl_slist* headers = nullptr;
    headers = curl_slist_append(headers, "Accept: application/json");
    headers = curl_slist_append(headers, "Content-Type: application/json");
    const std::string auth_header = "X-World-Server-Key: " + config.api_key;
    const std::string node_header = "X-World-Server-Node: " + config.node_key;
    headers = curl_slist_append(headers, auth_header.c_str());
    headers = curl_slist_append(headers, node_header.c_str());
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_POST, 1L);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body.c_str());
    curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, static_cast<long>(body.size()));
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, collect_response);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response_text);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, 1500L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, 4000L);
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
    const auto result = curl_easy_perform(curl);
    http_status = 0;
    if (result == CURLE_OK) curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_status);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    if (result != CURLE_OK) {
        error = std::string("ChatServer request failed: ") + curl_easy_strerror(result);
        return false;
    }
    if (http_status != 201) {
        error = "ChatServer rejected nearby message (HTTP " + std::to_string(http_status) + ")";
        return false;
    }
    try {
        const auto response = Json::parse(response_text);
        message_id = response.at("message").at("id").get<std::string>();
        if (message_id.empty()) {
            error = "ChatServer response did not contain a message ID";
            return false;
        }
    } catch (const std::exception& exception) {
        error = std::string("invalid ChatServer response: ") + exception.what();
        return false;
    }
    return true;
}

} // namespace

struct EnetServer::Impl {
    ServerConfig config;
    ENetHost* host{};
    std::unordered_map<ENetPeer*, PlayerState> players;
    std::vector<MonsterRuntime> monsters;
    std::mutex monster_config_mutex;
    std::condition_variable monster_config_cv;
    bool monster_config_stop_requested{false};
    bool pending_monster_config_ready{false};
    std::vector<MonsterRuntime> pending_monster_config;
    std::thread monster_config_thread;
    std::vector<LootEntry> loot_table;
    std::mutex loot_table_mutex;
    std::mutex loot_refresh_mutex;
    std::condition_variable loot_refresh_cv;
    bool loot_refresh_stop_requested{false};
    std::thread loot_refresh_thread;
    std::vector<GroundDropRuntime> ground_drops;
    std::vector<ProjectileRuntime> projectiles;
    std::unique_ptr<honghuang::persistence::DurableOutbox> durable_outbox;
    // Declared after durable_outbox so it is destroyed first and never outlives its SQLite owner.
    std::unique_ptr<honghuang::persistence::MonsterContributionWriter> monster_contribution_writer;
    std::mutex outbox_mutex;
    std::condition_variable outbox_cv;
    bool outbox_stop_requested{false};
    std::thread outbox_thread;
    std::mutex drop_mutex;
    std::condition_variable drop_cv;
    std::deque<DropJob> pending_drop_jobs;
    std::deque<DropJobResult> completed_drop_jobs;
    bool drop_stop_requested{false};
    std::thread drop_thread;
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
    std::mutex reward_mutex;
    std::condition_variable reward_cv;
    std::deque<CharacterRewardEvent> pending_rewards;
    bool reward_stop_requested{false};
    std::thread reward_thread;
    std::mutex chat_mutex;
    std::condition_variable chat_cv;
    std::deque<ChatJob> pending_chat_jobs;
    std::deque<ChatJobResult> completed_chat_jobs;
    bool chat_stop_requested{false};
    std::thread chat_thread;
    std::mutex consumable_mutex;
    std::condition_variable consumable_cv;
    std::deque<ConsumableJob> pending_consumable_jobs;
    std::deque<ConsumableJobResult> completed_consumable_jobs;
    std::unordered_set<std::string> pending_consumable_sessions;
    std::unordered_set<std::string> snapshot_inflight_sessions;
    std::unordered_set<std::string> skip_stale_consumable_snapshots;
    std::unordered_map<std::string, PlayerState> pending_consumable_closes;
    bool consumable_stop_requested{false};
    std::thread consumable_thread;
    std::mutex combat_refresh_mutex;
    std::condition_variable combat_refresh_cv;
    std::deque<CombatRefreshJob> pending_combat_refresh_jobs;
    std::deque<CombatRefreshResult> completed_combat_refresh_jobs;
    std::unordered_set<std::string> pending_combat_refresh_sessions;
    bool combat_refresh_stop_requested{false};
    std::thread combat_refresh_thread;
    std::mutex bounty_refresh_mutex;
    std::condition_variable bounty_refresh_cv;
    std::deque<BountyRefreshJob> pending_bounty_refresh_jobs;
    std::deque<BountyRefreshResult> completed_bounty_refresh_jobs;
    std::unordered_set<std::string> pending_bounty_refresh_sessions;
    bool bounty_refresh_stop_requested{false};
    std::thread bounty_refresh_thread;
    Clock::time_point last_bounty_refresh_enqueued_at{};
    std::mutex chat_outbox_mutex;
    std::condition_variable chat_outbox_cv;
    bool chat_outbox_stop_requested{false};
    std::thread chat_outbox_thread;
    Clock::time_point last_chat_outbox_metrics_at{};

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
            monsters.back().contribution_instance_id = make_event_uuid();
        };
        if (config.world_id == "qingyun_human") {
            add_monster("wolf-001", "wilderness_wolf", "荒原狼", 3, 80.0F, 12.0F, 4.0F,
                        2.8F, 10.0F, 24.0F, -12.0F, -8.0F);
            add_monster("wolf-002", "wilderness_wolf", "荒原狼", 3, 80.0F, 12.0F, 4.0F,
                        2.8F, 10.0F, 24.0F, 13.0F, -7.0F);
            add_monster("wolf-003", "wilderness_wolf", "荒原狼", 3, 80.0F, 12.0F, 4.0F,
                        2.8F, 10.0F, 24.0F, 0.0F, 17.0F);
        } else if (config.world_id == "underworld_fengdu") {
            add_monster("wraith-001", "wandering_wraith", "游祟", 3, 80.0F, 12.0F, 4.0F,
                        2.4F, 10.0F, 24.0F, -12.0F, -8.0F);
            add_monster("wraith-002", "wandering_wraith", "游祟", 3, 80.0F, 12.0F, 4.0F,
                        2.4F, 10.0F, 24.0F, 13.0F, -7.0F);
            add_monster("wraith-003", "wandering_wraith", "游祟", 3, 80.0F, 12.0F, 4.0F,
                        2.4F, 10.0F, 24.0F, 0.0F, 17.0F);
            add_monster("war-soul-001", "blazing_war_soul", "炽战残魂", 4, 105.0F, 16.0F, 5.0F,
                        2.5F, 11.0F, 26.0F, -24.0F, -18.0F);
            add_monster("war-soul-elite-001", "blazing_war_soul_elite", "精英炽战残魂", 6, 190.0F, 22.0F, 8.0F,
                        2.2F, 12.0F, 28.0F, -34.0F, 2.0F);
            add_monster("war-soul-ancient-001", "blazing_war_soul_ancient", "远古炽战残魂", 9, 360.0F, 30.0F, 14.0F,
                        1.9F, 13.0F, 30.0F, 34.0F, 3.0F);
            add_monster("battlefield-god-soul-001", "ancient_battlefield_god_soul", "古战场·上古战神残魂", 12, 720.0F, 38.0F, 20.0F,
                        1.7F, 15.0F, 32.0F, -43.0F, 27.0F);
            // Rare soul bodies are dormant spawn points. Resolve them by stable
            // runtime ID rather than vector position so future spawn additions
            // cannot silently assign the rare schedule to the wrong monsters.
            const auto configure_rare_spawn = [&](const std::string& runtime_id,
                                                   int chance_percent,
                                                   int retry_seconds,
                                                   int first_delay_seconds) {
                const auto found = std::find_if(monsters.begin(), monsters.end(),
                    [&](const MonsterRuntime& monster) { return monster.runtime_id == runtime_id; });
                if (found == monsters.end()) {
                    std::cerr << "Rare soul spawn point missing: " << runtime_id << '\n';
                    return;
                }
                found->rare_spawn = true;
                found->spawn_chance_percent = std::clamp(chance_percent, 1, 100);
                found->retry_spawn_seconds = std::max(retry_seconds, 1);
                found->state.mode = honghuang::simulation::MonsterMode::Dead;
                found->respawn_at = Clock::now() + std::chrono::seconds(std::max(first_delay_seconds, 1));
            };
            configure_rare_spawn("war-soul-elite-001", 35, 180, 60);
            configure_rare_spawn("war-soul-ancient-001", 12, 600, 240);
            // The battlefield god soul is a distinct high-risk encounter. Its
            // soul reward is still gated by the player's own causal choice.
            configure_rare_spawn("battlefield-god-soul-001", 5, 900, 300);
            add_monster("ironbone-001", "ironbone_beast_soul", "铁骨兽魂", 4, 145.0F, 13.0F, 9.0F,
                        1.8F, 10.0F, 25.0F, 25.0F, -19.0F);
            add_monster("gale-wraith-001", "gale_wraith", "疾风游魂", 4, 75.0F, 15.0F, 3.0F,
                        3.8F, 13.0F, 28.0F, -26.0F, 19.0F);
            add_monster("spirit-wisp-001", "spirit_scholar_wisp", "灵识游魂", 5, 90.0F, 18.0F, 4.0F,
                        2.2F, 12.0F, 27.0F, 26.0F, 18.0F);
            add_monster("wangchuan-echo-wisp-001", "wangchuan_echo_wisp", "忘川回音灵识", 8, 245.0F, 24.0F, 12.0F,
                        1.8F, 11.0F, 26.0F, 23.0F, -20.0F);
            configure_rare_spawn("wangchuan-echo-wisp-001", 20, 300, 90);
            add_monster("life-soul-001", "life_ancient_soul", "生机古魂", 6, 180.0F, 18.0F, 10.0F,
                        1.6F, 10.0F, 25.0F, 0.0F, -30.0F);
            add_monster("faceless-001", "faceless_essence", "无相灵魄", 8, 220.0F, 22.0F, 12.0F,
                        1.4F, 9.0F, 24.0F, 0.0F, 31.0F);
        }
    }


    static std::int64_t wall_clock_ms() {
        return std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count();
    }

    bool enqueue_durable_event(const std::string& event_id, const std::string& type,
                               const Json& payload, std::string& error) {
        if (!durable_outbox) { error = "durable outbox is not initialized"; return false; }
        const auto now = wall_clock_ms();
        const bool stored = durable_outbox->enqueue(
            honghuang::persistence::OutboxEvent{event_id, type, payload.dump(), 0, now, now, {}}, error);
        if (stored) {
            outbox_cv.notify_one();
            chat_outbox_cv.notify_one();
        }
        return stored;
    }

    bool enqueue_durable_events(const std::vector<honghuang::persistence::OutboxEvent>& events,
                                std::string& error) {
        if (!durable_outbox) { error = "durable outbox is not initialized"; return false; }
        if (events.empty()) return true;
        const bool stored = durable_outbox->enqueue_batch(events, error);
        if (stored) {
            outbox_cv.notify_one();
            chat_outbox_cv.notify_one();
        }
        return stored;
    }

    void start_outbox_worker() {
        outbox_stop_requested = false;
        outbox_thread = std::thread([this] {
            while (true) {
                {
                    std::lock_guard lock(outbox_mutex);
                    if (outbox_stop_requested) return;
                }
                std::string storage_error;
                auto event = durable_outbox->claim_due_excluding(wall_clock_ms(), "nearby_chat", storage_error);
                if (!event) {
                    if (!storage_error.empty()) std::cerr << "Outbox claim failed: " << storage_error << '\n';
                    std::unique_lock lock(outbox_mutex);
                    if (outbox_stop_requested) return;
                    outbox_cv.wait_for(lock, std::chrono::milliseconds(500));
                    continue;
                }

                long status = 0;
                std::string message_id;
                std::string delivery_error;
                bool delivered = false;
                bool is_drop = false;
                GroundDropRuntime delivered_drop;
                try {
                    const Json payload = Json::parse(event->payload);
                    if (event->event_type == "character_reward") {
                        CharacterRewardEvent reward{
                            event->event_id, payload.at("session_id").get<std::string>(),
                            payload.at("character_id").get<std::string>(),
                            payload.at("experience").get<std::int64_t>(),
                            payload.at("cultivation").get<std::int64_t>(), event->attempts
                        };
                        delivered = deliver_character_reward(config, reward, status, delivery_error);
                    } else if (event->event_type == "soul_reward") {
                        SoulRewardEvent reward{
                            event->event_id, payload.at("session_id").get<std::string>(),
                            payload.at("character_id").get<std::string>(),
                            payload.at("experience").get<std::int64_t>(),
                            payload.at("source").get<std::string>()
                        };
                        delivered = deliver_soul_reward(config, reward, status, delivery_error);
                    } else if (event->event_type == "bounty_objective_event") {
                        Json response;
                        delivered = backend_inventory_request(config, "/api/v1/servers/bounties/events",
                                                              &payload, status, response, delivery_error); 
                    } else if (event->event_type == "bounty_monster_contributions") {
                        Json response;
                        delivered = backend_inventory_request(config, "/api/v1/servers/bounties/contributions",
                                                              &payload, status, response, delivery_error);
                    } else if (event->event_type == "soul_absorption") {
                        SoulAbsorptionEvent absorption{
                            event->event_id, payload.at("session_id").get<std::string>(),
                            payload.at("character_id").get<std::string>(),
                            payload.at("source_entity_id").get<std::string>(),
                            payload.at("source_entity_kind").get<std::string>()
                        };
                        delivered = deliver_soul_absorption(config, absorption, status, delivery_error);
                    } else if (event->event_type == "ground_drop_pickup") {
                        is_drop = true;
                        GroundDropRuntime pickup_drop{
                            payload.at("drop_id").get<std::string>(),
                            payload.at("drop_session_id").get<std::string>(),
                            payload.at("character_id").get<std::string>(),
                            payload.at("item_id").get<std::string>(),
                            payload.at("quantity").get<int>(),
                            payload.at("position_x").get<float>(),
                            payload.at("position_z").get<float>(),
                            Clock::now() + std::chrono::milliseconds(60000), true
                        };
                        DropJob pickup_job{
                            true, pickup_drop, event->event_id,
                            payload.at("request_session_id").get<std::string>(), event->attempts
                        };
                        delivered_drop = pickup_drop;
                        delivered = deliver_ground_pickup(config, pickup_job, status, delivery_error);
                    } else if (event->event_type == "ground_drop_create") {
                        is_drop = true;
                        const auto expiry_ms = payload.at("expires_at_unix_ms").get<std::int64_t>();
                        const auto remaining_ms = std::max<std::int64_t>(0, expiry_ms - wall_clock_ms());
                        delivered_drop = GroundDropRuntime{
                            payload.at("drop_id").get<std::string>(),
                            payload.at("session_id").get<std::string>(),
                            payload.at("character_id").get<std::string>(),
                            payload.at("item_id").get<std::string>(),
                            payload.at("quantity").get<int>(),
                            payload.at("position_x").get<float>(),
                            payload.at("position_z").get<float>(),
                            Clock::now() + std::chrono::milliseconds(remaining_ms), false
                        };
                        delivered = deliver_ground_drop(config, delivered_drop, status, delivery_error);
                    } else {
                        status = 400;
                        delivery_error = "unsupported durable outbox event type: " + event->event_type;
                    }
                } catch (const std::exception& exception) {
                    status = 400;
                    delivery_error = std::string("invalid outbox payload: ") + exception.what();
                }

                if (delivered) {
                    std::string mark_error;
                    if (!durable_outbox->mark_delivered(event->event_id, mark_error))
                        std::cerr << "Outbox delivered marker failed; idempotent replay expected: " << mark_error << '\n';
                    if (is_drop) {
                        std::lock_guard lock(drop_mutex);
                        const bool pickup = event->event_type == "ground_drop_pickup";
                        completed_drop_jobs.push_back(DropJobResult{
                            pickup, std::move(delivered_drop), event->event_id, true, {}
                        });
                    }
                    continue;
                }

                if (status >= 300 && status < 500) {
                    std::string dead_error;
                    if (!durable_outbox->move_to_dead_letter(
                            event->event_id, event->attempts + 1, delivery_error, dead_error))
                        std::cerr << "Outbox dead-letter update failed: " << dead_error << '\n';
                    else
                        std::cerr << "Outbox event dead-lettered (HTTP " << status << "): "
                                  << event->event_id << " " << delivery_error << '\n';
                    if (event->event_type == "ground_drop_pickup") {
                        try {
                            const Json payload = Json::parse(event->payload);
                            GroundDropRuntime failed_drop{
                                payload.at("drop_id").get<std::string>(),
                                payload.at("drop_session_id").get<std::string>(),
                                payload.at("character_id").get<std::string>(),
                                payload.at("item_id").get<std::string>(),
                                payload.at("quantity").get<int>(),
                                payload.at("position_x").get<float>(),
                                payload.at("position_z").get<float>(),
                                Clock::now() + std::chrono::seconds(60), true
                            };
                            std::lock_guard lock(drop_mutex);
                            completed_drop_jobs.push_back(DropJobResult{
                                true, std::move(failed_drop), event->event_id, false, delivery_error
                            });
                        } catch (const std::exception&) {
                            std::cerr << "Could not reconstruct failed pickup event " << event->event_id << '\n';
                        }
                    }
                    continue;
                }

                const auto attempts = event->attempts == std::numeric_limits<std::uint32_t>::max()
                    ? event->attempts : event->attempts + 1;
                const auto exponent = std::min<std::uint32_t>(attempts, 8U);
                const auto delay_ms = std::min<std::int64_t>(1000LL * (1LL << exponent), 300000LL);
                std::string retry_error;
                if (!durable_outbox->schedule_retry(
                        event->event_id, attempts, wall_clock_ms() + delay_ms,
                        delivery_error, retry_error))
                    std::cerr << "Outbox retry scheduling failed: " << retry_error << '\n';
            }
        });
    }

    void start_chat_outbox_worker() {
        chat_outbox_stop_requested = false;
        chat_outbox_thread = std::thread([this] {
            while (true) {
                {
                    std::lock_guard lock(chat_outbox_mutex);
                    if (chat_outbox_stop_requested) return;
                }
                const auto metrics_now = Clock::now();
                if (last_chat_outbox_metrics_at == Clock::time_point{} ||
                    metrics_now - last_chat_outbox_metrics_at >= std::chrono::seconds(60)) {
                    std::string metrics_error;
                    const auto metrics = durable_outbox->stats(wall_clock_ms(), metrics_error, "nearby_chat");
                    if (metrics_error.empty()) {
                        std::clog << "[ChatOutbox] pending=" << metrics.pending
                                  << " inflight=" << metrics.inflight
                                  << " dead_letter=" << metrics.dead_letter
                                  << " oldest_pending_seconds=" << metrics.oldest_pending_age_ms / 1000
                                  << " oldest_dead_letter_seconds=" << metrics.oldest_dead_letter_age_ms / 1000
                                  << '\n';
                        if (metrics.dead_letter > 0 || metrics.oldest_pending_age_ms >= 60000) {
                            std::cerr << "[ChatOutbox][WARN] delivery attention required: dead_letter="
                                      << metrics.dead_letter
                                      << " oldest_pending_seconds=" << metrics.oldest_pending_age_ms / 1000
                                      << '\n';
                        }
                    } else {
                        std::cerr << "[ChatOutbox] metrics failed: " << metrics_error << '\n';
                    }
                    last_chat_outbox_metrics_at = metrics_now;
                }
                std::string storage_error;
                auto event = durable_outbox->claim_due_type(wall_clock_ms(), "nearby_chat", storage_error);
                if (!event) {
                    if (!storage_error.empty()) std::cerr << "Chat outbox claim failed: " << storage_error << '\n';
                    std::unique_lock lock(chat_outbox_mutex);
                    if (chat_outbox_stop_requested) return;
                    chat_outbox_cv.wait_for(lock, std::chrono::milliseconds(500));
                    continue;
                }

                long status = 0;
                std::string message_id;
                std::string delivery_error;
                bool delivered = false;
                try {
                    const Json payload = Json::parse(event->payload);
                    ChatJob chat;
                    chat.session_id = payload.at("session_id").get<std::string>();
                    chat.character_id = payload.at("character_id").get<std::string>();
                    chat.client_message_id = payload.at("client_message_id").get<std::string>();
                    chat.content = payload.at("content").get<std::string>();
                    chat.recipient_character_ids = payload.at("recipient_character_ids").get<std::vector<std::string>>();
                    delivered = deliver_chat_message(config, chat, status, message_id, delivery_error);
                } catch (const std::exception& exception) {
                    status = 400;
                    delivery_error = std::string("invalid nearby chat outbox payload: ") + exception.what();
                }

                if (delivered) {
                    std::string mark_error;
                    if (!durable_outbox->mark_delivered(event->event_id, mark_error)) {
                        std::cerr << "Nearby chat delivered marker failed; idempotent replay expected: "
                                  << mark_error << '\n';
                    }
                    continue;
                }
                if (honghuang::network::chat_delivery_is_permanent_http_error(status)) {
                    std::string dead_error;
                    if (!durable_outbox->move_to_dead_letter(
                            event->event_id, event->attempts + 1, delivery_error, dead_error)) {
                        std::cerr << "Nearby chat dead-letter update failed: " << dead_error << '\n';
                    } else {
                        std::cerr << "Nearby chat outbox event dead-lettered (HTTP " << status
                                  << "): " << event->event_id << " " << delivery_error << '\n';
                    }
                    continue;
                }
                const auto attempts = event->attempts == std::numeric_limits<std::uint32_t>::max()
                    ? event->attempts : event->attempts + 1;
                const auto exponent = std::min<std::uint32_t>(attempts, 8U);
                const auto delay_ms = std::min<std::int64_t>(1000LL * (1LL << exponent), 300000LL);
                std::string retry_error;
                if (!durable_outbox->schedule_retry(
                        event->event_id, attempts, wall_clock_ms() + delay_ms,
                        delivery_error, retry_error)) {
                    std::cerr << "Nearby chat retry scheduling failed: " << retry_error << '\n';
                }
            }
        });
    }

    void stop_chat_outbox_worker() {
        {
            std::lock_guard lock(chat_outbox_mutex);
            chat_outbox_stop_requested = true;
        }
        chat_outbox_cv.notify_all();
        if (chat_outbox_thread.joinable()) chat_outbox_thread.join();
    }

    void stop_outbox_worker() {
        {
            std::lock_guard lock(outbox_mutex);
            outbox_stop_requested = true;
        }
        outbox_cv.notify_all();
        if (outbox_thread.joinable()) outbox_thread.join();
    }

    void start_reward_worker() {
        reward_stop_requested = false;
        reward_thread = std::thread([this] {
            while (true) {
                CharacterRewardEvent reward;
                {
                    std::unique_lock lock(reward_mutex);
                    reward_cv.wait(lock, [this] {
                        return reward_stop_requested || !pending_rewards.empty();
                    });
                    if (reward_stop_requested && pending_rewards.empty()) return;
                    reward = std::move(pending_rewards.front());
                    pending_rewards.pop_front();
                }
                long status = 0;
                std::string error;
                if (deliver_character_reward(config, reward, status, error)) {
                    std::cout << "Character reward persisted: character=" << reward.character_id
                              << " experience=" << reward.experience
                              << " cultivation=" << reward.cultivation << '\n';
                    continue;
                }
                const bool retryable = status == 0 || status >= 500;
                if (retryable && reward.attempts < 6) {
                    ++reward.attempts;
                    const auto delay = std::chrono::seconds(
                        std::min<unsigned int>(1U << std::min(reward.attempts, 4U), 10U));
                    std::cerr << "Character reward delivery will retry in " << delay.count()
                              << "s: " << error << '\n';
                    std::this_thread::sleep_for(delay);
                    {
                        std::lock_guard lock(reward_mutex);
                        pending_rewards.push_front(std::move(reward));
                    }
                    reward_cv.notify_one();
                } else {
                    std::cerr << "Character reward was not persisted and will not be retried: "
                              << error << '\n';
                }
            }
        });
    }

    void enqueue_character_reward(CharacterRewardEvent reward) {
        const Json payload{
            {"session_id", reward.session_id}, {"character_id", reward.character_id},
            {"experience", reward.experience}, {"cultivation", reward.cultivation}
        };
        std::string error;
        if (!enqueue_durable_event(reward.event_id, "character_reward", payload, error))
            std::cerr << "Could not persist character reward: " << error << '\n';
    }

    void enqueue_soul_reward(const PlayerState& player, std::int64_t experience,
                             const std::string& source) {
        if (experience <= 0 || source.empty()) return;
        const auto event_id = make_event_uuid();
        const Json payload{
            {"session_id", player.session_id},
            {"character_id", player.character_id},
            {"experience", experience},
            {"source", source}
        };
        std::string error;
        if (!enqueue_durable_event(event_id, "soul_reward", payload, error))
            std::cerr << "Could not persist soul reward: " << error << '\n';
    }

    honghuang::persistence::MonsterContributionRecord make_monster_contribution_record(
        const MonsterRuntime& monster, const std::string& session_id,
        const std::string& character_id,
        const std::vector<BountyObjectiveSubscription>& subscriptions,
        std::int64_t effective_damage) const {
        honghuang::persistence::MonsterContributionRecord record;
        record.write_id = make_event_uuid();
        record.monster_instance_id = monster.contribution_instance_id;
        record.monster_definition_id = monster.definition.id;
        record.session_id = session_id;
        record.character_id = character_id;
        record.total_damage = effective_damage;
        record.hit_count = 1;
        record.first_hit_at_ms = wall_clock_ms();
        record.last_hit_at_ms = record.first_hit_at_ms;

        Json objectives = Json::array();
        for (const auto& objective : subscriptions) {
            if (objective.event_type != "monster_killed" ||
                objective.objective_key != monster.definition.id) continue;
            const auto duplicate = std::any_of(objectives.begin(), objectives.end(),
                [&objective](const Json& existing) {
                    return existing.value("task_id", std::string{}) == objective.task_id &&
                           existing.value("objective_key", std::string{}) == objective.objective_key &&
                           existing.value("event_type", std::string{}) == objective.event_type;
                });
            if (!duplicate) {
                objectives.push_back({
                    {"task_id", objective.task_id},
                    {"objective_key", objective.objective_key},
                    {"event_type", objective.event_type}
                });
            }
        }
        record.bounty_objectives_json = objectives.dump();
        return record;
    }

    honghuang::persistence::MonsterContributionRecord make_monster_contribution_record(
        const MonsterRuntime& monster, const PlayerState& player,
        std::int64_t effective_damage) const {
        return make_monster_contribution_record(
            monster, player.session_id, player.character_id, player.bounty_objectives, effective_damage);
    }

    void record_monster_damage(MonsterRuntime& monster, const std::string& session_id,
                               const std::string& character_id,
                               const std::vector<BountyObjectiveSubscription>& subscriptions,
                               std::int64_t effective_damage) {
        if (effective_damage <= 0 || session_id.empty() || character_id.empty()) return;
        // Keep the legacy in-memory compatibility view bounded even if a spawn is attacked by a crowd.
        const std::string contributor_key = session_id + ":" + character_id;
        auto found = monster.damage_contributions.find(contributor_key);
        if (found == monster.damage_contributions.end()) {
            constexpr std::size_t kMaximumContributorsPerSpawn = 256;
            if (monster.damage_contributions.size() >= kMaximumContributorsPerSpawn) {
                // Keep the bounded ledger focused on the strongest observed
                // contributors instead of permanently favoring the first 64
                // characters to touch the spawn. The incoming hit is the only
                // evidence available for an unseen contributor, so admission
                // is intentionally conservative and deterministic.
                auto weakest = std::min_element(
                    monster.damage_contributions.begin(), monster.damage_contributions.end(),
                    [](const auto& left, const auto& right) {
                        if (left.second.total_damage != right.second.total_damage)
                            return left.second.total_damage < right.second.total_damage;
                        return left.second.character_id > right.second.character_id;
                    });
                if (weakest == monster.damage_contributions.end() ||
                    effective_damage <= weakest->second.total_damage) {
                    return;
                }
                monster.damage_contributions.erase(weakest);
            }
            MonsterDamageContribution contribution;
            contribution.session_id = session_id;
            contribution.character_id = character_id;
            contribution.first_hit_at = Clock::now();
            contribution.last_hit_at = contribution.first_hit_at;
            found = monster.damage_contributions.emplace(contributor_key, std::move(contribution)).first;
        }
        auto& contribution = found->second;
        for (const auto& objective : subscriptions) {
            if (objective.event_type != "monster_killed" ||
                objective.objective_key != monster.definition.id) continue;
            const auto already_tracked = std::any_of(
                contribution.bounty_objectives.begin(), contribution.bounty_objectives.end(),
                [&objective](const auto& existing) {
                    return existing.task_id == objective.task_id &&
                           existing.objective_key == objective.objective_key &&
                           existing.event_type == objective.event_type;
                });
            if (!already_tracked) contribution.bounty_objectives.push_back(objective);
        }
        if (contribution.total_damage > std::numeric_limits<std::int64_t>::max() - effective_damage)
            contribution.total_damage = std::numeric_limits<std::int64_t>::max();
        else
            contribution.total_damage += effective_damage;
        if (contribution.hit_count < std::numeric_limits<std::int64_t>::max())
            ++contribution.hit_count;
        contribution.last_hit_at = Clock::now();
    }

    void record_monster_damage(MonsterRuntime& monster, const PlayerState& player,
                               std::int64_t effective_damage) {
        record_monster_damage(monster, player.session_id, player.character_id,
                              player.bounty_objectives, effective_damage);
    }

    Json monster_contribution_snapshot(const MonsterRuntime& monster) const {
        std::vector<MonsterDamageContribution> contributors;
        contributors.reserve(monster.damage_contributions.size());
        for (const auto& [key, contribution] : monster.damage_contributions) {
            (void)key;
            contributors.push_back(contribution);
        }
        std::sort(contributors.begin(), contributors.end(), [](const auto& left, const auto& right) {
            if (left.total_damage != right.total_damage) return left.total_damage > right.total_damage;
            return left.character_id < right.character_id;
        });
        Json result = Json::array();
        for (const auto& contribution : contributors) {
            result.push_back({
                {"session_id", contribution.session_id},
                {"character_id", contribution.character_id},
                {"damage", contribution.total_damage},
                {"hit_count", contribution.hit_count}
            });
        }
        return result;
    }

    void log_monster_contribution_snapshot(const MonsterRuntime& monster) const {
        const auto snapshot = monster_contribution_snapshot(monster);
        if (snapshot.empty()) return;
        std::cout << "Monster defeated; authoritative damage contributors: monster="
                  << monster.runtime_id << " contributors=" << snapshot.dump() << '\n';
    }

    void enqueue_bounty_kill_events(const PlayerState* killer, const MonsterRuntime& monster) {
        std::vector<honghuang::persistence::OutboxEvent> batch;
        const auto now = wall_clock_ms();
        const auto contributors = monster_contribution_snapshot(monster);

        // A bounty contribution snapshot belongs to every task represented by
        // at least one accepted contributor's cached objective subscription.
        // The final hitter is not required to be a participant.
        std::vector<BountyObjectiveSubscription> objectives;
        for (const auto& [key, contribution] : monster.damage_contributions) {
            (void)key;
            for (const auto& objective : contribution.bounty_objectives) {
                const auto already_tracked = std::any_of(
                    objectives.begin(), objectives.end(), [&objective](const auto& existing) {
                        return existing.task_id == objective.task_id &&
                               existing.objective_key == objective.objective_key &&
                               existing.event_type == objective.event_type;
                    });
                if (!already_tracked) objectives.push_back(objective);
            }
        }

        for (const auto& objective : objectives) {
            if (objective.event_type != "monster_killed" ||
                objective.objective_key != monster.definition.id) continue;

            // Objective progress remains attributed only to an authenticated
            // online killer with the matching subscription. A delayed burn tick
            // may defeat the monster after its owner has disconnected; in that
            // case we still persist prior contributors below, without inventing
            // a killer identity or granting kill progress.
            const auto killer_has_objective = killer != nullptr && std::any_of(
                killer->bounty_objectives.begin(), killer->bounty_objectives.end(),
                [&objective](const auto& killer_objective) {
                    return killer_objective.task_id == objective.task_id &&
                           killer_objective.objective_key == objective.objective_key &&
                           killer_objective.event_type == objective.event_type;
                });
            if (killer_has_objective) {
                const auto event_id = make_event_uuid();
                const Json kill_payload{
                    {"event_id", event_id},
                    {"task_id", objective.task_id},
                    {"session_id", killer->session_id},
                    {"character_id", killer->character_id},
                    {"objective_key", objective.objective_key},
                    {"event_type", "monster_killed"}
                };
                batch.push_back(honghuang::persistence::OutboxEvent{
                    event_id, "bounty_objective_event", kill_payload.dump(), 0, now, now, {}
                });
            }

            if (!contributors.empty()) {
                const auto contribution_event_id = make_event_uuid();
                const Json contribution_payload{
                    {"event_id", contribution_event_id},
                    {"task_id", objective.task_id},
                    {"monster_instance_id", monster.contribution_instance_id},
                    {"monster_definition_id", objective.objective_key},
                    {"contributors", contributors}
                };
                batch.push_back(honghuang::persistence::OutboxEvent{
                    contribution_event_id, "bounty_monster_contributions",
                    contribution_payload.dump(), 0, now, now, {}
                });
            }
        }
        if (batch.empty()) return;
        std::string error;
        if (!enqueue_durable_events(batch, error)) {
            std::cerr << "Could not atomically persist bounty kill and contribution events for monster "
                      << monster.runtime_id << ": " << error << '\n';
        }
    }

    void enqueue_soul_absorption(const PlayerState& player, const MonsterRuntime& monster) {
        if (config.world_id != "underworld_fengdu") return;
        const auto& kind = monster.definition.id;
        if (kind != "wandering_wraith" && kind != "blazing_war_soul" &&
            kind != "blazing_war_soul_elite" && kind != "blazing_war_soul_ancient" &&
            kind != "blazing_war_soul_mythic" && kind != "ancient_battlefield_god_soul" &&
            kind != "ironbone_beast_soul" && kind != "gale_wraith" &&
            kind != "spirit_scholar_wisp" && kind != "wangchuan_echo_wisp" && kind != "life_ancient_soul" &&
            kind != "faceless_essence") return;
        const auto event_id = make_event_uuid();
        const Json payload{
            {"session_id", player.session_id},
            {"character_id", player.character_id},
            {"source_entity_id", monster.runtime_id},
            {"source_entity_kind", monster.definition.id}
        };
        std::string error;
        if (!enqueue_durable_event(event_id, "soul_absorption", payload, error))
            std::cerr << "Could not persist soul absorption: " << error << '\n';
    }

    void stop_reward_worker() {
        {
            std::lock_guard lock(reward_mutex);
            reward_stop_requested = true;
        }
        reward_cv.notify_all();
        if (reward_thread.joinable()) reward_thread.join();
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
                    {
                        std::lock_guard lock(consumable_mutex);
                        if (pending_consumable_sessions.contains(session_id)) continue;
                        if (skip_stale_consumable_snapshots.erase(session_id) > 0) continue;
                        // Reserve this session before issuing the HTTP write.
                        // Consumable commands are rejected while this reservation
                        // exists, so the two database writes cannot cross.
                        snapshot_inflight_sessions.insert(session_id);
                    }
                    bool inactive = false;
                    std::string error;
                    const bool saved = save_periodic_position(config, player, inactive, error);
                    {
                        std::lock_guard lock(consumable_mutex);
                        snapshot_inflight_sessions.erase(session_id);
                    }
                    if (saved) continue;
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
        std::unordered_set<std::string> consumable_sessions;
        {
            std::lock_guard lock(consumable_mutex);
            consumable_sessions = pending_consumable_sessions;
        }
        {
            std::lock_guard lock(persistence_mutex);
            for (const auto& [peer, player] : players) {
                (void)peer;
                // Never write an older in-memory resource snapshot while a DB
                // consumable transaction is in flight for this character.
                if (consumable_sessions.contains(player.session_id)) continue;
                pending_snapshots[player.session_id] = player;
            }
        }
        persistence_cv.notify_one();
    }

    void close_player_session_or_defer(ENetPeer* peer) {
        const auto player = players.find(peer);
        if (player == players.end()) return;
        bool consumable_pending = false;
        {
            std::lock_guard lock(consumable_mutex);
            consumable_pending = pending_consumable_sessions.contains(player->second.session_id);
        }
        if (consumable_pending) {
            pending_consumable_closes[player->second.session_id] = player->second;
        } else {
            std::string close_error;
            if (!save_and_close_session(config, player->second, close_error)) {
                std::cerr << "Could not persist disconnected player session: " << close_error << '\n';
            }
        }
        players.erase(player);
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
                std::cout << "Closing revoked world session for character: "
                          << it->second.character_id << '\n';
                // The backend marks the session as 'saving' before the periodic
                // snapshot receives HTTP 409. Persist the latest state and close
                // the session before removing the peer.
                broadcast_player_event(honghuang::protocol::MessageType::PlayerLeft,
                                       it->second, it->first);
                const auto peer = it->first;
                ++it;
                close_player_session_or_defer(peer);
                enet_peer_disconnect_later(peer, 7);
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
            {"birth_inheritance", player.birth_inheritance},
            {"equipment", player.equipment},
            {"mana", player.mana}, {"max_mana", player.max_mana},
            {"poisoned", player.poison_effect.ticks_remaining > 0},
            {"x", player.x}, {"y", player.y}, {"z", player.z},
            {"yaw", player.yaw}
        };
        for (const auto& [peer, recipient] : players) {
            (void)recipient;
            if (peer == excluded_peer) continue;
            send_json(peer, type, event);
        }
    }

    std::string player_weapon_type(const PlayerState& player) const {
        for (const auto& item : player.equipment) {
            if (!item.is_object()) continue;
            const auto slot = item.value("slot", item.value("equipment_slot", std::string{}));
            if (slot != "weapon") continue;
            const auto weapon_type = item.value("weapon_type", std::string{});
            if (!weapon_type.empty()) return weapon_type;
            // Compatibility for snapshots created before migration 000049.
            std::string identity = item.value("name", std::string{}) + " " + item.value("item_id", std::string{});
            std::transform(identity.begin(), identity.end(), identity.begin(),
                           [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
            if (identity.find("spear") != std::string::npos || identity.find("lance") != std::string::npos ||
                identity.find("长枪") != std::string::npos || identity.find("长矛") != std::string::npos ||
                identity.find("枪") != std::string::npos) return "spear";
            if (identity.find("bow") != std::string::npos || identity.find("crossbow") != std::string::npos ||
                identity.find("弓") != std::string::npos) return "bow";
            if (identity.find("staff") != std::string::npos || identity.find("wand") != std::string::npos ||
                identity.find("法杖") != std::string::npos || identity.find("拂尘") != std::string::npos ||
                identity.find("法器") != std::string::npos) return "staff";
            if (identity.find("hammer") != std::string::npos || identity.find("锤") != std::string::npos) return "hammer";
            if (identity.find("axe") != std::string::npos || identity.find("斧") != std::string::npos) return "axe";
            if (identity.find("dagger") != std::string::npos || identity.find("匕首") != std::string::npos) return "dagger";
            if (identity.find("sword") != std::string::npos || identity.find("blade") != std::string::npos ||
                identity.find("剑") != std::string::npos || identity.find("刀") != std::string::npos) return "sword";
        }
        return {};
    }

    std::string player_attack_style(const PlayerState& player) const {
        const auto weapon_type = player_weapon_type(player);
        if (weapon_type == "spear") return "spear_thrust";
        if (weapon_type == "bow") return "ranged_shot";
        if (weapon_type == "staff" || weapon_type == "focus") return "staff_cast";
        if (weapon_type == "axe" || weapon_type == "hammer") return "heavy_swing";
        if (weapon_type == "sword" || weapon_type == "dagger") return "sword_slash";
        return "melee";
    }
    void broadcast_player_action_event(const PlayerState& player,
                                       const std::string& action,
                                       const std::string& target_entity_id = {},
                                       const std::string& attack_style = {},
                                       ENetPeer* excluded_peer = nullptr) {
        const Json event{
            {"character_id", player.character_id},
            {"action", action},
            {"target_entity_id", target_entity_id},
            {"attack_style", attack_style}
        };
        const double interest_radius_squared =
            static_cast<double>(kInterestRadius) * static_cast<double>(kInterestRadius);
        for (const auto& [peer, recipient] : players) {
            if (peer == excluded_peer) continue;
            const double dx = static_cast<double>(recipient.x) - player.x;
            const double dz = static_cast<double>(recipient.z) - player.z;
            if (dx * dx + dz * dz > interest_radius_squared) continue;
            send_json(peer, honghuang::protocol::MessageType::PlayerActionEvent, event);
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


    void start_monster_config_refresh_worker() {
        monster_config_stop_requested=false;
        monster_config_thread=std::thread([this]{
            while(true){
                {
                    std::unique_lock lock(monster_config_mutex);
                    if(monster_config_cv.wait_for(lock,std::chrono::seconds(30),[this]{return monster_config_stop_requested;}))return;
                }
                std::vector<MonsterRuntime> refreshed;
                std::string error;
                if(!load_monster_spawn_config(config,refreshed,error)){
                    std::cerr<<"Monster spawn config refresh failed; keeping previous runtime: "<<error<<'\n';
                    continue;
                }
                const auto count=refreshed.size();
                {
                    std::lock_guard lock(monster_config_mutex);
                    pending_monster_config=std::move(refreshed);
                    pending_monster_config_ready=true;
                }
                std::cout<<"Monster spawn config fetched; entries="<<count<<"; awaiting main-loop apply\n";
            }
        });
    }

    void stop_monster_config_refresh_worker() {
        {
            std::lock_guard lock(monster_config_mutex);
            monster_config_stop_requested=true;
        }
        monster_config_cv.notify_all();
        if(monster_config_thread.joinable())monster_config_thread.join();
    }

    void apply_pending_monster_config() {
        std::vector<MonsterRuntime> refreshed;
        {
            std::lock_guard lock(monster_config_mutex);
            if(!pending_monster_config_ready)return;
            refreshed=std::move(pending_monster_config);
            pending_monster_config.clear();
            pending_monster_config_ready=false;
        }
        std::vector<MonsterRuntime> merged;
        merged.reserve(refreshed.size());
        for(auto& next:refreshed){
            const auto found=std::find_if(monsters.begin(),monsters.end(),[&](const MonsterRuntime& current){return current.runtime_id==next.runtime_id;});
            if(found==monsters.end()){
                merged.push_back(std::move(next));
                continue;
            }
            MonsterRuntime current=*found;
            const bool rare_changed=current.rare_spawn!=next.rare_spawn;
            const bool first_delay_changed=current.first_spawn_delay_seconds!=next.first_spawn_delay_seconds;
            current.definition=std::move(next.definition);
            current.spawn_chance_percent=next.spawn_chance_percent;
            current.retry_spawn_seconds=next.retry_spawn_seconds;
            current.first_spawn_delay_seconds=next.first_spawn_delay_seconds;
            if(rare_changed){
                current.rare_spawn=next.rare_spawn;
                if(current.rare_spawn){
                    current.state.health=0.0F;
                    current.state.mode=honghuang::simulation::MonsterMode::Dead;
                    current.state.target_id.clear();
                    current.respawn_at=next.respawn_at;
                }else{
                    current.state={current.definition.spawn_x,current.definition.spawn_z,current.definition.max_health};
                    current.contribution_instance_id=make_event_uuid();
                    current.damage_contributions.clear();
                    current.respawn_at=Clock::time_point{};
                }
            }else{
                current.rare_spawn=next.rare_spawn;
                current.state.health=std::min(current.state.health,current.definition.max_health);
                // A changed first-spawn delay takes effect immediately for a
                // dormant spawn point. Living monsters keep their current life.
                if(first_delay_changed&&current.state.mode==honghuang::simulation::MonsterMode::Dead){
                    current.respawn_at=Clock::now()+std::chrono::seconds(current.first_spawn_delay_seconds);
                }
            }
            merged.push_back(std::move(current));
        }
        monsters=std::move(merged);
        std::cout<<"Applied monster spawn configuration; active spawn points="<<monsters.size()<<'\n';
    }

    void start_bounty_refresh_worker() {
        bounty_refresh_stop_requested = false;
        bounty_refresh_thread = std::thread([this] {
            while (true) {
                BountyRefreshJob job;
                {
                    std::unique_lock lock(bounty_refresh_mutex);
                    bounty_refresh_cv.wait(lock, [this] {
                        return bounty_refresh_stop_requested || !pending_bounty_refresh_jobs.empty();
                    });
                    if (bounty_refresh_stop_requested) return;
                    job = std::move(pending_bounty_refresh_jobs.front());
                    pending_bounty_refresh_jobs.pop_front();
                }

                BountyRefreshResult result;
                result.session_id = job.session_id;
                result.character_id = job.character_id;
                long status = 0;
                result.success = fetch_bounty_objectives(
                    config, job.session_id, job.character_id, result.objectives, status, result.error);
                if (!result.success && result.error.empty()) {
                    result.error = "bounty objective refresh failed (HTTP " + std::to_string(status) + ")";
                }
                {
                    std::lock_guard lock(bounty_refresh_mutex);
                    completed_bounty_refresh_jobs.push_back(std::move(result));
                }
            }
        });
    }

    void stop_bounty_refresh_worker() {
        {
            std::lock_guard lock(bounty_refresh_mutex);
            bounty_refresh_stop_requested = true;
            pending_bounty_refresh_jobs.clear();
        }
        bounty_refresh_cv.notify_all();
        if (bounty_refresh_thread.joinable()) bounty_refresh_thread.join();
    }

    void enqueue_periodic_bounty_refreshes() {
        const auto now = Clock::now();
        if (last_bounty_refresh_enqueued_at != Clock::time_point{} &&
            now - last_bounty_refresh_enqueued_at < std::chrono::seconds(15)) return;
        last_bounty_refresh_enqueued_at = now;

        std::lock_guard lock(bounty_refresh_mutex);
        if (bounty_refresh_stop_requested || !bounty_refresh_thread.joinable()) return;
        for (const auto& [peer, player] : players) {
            (void)peer;
            if (player.session_id.empty() || player.character_id.empty() ||
                pending_bounty_refresh_sessions.contains(player.session_id)) continue;
            if (pending_bounty_refresh_jobs.size() >= 512) {
                std::cerr << "Bounty objective refresh queue is full; remaining sessions will retry later\n";
                break;
            }
            pending_bounty_refresh_sessions.insert(player.session_id);
            pending_bounty_refresh_jobs.push_back({player.session_id, player.character_id});
        }
        bounty_refresh_cv.notify_one();
    }

    void drain_bounty_refresh_results() {
        std::deque<BountyRefreshResult> completed;
        {
            std::lock_guard lock(bounty_refresh_mutex);
            completed.swap(completed_bounty_refresh_jobs);
            for (const auto& result : completed) pending_bounty_refresh_sessions.erase(result.session_id);
        }
        for (auto& result : completed) {
            if (!result.success) {
                std::cerr << "Bounty objective refresh failed for character "
                          << result.character_id << "; keeping previous subscriptions: "
                          << result.error << '\n';
                continue;
            }
            const auto player = std::find_if(players.begin(), players.end(), [&](const auto& entry) {
                return entry.second.session_id == result.session_id &&
                       entry.second.character_id == result.character_id;
            });
            if (player == players.end()) continue;
            const auto previous_count = player->second.bounty_objectives.size();
            player->second.bounty_objectives = std::move(result.objectives);
            std::cout << "Refreshed bounty objectives for character " << result.character_id
                      << "; previous=" << previous_count
                      << "; current=" << player->second.bounty_objectives.size() << '\n';
        }
    }

    void start_loot_refresh_worker() {
        loot_refresh_stop_requested = false;
        loot_refresh_thread = std::thread([this] {
            while (true) {
                {
                    std::unique_lock lock(loot_refresh_mutex);
                    if (loot_refresh_cv.wait_for(lock, std::chrono::seconds(30),
                            [this] { return loot_refresh_stop_requested; })) {
                        return;
                    }
                }
                std::vector<LootEntry> refreshed;
                std::string error;
                if (!load_loot_table(config, refreshed, error)) {
                    std::cerr << "Monster loot table refresh failed; keeping previous configuration: "
                              << error << '\n';
                    continue;
                }
                const auto count = refreshed.size();
                {
                    std::lock_guard lock(loot_table_mutex);
                    loot_table = std::move(refreshed);
                }
                std::cout << "Monster loot table refreshed; entries=" << count << '\n';
            }
        });
    }

    void stop_loot_refresh_worker() {
        {
            std::lock_guard lock(loot_refresh_mutex);
            loot_refresh_stop_requested = true;
        }
        loot_refresh_cv.notify_all();
        if (loot_refresh_thread.joinable()) loot_refresh_thread.join();
    }

    void start_drop_worker() {
        drop_stop_requested = false;
        drop_thread = std::thread([this] {
            while (true) {
                DropJob job;
                {
                    std::unique_lock lock(drop_mutex);
                    drop_cv.wait(lock, [this] { return drop_stop_requested || !pending_drop_jobs.empty(); });
                    if (drop_stop_requested && pending_drop_jobs.empty()) return;
                    job = std::move(pending_drop_jobs.front());
                    pending_drop_jobs.pop_front();
                }
                long status = 0;
                std::string error;
                const bool delivered = job.pickup
                    ? deliver_ground_pickup(config, job, status, error)
                    : deliver_ground_drop(config, job.drop, status, error);
                if (!delivered && (status == 0 || status >= 500) && job.attempts < 6) {
                    ++job.attempts;
                    const auto delay = std::chrono::seconds(
                        std::min<unsigned int>(1U << std::min(job.attempts, 4U), 10U));
                    std::cerr << "Inventory request will retry in " << delay.count()
                              << "s: " << error << '\n';
                    std::this_thread::sleep_for(delay);
                    {
                        std::lock_guard lock(drop_mutex);
                        pending_drop_jobs.push_front(std::move(job));
                    }
                    drop_cv.notify_one();
                    continue;
                }
                if (!delivered) std::cerr << "Inventory request failed permanently: " << error << '\n';
                {
                    std::lock_guard lock(drop_mutex);
                    completed_drop_jobs.push_back(DropJobResult{
                        job.pickup, std::move(job.drop), std::move(job.event_id), delivered, error
                    });
                }
            }
        });
    }

    bool enqueue_drop_job(DropJob job) {
        if (!job.pickup) {
            const auto expiry = wall_clock_ms() +
                std::chrono::duration_cast<std::chrono::milliseconds>(job.drop.expires_at - Clock::now()).count();
            const Json payload{
                {"drop_id", job.drop.id}, {"session_id", job.drop.session_id},
                {"character_id", job.drop.owner_character_id}, {"item_id", job.drop.item_id},
                {"quantity", job.drop.quantity}, {"position_x", job.drop.x},
                {"position_z", job.drop.z}, {"expires_at_unix_ms", expiry}
            };
            std::string error;
            if (!enqueue_durable_event(job.drop.id, "ground_drop_create", payload, error)) {
                std::cerr << "Could not persist ground drop: " << error << '\n';
                return false;
            }
            return true;
        }
        const auto expiry = wall_clock_ms() +
            std::chrono::duration_cast<std::chrono::milliseconds>(job.drop.expires_at - Clock::now()).count();
        const Json payload{
            {"drop_id", job.drop.id}, {"drop_session_id", job.drop.session_id},
            {"request_session_id", job.request_session_id},
            {"character_id", job.drop.owner_character_id}, {"item_id", job.drop.item_id},
            {"quantity", job.drop.quantity}, {"position_x", job.drop.x},
            {"position_z", job.drop.z}, {"expires_at_unix_ms", expiry}
        };
        std::string error;
        if (!enqueue_durable_event(job.event_id, "ground_drop_pickup", payload, error)) {
            std::cerr << "Could not persist pickup settlement: " << error << '\n';
            return false;
        }
        return true;
    }

    void stop_drop_worker() {
        {
            std::lock_guard lock(drop_mutex);
            drop_stop_requested = true;
        }
        drop_cv.notify_all();
        if (drop_thread.joinable()) drop_thread.join();
    }

    void drain_drop_results() {
        std::deque<DropJobResult> completed;
        {
            std::lock_guard lock(drop_mutex);
            completed.swap(completed_drop_jobs);
        }
        for (auto& result : completed) {
            if (!result.pickup) {
                if (result.success) ground_drops.push_back(std::move(result.drop));
                continue;
            }
            auto drop = std::find_if(ground_drops.begin(), ground_drops.end(), [&](const GroundDropRuntime& value) {
                return value.id == result.drop.id;
            });
            if (result.success) {
                if (drop != ground_drops.end()) ground_drops.erase(drop);
            } else if (drop != ground_drops.end()) {
                drop->pickup_pending = false;
            }
            for (const auto& [peer, player] : players) {
                if (player.character_id != result.drop.owner_character_id) continue;
                send_json(peer, honghuang::protocol::MessageType::PickupEvent, Json{
                    {"accepted", result.success}, {"drop_id", result.drop.id},
                    {"item_id", result.drop.item_id}, {"quantity", result.drop.quantity},
                    {"reason", result.success ? std::string{} : result.error}
                });
                break;
            }
        }
    }

    bool enqueue_consumable_job(ConsumableJob job) {
        const auto session_id = job.session_id;
        {
            std::lock_guard lock(consumable_mutex);
            if (consumable_stop_requested || !consumable_thread.joinable() ||
                pending_consumable_jobs.size() >= 128 ||
                pending_consumable_sessions.contains(session_id) ||
                snapshot_inflight_sessions.contains(session_id)) return false;
            pending_consumable_sessions.insert(session_id);
            skip_stale_consumable_snapshots.insert(session_id);
            pending_consumable_jobs.push_back(std::move(job));
        }
        {
            std::lock_guard lock(persistence_mutex);
            pending_snapshots.erase(session_id);
        }
        consumable_cv.notify_one();
        return true;
    }

    void start_consumable_worker() {
        consumable_stop_requested = false;
        consumable_thread = std::thread([this] {
            while (true) {
                ConsumableJob job;
                {
                    std::unique_lock lock(consumable_mutex);
                    consumable_cv.wait(lock, [this] { return consumable_stop_requested || !pending_consumable_jobs.empty(); });
                    if (consumable_stop_requested && pending_consumable_jobs.empty()) return;
                    job = std::move(pending_consumable_jobs.front());
                    pending_consumable_jobs.pop_front();
                }
                ConsumableJobResult result;
                result.session_id = job.session_id;
                result.character_id = job.character_id;
                result.request_id = job.request_id;
                result.item_id = job.item_id;
                const Json request{{"session_id", job.session_id}, {"character_id", job.character_id},
                    {"request_id", job.request_id}, {"item_id", job.item_id}, {"quantity", job.quantity},
                    {"health", job.health}, {"max_health", job.max_health},
                    {"mana", job.mana}, {"max_mana", job.max_mana}};
                long status = 0;
                Json response;
                std::string error;
                for (int attempt = 0; attempt < 3; ++attempt) {
                    error.clear();
                    response = Json::object();
                    result.success = backend_inventory_request(config, "/api/v1/servers/inventory/use",
                                                                 &request, status, response, error);
                    if (result.success || (status != 0 && status < 500)) break;
                    if (attempt < 2) std::this_thread::sleep_for(std::chrono::milliseconds(150 * (attempt + 1)));
                }
                if (result.success && response.is_object() &&
                    response.contains("health") && response["health"].is_number_integer() &&
                    response.contains("max_health") && response["max_health"].is_number_integer() &&
                    response.contains("mana") && response["mana"].is_number_integer() &&
                    response.contains("max_mana") && response["max_mana"].is_number_integer() &&
                    (!response.contains("health_effect") || response["health_effect"].is_number_integer()) &&
                    (!response.contains("mana_effect") || response["mana_effect"].is_number_integer()) &&
                    (!response.contains("health_restored") || response["health_restored"].is_number_integer()) &&
                    (!response.contains("mana_restored") || response["mana_restored"].is_number_integer()) &&
                    response.value("health_effect", response.value("health_restored", 0)) >= 0 &&
                    response.value("health_effect", response.value("health_restored", 0)) <= 200000 &&
                    response.value("mana_effect", response.value("mana_restored", 0)) >= 0 &&
                    response.value("mana_effect", response.value("mana_restored", 0)) <= 200000) {
                    const honghuang::simulation::ConsumableResources resources{
                        response["health"].get<std::int64_t>(),
                        response["max_health"].get<std::int64_t>(),
                        response["mana"].get<std::int64_t>(),
                        response["max_mana"].get<std::int64_t>()
                    };
                    if (honghuang::simulation::valid_consumable_resources(resources)) {
                        result.result = std::move(response);
                    } else {
                        result.success = false;
                        result.error = "后端返回的生命/灵力数值无效。";
                    }
                } else if (result.success) {
                    result.success = false;
                    result.error = "后端消耗品响应缺少资源字段。";
                } else {
                    result.error = error.empty() ? "消耗品结算失败（HTTP " + std::to_string(status) + "）。" : error;
                }
                {
                    std::lock_guard lock(consumable_mutex);
                    completed_consumable_jobs.push_back(std::move(result));
                }
            }
        });
    }

    void stop_consumable_worker() {
        {
            std::lock_guard lock(consumable_mutex);
            consumable_stop_requested = true;
        }
        consumable_cv.notify_all();
        if (consumable_thread.joinable()) consumable_thread.join();
    }

    void drain_consumable_results() {
        std::deque<ConsumableJobResult> completed;
        {
            std::lock_guard lock(consumable_mutex);
            completed.swap(completed_consumable_jobs);
        }
        for (auto& result : completed) {
            {
                std::lock_guard lock(consumable_mutex);
                pending_consumable_sessions.erase(result.session_id);
            }
            auto closing = pending_consumable_closes.find(result.session_id);
            if (closing != pending_consumable_closes.end()) {
                if (result.success) {
                    const auto health_effect = result.result.value("health_effect", result.result.value("health_restored", 0));
                    const auto mana_effect = result.result.value("mana_effect", result.result.value("mana_restored", 0));
                    closing->second.health = honghuang::simulation::clamp_current_resource_to_maximum(
                        closing->second.health + health_effect, closing->second.max_health);
                    closing->second.mana = honghuang::simulation::clamp_current_resource_to_maximum(
                        closing->second.mana + mana_effect, closing->second.max_mana);
                }
                std::string close_error;
                if (!save_and_close_session(config, closing->second, close_error)) {
                    std::cerr << "Could not close disconnected player after consumable settlement: "
                              << close_error << '\n';
                }
                pending_consumable_closes.erase(closing);
                continue;
            }
            const auto player = std::find_if(players.begin(), players.end(), [&](const auto& entry) {
                return entry.second.session_id == result.session_id && entry.second.character_id == result.character_id;
            });
            if (player == players.end()) continue;
            Json event{{"action", "consumable_use"}, {"accepted", result.success},
                       {"request_id", result.request_id}, {"item_id", result.item_id}};
            if (result.success) {
                auto& state = player->second;
                const auto previous_health = state.health;
                const auto previous_mana = state.mana;
                const auto health_effect = result.result.value("health_effect", result.result.value("health_restored", 0));
                const auto mana_effect = result.result.value("mana_effect", result.result.value("mana_restored", 0));
                state.health = honghuang::simulation::clamp_current_resource_to_maximum(
                    state.health + health_effect, state.max_health);
                state.mana = honghuang::simulation::clamp_current_resource_to_maximum(
                    state.mana + mana_effect, state.max_mana);
                event["health"] = state.health;
                event["max_health"] = state.max_health;
                event["mana"] = state.mana;
                event["max_mana"] = state.max_mana;
                event["health_restored"] = state.health - previous_health;
                event["mana_restored"] = state.mana - previous_mana;
                event["applied"] = true; // This response is now being applied to live PlayerState, including idempotent replays.
                event["duplicate_request"] = !result.result.value("applied", true);
            } else {
                event["reason"] = result.error;
            }
            send_json(player->first, honghuang::protocol::MessageType::CombatEvent, event);
        }
    }

    bool enqueue_combat_refresh(const PlayerState& player) {
        std::lock_guard lock(combat_refresh_mutex);
        if (combat_refresh_stop_requested || !combat_refresh_thread.joinable() ||
            pending_combat_refresh_jobs.size() >= 128 ||
            pending_combat_refresh_sessions.contains(player.session_id)) return false;
        pending_combat_refresh_sessions.insert(player.session_id);
        pending_combat_refresh_jobs.push_back({player.session_id, player.character_id});
        combat_refresh_cv.notify_one();
        return true;
    }

    void start_combat_refresh_worker() {
        combat_refresh_stop_requested = false;
        combat_refresh_thread = std::thread([this] {
            while (true) {
                CombatRefreshJob job;
                {
                    std::unique_lock lock(combat_refresh_mutex);
                    combat_refresh_cv.wait(lock, [this] { return combat_refresh_stop_requested || !pending_combat_refresh_jobs.empty(); });
                    if (combat_refresh_stop_requested && pending_combat_refresh_jobs.empty()) return;
                    job = std::move(pending_combat_refresh_jobs.front());
                    pending_combat_refresh_jobs.pop_front();
                }
                CombatRefreshResult result;
                result.session_id = job.session_id;
                result.character_id = job.character_id;
                const Json request{{"session_id", job.session_id}, {"character_id", job.character_id}};
                long status = 0;
                result.success = backend_inventory_request(config, "/api/v1/servers/sessions/combat-stats",
                                                           &request, status, result.stats, result.error);
                if (!result.success && result.error.empty()) {
                    result.error = "combat stat refresh failed (HTTP " + std::to_string(status) + ")";
                }
                {
                    std::lock_guard lock(combat_refresh_mutex);
                    completed_combat_refresh_jobs.push_back(std::move(result));
                }
            }
        });
    }

    void stop_combat_refresh_worker() {
        {
            std::lock_guard lock(combat_refresh_mutex);
            combat_refresh_stop_requested = true;
            pending_combat_refresh_jobs.clear();
        }
        combat_refresh_cv.notify_all();
        if (combat_refresh_thread.joinable()) combat_refresh_thread.join();
    }

    void drain_combat_refresh_results() {
        std::deque<CombatRefreshResult> completed;
        {
            std::lock_guard lock(combat_refresh_mutex);
            completed.swap(completed_combat_refresh_jobs);
        }
        for (auto& result : completed) {
            {
                std::lock_guard lock(combat_refresh_mutex);
                pending_combat_refresh_sessions.erase(result.session_id);
            }
            if (!result.success || !result.stats.is_object()) {
                if (!result.error.empty()) std::cerr << "Equipment combat refresh failed: " << result.error << '\n';
                continue;
            }
            const auto found = std::find_if(players.begin(), players.end(), [&](const auto& entry) {
                return entry.second.session_id == result.session_id && entry.second.character_id == result.character_id;
            });
            if (found == players.end()) continue;
            const auto& stats = result.stats;
            const auto integer_field = [&](const char* key) {
                return stats.contains(key) && stats[key].is_number_integer();
            };
            if (!integer_field("attack") || !integer_field("defense") ||
                !integer_field("max_health") || !integer_field("max_mana") ||
                !integer_field("constitution") || !integer_field("agility") ||
                !integer_field("spirit") || !integer_field("vitality") ||
                !stats.contains("movement_speed") || !stats["movement_speed"].is_number() ||
                !stats.contains("equipment") || !stats["equipment"].is_array()) {
                std::cerr << "Equipment combat refresh returned an incomplete payload for " << result.character_id << '\n';
                continue;
            }
            const auto attack = stats["attack"].get<std::int64_t>();
            const auto defense = stats["defense"].get<std::int64_t>();
            const auto max_health = stats["max_health"].get<std::int64_t>();
            const auto max_mana = stats["max_mana"].get<std::int64_t>();
            const auto speed = stats["movement_speed"].get<double>();
            const auto constitution = std::clamp<std::int64_t>(stats["constitution"].get<std::int64_t>(), 0, 100000);
            const auto agility = std::clamp<std::int64_t>(stats["agility"].get<std::int64_t>(), 0, 100000);
            const auto spirit = std::clamp<std::int64_t>(stats["spirit"].get<std::int64_t>(), 0, 100000);
            const auto vitality = std::clamp<std::int64_t>(stats["vitality"].get<std::int64_t>(), 0, 100000);
            if (attack < 1 || attack > 100000 || defense < 0 || defense > 100000 ||
                max_health < 1 || max_health > 10000000 || max_mana < 0 || max_mana > 10000000 ||
                !std::isfinite(speed) || speed <= 0.0 || speed > 10.0) {
                std::cerr << "Equipment combat refresh returned out-of-range stats for " << result.character_id << '\n';
                continue;
            }
            auto& player = found->second;
            const Json previous_equipment = player.equipment;
            const bool equipment_changed = player.equipment != stats["equipment"];
            const auto previous_spirit = player.spirit;
            const bool spirit_changed = previous_spirit != spirit;
            const bool combat_stats_changed = player.attack != attack || player.defense != defense ||
                player.max_health != max_health || player.max_mana != max_mana ||
                player.constitution != constitution || player.agility != agility ||
                spirit_changed || player.vitality != vitality ||
                std::abs(static_cast<double>(player.movement_speed) - speed) > 0.0001;
            // Spirit changes alter the regeneration interval. Start a fresh interval
            // instead of interpreting elapsed time using two different rates.
            if (spirit_changed) player.last_mana_regen_at = Clock::now();
            // Preserve the live resources: increasing an equipment cap must not heal or
            // restore mana. Removing a cap clamps current resources to the new maximum.
            player.health = honghuang::simulation::clamp_current_resource_to_maximum(player.health, max_health);
            player.mana = honghuang::simulation::clamp_current_resource_to_maximum(player.mana, max_mana);
            player.max_health = max_health;
            player.max_mana = max_mana;
            player.attack = attack;
            player.defense = defense;
            player.constitution = static_cast<std::int32_t>(constitution);
            player.agility = static_cast<std::int32_t>(agility);
            player.spirit = static_cast<std::int32_t>(spirit);
            player.vitality = static_cast<std::int32_t>(vitality);
            player.movement_speed = honghuang::simulation::effective_player_movement_speed(static_cast<float>(speed));
            player.equipment = stats["equipment"];
            if (player.equipment != previous_equipment) {
                broadcast_player_event(honghuang::protocol::MessageType::PlayerJoined, player);
            }
            if (combat_stats_changed || equipment_changed) {
                send_json(found->first, honghuang::protocol::MessageType::CombatEvent,
                    Json{{"action", "equipment_refresh"}, {"accepted", true},
                         {"health", player.health}, {"max_health", player.max_health},
                         {"mana", player.mana}, {"max_mana", player.max_mana},
                         {"attack", player.attack}, {"defense", player.defense},
                         {"movement_speed", player.movement_speed}});
            }
        }
    }

    bool enqueue_chat_job(ChatJob job) {
        std::lock_guard lock(chat_mutex);
        if (chat_stop_requested || !chat_thread.joinable() || pending_chat_jobs.size() >= 256) return false;
        pending_chat_jobs.push_back(std::move(job));
        chat_cv.notify_one();
        return true;
    }

    void start_chat_worker() {
        chat_stop_requested = false;
        chat_thread = std::thread([this] {
            while (true) {
                ChatJob job;
                {
                    std::unique_lock lock(chat_mutex);
                    chat_cv.wait(lock, [this] { return chat_stop_requested || !pending_chat_jobs.empty(); });
                    if (chat_stop_requested && pending_chat_jobs.empty()) return;
                    job = std::move(pending_chat_jobs.front());
                    pending_chat_jobs.pop_front();
                }

                ChatJobResult result;
                result.session_id = job.session_id;
                result.client_message_id = job.client_message_id;
                const std::string event_id = "nearby-chat:" + job.session_id + ":" + job.client_message_id;
                const Json payload{
                    {"session_id", job.session_id},
                    {"character_id", job.character_id},
                    {"client_message_id", job.client_message_id},
                    {"content", job.content},
                    {"recipient_character_ids", job.recipient_character_ids}
                };
                std::string storage_error;
                const auto existing = durable_outbox->find(event_id, storage_error);
                if (!storage_error.empty()) {
                    result.reason = storage_error;
                } else if (existing.has_value()) {
                    try {
                        const Json stored_payload = Json::parse(existing->payload);
                        const bool same_request =
                            existing->event_type == "nearby_chat" &&
                            stored_payload.value("session_id", std::string{}) == job.session_id &&
                            stored_payload.value("character_id", std::string{}) == job.character_id &&
                            stored_payload.value("client_message_id", std::string{}) == job.client_message_id &&
                            stored_payload.value("content", std::string{}) == job.content;
                        if (!same_request) {
                            result.reason = "client_message_id 已用于不同的聊天内容。";
                        } else {
                            result.accepted = enqueue_durable_event(
                                event_id, "nearby_chat", stored_payload, storage_error);
                        }
                    } catch (const std::exception& exception) {
                        storage_error = std::string("无法读取已有附近聊天事件：") + exception.what();
                    }
                    if (!result.accepted && result.reason.empty()) result.reason = storage_error;
                } else {
                    result.accepted = enqueue_durable_event(event_id, "nearby_chat", payload, storage_error);
                    if (!result.accepted) result.reason = storage_error;
                }
                if (!result.accepted && result.reason.empty()) {
                    result.reason = "附近聊天持久队列暂时不可用。";
                }
                {
                    std::lock_guard lock(chat_mutex);
                    if (completed_chat_jobs.size() >= 512) completed_chat_jobs.pop_front();
                    completed_chat_jobs.push_back(std::move(result));
                }
            }
        });
    }

    void stop_chat_worker() {
        {
            std::lock_guard lock(chat_mutex);
            chat_stop_requested = true;
        }
        chat_cv.notify_all();
        if (chat_thread.joinable()) chat_thread.join();
    }

    void drain_chat_results() {
        std::deque<ChatJobResult> completed;
        {
            std::lock_guard lock(chat_mutex);
            completed.swap(completed_chat_jobs);
        }
        for (const auto& result : completed) {
            const auto player = std::find_if(players.begin(), players.end(), [&](const auto& entry) {
                return entry.second.session_id == result.session_id;
            });
            if (player == players.end()) continue;
            Json response{
                {"accepted", result.accepted},
                {"client_message_id", result.client_message_id},
                {"channel", "nearby"}
            };
            if (result.accepted) {
                response["message_id"] = result.message_id;
            } else {
                response["reason"] = result.reason.empty() ? "聊天服务暂时不可用。" : result.reason;
            }
            send_json(player->first, honghuang::protocol::MessageType::ChatEvent, response);
        }
    }

    void handle_chat(ENetPeer* peer, const Json& command) {
        const auto player_it = players.find(peer);
        if (player_it == players.end()) return;
        auto& sender = player_it->second;
        const auto channel = command.value("channel", std::string("nearby"));
        const auto client_message_id = command.value("client_message_id", std::string{});
        const auto content = command.value("content", std::string{});
        const auto reject = [&](const std::string& reason) {
            send_json(peer, honghuang::protocol::MessageType::ChatEvent,
                      Json{{"accepted", false}, {"client_message_id", client_message_id},
                           {"channel", channel}, {"reason", reason}});
        };
        if (channel != "nearby") {
            reject("该频道请使用独立聊天连接发送。");
            return;
        }
        if (client_message_id.empty() || client_message_id.size() > 64 ||
            content.empty() || content.size() > 800) {
            reject("聊天消息格式无效。");
            return;
        }
        std::size_t characters = 0;
        for (const unsigned char byte : content) {
            if ((byte & 0xC0U) != 0x80U) ++characters;
            if (byte < 0x20U && byte != '\n' && byte != '\t') {
                reject("消息包含不允许的控制字符。");
                return;
            }
        }
        if (characters == 0 || characters > 200) {
            reject("聊天内容不能超过 200 个字符。");
            return;
        }
        const auto now = Clock::now();
        if (sender.last_chat_at.time_since_epoch().count() != 0 &&
            now - sender.last_chat_at < std::chrono::seconds(1)) {
            reject("发言过于频繁，请稍后再试。");
            return;
        }

        // The WorldServer is the authority for AOI. ChatServer receives only
        // this server-computed recipient snapshot and verifies every character
        // still has an active session on this exact world instance.
        ChatJob job;
        job.session_id = sender.session_id;
        job.character_id = sender.character_id;
        job.client_message_id = client_message_id;
        job.content = content;
        for (const auto& [recipient_peer, recipient] : players) {
            (void)recipient_peer;
            if (!honghuang::simulation::within_interest_radius(
                    sender.x, sender.z, recipient.x, recipient.z, kInterestRadius)) {
                continue;
            }
            job.recipient_character_ids.push_back(recipient.character_id);
        }
        if (job.recipient_character_ids.empty() || job.recipient_character_ids.size() > 512) {
            reject("附近接收人数超出当前频道限制。");
            return;
        }
        if (!enqueue_chat_job(std::move(job))) {
            reject("聊天服务队列繁忙，请稍后重试。");
            return;
        }
        sender.last_chat_at = now;
    }

    void handle_pickup(ENetPeer* peer, const Json& command) {
        auto player_it = players.find(peer);
        if (player_it == players.end()) return;
        auto& player = player_it->second;
        if (player.health <= 0) {
            send_json(peer, honghuang::protocol::MessageType::PickupEvent,
                      Json{{"accepted", false}, {"reason", "角色已倒地，无法拾取。"}});
            return;
        }
        const auto now = Clock::now();
        if (player.last_pickup_at.time_since_epoch().count() != 0 &&
            now - player.last_pickup_at < std::chrono::milliseconds(250)) {
            send_json(peer, honghuang::protocol::MessageType::PickupEvent,
                      Json{{"accepted", false}, {"reason", "拾取太频繁，请稍后再试。"}});
            return;
        }
        player.last_pickup_at = now;
        const auto drop_id = command.value("drop_id", std::string{});
        if (drop_id.empty() || drop_id.size() > 64) {
            send_json(peer, honghuang::protocol::MessageType::PickupEvent,
                      Json{{"accepted", false}, {"reason", "掉落物编号无效。"}});
            return;
        }
        auto drop = std::find_if(ground_drops.begin(), ground_drops.end(), [&](const GroundDropRuntime& value) {
            return value.id == drop_id;
        });
        if (drop == ground_drops.end() || drop->expires_at <= now || drop->pickup_pending) {
            send_json(peer, honghuang::protocol::MessageType::PickupEvent,
                      Json{{"accepted", false}, {"reason", "掉落物已消失或正在结算。"}});
            return;
        }
        if (drop->owner_character_id != player.character_id) {
            send_json(peer, honghuang::protocol::MessageType::PickupEvent,
                      Json{{"accepted", false}, {"reason", "这件掉落物不属于当前角色。"}});
            return;
        }
        const double dx = static_cast<double>(drop->x) - player.x;
        const double dz = static_cast<double>(drop->z) - player.z;
        constexpr double pickup_range = 3.0;
        if (dx * dx + dz * dz > pickup_range * pickup_range) {
            send_json(peer, honghuang::protocol::MessageType::PickupEvent,
                      Json{{"accepted", false}, {"reason", "距离掉落物太远。"}});
            return;
        }
        drop->pickup_pending = true;
        if (!enqueue_drop_job(DropJob{true, *drop, make_event_uuid(), player.session_id, 0})) {
            drop->pickup_pending = false;
            send_json(peer, honghuang::protocol::MessageType::PickupEvent,
                      Json{{"accepted", false}, {"reason", "拾取队列繁忙，请稍后重试。"}});
            return;
        }
        send_json(peer, honghuang::protocol::MessageType::PickupEvent,
                  Json{{"accepted", false}, {"pending", true}, {"drop_id", drop_id}, {"reason", "正在结算拾取……"}});
    }

    void handle_consumable_use(ENetPeer* peer, const Json& command) {
        const auto found = players.find(peer);
        if (found == players.end()) return;
        const auto& player = found->second;
        const auto request_id = command.value("request_id", std::string{});
        const auto item_id = command.value("item_id", std::string{});
        const auto quantity = command.value("quantity", 1);
        const auto reject = [&](const std::string& reason) {
            send_json(peer, honghuang::protocol::MessageType::CombatEvent,
                Json{{"action", "consumable_use"}, {"accepted", false}, {"request_id", request_id},
                     {"item_id", item_id}, {"reason", reason}});
        };
        if (player.health <= 0) { reject("角色已倒地，无法使用消耗品。"); return; }
        if (!honghuang::simulation::valid_consumable_request(request_id, item_id, quantity)) {
            reject("消耗品请求格式无效。"); return;
        }
        if (!enqueue_consumable_job(ConsumableJob{player.session_id, player.character_id, request_id, item_id, quantity,
                player.health, player.max_health, player.mana, player.max_mana})) {
            reject("消耗品结算队列繁忙，或当前角色已有一笔请求正在结算。"); return;
        }
        send_json(peer, honghuang::protocol::MessageType::CombatEvent,
            Json{{"action", "consumable_use"}, {"accepted", true}, {"pending", true},
                 {"request_id", request_id}, {"item_id", item_id}, {"reason", "正在结算消耗品……"}});
    }

    void enqueue_monster_drops(const MonsterRuntime& monster, const PlayerState& player) {
        static thread_local std::mt19937 generator(std::random_device{}());
        std::uniform_int_distribution<int> chance(1, 10000);
        std::vector<LootEntry> current_loot;
        {
            std::lock_guard lock(loot_table_mutex);
            current_loot = loot_table;
        }
        for (const auto& entry : current_loot) {
            if (entry.monster_id != monster.definition.id || chance(generator) > entry.drop_chance_bp) continue;
            std::uniform_int_distribution<int> quantity(entry.min_quantity, entry.max_quantity);
            GroundDropRuntime drop{
                make_event_uuid(), player.session_id, player.character_id, entry.item_id,
                quantity(generator), monster.state.x, monster.state.z,
                Clock::now() + std::chrono::minutes(15), false
            };
            enqueue_drop_job(DropJob{false, std::move(drop), {}, {}, 0});
        }
    }

    void handle_attack(ENetPeer* peer, const Json& command) {
        auto player_it = players.find(peer);
        if (player_it == players.end()) return;
        auto& player = player_it->second;
        if (player.health <= 0) {
            send_json(peer, honghuang::protocol::MessageType::CombatEvent,
                      Json{{"accepted", false}, {"reason", "角色已倒地，无法攻击。"}});
            return;
        }
        const auto now = Clock::now();
        const auto combat_profile = honghuang::simulation::weapon_combat_profile(player_weapon_type(player));
        const auto attack_cooldown = honghuang::simulation::agility_adjusted_attack_cooldown(
            combat_profile.cooldown, player.agility);
        if (player.last_attack_at.time_since_epoch().count() != 0 &&
            now - player.last_attack_at < attack_cooldown) {
            send_json(peer, honghuang::protocol::MessageType::CombatEvent,
                      Json{{"accepted", false}, {"reason", "攻击间隔中，请稍后再试。"}});
            return;
        }
        // Consume the cooldown even for misses to prevent invalid-target packet spam.
        player.last_attack_at = now;
        const auto target_id = command.value("target_entity_id", std::string{});
        if (target_id.empty() || target_id.size() > 96) {
            send_json(peer, honghuang::protocol::MessageType::CombatEvent,
                      Json{{"accepted", false}, {"reason", "攻击目标无效。"}});
            return;
        }
        auto target = std::find_if(monsters.begin(), monsters.end(), [&](const MonsterRuntime& monster) {
            return monster.runtime_id == target_id;
        });
        if (target == monsters.end() || target->state.mode == honghuang::simulation::MonsterMode::Dead) {
            send_json(peer, honghuang::protocol::MessageType::CombatEvent,
                      Json{{"accepted", false}, {"reason", "目标已消失或已被击败。"}});
            return;
        }
        const double dx = static_cast<double>(target->state.x) - player.x;
        const double dz = static_cast<double>(target->state.z) - player.z;
        if (dx * dx + dz * dz > static_cast<double>(combat_profile.range) * combat_profile.range) {
            send_json(peer, honghuang::protocol::MessageType::CombatEvent,
                      Json{{"accepted", false}, {"reason", "距离目标太远。"}});
            return;
        }
        player.last_combat_at = now;
        if (player_weapon_type(player) == "bow") {
            if (projectiles.size() >= 128) {
                send_json(peer, honghuang::protocol::MessageType::CombatEvent,
                          Json{{"accepted", false}, {"reason", "当前箭矢数量过多，请稍后再试。"}});
                return;
            }
            const double distance = std::sqrt(dx * dx + dz * dz);
            if (distance < 0.001) {
                send_json(peer, honghuang::protocol::MessageType::CombatEvent,
                          Json{{"accepted", false}, {"reason", "目标距离异常，无法发射箭矢。"}});
                return;
            }
            constexpr float projectile_speed = 24.0F;
            const auto projectile_id = make_event_uuid();
            projectiles.push_back(ProjectileRuntime{
                projectile_id, player.character_id, target->runtime_id,
                player.x, player.y + 1.15F, player.z,
                static_cast<float>(dx / distance) * projectile_speed,
                static_cast<float>(dz / distance) * projectile_speed,
                player.attack, combat_profile.power_basis_points,
                combat_profile.defense_penetration_basis_points,
                now + std::chrono::milliseconds(2200)
            });
            broadcast_player_action_event(player, "attack", target->runtime_id, "ranged_shot", peer);
            send_json(peer, honghuang::protocol::MessageType::CombatEvent,
                      Json{{"accepted", true}, {"projectile_spawned", true},
                           {"projectile_id", projectile_id}, {"target_entity_id", target->runtime_id}});
            return;
        }
        broadcast_player_action_event(player, "attack", target->runtime_id, player_attack_style(player), peer);
        const honghuang::simulation::CombatantStats attacker{player.attack, player.defense, 100, 100};
        const honghuang::simulation::CombatantStats defender{
            static_cast<std::int64_t>(target->definition.attack),
            static_cast<std::int64_t>(target->definition.defense),
            static_cast<std::int64_t>(target->state.health),
            static_cast<std::int64_t>(target->definition.max_health)
        };
        honghuang::simulation::DamageResult damage{};
        const honghuang::simulation::AttackProfile attack_profile{
            combat_profile.power_basis_points,
            combat_profile.defense_penetration_basis_points
        };
        if (!honghuang::simulation::calculate_damage(attacker, defender, attack_profile, damage)) {
            send_json(peer, honghuang::protocol::MessageType::CombatEvent,
                      Json{{"accepted", false}, {"reason", "伤害计算未通过校验。"}});
            return;
        }
        std::string contribution_error;
        const auto contribution_record = make_monster_contribution_record(*target, player, damage.damage);
        if (!monster_contribution_writer ||
            !monster_contribution_writer->submit_before_damage(
                contribution_record,
                [&target, &damage]() noexcept {
                    target->state.health = static_cast<float>(damage.remaining_health);
                },
                contribution_error)) {
            std::cerr << "Rejected melee hit because monster contribution was not admitted: "
                      << contribution_error << '\n';
            send_json(peer, honghuang::protocol::MessageType::CombatEvent,
                      Json{{"accepted", false}, {"reason", "战斗记录繁忙，请稍后再试。"}});
            return;
        }
        record_monster_damage(*target, player, damage.damage);
        std::int64_t experience_reward = 0;
        std::int64_t cultivation_reward = 0;
        if (damage.defeated) {
            target->state.mode = honghuang::simulation::MonsterMode::Dead;
            log_monster_contribution_snapshot(*target);
            enqueue_bounty_kill_events(&player, *target);
            target->slow_effect = {};
            target->burn_effect = {};
            target->burn_owner_character_id.clear();
            target->burn_owner_session_id.clear();
            target->burn_owner_bounty_objectives.clear();
            target->state.target_id.clear();
            // Respawn timing is owned by the world's spawn-point configuration.
            // This keeps live operations changes effective without hard-coded monster IDs.
            target->respawn_at = now + std::chrono::seconds(target->retry_spawn_seconds);
            experience_reward = 20 + static_cast<std::int64_t>(target->definition.level) * 10;
            cultivation_reward = 10 + static_cast<std::int64_t>(target->definition.level) * 5;
            enqueue_character_reward(CharacterRewardEvent{
                make_event_uuid(), player.session_id, player.character_id, experience_reward, cultivation_reward, 0
            });
            // The underworld's spirit trial grants permanent soul experience.
            const std::int64_t soul_experience_reward =
                config.world_id == "underworld_fengdu" ? 5 : 0;
            if (soul_experience_reward > 0)
                enqueue_soul_reward(player, soul_experience_reward, "underworld_trial:monster_hunt");
            enqueue_soul_absorption(player, *target);
            enqueue_monster_drops(*target, player);
        }
        const Json event{
            {"attacker_character_id", player.character_id},
            {"target_entity_id", target->runtime_id},
            {"target_name", target->definition.name},
            {"damage", damage.damage},
            {"remaining_health", damage.remaining_health},
            {"max_health", target->definition.max_health},
            {"defeated", damage.defeated},
            {"experience_reward", experience_reward},
            {"cultivation_reward", cultivation_reward},
            {"soul_experience_reward", damage.defeated && config.world_id == "underworld_fengdu" ? 5 : 0}
        };
        send_json(peer, honghuang::protocol::MessageType::CombatEvent, event);
    }

    void handle_spell_cast(ENetPeer* peer, const Json& command) {
        auto player_it = players.find(peer);
        if (player_it == players.end()) return;
        auto& player = player_it->second;
        const auto spell_id = command.value("spell_id", std::string{});
        const auto* spell = honghuang::simulation::find_spell_definition(spell_id);
        const auto reject = [&](const std::string& reason) {
            Json response{{"accepted", false}, {"action", "spell_cast"}, {"reason", reason},
                          {"mana", player.mana}, {"max_mana", player.max_mana}};
            if (!spell_id.empty() && spell_id.size() <= 64) response["spell_id"] = spell_id;
            if (spell != nullptr && honghuang::simulation::valid_spell_definition(*spell)) {
                response["cooldown_ms"] = spell->cooldown_ms;
            }
            send_json(peer, honghuang::protocol::MessageType::CombatEvent, response);
        };
        if (player.health <= 0) { reject("角色已倒地，无法施法。"); return; }
        const auto weapon = player_weapon_type(player);
        if (weapon != "staff" && weapon != "focus") { reject("装备法杖或法器后才能施展法术。"); return; }
        if (spell == nullptr || !spell->enabled || !honghuang::simulation::valid_spell_definition(*spell)) {
            reject("未知或未开放的法术。"); return;
        }
        if (player.pending_spell.has_value()) { reject("正在施法，请稍候。"); return; }
        const auto now = Clock::now();
        const auto last_spell = player.last_spell_at_by_id.find(std::string(spell->id));
        if (last_spell != player.last_spell_at_by_id.end() &&
            honghuang::simulation::spell_cooldown_remaining_ms(
                std::chrono::duration_cast<std::chrono::milliseconds>(
                    last_spell->second.time_since_epoch()).count(),
                std::chrono::duration_cast<std::chrono::milliseconds>(
                    now.time_since_epoch()).count(),
                spell->cooldown_ms) > 0) {
            reject("法术尚在冷却中。"); return;
        }
        if (!honghuang::simulation::can_pay_spell_cost(player.mana, spell->mana_cost)) {
            reject("灵力不足，无法施展该法术。"); return;
        }
        const auto target_id = command.value("target_entity_id", std::string{});
        if (target_id.empty() || target_id.size() > 96) { reject("施法目标无效。"); return; }
        const auto target = std::find_if(monsters.begin(), monsters.end(), [&](const MonsterRuntime& monster) {
            return monster.runtime_id == target_id;
        });
        if (target == monsters.end() || target->state.mode == honghuang::simulation::MonsterMode::Dead) {
            reject("目标已消失或已被击败。"); return;
        }
        const double dx = static_cast<double>(target->state.x) - player.x;
        const double dz = static_cast<double>(target->state.z) - player.z;
        if (dx * dx + dz * dz > static_cast<double>(spell->range) * spell->range) {
            reject("目标超出法术射程。"); return;
        }
        if (projectiles.size() >= 128) { reject("当前投射物数量过多，请稍后再试。"); return; }
        player.mana -= spell->mana_cost;
        player.last_spell_at_by_id[std::string(spell->id)] = now;
        player.pending_spell = PendingSpellCast{std::string(spell->id), target_id,
            now + std::chrono::milliseconds(spell->cast_time_ms)};
        send_json(peer, honghuang::protocol::MessageType::CombatEvent,
                  Json{{"accepted", true}, {"action", "spell_cast"}, {"phase", "casting"},
                       {"spell_id", std::string(spell->id)}, {"mana", player.mana},
                       {"max_mana", player.max_mana}, {"mana_cost", spell->mana_cost},
                       {"cast_time_ms", spell->cast_time_ms}, {"cooldown_ms", spell->cooldown_ms}});
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
                    {"birth_inheritance", entity.birth_inheritance},
                    {"equipment", entity.equipment},
                    {"mana", entity.mana}, {"max_mana", entity.max_mana},
                    {"x", entity.x}, {"y", entity.y}, {"z", entity.z},
                    {"yaw", entity.yaw},
                    {"last_input_sequence", entity.last_input_sequence},
                    {"slowed", honghuang::simulation::slow_is_active(entity.slow_effect,std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now().time_since_epoch()).count())},
                    {"frozen", honghuang::simulation::freeze_is_active(entity.freeze_effect,std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now().time_since_epoch()).count())},
                    {"poisoned", honghuang::simulation::periodic_damage_is_active(
                        entity.poison_effect, std::chrono::duration_cast<std::chrono::milliseconds>(
                            Clock::now().time_since_epoch()).count())}
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
                    {"x", monster.state.x}, {"y", 0.0F}, {"z", monster.state.z},
                    {"yaw", monster.state.yaw},
                    {"slowed", honghuang::simulation::slow_is_active(
                        monster.slow_effect, std::chrono::duration_cast<std::chrono::milliseconds>(
                            Clock::now().time_since_epoch()).count())},
                    {"frozen", honghuang::simulation::freeze_is_active(
                        monster.freeze_effect, std::chrono::duration_cast<std::chrono::milliseconds>(
                            Clock::now().time_since_epoch()).count())}
                });
            }
            for (const auto& projectile : projectiles) {
                if (projectile.expires_at <= Clock::now() ||
                    !honghuang::simulation::within_interest_radius(
                        projectile.x, projectile.z, recipient.x, recipient.z, kInterestRadius)) continue;
                entities.push_back({
                    {"entity_type", "projectile"}, {"entity_id", projectile.id},
                    {"projectile_type", projectile.projectile_type}, {"owner_character_id", projectile.owner_character_id},
                    {"x", projectile.x}, {"y", projectile.y}, {"z", projectile.z},
                    {"velocity_x", projectile.velocity_x}, {"velocity_z", projectile.velocity_z}
                });
            }
            for (const auto& drop : ground_drops) {
                if (drop.owner_character_id != recipient.character_id ||
                    drop.expires_at <= Clock::now() ||
                    !honghuang::simulation::within_interest_radius(
                        drop.x, drop.z, recipient.x, recipient.z, kInterestRadius)) continue;
                const auto item = std::find_if(loot_table.begin(), loot_table.end(), [&](const LootEntry& entry) {
                    return entry.item_id == drop.item_id;
                });
                entities.push_back({
                    {"entity_type", "drop"}, {"entity_id", drop.id}, {"item_id", drop.item_id},
                    {"item_name", item == loot_table.end() ? drop.item_id : item->item_name},
                    {"quality", item == loot_table.end() ? 1 : item->quality},
                    {"quantity", drop.quantity}, {"x", drop.x}, {"y", 0.15F}, {"z", drop.z}
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
        drain_drop_results();
        drain_combat_refresh_results();
        const auto now = Clock::now();
        for (auto& [peer, player] : players) {
            (void)peer;
            if (player.last_combat_refresh_at == Clock::time_point{} ||
                now - player.last_combat_refresh_at >= std::chrono::seconds(2)) {
                if (enqueue_combat_refresh(player)) player.last_combat_refresh_at = now;
            }
        }
        ground_drops.erase(std::remove_if(ground_drops.begin(), ground_drops.end(), [&](const GroundDropRuntime& drop) {
            return drop.expires_at <= now && !drop.pickup_pending;
        }), ground_drops.end());
        const auto elapsed = now - last_snapshot;
        if (elapsed < kSnapshotInterval) return;
        const float delta = std::clamp(std::chrono::duration<float>(elapsed).count(), 0.0F, 0.1F);
        for (auto& [peer, player] : players) {
            const auto effect_now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                now.time_since_epoch()).count();
            if (player.health <= 0) {
                player.poison_effect = {};
                player.poison_source_entity_id.clear();
                player.slow_effect = {};
            } else {
                const auto poison_damage = honghuang::simulation::consume_periodic_damage_tick(
                    player.poison_effect, effect_now_ms);
                if (poison_damage > 0) {
                    const auto applied_damage = std::min(player.health, poison_damage);
                    player.health -= applied_damage;
                    player.last_combat_at = now;
                    const bool poison_defeated = player.health <= 0;
                    const auto remaining_poison_ms = player.poison_effect.ticks_remaining <= 0 ? 0 :
                        std::max<std::int64_t>(0, player.poison_effect.next_tick_at_ms - effect_now_ms) +
                        static_cast<std::int64_t>(player.poison_effect.ticks_remaining - 1) *
                            player.poison_effect.interval_ms;
                    send_json(peer, honghuang::protocol::MessageType::CombatEvent,
                        Json{{"accepted", true}, {"source", "monster"},
                             {"source_entity_id", player.poison_source_entity_id},
                             {"attack_style", "poison_tick"}, {"status_effect", "poison"},
                             {"status_duration_ms", remaining_poison_ms},
                             {"damage", applied_damage}, {"health", player.health},
                             {"max_health", player.max_health}, {"defeated", poison_defeated}});
                    if (poison_defeated) {
                        player.poison_effect = {};
                        player.poison_source_entity_id.clear();
                        player.slow_effect = {};
                    }
                } else if (!honghuang::simulation::periodic_damage_is_active(
                               player.poison_effect, effect_now_ms)) {
                    player.poison_source_entity_id.clear();
                }
            }

            // Mana is server-authoritative: restore one point per interval while
            // alive, but pause the timer while a cast is being channelled.
            if (player.health <= 0 || player.pending_spell.has_value()) {
                player.last_mana_regen_at = now;
            } else if (player.mana >= player.max_mana) {
                player.last_mana_regen_at = now;
            } else {
                const bool in_combat = player.last_combat_at.time_since_epoch().count() != 0 &&
                    now - player.last_combat_at < kCombatInactivityWindow;
                const auto regen_interval_ms = honghuang::simulation::mana_regeneration_interval_ms(
                    in_combat, player.spirit,
                    static_cast<std::int32_t>(kManaRegenerationInterval.count()),
                    static_cast<std::int32_t>(kCombatManaRegenerationInterval.count()));
                if (in_combat != player.mana_regen_was_in_combat) {
                    player.mana_regen_was_in_combat = in_combat;
                    player.last_mana_regen_at = now;
                }
                const auto regen_elapsed_ms =
                    std::chrono::duration_cast<std::chrono::milliseconds>(
                        now - player.last_mana_regen_at).count();
                const auto restored = honghuang::simulation::mana_regeneration_amount(
                    regen_elapsed_ms, player.mana, player.max_mana, regen_interval_ms);
                if (restored > 0) {
                    player.mana += restored;
                    player.last_mana_regen_at +=
                        std::chrono::milliseconds(regen_interval_ms) * restored;
                }
            }

            if (player.health <= 0 || now - player.last_input_at > kInputTimeout) {
                player.move_x = 0.0F;
                player.move_z = 0.0F;
                player.jump_requested = false;
            }
            const float player_delta = honghuang::simulation::movement_delta_with_effect(
                delta, player.slow_effect, effect_now_ms);
            honghuang::simulation::integrate_horizontal(
                player.x, player.z, player.move_x, player.move_z, player_delta,
                player.movement_speed);
            honghuang::simulation::integrate_vertical(
                player.y, player.vertical_velocity, player.jump_requested, delta);

            // Rate-limited diagnostics make it possible to distinguish packet loss,
            // rejected/stale input, and a world-tick movement problem without flooding logs.
            if (now - player.last_movement_diagnostic_at >= std::chrono::seconds(1)) {
                const auto input_age_ms =
                    std::chrono::duration_cast<std::chrono::milliseconds>(now - player.last_input_at).count();
                std::ostringstream diagnostic;
                diagnostic << std::fixed << std::setprecision(2)
                           << "[MovementDiag] character=" << player.character_id
                           << " accepted_inputs=" << player.accepted_inputs_since_diagnostic
                           << " input_seq=" << player.last_input_sequence
                           << " move=(" << player.move_x << ',' << player.move_z << ')'
                           << " position=(" << player.x << ',' << player.y << ',' << player.z << ')'
                           << " health=" << player.health
                           << " input_age_ms=" << input_age_ms;
                std::cout << diagnostic.str() << std::endl;
                player.accepted_inputs_since_diagnostic = 0;
                player.last_movement_diagnostic_at = now;
            }
        }
        for (auto& [peer, player] : players) {
            if (!player.pending_spell.has_value() || player.pending_spell->completes_at > now) continue;
            const auto pending = *player.pending_spell;
            player.pending_spell.reset();
            const auto* spell = honghuang::simulation::find_spell_definition(pending.spell_id);
            auto target = std::find_if(monsters.begin(), monsters.end(), [&](const MonsterRuntime& monster) {
                return monster.runtime_id == pending.target_entity_id;
            });
            if (player.health <= 0 || spell == nullptr || target == monsters.end() ||
                target->state.mode == honghuang::simulation::MonsterMode::Dead) {
                if (spell != nullptr) player.mana = std::min(player.max_mana, player.mana + spell->mana_cost);
                send_json(peer, honghuang::protocol::MessageType::CombatEvent,
                          Json{{"accepted", false}, {"action", "spell_cast"},
                               {"spell_id", pending.spell_id}, {"cooldown_ms", spell != nullptr ? spell->cooldown_ms : 0},
                                {"reason", player.health <= 0 ? "施法中受到致命攻击，灵力已返还。" : "施法期间目标消失，灵力已返还。"},
                               {"mana", player.mana}, {"max_mana", player.max_mana}});
                continue;
            }
            const double dx = static_cast<double>(target->state.x) - player.x;
            const double dz = static_cast<double>(target->state.z) - player.z;
            const double distance = std::sqrt(dx * dx + dz * dz);
            if (distance < 0.001 || distance > spell->range || projectiles.size() >= 128) {
                player.mana = std::min(player.max_mana, player.mana + spell->mana_cost);
                send_json(peer, honghuang::protocol::MessageType::CombatEvent,
                          Json{{"accepted", false}, {"action", "spell_cast"},
                               {"spell_id", pending.spell_id}, {"cooldown_ms", spell->cooldown_ms},
                                {"reason", "法术释放条件已失效，灵力已返还。"},
                               {"mana", player.mana}, {"max_mana", player.max_mana}});
                continue;
            }
            const auto projectile_id = make_event_uuid();
            projectiles.push_back(ProjectileRuntime{
                projectile_id, player.character_id, target->runtime_id,
                player.x, player.y + 1.15F, player.z,
                static_cast<float>(dx / distance) * spell->projectile_speed,
                static_cast<float>(dz / distance) * spell->projectile_speed,
                player.attack, spell->power_basis_points, spell->defense_penetration_basis_points,
                now + std::chrono::duration_cast<Clock::duration>(std::chrono::duration<float>(spell->projectile_lifetime_seconds)),
                spell->element == honghuang::simulation::SpellElement::Ice ? "ice_bolt" : "fireball",
                spell->slow_duration_ms, spell->slow_multiplier, spell->freeze_duration_ms,
                 spell->burn_duration_ms, spell->burn_interval_ms,
                 spell->burn_damage_basis_points
            });
            broadcast_player_action_event(player, "cast", target->runtime_id,
                spell->element == honghuang::simulation::SpellElement::Ice ? "spell_ice_bolt" : "spell_fireball", peer);
            send_json(peer, honghuang::protocol::MessageType::CombatEvent,
                      Json{{"accepted", true}, {"action", "spell_cast"}, {"phase", "released"},
                           {"spell_id", std::string(spell->id)}, {"projectile_id", projectile_id},
                           {"mana", player.mana}, {"max_mana", player.max_mana}});
        }
        for (auto projectile = projectiles.begin(); projectile != projectiles.end();) {
            const auto owner = std::find_if(players.begin(), players.end(), [&](const auto& entry) {
                return entry.second.character_id == projectile->owner_character_id;
            });
            auto target = std::find_if(monsters.begin(), monsters.end(), [&](const MonsterRuntime& monster) {
                return monster.runtime_id == projectile->target_entity_id;
            });
            if (owner == players.end()) {
                projectile = projectiles.erase(projectile);
                continue;
            }
            if (projectile->expires_at <= now) {
                send_json(owner->first, honghuang::protocol::MessageType::CombatEvent,
                          Json{{"accepted", false}, {"reason", projectile->projectile_type == "fireball" ? "火球术未命中目标。" : (projectile->projectile_type == "ice_bolt" ? "冰锥术未命中目标。" : "箭矢未命中目标。")}});
                projectile = projectiles.erase(projectile);
                continue;
            }
            if (target == monsters.end() || target->state.mode == honghuang::simulation::MonsterMode::Dead) {
                send_json(owner->first, honghuang::protocol::MessageType::CombatEvent,
                          Json{{"accepted", false}, {"reason", projectile->projectile_type == "fireball" ? "目标已消失，火球术失效。" : (projectile->projectile_type == "ice_bolt" ? "目标已消失，冰锥术失效。" : "目标已消失，箭矢失效。")}});
                projectile = projectiles.erase(projectile);
                continue;
            }
            const bool hit = honghuang::simulation::advance_projectile(
                projectile->x, projectile->z, projectile->velocity_x, projectile->velocity_z,
                delta, target->state.x, target->state.z, 0.85F);
            if (!hit) {
                ++projectile;
                continue;
            }
            const honghuang::simulation::CombatantStats attacker{
                projectile->attack, 0, 100, 100
            };
            const honghuang::simulation::CombatantStats defender{
                static_cast<std::int64_t>(target->definition.attack),
                static_cast<std::int64_t>(target->definition.defense),
                static_cast<std::int64_t>(target->state.health),
                static_cast<std::int64_t>(target->definition.max_health)
            };
            honghuang::simulation::DamageResult damage{};
            const honghuang::simulation::AttackProfile attack_profile{
                projectile->power_basis_points,
                projectile->defense_penetration_basis_points
            };
            if (honghuang::simulation::calculate_damage(attacker, defender, attack_profile, damage)) {
                std::string contribution_error;
                const auto contribution = make_monster_contribution_record(
                    *target, owner->second, damage.damage);
                const bool admitted = monster_contribution_writer != nullptr &&
                    monster_contribution_writer->submit_before_damage(
                        contribution,
                        [target, remaining_health = damage.remaining_health]() noexcept {
                            target->state.health = static_cast<float>(remaining_health);
                        },
                        contribution_error);
                if (!admitted) {
                    std::cerr << "[MonsterContribution] projectile hit rejected; monster="
                              << target->definition.id << " instance="
                              << target->contribution_instance_id << " reason="
                              << (contribution_error.empty() ? "writer unavailable" : contribution_error)
                              << std::endl;
                    send_json(owner->first, honghuang::protocol::MessageType::CombatEvent,
                              Json{{"accepted", false}, {"source", "projectile"},
                                   {"source_entity_id", projectile->id},
                                   {"target_entity_id", target->runtime_id},
                                   {"reason", "战斗记录繁忙，本次攻击未生效，请稍后重试。"}});
                    projectile = projectiles.erase(projectile);
                    continue;
                }
                bool applied_slow = false;
                bool applied_freeze = false;
                std::int32_t applied_freeze_duration_ms = 0;
                bool applied_burn = false;
                if (projectile->slow_duration_ms > 0) {
                    const auto now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                        now.time_since_epoch()).count();
                    applied_slow = honghuang::simulation::apply_slow(
                        target->slow_effect, now_ms, projectile->slow_duration_ms,
                        projectile->slow_multiplier);
                }

                if (!damage.defeated && projectile->freeze_duration_ms > 0) {
                    applied_freeze_duration_ms = honghuang::simulation::monster_freeze_duration_ms(
                        projectile->freeze_duration_ms,target->definition.id,target->definition.name,target->rare_spawn);
                    applied_freeze = honghuang::simulation::apply_freeze(target->freeze_effect,
                        std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count(),
                        applied_freeze_duration_ms);
                }
                if (!damage.defeated && projectile->burn_duration_ms > 0) {
                    const auto now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                        now.time_since_epoch()).count();
                    const auto burn_damage = std::max<std::int64_t>(1,
                        projectile->attack * projectile->burn_damage_basis_points / 10000);
                    applied_burn = honghuang::simulation::apply_periodic_damage(
                        target->burn_effect, now_ms, projectile->burn_duration_ms,
                        projectile->burn_interval_ms, burn_damage);
                    if (applied_burn) {
                        target->burn_owner_character_id = projectile->owner_character_id;
                        target->burn_owner_session_id = owner->second.session_id;
                        target->burn_owner_bounty_objectives = owner->second.bounty_objectives;
                    }
                }
                record_monster_damage(*target, owner->second, damage.damage);
                std::int64_t experience_reward = 0;
                std::int64_t cultivation_reward = 0;
                if (damage.defeated) {
                    target->state.mode = honghuang::simulation::MonsterMode::Dead;
                    log_monster_contribution_snapshot(*target);
                    enqueue_bounty_kill_events(&owner->second, *target);
                    honghuang::simulation::clear_negative_statuses(target->slow_effect,target->freeze_effect,target->burn_effect);
                    target->burn_owner_character_id.clear();
            target->burn_owner_session_id.clear();
            target->burn_owner_bounty_objectives.clear();
                    target->state.target_id.clear();
                    target->respawn_at = now + std::chrono::seconds(target->retry_spawn_seconds);
                    experience_reward = 20 + static_cast<std::int64_t>(target->definition.level) * 10;
                    cultivation_reward = 10 + static_cast<std::int64_t>(target->definition.level) * 5;
                    enqueue_character_reward(CharacterRewardEvent{
                        make_event_uuid(), owner->second.session_id, owner->second.character_id,
                        experience_reward, cultivation_reward, 0
                    });
                    if (config.world_id == "underworld_fengdu")
                        enqueue_soul_reward(owner->second, 5, "underworld_trial:monster_hunt");
                    enqueue_soul_absorption(owner->second, *target);
                    enqueue_monster_drops(*target, owner->second);
                }
                send_json(owner->first, honghuang::protocol::MessageType::CombatEvent,
                          Json{{"accepted", true}, {"source", "projectile"},
                               {"source_entity_id", projectile->id},
                               {"projectile_type", projectile->projectile_type},
                               {"target_entity_id", target->runtime_id},
                               {"target_name", target->definition.name},
                               {"damage", damage.damage},
                               {"health", damage.remaining_health},
                               {"remaining_health", damage.remaining_health},
                               {"max_health", target->definition.max_health},
                               {"defeated", damage.defeated},
                               {"status_effect", applied_freeze ? "freeze" : (applied_slow ? "slow" : "")},
                               {"status_duration_ms", applied_freeze ? applied_freeze_duration_ms : (applied_slow ? projectile->slow_duration_ms : 0)},
                               {"burn_applied", applied_burn},
                               {"burn_duration_ms", applied_burn ? projectile->burn_duration_ms : 0},
                               {"experience_reward", experience_reward},
                               {"cultivation_reward", cultivation_reward},
                               {"soul_experience_reward", damage.defeated && config.world_id == "underworld_fengdu" ? 5 : 0}});
                const Json visual_event{
                    {"accepted", true}, {"visual_only", true}, {"source", "projectile"},
                    {"target_entity_id", target->runtime_id}, {"target_name", target->definition.name},
                    {"projectile_type", projectile->projectile_type}, {"damage", damage.damage}, {"health", damage.remaining_health},
                    {"max_health", target->definition.max_health}, {"defeated", damage.defeated},
                    {"status_effect", applied_freeze ? "freeze" : (applied_slow ? "slow" : "")},
                    {"status_duration_ms", applied_freeze ? applied_freeze_duration_ms : (applied_slow ? projectile->slow_duration_ms : 0)},
                    {"burn_applied", applied_burn},
                    {"burn_duration_ms", applied_burn ? projectile->burn_duration_ms : 0}
                };
                for (const auto& [recipient_peer, recipient] : players) {
                    if (recipient_peer == owner->first ||
                        !honghuang::simulation::within_interest_radius(
                            target->state.x, target->state.z, recipient.x, recipient.z, kInterestRadius)) continue;
                    send_json(recipient_peer, honghuang::protocol::MessageType::CombatEvent, visual_event);
                }
            }
            projectile = projectiles.erase(projectile);
        }
        for (auto& monster : monsters) {
            if (monster.state.mode == honghuang::simulation::MonsterMode::Dead) {
                if (monster.respawn_at.time_since_epoch().count() != 0 && now >= monster.respawn_at) {
                    if (monster.rare_spawn) {
                        static thread_local std::mt19937 generator(std::random_device{}());
                        std::uniform_int_distribution<int> roll(1, 100);
                        if (roll(generator) > monster.spawn_chance_percent) {
                            monster.respawn_at = now + std::chrono::seconds(monster.retry_spawn_seconds);
                            continue;
                        }
                    }
                    monster.state = {monster.definition.spawn_x, monster.definition.spawn_z,
                                     monster.definition.max_health};
                    monster.contribution_instance_id = make_event_uuid();
                    monster.damage_contributions.clear();
                    monster.respawn_at = Clock::time_point{};
                    monster.attack_phase = MonsterAttackPhase::Ready;
                    honghuang::simulation::clear_negative_statuses(monster.slow_effect,monster.freeze_effect,monster.burn_effect);
                    monster.burn_owner_character_id.clear();
                    monster.burn_owner_session_id.clear();
                    monster.burn_owner_bounty_objectives.clear();
                    monster.attack_target_character_id.clear();
                    monster.last_attack_at = Clock::time_point{};
                }
                continue;
            }
            const auto effect_now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                now.time_since_epoch()).count();
            const auto burn_effect_before_tick = monster.burn_effect;
            const auto burn_damage = honghuang::simulation::consume_periodic_damage_tick(
                monster.burn_effect, effect_now_ms);
            if (burn_damage <= 0 &&
                !honghuang::simulation::periodic_damage_is_active(monster.burn_effect, effect_now_ms)) {
                monster.burn_owner_character_id.clear();
                    monster.burn_owner_session_id.clear();
                    monster.burn_owner_bounty_objectives.clear();
            }
            if (burn_damage > 0) {
                const auto previous_health = static_cast<std::int64_t>(monster.state.health);
                const auto applied_burn_damage = std::min(burn_damage, previous_health);
                auto burn_owner = std::find_if(players.begin(), players.end(), [&](const auto& entry) {
                    return entry.second.character_id == monster.burn_owner_character_id;
                });
                if (!monster.burn_owner_session_id.empty() &&
                    !monster.burn_owner_character_id.empty()) {
                    std::string contribution_error;
                    const auto contribution = make_monster_contribution_record(
                        monster, monster.burn_owner_session_id, monster.burn_owner_character_id,
                        monster.burn_owner_bounty_objectives, applied_burn_damage);
                    const bool admitted = monster_contribution_writer != nullptr &&
                        monster_contribution_writer->submit_before_damage(
                            contribution,
                            [&monster, previous_health, applied_burn_damage]() noexcept {
                                monster.state.health = static_cast<float>(
                                    std::max<std::int64_t>(0, previous_health - applied_burn_damage));
                            },
                            contribution_error);
                    if (!admitted) {
                        // Keep the exact tick pending; do not apply damage without durable admission.
                        monster.burn_effect = burn_effect_before_tick;
                        std::cerr << "[MonsterContribution] burn tick deferred; monster="
                                  << monster.definition.id << " instance="
                                  << monster.contribution_instance_id << " reason="
                                  << (contribution_error.empty() ? "writer unavailable" : contribution_error)
                                  << std::endl;
                        if (burn_owner != players.end()) {
                            send_json(burn_owner->first, honghuang::protocol::MessageType::CombatEvent,
                                      Json{{"accepted", false}, {"source", "status_effect"},
                                           {"status_effect", "burn"},
                                           {"reason", "战斗记录繁忙，燃烧伤害将稍后重试。"}});
                        }
                        continue;
                    }
                    record_monster_damage(monster, monster.burn_owner_session_id,
                        monster.burn_owner_character_id, monster.burn_owner_bounty_objectives,
                        applied_burn_damage);
                } else {
                    // Defensive fallback for a legacy effect without a captured authenticated source.
                    monster.state.health = static_cast<float>(
                        std::max<std::int64_t>(0, previous_health - applied_burn_damage));
                }
                const bool burn_defeated = monster.state.health <= 0.0F;
                std::int64_t experience_reward = 0;
                std::int64_t cultivation_reward = 0;
                if (burn_defeated) {
                    monster.state.mode = honghuang::simulation::MonsterMode::Dead;
                    log_monster_contribution_snapshot(monster);
                    enqueue_bounty_kill_events(
                        burn_owner != players.end() ? &burn_owner->second : nullptr, monster);
                    monster.slow_effect = {};
                    monster.burn_effect = {};
                    monster.state.target_id.clear();
                    monster.respawn_at = now + std::chrono::seconds(monster.retry_spawn_seconds);
                    if (burn_owner != players.end()) {
                        experience_reward = 20 + static_cast<std::int64_t>(monster.definition.level) * 10;
                        cultivation_reward = 10 + static_cast<std::int64_t>(monster.definition.level) * 5;
                        enqueue_character_reward(CharacterRewardEvent{
                            make_event_uuid(), burn_owner->second.session_id, burn_owner->second.character_id,
                            experience_reward, cultivation_reward, 0
                        });
                    }
                    monster.burn_owner_character_id.clear();
                    monster.burn_owner_session_id.clear();
                    monster.burn_owner_bounty_objectives.clear();
                }
                const Json burn_event{
                    {"accepted", true}, {"source", "status_effect"}, {"status_effect", "burn"},
                    {"source_entity_id", monster.runtime_id}, {"target_entity_id", monster.runtime_id},
                    {"target_name", monster.definition.name}, {"damage", std::min(burn_damage, previous_health)},
                    {"health", static_cast<std::int64_t>(monster.state.health)},
                    {"max_health", monster.definition.max_health}, {"defeated", burn_defeated},
                    {"status_duration_ms", burn_defeated || monster.burn_effect.ticks_remaining <= 0 ? 0 :
                        std::max<std::int64_t>(0, monster.burn_effect.next_tick_at_ms - effect_now_ms) +
                        static_cast<std::int64_t>(monster.burn_effect.ticks_remaining - 1) *
                            monster.burn_effect.interval_ms},
                    {"experience_reward", experience_reward}, {"cultivation_reward", cultivation_reward}
                };
                if (burn_owner != players.end()) send_json(burn_owner->first,
                    honghuang::protocol::MessageType::CombatEvent, burn_event);
                for (const auto& [observer_peer, observer] : players) {
                    if (burn_owner != players.end() && observer_peer == burn_owner->first) continue;
                    if (honghuang::simulation::within_interest_radius(
                        monster.state.x, monster.state.z, observer.x, observer.z, kInterestRadius)) {
                        auto visual = burn_event;
                        visual["visual_only"] = true;
                        visual["experience_reward"] = 0;
                        visual["cultivation_reward"] = 0;
                        send_json(observer_peer, honghuang::protocol::MessageType::CombatEvent, visual);
                    }
                }
                if (burn_defeated) {
                    if (burn_owner != players.end()) {
                        if (config.world_id == "underworld_fengdu")
                            enqueue_soul_reward(burn_owner->second, 5, "underworld_trial:monster_hunt");
                        enqueue_soul_absorption(burn_owner->second, monster);
                        enqueue_monster_drops(monster, burn_owner->second);
                    }
                    continue;
                }
            }
            honghuang::simulation::MonsterTarget target_storage;
            const honghuang::simulation::MonsterTarget* nearest_target = nullptr;
            // Keep the current victim while they remain close enough; only acquire a
            // different player after the current target leaves the retention radius.
            if (monster.state.mode == honghuang::simulation::MonsterMode::Chasing &&
                !monster.state.target_id.empty()) {
                const auto current = std::find_if(players.begin(), players.end(), [&](const auto& entry) {
                    return entry.second.character_id == monster.state.target_id &&
                           entry.second.health > 0;
                });
                if (current != players.end()) {
                    const double dx = static_cast<double>(current->second.x) - monster.state.x;
                    const double dz = static_cast<double>(current->second.z) - monster.state.z;
                    const double retain_radius = std::min(
                        static_cast<double>(monster.definition.aggro_radius) * 1.25,
                        static_cast<double>(monster.definition.leash_radius));
                    if (dx * dx + dz * dz <= retain_radius * retain_radius) {
                        target_storage = {current->second.character_id, current->second.x,
                                          current->second.z, true};
                        nearest_target = &target_storage;
                    }
                }
            }
            double nearest_distance_squared = std::numeric_limits<double>::max();
            for (const auto& [peer, player] : players) {
                if (nearest_target != nullptr) break;
                (void)peer;
                if (player.health <= 0) continue;
                const double dx = static_cast<double>(player.x) - monster.state.x;
                const double dz = static_cast<double>(player.z) - monster.state.z;
                const double distance_squared = dx * dx + dz * dz;
                if (distance_squared < nearest_distance_squared) {
                    nearest_distance_squared = distance_squared;
                    target_storage = {player.character_id, player.x, player.z, true};
                    nearest_target = &target_storage;
                }
            }
            if (nearest_target != nullptr &&
                honghuang::simulation::monster_attack_profile(monster.definition).style == std::string("wolf_lunge")) {
                // Give each wolf a deterministic point on a small ring around its victim.
                // This spreads the pack without changing target selection or combat authority.
                std::uint32_t slot_hash = 2166136261U;
                for (const unsigned char ch : monster.runtime_id) {
                    slot_hash ^= ch;
                    slot_hash *= 16777619U;
                }
                const double angle = (static_cast<double>(slot_hash % 8U) / 8.0) * 6.283185307179586;
                const float slot_radius = std::min(0.65F, monster.definition.attack_range * 0.35F);
                target_storage.approach_x = target_storage.x + static_cast<float>(std::cos(angle) * slot_radius);
                target_storage.approach_z = target_storage.z + static_cast<float>(std::sin(angle) * slot_radius);
                target_storage.has_approach_position = true;
            }
            const auto effect_now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                now.time_since_epoch()).count();
            const bool monster_frozen = honghuang::simulation::freeze_is_active(monster.freeze_effect,effect_now_ms);
            const float monster_delta = monster_frozen ? 0.0F : honghuang::simulation::movement_delta_with_effect(delta,monster.slow_effect,effect_now_ms);
            if (!honghuang::simulation::tick_monster(
                    monster.definition, monster.state, nearest_target, monster_delta)) {
                std::cerr << "Skipping invalid monster simulation state: "
                          << monster.runtime_id << '\n';
                continue;
            }
            const auto attack_profile = honghuang::simulation::monster_attack_profile(monster.definition);
            const auto rare_scale = monster.rare_spawn ? 1.25 : 1.0;
            const auto windup_duration = std::chrono::milliseconds(
                static_cast<int>(std::lround(attack_profile.windup_ms * rare_scale)));
            const auto recovery_duration = std::chrono::milliseconds(
                static_cast<int>(std::lround(attack_profile.recovery_ms * rare_scale)));
            const auto attack_cooldown = std::chrono::milliseconds(
                static_cast<int>(std::lround(attack_profile.cooldown_ms * rare_scale)));
            const auto broadcast_attack_phase = [&](const std::string& phase) {
                const Json action{
                    {"source_entity_id", monster.runtime_id},
                    {"source", "monster"},
                    {"action", "attack"},
                    {"phase", phase},
                    {"attack_style", attack_profile.style},
                    {"attack_radius", attack_profile.splash_radius > 0.0F
                        ? attack_profile.splash_radius : attack_profile.range},
                    {"target_character_id", monster.attack_target_character_id},
                    {"windup_ms", windup_duration.count()},
                    {"recovery_ms", recovery_duration.count()}
                };
                for (const auto& [observer_peer, observer] : players) {
                    if (!honghuang::simulation::within_interest_radius(
                            monster.state.x, monster.state.z, observer.x, observer.z, kInterestRadius)) continue;
                    send_json(observer_peer, honghuang::protocol::MessageType::MonsterActionEvent, action);
                }
            };

            if (monster_frozen) {
                if (monster.attack_phase == MonsterAttackPhase::Windup) {
                    monster.attack_phase = MonsterAttackPhase::Ready;
                    broadcast_attack_phase("cancelled");
                    monster.attack_target_character_id.clear();
                }
                continue;
            }
            if (monster.state.mode != honghuang::simulation::MonsterMode::Chasing ||
                monster.state.target_id.empty()) {
                if (monster.attack_phase == MonsterAttackPhase::Windup) {
                    monster.attack_phase = MonsterAttackPhase::Ready;
                    monster.attack_target_character_id.clear();
                } else if (monster.attack_phase == MonsterAttackPhase::Recovery &&
                           now - monster.attack_phase_started_at >= recovery_duration) {
                    monster.attack_phase = MonsterAttackPhase::Ready;
                }
                continue;
            }

            auto victim = std::find_if(players.begin(), players.end(), [&](const auto& entry) {
                return entry.second.character_id == monster.state.target_id;
            });
            if (victim == players.end() || victim->second.health <= 0) {
                if (monster.attack_phase == MonsterAttackPhase::Windup) {
                    monster.attack_phase = MonsterAttackPhase::Ready;
                    monster.attack_target_character_id.clear();
                }
                continue;
            }
            auto& player = victim->second;
            const double attack_dx = static_cast<double>(player.x) - monster.state.x;
            const double attack_dz = static_cast<double>(player.z) - monster.state.z;
            const bool heavy_slam = std::string(attack_profile.style) == "heavy_slam";
            const double attack_range = heavy_slam
                ? static_cast<double>(attack_profile.splash_radius)
                : static_cast<double>(attack_profile.range);
            const bool in_attack_range = attack_dx * attack_dx + attack_dz * attack_dz <=
                attack_range * attack_range;

            if (monster.attack_phase == MonsterAttackPhase::Recovery) {
                if (now - monster.attack_phase_started_at < recovery_duration) continue;
                monster.attack_phase = MonsterAttackPhase::Ready;
            }
            if (monster.attack_phase == MonsterAttackPhase::Windup) {
                if (!in_attack_range || monster.attack_target_character_id != player.character_id) {
                    monster.attack_phase = MonsterAttackPhase::Ready;
                    monster.attack_target_character_id.clear();
                    continue;
                }
                if (now - monster.attack_phase_started_at < windup_duration) continue;
            } else {
                if (!in_attack_range) continue;
                if (monster.last_attack_at.time_since_epoch().count() != 0 &&
                    now - monster.last_attack_at < attack_cooldown) continue;
                monster.attack_phase = MonsterAttackPhase::Windup;
                monster.attack_phase_started_at = now;
                monster.attack_target_character_id = player.character_id;
                broadcast_attack_phase("windup");
                continue;
            }

            const honghuang::simulation::CombatantStats attacker{
                static_cast<std::int64_t>(monster.definition.attack),
                static_cast<std::int64_t>(monster.definition.defense), 1, 1
            };
            if (heavy_slam) {
                // Resolve the circular area at impact time so players can evade during windup.
                for (auto& [target_peer, target_player] : players) {
                    if (target_player.health <= 0) continue;
                    const double dx = static_cast<double>(target_player.x) - monster.state.x;
                    const double dz = static_cast<double>(target_player.z) - monster.state.z;
                    if (dx * dx + dz * dz > attack_range * attack_range) continue;
                    const honghuang::simulation::CombatantStats defender{
                        target_player.attack, target_player.defense,
                        target_player.health, target_player.max_health
                    };
                    honghuang::simulation::DamageResult damage{};
                    if (!honghuang::simulation::calculate_damage(
                            attacker, defender, honghuang::simulation::AttackProfile{}, damage)) {
                        std::cerr << "Heavy slam damage rejected by combat validation: "
                                  << monster.runtime_id << '\n';
                        continue;
                    }
                    target_player.health = damage.remaining_health;
                    target_player.last_combat_at = now;
                    if (damage.defeated) {
                        target_player.slow_effect = {};
                        target_player.poison_effect = {};
                        target_player.poison_source_entity_id.clear();
                    }
                    broadcast_player_action_event(target_player, "hit", monster.runtime_id, "heavy_slam", target_peer);
                    send_json(target_peer, honghuang::protocol::MessageType::CombatEvent,
                              Json{{"accepted", true}, {"source", "monster"},
                                   {"source_entity_id", monster.runtime_id},
                                   {"attack_style", "heavy_slam"},
                                   {"damage", damage.damage}, {"health", target_player.health},
                                   {"max_health", target_player.max_health},
                                   {"defeated", damage.defeated}});
                }
            } else {
                const honghuang::simulation::CombatantStats defender{
                    player.attack, player.defense, player.health, player.max_health
                };
                honghuang::simulation::DamageResult damage{};
                if (!honghuang::simulation::calculate_damage(
                        attacker, defender, honghuang::simulation::AttackProfile{}, damage)) {
                    std::cerr << "Monster attack rejected by combat validation: "
                              << monster.runtime_id << '\n';
                    monster.attack_phase = MonsterAttackPhase::Recovery;
                    monster.attack_phase_started_at = now;
                    continue;
                }
                player.health = damage.remaining_health;
                player.last_combat_at = now;
                if (damage.defeated) {
                    honghuang::simulation::clear_negative_statuses(player.slow_effect,player.freeze_effect,player.poison_effect);
                    player.poison_source_entity_id.clear();
                }
                bool applied_slow = false;
                bool applied_poison = false;
                const auto status_resistance_bp =
                    honghuang::simulation::negative_status_resistance_basis_points(
                        player.constitution, player.vitality);
                if (!damage.defeated && std::string(attack_profile.style) == "frost_bolt") {
                    const auto now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                        now.time_since_epoch()).count();
                    const auto slow_duration_ms = honghuang::simulation::resist_status_duration(
                        2200, 500, status_resistance_bp);
                    applied_slow = honghuang::simulation::apply_slow(
                        player.slow_effect, now_ms, slow_duration_ms, 0.70F);
                }
                if (!damage.defeated && std::string(attack_profile.style) == "poison_bolt") {
                    const auto now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                        now.time_since_epoch()).count();
                    const auto base_poison_damage = std::max<std::int64_t>(
                        1, static_cast<std::int64_t>(std::lround(monster.definition.attack * 0.15F)));
                    const auto poison_damage = honghuang::simulation::resist_status_damage(
                        base_poison_damage, status_resistance_bp);
                    const auto poison_duration_ms = honghuang::simulation::resist_status_duration(
                        4000, 1000, status_resistance_bp);
                    applied_poison = honghuang::simulation::apply_periodic_damage(
                        player.poison_effect, now_ms, poison_duration_ms, 1000, poison_damage);
                    if (applied_poison) player.poison_source_entity_id = monster.runtime_id;
                }
                broadcast_player_action_event(player, "hit", monster.runtime_id, attack_profile.style, victim->first);
                send_json(victim->first, honghuang::protocol::MessageType::CombatEvent,
                          Json{{"accepted", true}, {"source", "monster"},
                               {"source_entity_id", monster.runtime_id},
                               {"attack_style", attack_profile.style},
                               {"damage", damage.damage}, {"health", player.health},
                               {"max_health", player.max_health}, {"defeated", damage.defeated},
                               {"status_resistance_bp", (applied_poison || applied_slow) ? status_resistance_bp : 0},
                                {"status_effect", applied_poison ? "poison" : (applied_slow ? "slow" : "")},
                               {"status_duration_ms", applied_poison
                                    ? std::max<std::int64_t>(0, player.poison_effect.next_tick_at_ms -
                                        std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count()) +
                                      static_cast<std::int64_t>(std::max(0, player.poison_effect.ticks_remaining - 1)) *
                                        player.poison_effect.interval_ms
                                    : (applied_slow ? 2200 : 0)}});
            }
            monster.last_attack_at = now;
            monster.attack_phase = MonsterAttackPhase::Recovery;
            monster.attack_phase_started_at = now;
            broadcast_attack_phase("impact");
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
    std::filesystem::path outbox_path(impl_->config.outbox_database_path);
    if (outbox_path.has_parent_path()) {
        std::error_code directory_error;
        std::filesystem::create_directories(outbox_path.parent_path(), directory_error);
        if (directory_error) {
            std::cerr << "Could not create WorldServer data directory: " << directory_error.message() << '\n';
            return false;
        }
    }
    try {
        impl_->durable_outbox = std::make_unique<honghuang::persistence::DurableOutbox>(
            outbox_path.string(), 10000);
        impl_->monster_contribution_writer =
            std::make_unique<honghuang::persistence::MonsterContributionWriter>(
                *impl_->durable_outbox);
    } catch (const std::exception& exception) {
        impl_->monster_contribution_writer.reset();
        impl_->durable_outbox.reset();
        std::cerr << "Could not initialize durable persistence workers: " << exception.what() << '\n';
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
    impl_->start_chat_worker();
    impl_->start_persistence_worker();
    std::string loot_error;
    std::vector<MonsterRuntime> database_monsters;
    std::string monster_config_error;
    if(load_monster_spawn_config(impl_->config,database_monsters,monster_config_error)){
        impl_->monsters=std::move(database_monsters);
        std::cout<<"Loaded database monster spawn points="<<impl_->monsters.size()<<'\n';
    }else{
        std::cerr<<"Database monster config unavailable; retaining built-in startup fallback and retrying: "<<monster_config_error<<'\n';
    }
    impl_->start_monster_config_refresh_worker();
    if (!load_loot_table(impl_->config, impl_->loot_table, loot_error)) {
        std::cerr << "Monster loot table unavailable; periodic refresh will retry: " << loot_error << '\n';
    } else {
        std::cout << "Loaded " << impl_->loot_table.size() << " monster loot entries\n";
    }
    impl_->start_loot_refresh_worker();
    impl_->start_bounty_refresh_worker();
    std::string persisted_drop_error;
    if (!load_persisted_ground_drops(impl_->config, impl_->ground_drops, persisted_drop_error)) {
        std::cerr << "Persisted ground drops could not be restored: " << persisted_drop_error << '\n';
    } else {
        std::cout << "Restored " << impl_->ground_drops.size() << " persisted ground drops\n";
    }
    impl_->start_drop_worker();
    impl_->start_consumable_worker();
    impl_->start_combat_refresh_worker();
    impl_->start_outbox_worker();
    impl_->start_chat_outbox_worker();
    impl_->last_persistence = Clock::now();
    std::cout << "WorldServer ENet listening on UDP " << impl_->config.port << '\n';
    return true;
}

void EnetServer::poll(std::uint32_t timeout_ms) {
    if (impl_->host == nullptr) return;
    impl_->apply_pending_monster_config();
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
                        const std::string session_id = snapshot.value("session_id", std::string{});
                        const std::string character_id = snapshot.value("character_id", std::string{});
                        Json combat_stats;
                        long stats_http_status = 0;
                        std::string stats_error;
                        const Json stats_request{{"session_id", session_id}, {"character_id", character_id}};
                        if (!backend_inventory_request(impl_->config, "/api/v1/servers/sessions/combat-stats",
                                                       &stats_request, stats_http_status, combat_stats, stats_error) ||
                            !combat_stats.is_object() || !combat_stats.contains("attack") ||
                            !combat_stats.contains("defense") || !combat_stats.contains("health") ||
                            !combat_stats.contains("max_health") || !combat_stats.contains("mana") || !combat_stats.contains("max_mana") ||
                            !combat_stats.contains("movement_speed") || !combat_stats["movement_speed"].is_number() ||
                             !combat_stats.contains("constitution") || !combat_stats.contains("agility") || !combat_stats.contains("spirit") || !combat_stats.contains("vitality") ||
                              !combat_stats["constitution"].is_number_integer() || !combat_stats["agility"].is_number_integer() || !combat_stats["spirit"].is_number_integer() || !combat_stats["vitality"].is_number_integer() ||
                             !combat_stats["attack"].is_number_integer() ||
                            !combat_stats["defense"].is_number_integer() || !combat_stats["health"].is_number_integer() ||
                            !combat_stats["max_health"].is_number_integer() || !combat_stats["mana"].is_number_integer() || !combat_stats["max_mana"].is_number_integer() ||
                            combat_stats["mana"].get<std::int64_t>() < 0 ||
                            combat_stats["max_mana"].get<std::int64_t>() < 0 ||
                            combat_stats["mana"].get<std::int64_t>() > combat_stats["max_mana"].get<std::int64_t>() ||
                            combat_stats["max_mana"].get<std::int64_t>() > 10000000 ||
                            !std::isfinite(combat_stats["movement_speed"].get<double>()) ||
                            combat_stats["movement_speed"].get<double>() <= 0.0 ||
                            combat_stats["movement_speed"].get<double>() > 10.0) {
                            std::cerr << "Could not synchronize authoritative character combat stats: "
                                      << stats_error << std::endl;
                            send_json(event.peer, honghuang::protocol::MessageType::ServerReject,
                                      Json{{"reason", "character combat stats could not be synchronized"}});
                            enet_peer_disconnect_later(event.peer, 7);
                            PlayerState rejected_player;
                            rejected_player.session_id = session_id;
                            rejected_player.character_id = character_id;
                            rejected_player.x = snapshot.value("position_x", 0.0F);
                            rejected_player.y = snapshot.value("position_y", 0.0F);
                            rejected_player.z = snapshot.value("position_z", 0.0F);
                            rejected_player.yaw = snapshot.value("rotation_y", 0.0F);
                            std::string close_error;
                            if (!save_and_close_session(impl_->config, rejected_player, close_error)) {
                                std::cerr << "Could not close rejected world session: " << close_error << std::endl;
                            }
                        } else {
                        PlayerState player;
                        player.session_id = session_id;
                        player.character_id = character_id;
                        player.attack = combat_stats.at("attack").get<std::int64_t>();
                        player.defense = combat_stats.at("defense").get<std::int64_t>();
                        player.health = combat_stats.at("health").get<std::int64_t>();
                        player.max_health = combat_stats.at("max_health").get<std::int64_t>();
                        player.mana = combat_stats.at("mana").get<std::int64_t>();
                        player.max_mana = combat_stats.at("max_mana").get<std::int64_t>();
                        player.constitution = static_cast<std::int32_t>(std::clamp<std::int64_t>(
                            combat_stats.at("constitution").get<std::int64_t>(), 0, 100000));
                        player.agility = static_cast<std::int32_t>(std::clamp<std::int64_t>(
                            combat_stats.at("agility").get<std::int64_t>(), 0, 100000));
                        player.spirit = static_cast<std::int32_t>(std::clamp<std::int64_t>(
                            combat_stats.at("spirit").get<std::int64_t>(), 0, 100000));
                        player.vitality = static_cast<std::int32_t>(std::clamp<std::int64_t>(
                            combat_stats.at("vitality").get<std::int64_t>(), 0, 100000));
                        player.movement_speed = honghuang::simulation::effective_player_movement_speed(
                            combat_stats.at("movement_speed").get<float>());
                        player.name = snapshot.value("name", std::string{});
                        long bounty_http_status = 0;
                        std::string bounty_error;
                        if (!fetch_bounty_objectives(impl_->config, player.session_id, player.character_id,
                                                     player.bounty_objectives, bounty_http_status, bounty_error)) {
                            std::cerr << "Bounty objective subscriptions unavailable for character "
                                      << player.character_id << ": " << bounty_error << '\n';
                        } else {
                            std::cout << "Loaded " << player.bounty_objectives.size()
                                      << " bounty objective subscriptions for character "
                                      << player.character_id << '\n';
                        }
                        player.birth_inheritance = snapshot.value("birth_inheritance", Json::object());
                        if (!player.birth_inheritance.is_object()) player.birth_inheritance = Json::object();
                        player.equipment = snapshot.value("equipment", Json::array());
                        if (!player.equipment.is_array()) player.equipment = Json::array();
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
                        client_welcome["mana"] = impl_->players.at(event.peer).mana;
                        client_welcome["max_mana"] = impl_->players.at(event.peer).max_mana;
                        client_welcome.erase("session_id");
                        send_json(event.peer, honghuang::protocol::MessageType::ServerWelcome, client_welcome);
                        std::cout << "Authenticated character entered world: "
                                  << snapshot.value("character_id", std::string{}) << '\n';
                        }
                    }
                }
            } else if (frame.type == honghuang::protocol::MessageType::Heartbeat &&
                       impl_->players.contains(event.peer)) {
                const auto response = honghuang::protocol::encode_frame(
                    honghuang::protocol::MessageType::HeartbeatAck, {});
                auto* packet = enet_packet_create(response.data(), response.size(), ENET_PACKET_FLAG_RELIABLE);
                if (packet != nullptr && enet_peer_send(event.peer, 0, packet) != 0) enet_packet_destroy(packet);
            } else if (frame.type == honghuang::protocol::MessageType::ChatSendCommand &&
                       impl_->players.contains(event.peer)) {
                try {
                    const std::string payload(frame.payload.begin(), frame.payload.end());
                    const auto command = Json::parse(payload);
                    if (!command.is_object()) throw std::runtime_error("chat payload must be an object");
                    impl_->handle_chat(event.peer, command);
                } catch (const std::exception&) {
                    send_json(event.peer, honghuang::protocol::MessageType::ChatEvent,
                              Json{{"accepted", false}, {"reason", "聊天请求格式无效。"}});
                }
            } else if (frame.type == honghuang::protocol::MessageType::PickupCommand &&
                       impl_->players.contains(event.peer)) {
                try {
                    const std::string payload(frame.payload.begin(), frame.payload.end());
                    const auto command = Json::parse(payload);
                    impl_->handle_pickup(event.peer, command);
                } catch (const std::exception&) {
                    send_json(event.peer, honghuang::protocol::MessageType::PickupEvent,
                              Json{{"accepted", false}, {"reason", "拾取请求格式无效。"}});
                }
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
            } else if (frame.type == honghuang::protocol::MessageType::UseConsumableCommand &&
                       impl_->players.contains(event.peer)) {
                try {
                    const std::string payload(frame.payload.begin(), frame.payload.end());
                    const auto command = Json::parse(payload);
                    if (!command.is_object()) throw std::runtime_error("consumable payload must be an object");
                    impl_->handle_consumable_use(event.peer, command);
                } catch (const std::exception&) {
                    send_json(event.peer, honghuang::protocol::MessageType::CombatEvent,
                              Json{{"action", "consumable_use"}, {"accepted", false},
                                   {"reason", "消耗品请求格式无效。"}});
                }
            } else if (frame.type == honghuang::protocol::MessageType::SpellCastCommand &&
                       impl_->players.contains(event.peer)) {
                try {
                    const std::string payload(frame.payload.begin(), frame.payload.end());
                    const auto command = Json::parse(payload);
                    if (!command.is_object()) throw std::runtime_error("spell payload must be an object");
                    impl_->handle_spell_cast(event.peer, command);
                } catch (const std::exception&) {
                    send_json(event.peer, honghuang::protocol::MessageType::CombatEvent,
                              Json{{"accepted", false}, {"action", "spell_cast"}, {"reason", "法术请求格式无效。"}});
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
                            ++player.accepted_inputs_since_diagnostic;
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
                impl_->close_player_session_or_defer(event.peer);
            }
            std::cout << "ENet client disconnected\n";
            break;
        }
        case ENET_EVENT_TYPE_NONE:
            break;
        }
    }
    impl_->drain_chat_results();
    impl_->drain_consumable_results();
    impl_->drain_bounty_refresh_results();
    impl_->enqueue_periodic_bounty_refreshes();
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
        impl_->stop_monster_config_refresh_worker();
        impl_->stop_loot_refresh_worker();
        impl_->stop_bounty_refresh_worker();
        impl_->drain_bounty_refresh_results();

        impl_->stop_chat_worker();
        impl_->drain_chat_results();
        impl_->stop_consumable_worker();
        impl_->drain_consumable_results();
        impl_->stop_combat_refresh_worker();
        impl_->drain_combat_refresh_results();
        // Stop combat admission before this point, then give queued contribution
        // records a bounded opportunity to commit while SQLite is still alive.
        if (impl_->monster_contribution_writer) {
            constexpr auto kContributionShutdownDrainTimeout = std::chrono::seconds(5);
            if (!impl_->monster_contribution_writer->stop_after_drain(kContributionShutdownDrainTimeout)) {
                std::cerr << "[MonsterContribution] shutdown drain timed out; pending_records="
                          << impl_->monster_contribution_writer->pending_count()
                          << " last_error=" << impl_->monster_contribution_writer->last_error()
                          << ". Remaining in-memory records were not committed.\n";
            }
        }
        impl_->stop_chat_outbox_worker();
        impl_->stop_outbox_worker();
        impl_->stop_reward_worker();
        impl_->stop_drop_worker();
        impl_->drain_drop_results();
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
