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
    assert(result.damage == 1); // minimum damage applies even against heavy armor
    assert(result.remaining_health == 24);
    assert(!result.defeated);

    const CombatantStats invalid_defender{attack: 1, defense: -1, current_health: 10, max_health: 10};
    assert(!calculate_damage(attacker, invalid_defender, AttackProfile{}, result));
    const AttackProfile invalid_profile{10000, 10001};
    assert(!calculate_damage(attacker, defender, invalid_profile, result));

    // Monster attacks use the same authoritative defense calculation.
    const CombatantStats monster_attacker{attack: 12, defense: 4, current_health: 1, max_health: 1};
    const CombatantStats player_defender{attack: 20, defense: 5, current_health: 80, max_health: 100};
    assert(calculate_damage(monster_attacker, player_defender, AttackProfile{}, result));
    assert(result.damage == 7);
    assert(result.remaining_health == 73);
    assert(!result.defeated);

    return 0;
}
