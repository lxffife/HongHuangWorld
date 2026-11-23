#include "simulation/hell_trial_boss_phase.hpp"

#include <algorithm>
#include <cmath>

namespace honghuang::simulation {

HellTrialBossPhaseTransition HellTrialBossPhaseController::update(
    double health, double max_health) {
    HellTrialBossPhaseTransition result;
    result.phase = phase_;
    if (!std::isfinite(health) || !std::isfinite(max_health) || max_health <= 0.0)
        return result;

    const double ratio = std::clamp(health / max_health, 0.0, 1.0);
    int desired_phase = ratio <= 0.30 ? 3 : (ratio <= 0.65 ? 2 : 1);
    desired_phase = std::max(phase_, desired_phase);
    result.health_ratio = ratio;
    if (desired_phase != phase_) {
        phase_ = desired_phase;
        result.changed = true;
    }
    result.phase = phase_;
    return result;
}

int HellTrialBossPhaseController::phase() const { return phase_; }

void HellTrialBossPhaseController::reset() { phase_ = 0; }

double HellTrialBossPhaseController::attack_multiplier() const {
    if (phase_ >= 3) return 1.60;
    if (phase_ == 2) return 1.25;
    return 1.0;
}

double HellTrialBossPhaseController::tempo_multiplier() const {
    if (phase_ >= 3) return 0.75;
    if (phase_ == 2) return 0.90;
    return 1.0;
}

} // namespace honghuang::simulation
