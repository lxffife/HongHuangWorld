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

    // Bow range is enabled only alongside the server projectile path; spell weapons stay close-range.
    const auto bow = weapon_combat_profile("bow");
    const auto staff = weapon_combat_profile("staff");
    const auto focus = weapon_combat_profile("focus");
    assert(bow.range == 22.0F);
    assert(bow.cooldown.count() == 900);
    assert(staff.range == sword.range);
    assert(focus.range == sword.range);

    // Agility grants 0.1% critical chance per point, capped at 15%.
    assert(critical_chance_basis_points(0) == 0);
    assert(critical_chance_basis_points(1) == 10);
    assert(critical_chance_basis_points(100) == 1000);
    assert(critical_chance_basis_points(150) == 1500);
    assert(critical_chance_basis_points(100000) == 1500);
    assert(critical_chance_basis_points(-10) == 0);

    // Agility improves attack cadence by 0.1% per point, with a 20% cap.
    assert(agility_adjusted_attack_cooldown(std::chrono::milliseconds(1000), 0).count() == 1000);
    assert(agility_adjusted_attack_cooldown(std::chrono::milliseconds(1000), 50).count() == 950);
    assert(agility_adjusted_attack_cooldown(std::chrono::milliseconds(1000), 100).count() == 900);
    assert(agility_adjusted_attack_cooldown(std::chrono::milliseconds(1000), 200).count() == 800);
    assert(agility_adjusted_attack_cooldown(std::chrono::milliseconds(1000), 100000).count() == 800);
    assert(agility_adjusted_attack_cooldown(std::chrono::milliseconds(1000), -10).count() == 1000);
    assert(agility_adjusted_attack_cooldown(std::chrono::milliseconds(1), 200).count() == 100);
    assert(agility_adjusted_attack_cooldown(std::chrono::milliseconds::zero(), 100).count() == 0);

    const auto unknown = weapon_combat_profile("unknown");
    assert(unknown.range < dagger.range);
    assert(unknown.power_basis_points < sword.power_basis_points);

    return 0;
}
