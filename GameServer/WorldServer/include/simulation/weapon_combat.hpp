#pragma once

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <string_view>

namespace honghuang::simulation {

struct WeaponCombatProfile {
    float range;
    std::chrono::milliseconds cooldown;
    std::int32_t power_basis_points;
    std::int32_t defense_penetration_basis_points;
};

// Server-side balance profile selected only from the authenticated equipment snapshot.
// Staff and focus remain close-range until their server-authoritative spell projectiles exist.
inline WeaponCombatProfile weapon_combat_profile(std::string_view weapon_type) {
    if (weapon_type == "dagger") return {2.6F, std::chrono::milliseconds(480), 9000, 0};
    if (weapon_type == "spear") return {4.6F, std::chrono::milliseconds(800), 10500, 0};
    if (weapon_type == "axe") return {3.3F, std::chrono::milliseconds(850), 12500, 0};
    if (weapon_type == "hammer") return {3.0F, std::chrono::milliseconds(1000), 14000, 1000};
    if (weapon_type == "sword") return {3.5F, std::chrono::milliseconds(650), 10000, 0};
    if (weapon_type == "bow") return {22.0F, std::chrono::milliseconds(900), 10000, 0};
    if (weapon_type == "staff" || weapon_type == "focus")
        return {3.5F, std::chrono::milliseconds(700), 10000, 0};
    return {2.5F, std::chrono::milliseconds(700), 8000, 0};
}


 // Agility shortens the weapon's server-authoritative attack interval by 0.1%
 // per point, capped at 20%. A 100 ms floor prevents extreme attack rates.
// Agility grants 0.1% critical chance per point, capped at 15%.
inline std::int32_t critical_chance_basis_points(std::int32_t agility) {
    return std::clamp(agility, 0, 150) * 10;
}

inline std::chrono::milliseconds agility_adjusted_attack_cooldown(
    std::chrono::milliseconds base_cooldown, std::int32_t agility) {
    if (base_cooldown.count() <= 0) return std::chrono::milliseconds::zero();
    const auto base_ms = std::min<std::int64_t>(base_cooldown.count(), 60000);
    const auto effective_agility = std::clamp(agility, 0, 200);
    const auto reduction_basis_points = effective_agility * 10;
    const auto adjusted_ms =
        (base_ms * (10000 - reduction_basis_points) + 9999) / 10000;
    return std::chrono::milliseconds(std::max<std::int64_t>(100, adjusted_ms));
}

} // namespace honghuang::simulation
