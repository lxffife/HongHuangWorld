#include "simulation/weapon_combat.hpp"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>

int main() {
    using namespace honghuang::simulation;

    const auto dagger = weapon_combat_profile("dagger");
    assert(dagger.range == 2.6F);
    assert(dagger.cooldown.count() == 480);
    assert(dagger.power_basis_points == 9000);

    const auto spear = weapon_combat_profile("spear");
    assert(spear.range > dagger.range);
    assert(spear.cooldown.count() == 800);
    assert(spear.power_basis_points == 10500);

    const auto sword = weapon_combat_profile("sword");
    assert(sword.range == 3.5F);
    assert(sword.cooldown.count() == 650);
    assert(sword.power_basis_points == 10000);

    const auto axe = weapon_combat_profile("axe");
    const auto hammer = weapon_combat_profile("hammer");
    assert(axe.power_basis_points > sword.power_basis_points);
    assert(hammer.power_basis_points > axe.power_basis_points);
    assert(hammer.defense_penetration_basis_points == 1000);
    assert(hammer.cooldown > axe.cooldown);

    // Ranged types must not accidentally gain long-range hits before projectiles exist.
    const auto bow = weapon_combat_profile("bow");
    const auto staff = weapon_combat_profile("staff");
    const auto focus = weapon_combat_profile("focus");
    assert(bow.range == 22.0F);
    assert(bow.cooldown.count() == 900);
    assert(staff.range == sword.range);
    assert(focus.range == sword.range);

    const auto unknown = weapon_combat_profile("unknown");
    assert(unknown.range < dagger.range);
    assert(unknown.power_basis_points < sword.power_basis_points);

    return 0;
}
