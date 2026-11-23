#pragma once

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

private:
    int phase_{};
};

} // namespace honghuang::simulation
