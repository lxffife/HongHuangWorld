#include "simulation/combat.hpp"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>

int main() {
    using namespace honghuang::simulation;

    const CombatantStats attacker{attack: 120, defense: 10, current_health: 100, max_health: 100};
    const CombatantStats defender{attack: 30, defense: 20, current_health: 100, max_health: 100};
    DamageResult result{};

    assert(calculate_damage(attacker, defender, AttackProfile{}, result));
    assert(result.damage == 100);
    assert(result.remaining_health == 0);
    assert(result.defeated);

    const AttackProfile half_power{5000, 0};
    assert(calculate_damage(attacker, defender, half_power, result));
    assert(result.damage == 40);
    assert(result.remaining_health == 60);
    assert(!result.defeated);

    const AttackProfile full_penetration{10000, 10000};
    assert(calculate_damage(attacker, defender, full_penetration, result));
    assert(result.damage == 100);

    const CombatantStats heavily_armored{attack: 1, defense: 1000, current_health: 25, max_health: 25};
    assert(calculate_damage(attacker, heavily_armored, AttackProfile{}, result));
    assert(result.damage == 25); // damage is capped at remaining health

    const CombatantStats invalid_defender{attack: 1, defense: -1, current_health: 10, max_health: 10};
    assert(!calculate_damage(attacker, invalid_defender, AttackProfile{}, result));
    const AttackProfile invalid_profile{10000, 10001};
    assert(!calculate_damage(attacker, defender, invalid_profile, result));

    return 0;
}
