#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>

namespace honghuang::simulation {

struct PeriodicDamageEffect {
    std::int64_t expires_at_ms{};
    std::int64_t next_tick_at_ms{};
    std::int64_t damage_per_tick{};
    std::int32_t interval_ms{};
};

inline bool apply_periodic_damage(PeriodicDamageEffect& effect, std::int64_t now_ms,
                                  std::int32_t duration_ms, std::int32_t interval_ms,
                                  std::int64_t damage_per_tick) {
    if (now_ms < 0 || duration_ms <= 0 || duration_ms > 30000 ||
        interval_ms <= 0 || interval_ms > 10000 || damage_per_tick <= 0 ||
        now_ms > std::numeric_limits<std::int64_t>::max() - duration_ms ||
        now_ms > std::numeric_limits<std::int64_t>::max() - interval_ms) return false;
    if (effect.expires_at_ms <= now_ms) effect = {};
    effect.expires_at_ms = std::max(effect.expires_at_ms, now_ms + duration_ms);
    effect.next_tick_at_ms = std::min(effect.next_tick_at_ms == 0 ? now_ms + interval_ms
                                                                  : effect.next_tick_at_ms,
                                      now_ms + interval_ms);
    effect.damage_per_tick = std::max(effect.damage_per_tick, damage_per_tick);
    effect.interval_ms = std::min(effect.interval_ms == 0 ? interval_ms : effect.interval_ms,
                                  interval_ms);
    return true;
}

inline bool periodic_damage_is_active(const PeriodicDamageEffect& effect, std::int64_t now_ms) {
    return effect.expires_at_ms > now_ms && effect.damage_per_tick > 0 &&
           effect.interval_ms > 0 && effect.next_tick_at_ms > 0;
}

// Emit at most one tick per world update; delayed frames never cause a catch-up burst.
inline std::int64_t consume_periodic_damage_tick(PeriodicDamageEffect& effect,
                                                  std::int64_t now_ms) {
    if (!periodic_damage_is_active(effect, now_ms) || now_ms < effect.next_tick_at_ms) {
        if (effect.expires_at_ms <= now_ms) effect = {};
        return 0;
    }
    const auto damage = effect.damage_per_tick;
    if (now_ms > std::numeric_limits<std::int64_t>::max() - effect.interval_ms) effect = {};
    else effect.next_tick_at_ms = now_ms + effect.interval_ms;
    return damage;
}

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
