#include "simulation/hell_trial_wave_director.hpp"

#include <cassert>
#include <cstddef>
#include <string>

using honghuang::simulation::HellTrialWaveDirector;

int main() {
    HellTrialWaveDirector waves(1);
    assert(waves.enabled());
    assert(waves.stage() == 0);
    assert(waves.active_definition_id() == "hell_f01_tongue_wraith");
    assert(waves.is_unlocked("hell_f01_tongue_wraith"));
    assert(!waves.is_unlocked("hell_f01_sin_clerk"));
    assert(!waves.is_unlocked("hell_f01_tongue_jailer"));

    auto transition = waves.record_death("hell_f01_sin_clerk");
    assert(!transition.advanced && waves.stage() == 0);
    transition = waves.record_death("hell_f01_tongue_wraith");
    assert(transition.advanced && transition.stage == 1);
    assert(transition.unlocked_definition_id == "hell_f01_sin_clerk");
    assert(!waves.is_unlocked("hell_f01_tongue_wraith"));
    assert(waves.is_unlocked("hell_f01_sin_clerk"));

    // Duplicate death callbacks cannot skip a wave.
    transition = waves.record_death("hell_f01_tongue_wraith");
    assert(!transition.advanced && waves.stage() == 1);
    transition = waves.record_death("hell_f01_sin_clerk");
    assert(transition.advanced && transition.unlocked_definition_id == "hell_f01_echo_ghost");
    transition = waves.record_death("hell_f01_echo_ghost");
    assert(transition.advanced && transition.unlocked_definition_id == "hell_f01_tongue_jailer");
    assert(waves.stage() == 3);
    assert(waves.is_unlocked("hell_f01_tongue_jailer"));
    assert(!waves.is_unlocked("hell_f01_echo_ghost"));

    transition = waves.record_death("hell_f01_tongue_jailer");
    assert(transition.advanced && transition.completed);
    assert(waves.completed());
    assert(waves.active_definition_id().empty());
    assert(!waves.is_unlocked("hell_f01_tongue_jailer"));
    assert(!waves.record_death("hell_f01_tongue_jailer").advanced);

    HellTrialWaveDirector recovered(1);
    assert(recovered.restore_stage(2));
    assert(recovered.stage() == 2);
    assert(recovered.active_definition_id() == "hell_f01_echo_ghost");
    assert(!recovered.is_unlocked("hell_f01_tongue_wraith"));
    assert(recovered.restore_stage(4));
    assert(recovered.completed());
    assert(recovered.active_definition_id().empty());
    assert(!recovered.restore_stage(5));

    HellTrialWaveDirector invalid(0);
    assert(!invalid.enabled());
    assert(invalid.is_unlocked("any-monster"));

    // Every configured floor must preserve the same strict four-stage gate.
    const auto& floor_specs = honghuang::simulation::hell_trial_floor_specs();
    for (int floor = 1; floor <= honghuang::simulation::HellTrialEncounter::floor_count; ++floor) {
        HellTrialWaveDirector sequence(floor);
        const auto& spec = floor_specs[static_cast<std::size_t>(floor - 1)];
        for (std::size_t wave = 0; wave < spec.objective_monster_ids.size(); ++wave) {
            assert(sequence.active_definition_id() == spec.objective_monster_ids[wave]);
            const auto locked_id = spec.objective_monster_ids[
                (wave + 1) % spec.objective_monster_ids.size()];
            const auto locked = sequence.record_death(locked_id);
            assert(!locked.advanced && sequence.stage() == static_cast<int>(wave));
            const auto advanced = sequence.record_death(spec.objective_monster_ids[wave]);
            assert(advanced.advanced && advanced.stage == static_cast<int>(wave + 1));
        }
        const auto guardian = sequence.record_death(spec.guardian_id);
        assert(guardian.advanced && guardian.completed);
        assert(sequence.completed() && sequence.active_definition_id().empty());
    }
    return 0;
}
