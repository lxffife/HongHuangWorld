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
    assert(valid_spell_definition(*fireball));

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

    return 0;
}
