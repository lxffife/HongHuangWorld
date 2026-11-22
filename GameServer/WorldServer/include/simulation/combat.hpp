#pragma once

#include <algorithm>
#include <cstdint>
#include <limits>

namespace honghuang::simulation {

struct CombatantStats {
    std::int64_t attack{};
    std::int64_t defense{};
    std::int64_t current_health{};
    std::int64_t max_health{};
};

struct AttackProfile {
    // 10000 = 1.0x attack; 20000 = 2.0x attack.
    std::int32_t power_basis_points{10000};
    // 0 = no penetration; 10000 = ignore all defense.
    std::int32_t defense_penetration_basis_points{};
    bool critical{};
};

struct DamageResult {
    std::int64_t damage{};
    std::int64_t remaining_health{};
    bool defeated{};
    bool critical{};
};

// Deterministic server-side damage calculation. This function is deliberately
// free of randomness and world state so balance rules can be unit-tested.
inline bool calculate_damage(const CombatantStats& attacker,
                             const CombatantStats& defender,
                             const AttackProfile& profile,
                             DamageResult& result) {
    constexpr std::int64_t kMaxStat = 1'000'000'000LL;
    constexpr std::int32_t kMaxPowerBasisPoints = 100'000;

    if (attacker.attack < 0 || attacker.attack > kMaxStat ||
        defender.defense < 0 || defender.defense > kMaxStat ||
        defender.max_health < 1 || defender.max_health > kMaxStat ||
        defender.current_health < 0 || defender.current_health > defender.max_health ||
        profile.power_basis_points < 1 ||
        profile.power_basis_points > kMaxPowerBasisPoints ||
        profile.defense_penetration_basis_points < 0 ||
        profile.defense_penetration_basis_points > 10'000) {
        return false;
    }

    const auto remaining_defense = 10'000LL - profile.defense_penetration_basis_points;
    const auto effective_defense = defender.defense * remaining_defense / 10'000LL;
    auto scaled_attack = attacker.attack * profile.power_basis_points / 10'000LL;
    if (profile.critical) scaled_attack = scaled_attack * 15'000LL / 10'000LL;
    const auto damage = std::max<std::int64_t>(1, scaled_attack - effective_defense);
    result.damage = std::min(damage, defender.current_health);
    result.remaining_health = defender.current_health - result.damage;
    result.defeated = result.remaining_health == 0;
    result.critical = profile.critical;
    return true;
}

} // namespace honghuang::simulation
