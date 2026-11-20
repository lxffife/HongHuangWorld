#pragma once

#include <algorithm>
#include <cstdint>

namespace honghuang::simulation {

// Returns whole mana points restored for an elapsed interval. Invalid inputs
// fail closed; callers retain fractional time by advancing only consumed ticks.
// Spirit improves mana recovery by 0.2% per point, capped at 30%.
// The cap prevents extreme attributes or equipment bonuses from breaking pacing.
inline std::int32_t mana_regeneration_interval_ms(bool in_combat,
                                                   std::int32_t spirit,
                                                   std::int32_t normal_interval_ms,
                                                   std::int32_t combat_interval_ms) {
    if (normal_interval_ms <= 0 || combat_interval_ms <= 0 || spirit < 0) return 0;
    const auto base_interval = in_combat ? combat_interval_ms : normal_interval_ms;
    const auto reduction_basis_points = std::min<std::int64_t>(
        static_cast<std::int64_t>(spirit) * 20, 3000);
    return static_cast<std::int32_t>(
        static_cast<std::int64_t>(base_interval) * (10000 - reduction_basis_points) / 10000);
}

// Equipment cap changes preserve current resources unless the new cap is lower.
// Invalid negative caps fail closed to zero.
inline std::int64_t clamp_current_resource_to_maximum(std::int64_t current,
                                                       std::int64_t new_maximum) {
    if (new_maximum < 0) return 0;
    return std::clamp<std::int64_t>(current, 0, new_maximum);
}

inline std::int64_t mana_regeneration_amount(std::int64_t elapsed_ms,
                                             std::int64_t current_mana,
                                             std::int64_t max_mana,
                                             std::int32_t interval_ms) {
    if (elapsed_ms < 0 || current_mana < 0 || max_mana < 0 ||
        current_mana >= max_mana || interval_ms <= 0) return 0;
    const auto ticks = elapsed_ms / interval_ms;
    return std::min(ticks, max_mana - current_mana);
}

} // namespace honghuang::simulation
