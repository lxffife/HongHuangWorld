#include "simulation/hell_trial_boss_phase.hpp"

#include <cassert>
#include <cmath>
#include <limits>
#include <string>

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
    // Phase two uses a deterministic floor signature, while phase three
    // becomes a larger area attack on every floor.
    HellTrialBossPhaseController themed;
    const honghuang::simulation::MonsterDefinition guardian{
        "hell_f01_tongue_jailer", "拔舌判官", 11, 1000.0F, 40.0F, 10.0F,
        2.0F, 16.0F, 40.0F, 0.0F, 0.0F, 1.8F
    };
    auto profile = themed.attack_profile(guardian, 1);
    assert(std::string(profile.style) == "melee");
    themed.update(650.0, 1000.0);
    profile = themed.attack_profile(guardian, 1);
    assert(std::string(profile.style) == "soul_bolt");
    assert(profile.range == 7.0F && profile.windup_ms == 720);
    const auto other_floor = themed.attack_profile(guardian, 2);
    assert(std::string(other_floor.style) == "blade_slash");
    assert(other_floor.range == 2.8F);
    const auto invalid_floor = themed.attack_profile(guardian, 19);
    assert(std::string(invalid_floor.style) == "melee");
    const char* expected_signatures[] = {
        "soul_bolt", "blade_slash", "poison_bolt",
        "frost_bolt", "heavy_slam", "blade_slash"
    };
    for (int floor = 1; floor <= 18; ++floor) {
        const auto floor_profile = themed.attack_profile(guardian, floor);
        assert(std::string(floor_profile.style) ==
               expected_signatures[(floor - 1) % 6]);
        assert(floor_profile.windup_ms > 0);
        assert(floor_profile.recovery_ms > 0);
        assert(floor_profile.cooldown_ms > 0);
    }

    themed.update(300.0, 1000.0);
    profile = themed.attack_profile(guardian, 1);
    assert(std::string(profile.style) == "heavy_slam");
    assert(profile.splash_radius > 5.0F && profile.range == profile.splash_radius);
    assert(profile.cooldown_ms == 2500);

    boss.reset();
    assert(boss.phase() == 0);
    assert(std::abs(boss.attack_multiplier() - 1.0) < 0.001);
    return 0;
}
