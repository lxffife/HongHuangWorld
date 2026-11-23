#include "simulation/hell_trial_progression.hpp"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>

int main() {
    using namespace honghuang::simulation;

    HellTrialProgression progression;
    assert(HellTrialProgression::floor_count == 18);
    assert(progression.highest_unlocked_floor() == 1);
    assert(progression.can_enter_floor(1));
    assert(!progression.can_enter_floor(2));
    assert(!progression.can_enter_floor(0));
    assert(!progression.can_enter_floor(19));

    assert(progression.complete_floor(2, true, true) == HellTrialCompletion::floor_locked);
    assert(progression.complete_floor(1, false, true) == HellTrialCompletion::objective_incomplete);
    assert(progression.complete_floor(1, true, false) == HellTrialCompletion::guardian_alive);
    assert(!progression.is_floor_completed(1));

    assert(progression.complete_floor(1, true, true) == HellTrialCompletion::accepted);
    assert(progression.is_floor_completed(1));
    assert(progression.highest_unlocked_floor() == 2);
    assert(progression.can_enter_floor(1)); // Completed floors remain replayable.
    assert(progression.can_enter_floor(2));
    assert(progression.complete_floor(1, true, true) == HellTrialCompletion::already_completed);

    for (int floor = 2; floor < HellTrialProgression::floor_count; ++floor) {
        assert(progression.complete_floor(floor, true, true) == HellTrialCompletion::accepted);
        assert(progression.highest_unlocked_floor() == floor + 1);
        assert(!progression.can_enter_floor(floor + 2));
    }

    assert(progression.can_enter_floor(18));
    assert(!progression.final_trial_completed());
    assert(progression.complete_floor(18, true, false) == HellTrialCompletion::guardian_alive);
    assert(progression.complete_floor(18, true, true) == HellTrialCompletion::accepted);
    assert(progression.final_trial_completed());
    assert(progression.highest_unlocked_floor() == 18);
    assert(!progression.can_enter_floor(19));
    assert(progression.complete_floor(19, true, true) == HellTrialCompletion::invalid_floor);
    return 0;
}
