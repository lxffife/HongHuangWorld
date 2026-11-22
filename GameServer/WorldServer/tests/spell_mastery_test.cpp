#include "simulation/spell_mastery.hpp"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>
#include <string>

int main() {
    using namespace honghuang::simulation;

    assert(spell_mastery_level(-1) == 1);
    assert(spell_mastery_level(0) == 1);
    assert(spell_mastery_level(99) == 1);
    assert(spell_mastery_level(100) == 2);
    assert(spell_mastery_level(299) == 2);
    assert(spell_mastery_level(300) == 3);
    assert(spell_mastery_level(4500) == 10);
    assert(spell_mastery_level(99999) == 10);

    SpellMastery fireball{"fireball", 95, 1};
    fireball = award_spell_mastery_xp(fireball, 5);
    assert(fireball.experience == 100);
    assert(fireball.level == 2);

    // A single confirmed hit cannot grant an unbounded amount of skill XP.
    fireball = award_spell_mastery_xp(fireball, 100000);
    assert(fireball.experience == 110);
    assert(fireball.level == 2);

    // Misses and invalid awards do not advance mastery.
    const auto after_miss = award_spell_mastery_xp(fireball, 0);
    assert(after_miss.experience == fireball.experience);
    const auto after_negative = award_spell_mastery_xp(fireball, -5);
    assert(after_negative.experience == fireball.experience);

    // Mastery is capped, including corrupted/out-of-range persisted values.
    SpellMastery capped{"ice_bolt", 4498, 9};
    capped = award_spell_mastery_xp(capped, 10);
    assert(capped.experience == kSpellMasteryMaxXp);
    assert(capped.level == 10);
    capped = award_spell_mastery_xp(capped, 10);
    assert(capped.experience == kSpellMasteryMaxXp);

    const auto invalid_id = award_spell_mastery_xp({"", 20, 1}, 10);
    assert(invalid_id.experience == 20);
    const auto overlong_id = award_spell_mastery_xp({std::string(65, 'x'), 20, 1}, 10);
    assert(overlong_id.experience == 20);

    assert(spell_mastery_power_bonus_basis_points(0) == 0);
    assert(spell_mastery_power_bonus_basis_points(1) == 0);
    assert(spell_mastery_power_bonus_basis_points(5) == 400);
    assert(spell_mastery_power_bonus_basis_points(10) == 900);
    assert(spell_mastery_power_bonus_basis_points(99) == 900);
    return 0;
}
