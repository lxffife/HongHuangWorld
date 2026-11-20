#include "simulation/status_effect.hpp"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>
#include <cmath>
#include <limits>

int main() {
    using namespace honghuang::simulation;
    TimedSlowEffect effect;
    assert(!slow_is_active(effect, 1000));
    assert(apply_slow(effect, 1000, 3000, 0.55F));
    assert(slow_is_active(effect, 1001));
    assert(std::abs(movement_delta_with_effect(0.1F, effect, 2000) - 0.055F) < 0.00001F);
    assert(apply_slow(effect, 2000, 3000, 0.8F));
    assert(effect.expires_at_ms == 5000);
    assert(effect.movement_multiplier == 0.55F);
    assert(apply_slow(effect, 4500, 1000, 0.7F));
    assert(effect.expires_at_ms == 5500);
    assert(effect.movement_multiplier == 0.55F);
    assert(!slow_is_active(effect, 5500));
    assert(std::abs(movement_delta_with_effect(0.1F, effect, 5500) - 0.1F) < 0.00001F);
    // A new application after expiry starts fresh instead of inheriting the old stronger slow.
    assert(apply_slow(effect, 6000, 1000, 0.8F));
    assert(effect.expires_at_ms == 7000);
    assert(effect.movement_multiplier == 0.8F);

    assert(!apply_slow(effect, 0, 0, 0.5F));
    assert(!apply_slow(effect, 0, 1000, 1.0F));
    assert(!apply_slow(effect, 0, 1000, std::numeric_limits<float>::quiet_NaN()));
    assert(!apply_slow(effect, INT64_MAX - 10, 1000, 0.5F));
    assert(movement_delta_with_effect(-1.0F, effect, 4500) == 0.0F);
    assert(negative_status_resistance_basis_points(100, 100) == 3000);
    assert(negative_status_resistance_basis_points(500, 500) == 5000);
    assert(negative_status_resistance_basis_points(-1, 100) == 0);
    assert(resist_status_damage(20, 3000) == 14);
    assert(resist_status_damage(1, 5000) == 1);
    assert(resist_status_damage(20, 20000) == 1);
    assert(resist_status_duration(4000, 1000, 3000) == 2800);
    assert(resist_status_duration(4000, 1000, 10000) == 1000);
    assert(resist_status_duration(4000, 5000, 3000) == 0);
    PeriodicDamageEffect burn;
    assert(!periodic_damage_is_active(burn, 1000));
    assert(apply_periodic_damage(burn, 1000, 3000, 1000, 5));
    assert(periodic_damage_is_active(burn, 1001));
    assert(consume_periodic_damage_tick(burn, 1999) == 0);
    assert(consume_periodic_damage_tick(burn, 2000) == 5);
    assert(burn.next_tick_at_ms == 3000);
    assert(apply_periodic_damage(burn, 2500, 3000, 1000, 3));
    assert(burn.expires_at_ms == 5500 && burn.damage_per_tick == 5);
    assert(consume_periodic_damage_tick(burn, 3000) == 5);
    // A delayed world frame emits one tick, never a catch-up burst.
    assert(consume_periodic_damage_tick(burn, 5100) == 5);
    assert(consume_periodic_damage_tick(burn, 5500) == 0);
    assert(periodic_damage_is_active(burn, 5500));
    assert(periodic_damage_is_active(burn, 5501));
    // The last scheduled tick is preserved even when the world loop runs after nominal expiry.
    assert(consume_periodic_damage_tick(burn, 6100) == 5);
    assert(!periodic_damage_is_active(burn, 6100));
    assert(apply_periodic_damage(burn, 7000, 2000, 500, 2));
    assert(burn.damage_per_tick == 2 && burn.next_tick_at_ms == 7500);
    assert(!apply_periodic_damage(burn, 0, 0, 1000, 1));
    assert(!apply_periodic_damage(burn, 0, 1000, 0, 1));
    assert(!apply_periodic_damage(burn, 0, 1000, 1000, 0));
    assert(!apply_periodic_damage(burn, INT64_MAX - 10, 1000, 500, 1));
    PeriodicDamageEffect final_tick;
    assert(apply_periodic_damage(final_tick, 100, 1000, 1000, 7));
    assert(consume_periodic_damage_tick(final_tick, 1200) == 7); // A delayed final tick is not lost.

    // Poison shares the bounded periodic-damage engine but refreshes independently.
    PeriodicDamageEffect poison;
    assert(apply_periodic_damage(poison, 1000, 4000, 1000, 3));
    assert(consume_periodic_damage_tick(poison, 2000) == 3);
    assert(apply_periodic_damage(poison, 2500, 4000, 1000, 5));
    assert(poison.damage_per_tick == 5);
    assert(poison.ticks_remaining >= 3);
    assert(consume_periodic_damage_tick(poison, 3000) == 5);
    assert(consume_periodic_damage_tick(poison, 4000) == 5);
    return 0;
}
