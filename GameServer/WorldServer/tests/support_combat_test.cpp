#include "simulation/support_combat.hpp"
#include "simulation/status_effect.hpp"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>

int main() {
    using namespace honghuang::simulation;
    assert(life_mend_amount(0) == 30);
    assert(life_mend_amount(10) == 50);
    assert(life_mend_amount(-4) == 30);
    assert(life_mend_amount(1000000) == 200030);
    assert(guardian_aegis_amount(100) == 25);
    assert(guardian_aegis_amount(3) == 1);
    assert(guardian_aegis_amount(0) == 0);
    std::int64_t shield = 25;
    assert(absorb_with_shield(10, shield) == 10 && shield == 15);
    assert(absorb_with_shield(30, shield) == 15 && shield == 0);
    assert(absorb_with_shield(5, shield) == 0 && shield == 0);
    shield = 20;
    assert(absorb_with_shield(-5, shield) == 0 && shield == 20);
    assert(support_target_in_range(12.0, 0.0));
    assert(!support_target_in_range(12.01, 0.0));
    assert(!support_target_in_range(0.0, 0.0, 0.0));
    assert(kPurifyManaCost == 14);
    assert(kPurifyCooldownMs == 10000);
    assert(purified_effect_count(false, false, false) == 0);
    assert(purified_effect_count(true, false, false) == 1);
    assert(purified_effect_count(false, true, true) == 2);
    assert(purified_effect_count(true, true, true) == 3);

    TimedSlowEffect slow;
    TimedFreezeEffect freeze;
    PeriodicDamageEffect poison;
    assert(apply_slow(slow, 1000, 3000, 0.55F));
    assert(apply_freeze(freeze, 1000, 700));
    assert(apply_periodic_damage(poison, 1000, 3000, 1000, 4));
    assert(purified_effect_count(slow_is_active(slow, 1100),
                                 freeze_is_active(freeze, 1100),
                                 periodic_damage_is_active(poison, 1100)) == 3);
    clear_negative_statuses(slow, freeze, poison);
    assert(!slow_is_active(slow, 1100));
    assert(!freeze_is_active(freeze, 1100));
    assert(!periodic_damage_is_active(poison, 1100));
}
