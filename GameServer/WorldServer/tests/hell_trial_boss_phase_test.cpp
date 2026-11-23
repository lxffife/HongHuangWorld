#include "simulation/hell_trial_boss_phase.hpp"

#include <cassert>
#include <cmath>
#include <limits>

using honghuang::simulation::HellTrialBossPhaseController;

int main() {
    HellTrialBossPhaseController boss;
    auto transition = boss.update(1000.0, 1000.0);
    assert(transition.changed && transition.phase == 1);
    assert(std::abs(boss.attack_multiplier() - 1.0) < 0.001);

    transition = boss.update(650.0, 1000.0);
    assert(transition.changed && transition.phase == 2);
    assert(std::abs(boss.attack_multiplier() - 1.25) < 0.001);
    assert(std::abs(boss.tempo_multiplier() - 0.90) < 0.001);

    transition = boss.update(300.0, 1000.0);
    assert(transition.changed && transition.phase == 3);
    assert(std::abs(boss.attack_multiplier() - 1.60) < 0.001);
    assert(std::abs(boss.tempo_multiplier() - 0.75) < 0.001);

    // Healing cannot roll a boss back to an easier phase.
    transition = boss.update(900.0, 1000.0);
    assert(!transition.changed && transition.phase == 3);

    // Invalid health snapshots cannot mutate phase state.
    transition = boss.update(std::numeric_limits<double>::quiet_NaN(), 1000.0);
    assert(!transition.changed && transition.phase == 3);
    transition = boss.update(1.0, 0.0);
    assert(!transition.changed && transition.phase == 3);
    boss.reset();
    assert(boss.phase() == 0);
    assert(std::abs(boss.attack_multiplier() - 1.0) < 0.001);
    return 0;
}
