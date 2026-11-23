#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace honghuang::simulation {

inline constexpr float kAllyReviveRange = 3.5F;
inline constexpr std::int64_t kAllyReviveChannelMs = 5000;
inline constexpr std::int64_t kAllyReviveCooldownMs = 45000;
inline constexpr std::int64_t kAllyReviveHealthPercent = 25;

inline std::int64_t ally_revive_health(std::int64_t maximum_health) {
    if (maximum_health <= 0) return 0;
    return std::max<std::int64_t>(1, maximum_health / 4);
}

inline bool ally_revive_in_range(double dx, double dz, double range = kAllyReviveRange) {
    if (!std::isfinite(dx) || !std::isfinite(dz) ||
        !std::isfinite(range) || range <= 0.0 || range > 20.0) return false;
    return dx * dx + dz * dz <= range * range;
}

inline bool ally_revive_channel_valid(bool rescuer_alive, bool rescuer_undamaged,
                                      bool rescuer_stationary, bool target_connected,
                                      bool target_downed, bool death_persisted) {
    return rescuer_alive && rescuer_undamaged && rescuer_stationary &&
        target_connected && target_downed && death_persisted;
}

} // namespace honghuang::simulation
