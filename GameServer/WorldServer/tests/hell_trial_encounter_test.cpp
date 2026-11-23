#include "simulation/hell_trial_encounter.hpp"

#include <cassert>
#include <string>

using honghuang::simulation::HellTrialEncounter;
using honghuang::simulation::hell_trial_floor_specs;

int main() {
    const auto& specs = hell_trial_floor_specs();
    assert(specs.size() == 18);
    for (int floor = 1; floor <= HellTrialEncounter::floor_count; ++floor) {
        HellTrialEncounter encounter(floor);
        assert(encounter.enabled());
        assert(encounter.floor() == floor);
        assert(encounter.spec() != nullptr);
        assert(!encounter.spec()->name.empty());
        assert(!encounter.spec()->guardian_id.empty());
        assert(encounter.spec()->objective_required == 3);
        assert(!encounter.completed());
    }

    HellTrialEncounter invalid(19);
    assert(!invalid.enabled());
    assert(invalid.floor() == 0);

    HellTrialEncounter encounter(1);
    auto result = encounter.record_monster_death("mob-a", "hell_f01_tongue_wraith");
    assert(result.objective_kill_recorded && result.objective_kills == 1);
    result = encounter.record_monster_death("mob-a", "hell_f01_tongue_wraith");
    assert(!result.objective_kill_recorded && result.objective_kills == 1);
    result = encounter.record_monster_death("mob-b", "hell_f01_sin_clerk");
    assert(result.objective_kill_recorded && result.objective_kills == 2);
    result = encounter.record_monster_death("mob-c", "hell_f01_echo_ghost");
    assert(result.objective_kill_recorded && result.objective_kills == 3);
    assert(!result.completion_ready); // Objective alone cannot complete the floor.

    result = encounter.record_monster_death("boss-1", "hell_f01_tongue_jailer");
    assert(result.guardian_killed && result.guardian_defeated);
    assert(result.completion_ready);
    assert(encounter.completed());

    result = encounter.record_monster_death("boss-1", "hell_f01_tongue_jailer");
    assert(!result.completion_ready); // Completion callback is emitted only once.

    HellTrialEncounter boss_first(18);
    result = boss_first.record_monster_death("boss-18", "hell_f18_abyss_judge");
    assert(result.guardian_killed && !result.completion_ready);
    boss_first.record_monster_death("mob-18a", "hell_f18_void_blade");
    boss_first.record_monster_death("mob-18b", "hell_f18_abyssal_chain");
    result = boss_first.record_monster_death("mob-18c", "hell_f18_last_sinner");
    assert(result.objective_kills == 3 && result.completion_ready);

    HellTrialEncounter unrelated(7);
    result = unrelated.record_monster_death("mob-x", "hell_f01_tongue_wraith");
    assert(!result.objective_kill_recorded);
    assert(!result.guardian_killed);
    return 0;
}
