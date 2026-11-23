#pragma once

#include "simulation/monster.hpp"

namespace honghuang::simulation {

struct HellTrialBossPhaseTransition {
    bool changed{};
    int phase{};
    double health_ratio{};
};

class HellTrialBossPhaseController {
public:
    HellTrialBossPhaseTransition update(double health, double max_health);
    int phase() const;
    void reset();
    double attack_multiplier() const;
    double tempo_multiplier() const;
    MonsterAttackProfile attack_profile(const MonsterDefinition& definition, int floor) const;

private:
    int phase_{};
};

} // namespace honghuang::simulation
