#pragma once

#include <algorithm>
#include <cstdint>

namespace honghuang::simulation {

inline constexpr std::int64_t kLifeMendManaCost = 18;
inline constexpr std::int64_t kLifeMendCooldownMs = 6000;
inline constexpr std::int64_t kLifeMendBaseHealing = 30;
inline constexpr std::int64_t kLifeMendSpiritScaling = 2;
inline constexpr double kSupportSpellRange = 12.0;

inline constexpr std::int64_t kGuardianAegisManaCost = 22;
inline constexpr std::int64_t kGuardianAegisCooldownMs = 12000;
inline constexpr std::int64_t kGuardianAegisHealthPercent = 25;
inline constexpr std::int64_t kGuardianAegisDurationMs = 8000;

inline std::int64_t life_mend_amount(std::int64_t spirit) {
    if (spirit < 0) spirit = 0;
    return std::min<std::int64_t>(1000000,
        kLifeMendBaseHealing + std::min<std::int64_t>(spirit, 100000) * kLifeMendSpiritScaling);
}

inline std::int64_t guardian_aegis_amount(std::int64_t target_max_health) {
    if (target_max_health <= 0) return 0;
    return std::max<std::int64_t>(1, target_max_health / 4);
}

inline std::int64_t absorb_with_shield(std::int64_t incoming_damage,
                                       std::int64_t& shield_health) {
    if (incoming_damage <= 0 || shield_health <= 0) return 0;
    const auto absorbed = std::min(incoming_damage, shield_health);
    shield_health -= absorbed;
    return absorbed;
}

inline bool support_target_in_range(double dx, double dz,
                                    double range = kSupportSpellRange) {
    if (range <= 0.0 || range > 50.0) return false;
    return dx * dx + dz * dz <= range * range;
}

} // namespace honghuang::simulation
