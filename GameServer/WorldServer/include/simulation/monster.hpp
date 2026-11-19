#pragma once

#include <algorithm>
#include <cmath>
#include <string>

namespace honghuang::simulation {

enum class MonsterMode { Idle, Chasing, Returning, Dead };

struct MonsterDefinition {
    std::string id;
    std::string name;
    int level{1};
    float max_health{100.0F};
    float attack{10.0F};
    float defense{2.0F};
    float move_speed{2.5F};
    float aggro_radius{10.0F};
    float leash_radius{24.0F};
    float spawn_x{};
    float spawn_z{};
    float attack_range{1.8F};
};

struct MonsterAttackProfile {
    int windup_ms{520};
    int recovery_ms{420};
    int cooldown_ms{1500};
    float range{};
    const char* style{"melee"};
};

// Keep archetype cadence server-authoritative. Names/IDs are the stable data
// already supplied by the spawn catalogue; unknown monsters retain safe defaults.
inline MonsterAttackProfile monster_attack_profile(const MonsterDefinition& definition) {
    MonsterAttackProfile profile;
    profile.range = definition.attack_range;
    const auto& key = definition.id + " " + definition.name;
    if (key.find("wolf") != std::string::npos || key.find("荒原狼") != std::string::npos) {
        profile.windup_ms = 320;
        profile.recovery_ms = 300;
        profile.cooldown_ms = 900;
        profile.style = "wolf_lunge";
    } else if (key.find("iron_beast") != std::string::npos || key.find("铁骨兽") != std::string::npos) {
        profile.windup_ms = 1000;
        profile.recovery_ms = 900;
        profile.cooldown_ms = 2500;
        profile.style = "heavy_slam";
    } else if (key.find("warrior") != std::string::npos || key.find("战魂") != std::string::npos) {
        profile.windup_ms = 620;
        profile.recovery_ms = 560;
        profile.cooldown_ms = 1650;
        profile.style = "blade_slash";
    } else if (key.find("soul") != std::string::npos || key.find("游魂") != std::string::npos ||
               key.find("wraith") != std::string::npos) {
        profile.windup_ms = 760;
        profile.recovery_ms = 680;
        profile.cooldown_ms = 2100;
        profile.range = std::min(std::max(definition.attack_range, 6.0F),
                                 definition.leash_radius - 0.1F);
        profile.style = "soul_bolt";
    }
    return profile;
}

struct MonsterTarget {
    std::string id;
    float x{};
    float z{};
    bool alive{true};
};

struct MonsterState {
    float x{};
    float z{};
    float health{100.0F};
    MonsterMode mode{MonsterMode::Idle};
    std::string target_id;
    float yaw{};
};

inline bool valid_monster_definition(const MonsterDefinition& definition) {
    const auto finite_nonnegative = [](float value) {
        return std::isfinite(value) && value >= 0.0F;
    };
    return !definition.id.empty() && !definition.name.empty() &&
        definition.level >= 1 && definition.level <= 10'000 &&
        std::isfinite(definition.max_health) && definition.max_health > 0.0F &&
        finite_nonnegative(definition.attack) && finite_nonnegative(definition.defense) &&
        std::isfinite(definition.move_speed) && definition.move_speed > 0.0F &&
        std::isfinite(definition.aggro_radius) && definition.aggro_radius > 0.0F &&
        std::isfinite(definition.leash_radius) &&
        definition.leash_radius >= definition.aggro_radius &&
        std::isfinite(definition.spawn_x) && std::isfinite(definition.spawn_z) &&
        std::isfinite(definition.attack_range) && definition.attack_range > 0.0F &&
        definition.attack_range < definition.leash_radius;
}

// Server-authoritative, deterministic movement/aggro step. Combat is deliberately
// separate: this function only chooses a mode and moves the monster in the X/Z plane.
inline bool tick_monster(const MonsterDefinition& definition, MonsterState& state,
                         const MonsterTarget* target, float delta_seconds) {
    if (!valid_monster_definition(definition) ||
        !std::isfinite(state.x) || !std::isfinite(state.z) ||
        !std::isfinite(state.health) || state.health < 0.0F ||
        state.health > definition.max_health ||
        !std::isfinite(delta_seconds) || delta_seconds < 0.0F) {
        return false;
    }

    if (state.health <= 0.0F || state.mode == MonsterMode::Dead) {
        state.health = 0.0F;
        state.mode = MonsterMode::Dead;
        state.target_id.clear();
        return true;
    }

    const auto distance_squared = [](float ax, float az, float bx, float bz) {
        const double dx = static_cast<double>(ax) - bx;
        const double dz = static_cast<double>(az) - bz;
        return dx * dx + dz * dz;
    };
    const double leash_sq = static_cast<double>(definition.leash_radius) * definition.leash_radius;
    const bool outside_leash = distance_squared(
        state.x, state.z, definition.spawn_x, definition.spawn_z) > leash_sq;

    if (outside_leash) {
        state.mode = MonsterMode::Returning;
        state.target_id.clear();
    } else if (target != nullptr && target->alive && !target->id.empty() &&
               std::isfinite(target->x) && std::isfinite(target->z)) {
        const bool retaining_target = state.mode == MonsterMode::Chasing &&
            target->id == state.target_id;
        const double aggro_radius = retaining_target
            ? std::min(static_cast<double>(definition.aggro_radius) * 1.25,
                       static_cast<double>(definition.leash_radius))
            : static_cast<double>(definition.aggro_radius);
        if (distance_squared(state.x, state.z, target->x, target->z) <=
            aggro_radius * aggro_radius) {
            state.mode = MonsterMode::Chasing;
            state.target_id = target->id;
        } else if (state.mode == MonsterMode::Chasing) {
            state.mode = MonsterMode::Returning;
            state.target_id.clear();
        }
    } else if (state.mode == MonsterMode::Chasing) {
        state.mode = MonsterMode::Returning;
        state.target_id.clear();
    }

    float destination_x = definition.spawn_x;
    float destination_z = definition.spawn_z;
    if (state.mode == MonsterMode::Chasing && target != nullptr) {
        destination_x = target->x;
        destination_z = target->z;
    }

    const float dx = destination_x - state.x;
    const float dz = destination_z - state.z;
    const double distance = std::hypot(static_cast<double>(dx), static_cast<double>(dz));
    if (distance > 0.001) {
        // Godot characters face local -Z; keep the server snapshot as the facing authority.
        state.yaw = std::atan2(-dx, -dz);
    }
    if (state.mode == MonsterMode::Chasing &&
        distance <= static_cast<double>(definition.attack_range)) {
        return true;
    }
    if (distance <= 0.001 || delta_seconds == 0.0F) {
        if (state.mode == MonsterMode::Returning) state.mode = MonsterMode::Idle;
        return true;
    }

    const float step = definition.move_speed * std::min(delta_seconds, 0.1F);
    const double desired_travel = state.mode == MonsterMode::Chasing
        ? distance - static_cast<double>(definition.attack_range)
        : distance;
    const float travel = static_cast<float>(std::min(static_cast<double>(step), desired_travel));
    state.x += dx / static_cast<float>(distance) * travel;
    state.z += dz / static_cast<float>(distance) * travel;
    if (state.mode == MonsterMode::Returning &&
        distance_squared(state.x, state.z, definition.spawn_x, definition.spawn_z) <= 0.01) {
        state.mode = MonsterMode::Idle;
    }
    return true;
}

} // namespace honghuang::simulation
