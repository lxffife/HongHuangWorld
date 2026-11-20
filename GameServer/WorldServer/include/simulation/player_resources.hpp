#pragma once

#include <algorithm>
#include <cstdint>

namespace honghuang::simulation {

// Returns whole mana points restored for an elapsed interval. Invalid inputs
// fail closed; callers retain fractional time by advancing only consumed ticks.
inline std::int32_t mana_regeneration_interval_ms(bool in_combat,
                                                         std::int32_t normal_interval_ms,
                                                         std::int32_t combat_interval_ms) {
    if (normal_interval_ms <= 0 || combat_interval_ms <= 0) return 0;
    return in_combat ? combat_interval_ms : normal_interval_ms;
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
