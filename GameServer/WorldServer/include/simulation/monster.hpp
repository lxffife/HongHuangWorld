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
    float splash_radius{};
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
        profile.splash_radius = std::min(std::max(definition.attack_range * 2.0F, 3.6F),
                                         definition.leash_radius - 0.1F);
        profile.style = "heavy_slam";
    } else if (key.find("warrior") != std::string::npos || key.find("战魂") != std::string::npos) {
        profile.windup_ms = 620;
        profile.recovery_ms = 560;
        profile.cooldown_ms = 1650;
        profile.style = "blade_slash";
    } else if (key.find("frost") != std::string::npos || key.find("ice_soul") != std::string::npos ||
               key.find("冰魂") != std::string::npos || key.find("冰系游魂") != std::string::npos) {
        profile.windup_ms = 820;
        profile.recovery_ms = 720;
        profile.cooldown_ms = 2400;
        if (definition.leash_radius > 6.1F) {
            profile.range = std::min(std::max(definition.attack_range, 6.0F),
                                     definition.leash_radius - 0.1F);
        }
        profile.style = "frost_bolt";
    } else if (key.find("soul") != std::string::npos || key.find("游魂") != std::string::npos ||
               key.find("wraith") != std::string::npos) {
        profile.windup_ms = 760;
        profile.recovery_ms = 680;
        profile.cooldown_ms = 2100;
        if (definition.leash_radius > 6.1F) {
            profile.range = std::min(std::max(definition.attack_range, 6.0F),
                                     definition.leash_radius - 0.1F);
        }
        profile.style = "soul_bolt";
    }
    return profile;
}

struct MonsterTarget {
    std::string id;
    float x{};
    float z{};
    bool alive{true};
    float approach_x{};
    float approach_z{};
    bool has_approach_position{false};
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
    bool retreating = false;
    double distance = 0.0;
    float dx = destination_x - state.x;
    float dz = destination_z - state.z;

    double movement_attack_range = static_cast<double>(definition.attack_range);
    if (state.mode == MonsterMode::Chasing && target != nullptr) {
        const auto profile = monster_attack_profile(definition);
        movement_attack_range = static_cast<double>(profile.range);
        const bool wolf_pack_position = std::string(profile.style) == "wolf_lunge" &&
            target->has_approach_position;
        const float movement_target_x = wolf_pack_position ? target->approach_x : target->x;
        const float movement_target_z = wolf_pack_position ? target->approach_z : target->z;
        dx = movement_target_x - state.x;
        dz = movement_target_z - state.z;
        distance = std::hypot(static_cast<double>(dx), static_cast<double>(dz));
        if (wolf_pack_position) {
            const double slot_radius = std::hypot(
                static_cast<double>(target->approach_x - target->x),
                static_cast<double>(target->approach_z - target->z));
            movement_attack_range = std::max(0.1, movement_attack_range - slot_radius);
        }
        if (std::string(profile.style) == "soul_bolt" ||
            std::string(profile.style) == "frost_bolt") {
            // Ranged souls kite at roughly 72% of their attack range. They still
            // remain inside attack range, so a windup can complete if the player
            // does not keep closing the gap.
            const double preferred_distance = static_cast<double>(profile.range) * 0.72;
            const double target_distance = std::hypot(
                static_cast<double>(target->x - state.x),
                static_cast<double>(target->z - state.z));
            retreating = target_distance < preferred_distance && target_distance > 0.001;
            if (retreating) {
                dx = state.x - target->x;
                dz = state.z - target->z;
                distance = target_distance;
            }
        }
    } else {
        distance = std::hypot(static_cast<double>(dx), static_cast<double>(dz));
    }

    if (state.mode == MonsterMode::Chasing && target != nullptr) {
        const float face_dx = target->x - state.x;
        const float face_dz = target->z - state.z;
        if (std::hypot(static_cast<double>(face_dx), static_cast<double>(face_dz)) > 0.001) {
            // Even while kiting, ranged souls keep facing their target.
            state.yaw = std::atan2(-face_dx, -face_dz);
        }
    } else if (distance > 0.001) {
        // Godot characters face local -Z; keep the server snapshot as the facing authority.
        state.yaw = std::atan2(-dx, -dz);
    }

    if (state.mode == MonsterMode::Chasing && !retreating &&
        distance <= movement_attack_range) {
        return true;
    }
    if (distance <= 0.001 || delta_seconds == 0.0F) {
        if (state.mode == MonsterMode::Returning) state.mode = MonsterMode::Idle;
        return true;
    }

    const float step = definition.move_speed * std::min(delta_seconds, 0.1F);
    double desired_travel = state.mode == MonsterMode::Chasing
        ? (retreating
            ? static_cast<double>(definition.attack_range) * 0.72 - distance
            : distance - movement_attack_range)
        : distance;
    if (retreating) {
        const double from_spawn = std::hypot(
            static_cast<double>(state.x - definition.spawn_x),
            static_cast<double>(state.z - definition.spawn_z));
        const double leash_remaining = std::max(
            0.0, static_cast<double>(definition.leash_radius) - from_spawn - 0.05);
        desired_travel = std::min(desired_travel, leash_remaining);
    }
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
