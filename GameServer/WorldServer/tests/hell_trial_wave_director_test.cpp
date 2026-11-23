#include "simulation/hell_trial_wave_director.hpp"

#include <cassert>
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

    HellTrialWaveDirector invalid(0);
    assert(!invalid.enabled());
    assert(invalid.is_unlocked("any-monster"));
    return 0;
}
