#include "simulation/spell_combat.hpp"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>
#include <limits>

int main() {
    using namespace honghuang::simulation;

    const auto* fireball = find_spell_definition("fireball");
    assert(fireball != nullptr);
    assert(fireball->element == SpellElement::Fire);
    assert(fireball->mana_cost == 18);
    assert(fireball->cast_time_ms == 350);
    assert(fireball->cooldown_ms == 1800);
    assert(fireball->range == 20.0F);
    assert(fireball->projectile_speed == 16.0F);
    assert(fireball->projectile_lifetime_seconds == 1.8F);
    assert(fireball->power_basis_points == 12500);
    assert(fireball->slow_duration_ms == 0 && fireball->slow_multiplier == 1.0F);
    assert(fireball->freeze_duration_ms == 0);
    assert(fireball->burn_duration_ms == 3000);
    assert(fireball->burn_interval_ms == 1000);
    assert(fireball->burn_damage_basis_points == 2000);
    assert(valid_spell_definition(*fireball));

    const auto* ice_bolt = find_spell_definition("ice_bolt");
    assert(ice_bolt != nullptr && ice_bolt->element == SpellElement::Ice);
    assert(ice_bolt->mana_cost == 16 && ice_bolt->cast_time_ms == 300);
    assert(ice_bolt->range == 18.0F && ice_bolt->power_basis_points == 8500);
    assert(ice_bolt->slow_duration_ms == 3000);
    assert(ice_bolt->slow_multiplier == 0.55F);
    assert(ice_bolt->freeze_duration_ms == 700);
    assert(ice_bolt->burn_duration_ms == 0);
    assert(valid_spell_definition(*ice_bolt));

    // Unknown client-provided spell IDs are never resolved by the server catalog.
    assert(find_spell_definition("client_damage_999") == nullptr);
    assert(find_spell_definition("") == nullptr);

    assert(can_pay_spell_cost(18, 18));
    assert(can_pay_spell_cost(30, 18));
    assert(!can_pay_spell_cost(17, 18));
    assert(!can_pay_spell_cost(-1, 18));
    assert(!can_pay_spell_cost(100, 0));
    assert(!can_pay_spell_cost(100, -1));

    auto invalid = *fireball;
    invalid.range = std::numeric_limits<float>::quiet_NaN();
    assert(!valid_spell_definition(invalid));

    invalid = *fireball;
    invalid.projectile_speed = 0.0F;
    assert(!valid_spell_definition(invalid));

    invalid = *fireball;
    invalid.mana_cost = 0;
    assert(!valid_spell_definition(invalid));

    invalid = *fireball;
    invalid.defense_penetration_basis_points = 10001;
    assert(!valid_spell_definition(invalid));

    invalid = *ice_bolt;
    invalid.slow_duration_ms = 30001;
    assert(!valid_spell_definition(invalid));
    invalid = *ice_bolt;
    invalid.freeze_duration_ms = 5001;
    assert(!valid_spell_definition(invalid));
    invalid = *ice_bolt;
    invalid.slow_multiplier = 1.2F;
    assert(!valid_spell_definition(invalid));
    invalid = *fireball;
    invalid.burn_interval_ms = 0;
    assert(!valid_spell_definition(invalid));
    invalid = *fireball;
    invalid.burn_damage_basis_points = 10001;
    assert(!valid_spell_definition(invalid));
    invalid = *fireball;
    invalid.slow_duration_ms = 1000; // A timed effect must actually slow.
    assert(!valid_spell_definition(invalid));

    return 0;
}
