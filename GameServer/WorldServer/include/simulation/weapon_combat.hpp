#pragma once

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
// Bow and focus weapons intentionally remain close-range until projectile simulation exists.
inline WeaponCombatProfile weapon_combat_profile(std::string_view weapon_type) {
    if (weapon_type == "dagger") return {2.6F, std::chrono::milliseconds(480), 9000, 0};
    if (weapon_type == "spear") return {4.6F, std::chrono::milliseconds(800), 10500, 0};
    if (weapon_type == "axe") return {3.3F, std::chrono::milliseconds(850), 12500, 0};
    if (weapon_type == "hammer") return {3.0F, std::chrono::milliseconds(1000), 14000, 1000};
    if (weapon_type == "sword") return {3.5F, std::chrono::milliseconds(650), 10000, 0};
    if (weapon_type == "bow" || weapon_type == "staff" || weapon_type == "focus")
        return {3.5F, std::chrono::milliseconds(700), 10000, 0};
    return {2.5F, std::chrono::milliseconds(700), 8000, 0};
}

} // namespace honghuang::simulation
