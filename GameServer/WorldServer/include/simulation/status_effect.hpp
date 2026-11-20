#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>

namespace honghuang::simulation {

struct TimedSlowEffect {
    std::int64_t expires_at_ms{};
    float movement_multiplier{1.0F};
};

inline bool apply_slow(TimedSlowEffect& effect, std::int64_t now_ms,
                       std::int32_t duration_ms, float movement_multiplier) {
    if (now_ms < 0 || duration_ms <= 0 || duration_ms > 30000 ||
        !std::isfinite(movement_multiplier) ||
        movement_multiplier <= 0.0F || movement_multiplier >= 1.0F ||
        now_ms > std::numeric_limits<std::int64_t>::max() - duration_ms) {
        return false;
    }
    // An expired effect must not leak its old multiplier into a new application.
    if (effect.expires_at_ms <= now_ms) effect = {};
    // Refresh policy: keep the stronger slow and the later expiry; repeated
    // hits cannot shorten an existing effect or stack movement penalties.
    effect.expires_at_ms = std::max(effect.expires_at_ms, now_ms + duration_ms);
    effect.movement_multiplier = std::min(effect.movement_multiplier, movement_multiplier);
    return true;
}

inline bool slow_is_active(const TimedSlowEffect& effect, std::int64_t now_ms) {
    return effect.expires_at_ms > now_ms && effect.movement_multiplier > 0.0F &&
           effect.movement_multiplier < 1.0F;
}

inline float movement_delta_with_effect(float delta_seconds,
                                         const TimedSlowEffect& effect,
                                         std::int64_t now_ms) {
    if (!std::isfinite(delta_seconds) || delta_seconds < 0.0F) return 0.0F;
    return delta_seconds * (slow_is_active(effect, now_ms)
        ? effect.movement_multiplier : 1.0F);
}

} // namespace honghuang::simulation
