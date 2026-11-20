#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <string_view>

namespace honghuang::simulation {

struct PeriodicDamageEffect {
    std::int64_t expires_at_ms{};
    std::int64_t next_tick_at_ms{};
    std::int64_t damage_per_tick{};
    std::int32_t interval_ms{};
    std::int32_t ticks_remaining{};
};

inline bool apply_periodic_damage(PeriodicDamageEffect& effect, std::int64_t now_ms,
                                  std::int32_t duration_ms, std::int32_t interval_ms,
                                  std::int64_t damage_per_tick) {
    if (now_ms < 0 || duration_ms <= 0 || duration_ms > 30000 ||
        interval_ms <= 0 || interval_ms > 10000 || damage_per_tick <= 0 ||
        now_ms > std::numeric_limits<std::int64_t>::max() - duration_ms ||
        now_ms > std::numeric_limits<std::int64_t>::max() - interval_ms) return false;
    if (effect.ticks_remaining <= 0) effect = {};
    effect.expires_at_ms = std::max(effect.expires_at_ms, now_ms + duration_ms);
    effect.interval_ms = std::min(effect.interval_ms == 0 ? interval_ms : effect.interval_ms,
                                  interval_ms);
    effect.next_tick_at_ms = std::min(effect.next_tick_at_ms == 0 ? now_ms + effect.interval_ms
                                                                  : effect.next_tick_at_ms,
                                      now_ms + effect.interval_ms);
    effect.damage_per_tick = std::max(effect.damage_per_tick, damage_per_tick);
    const auto refreshed_ticks = (duration_ms + effect.interval_ms - 1) / effect.interval_ms;
    effect.ticks_remaining = std::max(effect.ticks_remaining, refreshed_ticks);
    return true;
}

inline bool periodic_damage_is_active(const PeriodicDamageEffect& effect, std::int64_t now_ms) {
    (void)now_ms;
    return effect.ticks_remaining > 0 && effect.damage_per_tick > 0 &&
           effect.interval_ms > 0 && effect.next_tick_at_ms > 0;
}

// Emit at most one tick per world update; delayed frames never cause a catch-up burst.
inline std::int64_t consume_periodic_damage_tick(PeriodicDamageEffect& effect,
                                                  std::int64_t now_ms) {
    if (!periodic_damage_is_active(effect, now_ms) || now_ms < effect.next_tick_at_ms) {
        if (effect.ticks_remaining <= 0) effect = {};
        return 0;
    }
    const auto damage = effect.damage_per_tick;
    --effect.ticks_remaining;
    if (effect.ticks_remaining <= 0 ||
        now_ms > std::numeric_limits<std::int64_t>::max() - effect.interval_ms) {
        effect = {};
    } else {
        effect.next_tick_at_ms = now_ms + effect.interval_ms;
    }
    return damage;
}

// Constitution and vitality contribute to resistance against negative status effects.
 // The cap prevents high-level characters from becoming fully immune.
inline std::int32_t negative_status_resistance_basis_points(std::int32_t constitution,
                                                             std::int32_t vitality) {
    if (constitution < 0 || vitality < 0) return 0;
    const auto raw = static_cast<std::int64_t>(constitution) * 20 +
                     static_cast<std::int64_t>(vitality) * 10;
    return static_cast<std::int32_t>(std::min<std::int64_t>(5000, raw));
}

inline std::int64_t resist_status_damage(std::int64_t base_damage,
                                         std::int32_t resistance_basis_points) {
    if (base_damage <= 0) return 0;
    const auto resistance = std::clamp(resistance_basis_points, 0, 10000);
    const auto remaining_basis_points = 10000 - resistance;
    const auto reduced = (base_damage / 10000) * remaining_basis_points +
                         (base_damage % 10000) * remaining_basis_points / 10000;
    return std::max<std::int64_t>(1, reduced);
}

inline std::int32_t resist_status_duration(std::int32_t base_duration_ms,
                                           std::int32_t minimum_duration_ms,
                                           std::int32_t resistance_basis_points) {
    if (base_duration_ms <= 0 || minimum_duration_ms < 0 ||
        minimum_duration_ms > base_duration_ms) return 0;
    const auto resistance = std::clamp(resistance_basis_points, 0, 10000);
    const auto reduced = static_cast<std::int64_t>(base_duration_ms) *
                         (10000 - resistance) / 10000;
    return static_cast<std::int32_t>(std::max<std::int64_t>(minimum_duration_ms, reduced));
}


struct TimedFreezeEffect { std::int64_t expires_at_ms{}; };
inline bool apply_freeze(TimedFreezeEffect& e,std::int64_t now,std::int32_t duration){
 if(now<0||duration<=0||duration>5000||now>std::numeric_limits<std::int64_t>::max()-duration)return false;
 e.expires_at_ms=std::max(e.expires_at_ms,now+duration);return true;
}
inline bool freeze_is_active(const TimedFreezeEffect& e,std::int64_t now){return e.expires_at_ms>now;}
inline std::int32_t monster_freeze_duration_ms(std::int32_t base,std::string_view id,std::string_view name,bool rare){
 if(base<=0||base>5000)return 0;
 const bool elite=rare||id.find("elite")!=std::string_view::npos||id.find("boss")!=std::string_view::npos||
 name.find("精英")!=std::string_view::npos||name.find("首领")!=std::string_view::npos||
 name.find("Boss")!=std::string_view::npos||name.find("boss")!=std::string_view::npos;
 return elite?std::max<std::int32_t>(150,base*35/100):base;
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


inline void clear_negative_statuses(TimedSlowEffect& slow,TimedFreezeEffect& freeze,PeriodicDamageEffect& dot){
 slow={};freeze={};dot={};
}
} // namespace honghuang::simulation
